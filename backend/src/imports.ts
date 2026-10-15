import { createHash } from "node:crypto";
import { execFile } from "node:child_process";
import { mkdir, mkdtemp, rm } from "node:fs/promises";
import { join } from "node:path";
import { promisify } from "node:util";
import { publishAssets } from "./assets";
import type { Config } from "./config";
import { IMPORT_BODY_LIMIT, readBody } from "./request-body";
import type { Store } from "./store";
import { TIMELINE_VERSION } from "./timeline";
import { APIError, object, parseAnalysis, parseContent, parseRequest, parseTimeline, sentences, text, type StoryRecord, type Timeline } from "./types";

const execute = promisify(execFile);
const IMPORT_NAMESPACE = "b20805d6-cf78-4c91-848b-981ad34a8c21";
export function importID(format: string, id: string): string {
  const namespace = Buffer.from(IMPORT_NAMESPACE.replaceAll("-", ""), "hex");
  const bytes = createHash("sha1").update(namespace).update(`${format}:${id}`).digest().subarray(0, 16);
  bytes[6] = (bytes[6]! & 15) | 80;
  bytes[8] = (bytes[8]! & 63) | 128;
  const hex = bytes.toString("hex");
  return `${hex.slice(0, 8)}-${hex.slice(8, 12)}-${hex.slice(12, 16)}-${hex.slice(16, 20)}-${hex.slice(20)}`;
}

function json(value: string, name: string): unknown {
  try { return JSON.parse(value); } catch { throw new APIError(400, `${name} 不是有效的 JSON`); }
}
function metadata(value: FormDataEntryValue | null, name: string, limit: number): string {
  if (typeof value !== "string" || Buffer.byteLength(value) > limit) throw new APIError(400, `无效的 ${name}`);
  return value;
}
async function media(value: FormDataEntryValue | null, name: string, limit: number): Promise<Uint8Array | null> {
  if (value === null) return null;
  if (!(value instanceof File) || value.size === 0 || value.size > limit) throw new APIError(400, `无效的 ${name} 文件`);
  return new Uint8Array(await value.arrayBuffer());
}

export async function importStory(request: Request, config: Config, store: Store): Promise<{ story: StoryRecord; imported: boolean }> {
  const contentType = request.headers.get("content-type") ?? "";
  if (!contentType.toLowerCase().startsWith("multipart/form-data;")) throw new APIError(415, "请使用 multipart/form-data");
  const bytes = await readBody(request, IMPORT_BODY_LIMIT);
  let form: FormData;
  try { form = await new Response(bytes, { headers: { "Content-Type": contentType } }).formData(); }
  catch { throw new APIError(400, "上传表单无效"); }
  const names = [...form.keys()];
  if (new Set(names).size !== names.length || names.some(name => !["story", "cover", "audio", "timeline"].includes(name))) throw new APIError(400, "上传字段无效或重复");
  const raw = object(json(metadata(form.get("story"), "story", 1024 * 1024), "story"));
  const source = object(raw.source);
  const importedFrom = {
    format: text(source.format, "source.format", 100, false),
    id: text(source.id, "source.id", 500, false),
    metadata: object(source.metadata ?? {}),
  };
  if (Buffer.byteLength(JSON.stringify(importedFrom.metadata)) > 64 * 1024) throw new APIError(400, "原始元数据过大");
  const createdAt = text(raw.createdAt, "createdAt", 40, false);
  if (!/^\d{4}-\d{2}-\d{2}T/.test(createdAt) || !Number.isFinite(Date.parse(createdAt))) throw new APIError(400, "创建时间无效");
  const generationRequest = parseRequest(raw.generationRequest), content = parseContent(raw.content);
  for (const sentence of sentences(content)) {
    const displayed = sentence.c.flatMap(chunk => chunk.w.map(word => word.s)).join("");
    if (displayed.replace(/\s/g, "") !== sentence.text.replace(/\s/g, "")) throw new APIError(400, "逐词标注与正文不一致");
  }
  const count = sentences(content).length;
  const analyses: StoryRecord["analyses"] = {};
  for (const [index, analysis] of Object.entries(object(raw.analyses ?? {}))) {
    if (!/^(0|[1-9]\d*)$/.test(index) || Number(index) >= count) throw new APIError(400, "解析的句子编号无效");
    analyses[index] = parseAnalysis(analysis);
  }
  const cover = await media(form.get("cover"), "cover", 4 * 1024 * 1024);
  const audio = await media(form.get("audio"), "audio", 12 * 1024 * 1024);
  let timeline: Timeline | null = null;
  if (audio) {
    timeline = parseTimeline(json(metadata(form.get("timeline"), "timeline", 1024 * 1024), "timeline"), content);
    if (timeline.version !== TIMELINE_VERSION) throw new APIError(400, `时间轴版本必须是 ${TIMELINE_VERSION}`);
  } else if (form.has("timeline")) throw new APIError(400, "时间轴必须与音频一起上传");
  const id = importID(importedFrom.format, importedFrom.id);
  const fingerprint = createHash("sha256").update(JSON.stringify({ createdAt, generationRequest, content, analyses, importedFrom, timeline }));
  for (const file of [cover, audio]) fingerprint.update(file ? createHash("sha256").update(file).digest() : "missing");
  const checksum = fingerprint.digest("hex");
  const existing = () => {
    const story = store.getStory(id);
    if (story && story.importedFrom?.checksum !== checksum) throw new APIError(409, "该来源已导入其他内容，不会覆盖现有短文");
    return story;
  };
  const previous = existing();
  if (previous) return { story: previous, imported: false };

  const temporaryRoot = join(config.dataDir, "tmp");
  await mkdir(temporaryRoot, { recursive: true, mode: 0o700 });
  const temporary = await mkdtemp(join(temporaryRoot, "import-"));
  const versions: string[] = [];
  let committed = false;
  const probe = async (name: string, data: Uint8Array) => {
    const path = join(temporary, name);
    await Bun.write(path, data);
    try {
      const result = await execute(config.ffprobe, ["-v", "error", "-protocol_whitelist", "file,pipe", "-show_format", "-show_streams", "-of", "json", path], { timeout: 30000, maxBuffer: 1024 * 1024 });
      return JSON.parse(result.stdout) as { format: { duration?: string; format_name?: string }; streams: { codec_name?: string; codec_type?: string; width?: number; height?: number }[] };
    } catch { throw new APIError(400, "媒体文件无法读取，请上传 JPEG 封面和 AAC/M4A 音频"); }
  };
  try {
    let coverVersion: string | null = null, audioVersion: string | null = null;
    if (cover) {
      const details = await probe("cover.jpg", cover);
      const image = details.streams[0];
      if (cover[0] !== 255 || cover[1] !== 216 || image?.codec_name !== "mjpeg" || !image.width || !image.height || image.width > 8000 || image.height > 8000) throw new APIError(400, "封面必须是有效的 JPEG 图片");
      coverVersion = await publishAssets(config.dataDir, id, { "cover.jpg": cover });
      versions.push(coverVersion);
    }
    if (audio && timeline) {
      const details = await probe("audio.m4a", audio);
      const duration = Number(details.format.duration);
      if (!details.format.format_name?.split(",").includes("mov") || details.streams.length !== 1 || details.streams[0]?.codec_name !== "aac" || !Number.isFinite(duration) || Math.abs(duration - timeline.duration) > 0.1) throw new APIError(400, "音频必须是与时间轴时长一致的 AAC/M4A 文件");
      audioVersion = await publishAssets(config.dataDir, id, { "audio.m4a": audio, "timeline.json": JSON.stringify(timeline) });
      versions.push(audioVersion);
    }
    const story: StoryRecord = {
      id, createdAt: new Date(createdAt).toISOString(), updatedAt: new Date().toISOString(),
      language: generationRequest.language, level: generationRequest.level, genre: generationRequest.genre,
      generationRequest, content, analyses, importedFrom: { ...importedFrom, checksum },
      coverStatus: coverVersion ? "ready" : "missing", audioStatus: audioVersion ? "ready" : "missing", coverVersion, audioVersion,
    };
    const result = store.db.transaction(() => {
      const previous = existing();
      if (previous) return { story: previous, imported: false };
      store.saveStory(story);
      committed = true;
      return { story, imported: true };
    }).immediate();
    return result;
  } finally {
    await rm(temporary, { recursive: true, force: true });
    if (!committed) for (const version of versions) await rm(join(config.dataDir, "assets", id, version), { recursive: true, force: true });
  }
}
