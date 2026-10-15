import { mkdir, rename, rm } from "node:fs/promises";
import { join } from "node:path";
import { execFile } from "node:child_process";
import { promisify } from "node:util";
import type { Config } from "./config";
import type { AIProvider } from "./gateway";
import { align, estimate } from "./timeline";
import { APIError, parseTimeline, words, type StoryRecord, type Timeline } from "./types";
import { coverPrompt, speechInstructions } from "./prompts";

const execute = promisify(execFile);
export function assetPath(directory: string, story: StoryRecord, name: "cover" | "audio" | "timeline"): string | null {
  const version = name === "cover" ? story.coverVersion : story.audioVersion;
  if (!version) return null;
  return join(directory, "assets", story.id, version, { cover: "cover.jpg", audio: "audio.m4a", timeline: "timeline.json" }[name]);
}
export async function publishAssets(directory: string, storyId: string, files: Record<string, Uint8Array | string>): Promise<string> {
  const version = crypto.randomUUID(), root = join(directory, "assets", storyId), temporary = join(root, `.staging-${version}`);
  await mkdir(temporary, { recursive: true, mode: 0o700 });
  try {
    for (const [name, data] of Object.entries(files)) await Bun.write(join(temporary, name), data);
    await rename(temporary, join(root, version));
  } finally { await rm(temporary, { recursive: true, force: true }); }
  return version;
}
export class AssetGenerator {
  constructor(private config: Config, private ai: AIProvider) {}
  private async run(program: string, args: string[], signal?: AbortSignal): Promise<string> {
    try { return (await execute(program, args, { timeout: 180000, maxBuffer: 1024 * 1024, signal })).stdout; }
    catch (error) {
      if (signal?.aborted) throw signal.reason;
      const code = (error as NodeJS.ErrnoException).code;
      throw new APIError(502, code === "ENOENT" ? `找不到 ${program}，请安装 FFmpeg` : "媒体处理失败，请检查 FFmpeg 和输入文件");
    }
  }
  async cover(story: StoryRecord, signal?: AbortSignal): Promise<string> {
    const temp = join(this.config.dataDir, "tmp", crypto.randomUUID());
    await mkdir(temp, { recursive: true, mode: 0o700 });
    try {
      await Bun.write(join(temp, "source"), await this.ai.image(coverPrompt(story.content.coverPrompt), signal));
      await this.run(this.config.ffmpeg, ["-v", "error", "-nostdin", "-y", "-i", join(temp, "source"), "-frames:v", "1", "-vf", "scale='min(1200,iw)':-2", "-q:v", "3", join(temp, "cover.jpg")], signal);
      return await publishAssets(this.config.dataDir, story.id, { "cover.jpg": await Bun.file(join(temp, "cover.jpg")).bytes() });
    } finally { await rm(temp, { recursive: true, force: true }); }
  }
  async audio(story: StoryRecord, signal?: AbortSignal): Promise<string> {
    const temp = join(this.config.dataDir, "tmp", crypto.randomUUID());
    await mkdir(temp, { recursive: true, mode: 0o700 });
    try {
      const input = story.content.paragraphs.map(p => p.sentences.map(s => s.text).join(story.language === "ja" ? "" : " ")).join("\n\n");
      const wav = await this.ai.speech(input, story.language === "ja" ? "Kore" : "Zephyr", speechInstructions(story), signal);
      const source = join(temp, "source.wav"), output = join(temp, "audio.m4a");
      await Bun.write(source, wav);
      await this.run(this.config.ffmpeg, ["-v", "error", "-nostdin", "-y", "-i", source, "-vn", "-c:a", "aac", "-b:a", "64k", "-movflags", "+faststart", output], signal);
      const duration = Number((await this.run(this.config.ffprobe, ["-v", "error", "-show_entries", "format=duration", "-of", "default=noprint_wrappers=1:nokey=1", output], signal)).trim());
      if (!Number.isFinite(duration) || duration <= 0 || duration > 86400) throw new APIError(502, "音频时长无效");
      let timeline: Timeline;
      try { timeline = parseTimeline(align(words(story.content), await this.ai.transcribe(wav, signal), duration), story.content); }
      catch (error) { if (signal?.aborted) throw error; timeline = estimate(words(story.content), duration); }
      parseTimeline(timeline, story.content);
      return await publishAssets(this.config.dataDir, story.id, { "audio.m4a": await Bun.file(output).bytes(), "timeline.json": JSON.stringify(timeline) });
    } finally { await rm(temp, { recursive: true, force: true }); }
  }
}
