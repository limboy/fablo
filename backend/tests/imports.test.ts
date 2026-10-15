import { afterEach, expect, test } from "bun:test";
import { readdir, rm } from "node:fs/promises";
import { join } from "node:path";
import { createHandler } from "../src/server";
import { Store } from "../src/store";
import { importID } from "../src/imports";
import { IMPORT_BODY_LIMIT, JSON_BODY_LIMIT } from "../src/request-body";
import { estimate } from "../src/timeline";
import { config, content, request, analysis, wav, provider } from "./fixtures";

const environments: { store: Store; directory: string }[] = [];
afterEach(async () => { for (const { store, directory } of environments.splice(0)) { store.close(); await rm(directory, { recursive: true, force: true }); } });
function environment() {
  const settings = config(), store = new Store(settings.dataDir), handler = createHandler(settings, store);
  environments.push({ store, directory: settings.dataDir });
  const payload = () => ({
    source: { format: "japanese-short-essays-v1", id: "original-folder", metadata: { level: "JLPT N5-N4", setting: "町の図書館", perspective: "一人称" } },
    createdAt: "2026-08-19T00:00:00.000Z", generationRequest: request, content: structuredClone(content), analyses: { "0": analysis },
  });
  const post = (form: FormData, authenticated = true) => handler(new Request("https://fablo.example.com/v1/imports", {
    method: "POST", headers: authenticated ? { Authorization: `Bearer ${settings.apiToken}` } : {}, body: form,
  }));
  const form = (value: unknown = payload()) => { const data = new FormData(); data.set("story", JSON.stringify(value)); return data; };
  return { settings, store, handler, payload, post, form };
}

test("imports existing content and original metadata without generation jobs; source IDs are stable", async () => {
  const { store, handler, settings, post, form, payload } = environment();
  expect((await post(form(), false)).status).toBe(401);
  expect(store.countStories()).toBe(0);
  const response = await post(form());
  expect(response.status).toBe(201);
  const result = await response.json();
  expect(result.imported).toBe(true);
  expect(result.story.id).toBe(importID("japanese-short-essays-v1", "original-folder"));
  expect(result.story.createdAt).toBe(payload().createdAt);
  expect(result.story.importedFrom.metadata).toEqual(payload().source.metadata);
  expect(result.story.generationRequest).toEqual(request);
  expect(result.story.content).toEqual(content);
  expect(result.story.analyses["0"]).toEqual(analysis);
  expect(result.story.audioStatus).toBe("missing");
  expect(store.listJobs()).toEqual([]);
  const listing = await (await handler(new Request("https://fablo.example.com/v1/stories", { headers: { Authorization: `Bearer ${settings.apiToken}` } }))).json();
  expect(listing.stories).toHaveLength(1);
  // The full original manuscript is returned in details, not in every library poll.
  expect(listing.stories[0].importedFrom).toBeUndefined();
  expect(listing.stories[0].content).toBeUndefined();
});

test("retries are idempotent and conflicting content never overwrites an existing story", async () => {
  const { store, post, form, payload } = environment();
  const first = await (await post(form())).json();
  const revision = store.revision();
  const duplicate = await post(form());
  expect(duplicate.status).toBe(200);
  expect((await duplicate.json()).imported).toBe(false);
  expect(store.revision()).toBe(revision);
  const changed = payload(); changed.content.title = "Different content";
  expect((await post(form(changed))).status).toBe(409);
  expect(store.getStory(first.story.id)?.content.title).toBe(content.title);
  expect(store.countStories()).toBe(1);
});

test("rejects malformed imports and enforces separate upload and ordinary JSON limits", async () => {
  const { store, settings, handler, post, form, payload } = environment();
  const empty = new FormData();
  expect((await post(empty)).status).toBe(400);
  const invalid = payload(); invalid.generationRequest = { ...request, level: "N5" };
  expect((await post(form(invalid))).status).toBe(400);
  const mismatched = payload(); mismatched.content.paragraphs[0]!.sentences[0]!.text = "Different text";
  expect((await post(form(mismatched))).status).toBe(400);
  const duplicate = form(); duplicate.append("story", "{}");
  expect((await post(duplicate)).status).toBe(400);
  const orphanTimeline = form(); orphanTimeline.set("timeline", "{}");
  expect((await post(orphanTimeline)).status).toBe(400);
  const badIndex = { ...payload(), analyses: { "999": analysis } };
  expect((await post(form(badIndex))).status).toBe(400);
  const oversized = new Request("https://fablo.example.com/v1/imports", { method: "POST", headers: { Authorization: `Bearer ${settings.apiToken}`, "Content-Type": "multipart/form-data; boundary=test", "Content-Length": String(IMPORT_BODY_LIMIT + 1) }, body: "test" });
  expect((await handler(oversized)).status).toBe(413);
  const json = new Request("https://fablo.example.com/v1/generations", { method: "POST", headers: { Authorization: `Bearer ${settings.apiToken}`, "Content-Type": "application/json" }, body: JSON.stringify({ ...request, topic: "x".repeat(JSON_BODY_LIMIT) }) });
  expect((await handler(json)).status).toBe(413);
  expect(store.countStories()).toBe(0);
});

async function encodedMedia(directory: string) {
  const source = join(directory, "source.wav"), png = join(directory, "source.png"), audio = join(directory, "audio.m4a"), cover = join(directory, "cover.jpg");
  await Bun.write(source, wav());
  await Bun.write(png, await provider().image(""));
  for (const args of [["-i", source, "-c:a", "aac", "-movflags", "+faststart", audio], ["-i", png, "-frames:v", "1", cover]]) {
    const child = Bun.spawn([Bun.which("ffmpeg")!, "-v", "error", "-nostdin", "-y", ...args], { stdout: "ignore", stderr: "pipe" });
    if (await child.exited) throw new Error(await new Response(child.stderr).text());
  }
  const probe = Bun.spawn([Bun.which("ffprobe")!, "-v", "error", "-show_entries", "format=duration", "-of", "default=noprint_wrappers=1:nokey=1", audio], { stdout: "pipe" });
  const duration = Number(await new Response(probe.stdout).text());
  if (await probe.exited) throw new Error("ffprobe failed");
  return { audio, cover, timeline: estimate([["Hello", "world", "."], ["Good", "morning", "."]], duration) };
}

test.skipIf(!Bun.which("ffmpeg") || !Bun.which("ffprobe"))("publishes media atomically, handles concurrent retries, and cleans up failed imports", async () => {
  const { settings, store, handler, post, form } = environment();
  const media = await encodedMedia(settings.dataDir);
  const upload = (badAudio = false) => {
    const data = form(); data.set("cover", Bun.file(media.cover), "cover.jpg");
    data.set("audio", badAudio ? new Blob(["not audio"]) : Bun.file(media.audio), "audio.m4a");
    data.set("timeline", JSON.stringify(media.timeline));
    return data;
  };
  expect((await post(upload(true))).status).toBe(400);
  expect(store.countStories()).toBe(0);
  const id = importID("japanese-short-essays-v1", "original-folder");
  expect(await readdir(join(settings.dataDir, "assets", id))).toEqual([]);
  const results = await Promise.all([post(upload()), post(upload())]);
  expect(results.map(r => r.status).sort()).toEqual([200, 201]);
  const story = store.getStory(id)!;
  expect(story.audioStatus).toBe("ready"); expect(story.coverStatus).toBe("ready");
  expect(await readdir(join(settings.dataDir, "assets", id))).toHaveLength(2);
  expect(await readdir(join(settings.dataDir, "tmp"))).toEqual([]);
  const get = (asset: string) => handler(new Request(`https://fablo.example.com/v1/stories/${id}/assets/${asset}`, { headers: { Authorization: `Bearer ${settings.apiToken}` } }));
  expect((await get("cover")).headers.get("content-type")).toBe("image/jpeg");
  expect((await get("audio")).headers.get("content-type")).toBe("audio/mp4");
  expect(await (await get("timeline")).json()).toEqual(media.timeline);
  const bytes = await (await get("audio")).arrayBuffer();
  expect(bytes.byteLength).toBe(Bun.file(media.audio).size);
});
