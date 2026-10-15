import { afterEach, describe, expect, test } from "bun:test";
import { rmSync } from "node:fs";
import { join } from "node:path";
import { createHandler } from "../src/server";
import { Store } from "../src/store";
import { Worker } from "../src/worker";
import { publishAssets } from "../src/assets";
import { APIError, parseContent, parseRequest, parseTimeline } from "../src/types";
import { align, estimate } from "../src/timeline";
import { config, request, content, record, provider, analysis } from "./fixtures";

const environments: { store: Store; directory: string }[] = [];
afterEach(() => { for (const { store, directory } of environments.splice(0)) { store.close(); rmSync(directory, { recursive: true, force: true }); } });
function environment() {
  const settings = config(), store = new Store(settings.dataDir), handler = createHandler(settings, store);
  environments.push({ store, directory: settings.dataDir });
  const call = (path: string, init: RequestInit = {}, authenticated = true) => handler(new Request(`https://fablo.example.com${path}`, {
    ...init, headers: { ...(authenticated ? { Authorization: `Bearer ${settings.apiToken}` } : {}), ...init.headers },
  }));
  const post = (path: string, value?: unknown, headers: Record<string, string> = {}) => call(path, { method: "POST", headers: { "Content-Type": "application/json", ...headers }, body: value === undefined ? undefined : JSON.stringify(value) });
  return { settings, store, call, post, handler };
}

describe("API and persistent jobs", () => {
  test("stopping the queue runner settles its active job and leaves queued jobs for restart", async () => {
    const { store, settings } = environment(), story = record();
    store.saveStory(story);
    const active = store.enqueue("analysis", story.id, { index: 0 });
    const queued = store.enqueue("analysis", story.id, { index: 1 });
    let entered!: () => void;
    const started = new Promise<void>(resolve => { entered = resolve; });
    const worker = new Worker(store, settings, provider({ structured: async (_s, _u, _n, _schema, signal) => {
      entered();
      return new Promise((_resolve, reject) => { signal!.addEventListener("abort", () => reject(signal!.reason), { once: true }); });
    } }));
    const controller = new AbortController(), running = worker.runLoop(controller.signal);
    await started;
    controller.abort();
    await running;
    expect(store.getJob(active.id)?.status).toBe("failed");
    expect(store.getJob(queued.id)?.status).toBe("queued");
    await new Worker(store, settings, provider()).tick();
    expect(store.getJob(queued.id)?.status).toBe("completed");
    expect(store.getStory(story.id)?.analyses["1"]).toEqual(analysis);
  });

  test("requires auth for administration, validates browser origins, and supports private cookie sessions", async () => {
    const { call, settings } = environment();
    expect((await call("/health", {}, false)).status).toBe(200);
    expect((await call("/v1/jobs", {}, false)).status).toBe(401);
    expect((await call("/v1/jobs", { headers: { Origin: "https://evil.example" } })).status).toBe(403);
    const cors = await call("/v1/jobs", { headers: { Origin: "https://web.example.com" } });
    expect(cors.headers.get("access-control-allow-origin")).toBe("https://web.example.com");
    const login = await call("/v1/session", { method: "POST", headers: { "Content-Type": "application/json", Origin: "https://fablo.example.com" }, body: JSON.stringify({ token: settings.apiToken }) }, false);
    const cookie = login.headers.get("set-cookie")!;
    expect(cookie).toContain("HttpOnly"); expect(cookie).toContain("Secure"); expect(cookie).toContain("SameSite=Strict");
    expect((await call("/v1/jobs", { headers: { Cookie: cookie.split(";")[0]! } }, false)).status).toBe(200);
    expect((await call("/v1/session", { method: "DELETE", headers: { Cookie: cookie.split(";")[0]! } }, false)).status).toBe(204);
    expect((await call("/v1/jobs", { headers: { Cookie: cookie.split(";")[0]! } }, false)).status).toBe(401);
  });

  test("public readers can list stories, read content and fetch existing analyses without creating jobs", async () => {
    const { call, store } = environment(), story = record();
    story.analyses["0"] = analysis;
    store.saveStory(story);
    const revision = store.revision();
    const listing = await (await call("/v1/stories/", {}, false)).json();
    expect(listing.stories).toHaveLength(1);
    expect(listing.stories[0].id).toBe(story.id);
    expect(listing.stories[0].content).toBeUndefined();
    const base = `/v1/stories/${story.id}`;
    const detail = await (await call(base, {}, false)).json();
    expect(detail.content).toEqual(content);
    expect(detail.analyses).toEqual({ "0": analysis });
    expect((await (await call(`${base}/status`, {}, false)).json()).id).toBe(story.id);
    expect(await (await call(`${base}/analyses/0`, {}, false)).json()).toEqual({ analysis });
    expect((await call(`${base}/analyses/1`, {}, false)).status).toBe(404);
    expect((await call(`${base}/analyses/100`, {}, false)).status).toBe(400);
    expect((await call(`/v1/stories/${crypto.randomUUID()}`, {}, false)).status).toBe(404);
    expect((await call("/v1/stories/not-a-uuid", {}, false)).status).toBe(400);
    expect(store.revision()).toBe(revision);
    expect(store.listJobs()).toEqual([]);
  });

  test("public reading never authorizes writes or access to administrative jobs", async () => {
    const { call, store } = environment(), story = record();
    story.analyses["0"] = analysis;
    store.saveStory(story);
    const job = store.enqueue("analysis", story.id, { index: 1 });
    const protectedRoutes = [
      ["POST", "/v1/imports"], ["POST", "/v1/generations"], ["DELETE", "/v1/session"],
      ["GET", "/v1/jobs"], ["GET", `/v1/jobs/${job.id}`],
      ["POST", `/v1/jobs/${job.id}/retry`], ["DELETE", `/v1/jobs/${job.id}`],
      ["DELETE", `/v1/stories/${story.id}`],
      ...["cover", "audio", "analyses/0", "analyses/1", "assets/cover"].map(action => ["POST", `/v1/stories/${story.id}/${action}`]),
    ];
    for (const [method, path] of protectedRoutes) {
      expect((await call(path!, { method }, false)).status).toBe(401);
      expect((await call(path!, { method, headers: { Authorization: "Bearer invalid" } }, false)).status).toBe(401);
    }
    expect(store.getStory(story.id)).toEqual(story);
    expect(store.listJobs()).toEqual([job]);
  });

  test("any browser origin can read public content while administrative CORS remains restricted", async () => {
    const { call } = environment(), origin = "https://reader.example.net";
    const response = await call("/v1/stories", { headers: { Origin: origin } }, false);
    expect(response.status).toBe(200);
    expect(response.headers.get("access-control-allow-origin")).toBe(origin);
    expect(response.headers.get("access-control-allow-credentials")).toBeNull();
    expect(response.headers.get("access-control-allow-methods")).toBe("GET,HEAD,OPTIONS");
    expect(response.headers.get("vary")).toBe("Origin");
    const trusted = await call("/v1/stories", { headers: { Origin: "https://web.example.com" } }, false);
    expect(trusted.headers.get("access-control-allow-credentials")).toBe("true");
    const preflight = await call("/v1/stories/", { method: "OPTIONS", headers: { Origin: origin, "Access-Control-Request-Method": "GET" } }, false);
    expect(preflight.status).toBe(204);
    expect(preflight.headers.get("access-control-allow-origin")).toBe(origin);
    expect(preflight.headers.get("vary")).toContain("Access-Control-Request-Method");
    const missing = await call(`/v1/stories/${crypto.randomUUID()}`, { headers: { Origin: origin } }, false);
    expect(missing.status).toBe(404);
    expect(missing.headers.get("access-control-allow-origin")).toBe(origin);
    for (const [method, path] of [["DELETE", "/v1/stories"], ["POST", `/v1/stories/${crypto.randomUUID()}/analyses/0`], ["GET", "/v1/jobs"]]) {
      const blocked = await call(path!, { method: "OPTIONS", headers: { Origin: origin, "Access-Control-Request-Method": method! } }, false);
      expect(blocked.status).toBe(403);
      expect(blocked.headers.get("access-control-allow-origin")).toBeNull();
    }
    expect((await call("/v1/generations", { method: "POST", headers: { Origin: origin, "Access-Control-Request-Method": "GET" } })).status).toBe(403);
  });

  test("generation is idempotent across connections and rejects changed payloads", async () => {
    const { post, store, settings } = environment();
    const headers = { "Idempotency-Key": "persistent-request" };
    const first = await post("/v1/generations", request, headers);
    expect(first.status).toBe(202);
    const job = await first.json();
    const otherConnection = new Store(settings.dataDir);
    try {
      expect(otherConnection.getJob(job.id)?.status).toBe("queued");
      expect((await (await post("/v1/generations", request, headers)).json()).id).toBe(job.id);
      expect((await post("/v1/generations", { ...request, topic: "different" }, headers)).status).toBe(409);
      expect(store.listJobs()).toHaveLength(1);
    } finally { otherConnection.close(); }
    expect((await post("/v1/generations", request)).status).toBe(400);
    expect((await post("/v1/generations", { ...request, level: "N1" }, { "Idempotency-Key": "bad-level" })).status).toBe(400);
  });

  test("publishes text first and independently queues media; analysis is cached", async () => {
    const { post, call, store, settings } = environment();
    const job = await (await post("/v1/generations", request, { "Idempotency-Key": "story-request" })).json();
    expect((await (await call("/v1/stories")).json()).stories).toHaveLength(0);
    let textCalls = 0;
    const worker = new Worker(store, settings, provider({ structured: async (_s, _u, name) => { textCalls++; return structuredClone(name === "story" ? content : analysis); } }));
    await worker.tick();
    const listing = await (await call("/v1/stories")).json();
    expect(listing.stories).toHaveLength(1);
    expect(listing.stories[0].id).toBe(job.storyId);
    expect(listing.stories[0].content).toBeUndefined();
    expect(listing.stories[0].title).toBe(content.title);
    expect(listing.stories[0].audioStatus).toBe("queued");
    expect(listing.stories[0].generationRequest).toEqual(request);
    const fullStory = await (await call(`/v1/stories/${job.storyId.toUpperCase()}`)).json();
    expect(fullStory.content).toEqual(content);
    expect(fullStory.generationRequest).toEqual(request);
    for (const media of store.listJobs()) expect(media.request).toEqual(request);
    const parse = await post(`/v1/stories/${job.storyId}/analyses/0`);
    expect(parse.status).toBe(202);
    // Analysis has priority over queued media.
    await worker.tick();
    const cached = await post(`/v1/stories/${job.storyId}/analyses/0`);
    expect(cached.status).toBe(200);
    expect((await cached.json()).analysis).toEqual(analysis);
    expect(textCalls).toBe(2);
    expect((await post(`/v1/stories/${job.storyId}/analyses/100`)).status).toBe(400);
  });

  test("recovers original generation metadata for existing stories on startup", async () => {
    const { store, settings, call } = environment(), original = record();
    const { generationRequest: _, ...legacy } = original;
    store.db.query("INSERT INTO stories VALUES (?,?,?,?)").run(legacy.id, JSON.stringify(legacy), legacy.createdAt, legacy.updatedAt);
    store.enqueue("story", legacy.id, { request });
    store.enqueue("audio", legacy.id);
    const reopened = new Store(settings.dataDir);
    try {
      expect(reopened.getStory(legacy.id)?.generationRequest).toEqual(request);
      expect(reopened.getStory(legacy.id)?.createdAt).toBe(legacy.createdAt);
      const listing = await (await call("/v1/stories")).json();
      expect(listing.stories[0].generationRequest).toEqual(request);
      expect(reopened.listJobs().find(job => job.kind === "audio")?.request).toEqual(request);
    } finally { reopened.close(); }
  });

  test("failed jobs survive restart, have explicit retries, and respect queue limits", async () => {
    const { settings, store, post } = environment();
    settings.maxQueuedJobs = 1;
    const first = await (await post("/v1/generations", request, { "Idempotency-Key": "failed-request" })).json();
    expect((await post("/v1/generations", request, { "Idempotency-Key": "another-request" })).status).toBe(429);
    await new Worker(store, settings, provider({ structured: async () => { throw new APIError(502, "上游暂不可用"); } })).tick();
    expect(store.getJob(first.id)?.error).toBe("上游暂不可用");
    expect((await post(`/v1/jobs/${first.id}/retry`)).status).toBe(202);
    expect(store.getJob(first.id)?.status).toBe("queued");
    const claimed = store.claim("old-worker")!;
    store.db.query("UPDATE jobs SET lease_until=0 WHERE id=?").run(claimed.id);
    store.claim("new-worker");
    expect(store.getJob(first.id)?.status).toBe("failed");
    expect(store.owns(claimed)).toBe(false);
  });

  test("pagination is stable for tied dates and rejects invalid cursors", async () => {
    const { store, call } = environment();
    const date = new Date().toISOString();
    for (let i = 0; i < 3; i++) { const s = record(); s.createdAt = date; store.saveStory(s); }
    const first = await (await call("/v1/stories?limit=2", {}, false)).json();
    const next = await (await call(`/v1/stories?limit=2&cursor=${first.nextCursor}`, {}, false)).json();
    expect(new Set([...first.stories, ...next.stories].map(s => s.id)).size).toBe(3);
    expect(next.nextCursor).toBeNull();
    expect((await call("/v1/stories?cursor=invalid", {}, false)).status).toBe(400);
    expect((await call("/v1/stories?limit=10000", {}, false)).status).toBe(400);
  });

  test("deleting a story fences an analysis already running on the worker", async () => {
    const { store, call, settings } = environment(), story = record();
    store.saveStory(story);
    const job = store.enqueue("analysis", story.id, { index: 0 });
    let resolve!: (value: unknown) => void;
    let began!: () => void;
    const started = new Promise<void>(r => { began = r; });
    const ai = provider({ structured: async () => { began(); return new Promise(r => { resolve = r; }); } });
    const running = new Worker(store, settings, ai).tick();
    await started;
    expect((await call(`/v1/stories/${story.id}`, { method: "DELETE" })).status).toBe(204);
    resolve(analysis); await running;
    expect(store.getStory(story.id)).toBeNull();
    expect(store.getJob(job.id)?.status).toBe("completed");
    expect((await call(`/v1/stories/${story.id}`)).status).toBe(404);
  });

  test("public resource downloads support ranges, HEAD, conditional requests and pinned asset versions", async () => {
    const { store, call, settings } = environment(), story = record();
    const version = await publishAssets(settings.dataDir, story.id, { "cover.jpg": "cover", "audio.m4a": Buffer.from("0123456789"), "timeline.json": "{}" });
    story.coverVersion = version; story.coverStatus = "ready";
    story.audioVersion = version; story.audioStatus = "ready"; store.saveStory(story);
    const path = `/v1/stories/${story.id}/assets/audio?version=${version}`;
    expect((await call(path, {}, false)).status).toBe(200);
    for (const [name, type, expected] of [["cover", "image/jpeg", "cover"], ["timeline", "application/json", "{}"]]) {
      const resource = await call(`/v1/stories/${story.id}/assets/${name}`, {}, false);
      expect(resource.headers.get("content-type")).toBe(type!);
      expect(await resource.text()).toBe(expected!);
    }
    const range = await call(path, { headers: { Range: "bytes=2-5", Origin: "https://reader.example.net" } }, false);
    expect(range.status).toBe(206); expect(await range.text()).toBe("2345");
    expect(range.headers.get("content-range")).toBe("bytes 2-5/10");
    expect(range.headers.get("access-control-allow-origin")).toBe("https://reader.example.net");
    expect(range.headers.get("cache-control")).toBe("public, no-cache");
    expect((await call(path, { headers: { "If-None-Match": `"${version}"` } }, false)).status).toBe(304);
    expect((await call(path, { headers: { Range: "bytes=99-" } }, false)).status).toBe(416);
    const head = await call(path, { method: "HEAD", headers: { Origin: "https://reader.example.net" } }, false);
    expect(head.status).toBe(200);
    expect(head.headers.get("content-length")).toBe("10");
    expect(await head.text()).toBe("");
    const newVersion = await publishAssets(settings.dataDir, story.id, { "audio.m4a": "new" });
    store.assetStatus(story.id, "audio", "ready", newVersion);
    expect(await (await call(path, {}, false)).text()).toBe("0123456789");
    expect((await call(`/v1/stories/${story.id}/assets/audio?version=../secret`, {}, false)).status).toBe(400);
  });
});

describe("timeline compatibility", () => {
  test("aligns words, preserves punctuation and validates against the reader layout", () => {
    const words = [["Hello", "world", "."], ["Good", "morning", "."]];
    const timeline = align(words, [
      { text: "Hello", offsetMilliseconds: 0, durationMilliseconds: 200 },
      { text: "world", offsetMilliseconds: 300, durationMilliseconds: 200 },
      { text: "Good", offsetMilliseconds: 1000, durationMilliseconds: 200 },
      { text: "morning", offsetMilliseconds: 1300, durationMilliseconds: 500 },
    ], 2);
    expect(timeline.isAligned).toBe(true);
    expect(timeline.wordStarts).toEqual([[0, 0.3, null], [1, 1.3, null]]);
    expect(parseTimeline(timeline, content)).toEqual(timeline);
    expect(() => parseTimeline({ ...timeline, sentenceEnds: [9, 9] }, content)).toThrow();
  });
  test("folds Japanese kana and estimates unsupported long alignments", () => {
    const timeline = align([["キツネ", "です", "。"]], [{ text: "きつねです", offsetMilliseconds: 0, durationMilliseconds: 900 }], 1);
    expect(timeline.isAligned).toBe(true);
    expect(timeline.wordStarts[0]![2]).toBeNull();
    expect(align([["a".repeat(3000)]], [{ text: "a".repeat(3000), offsetMilliseconds: 0, durationMilliseconds: 900 }], 1).isAligned).toBe(false);
    expect(estimate([["!"], ["Hello"]], 1).sentenceStarts).toEqual([0, 0]);
  });
  test("rejects malformed content and unsupported generation requests", () => {
    expect(() => parseContent({ ...content, paragraphs: [] })).toThrow();
    expect(() => parseRequest({ ...request, language: "fr" })).toThrow();
  });
});

describe("media pipeline", () => {
  test.skipIf(!Bun.which("ffmpeg") || !Bun.which("ffprobe"))("encodes audio and publishes a compatible fallback timeline when transcription fails", async () => {
    const { settings, store, call } = environment(), story = record();
    store.saveStory(story);
    store.enqueue("audio", story.id);
    const worker = new Worker(store, settings, provider({ transcribe: async () => { throw new Error("transcription unavailable"); } }));
    await worker.tick();
    const updated = store.getStory(story.id)!;
    expect(updated.audioStatus).toBe("ready");
    const audio = await call(`/v1/stories/${story.id}/assets/audio`);
    expect(audio.status).toBe(200); expect((await audio.arrayBuffer()).byteLength).toBeGreaterThan(100);
    const timeline = await (await call(`/v1/stories/${story.id}/assets/timeline`)).json();
    expect(timeline.isAligned).toBe(false);
    expect(parseTimeline(timeline, story.content)).toEqual(timeline);
    expect(await Bun.file(join(settings.dataDir, "assets", story.id, updated.audioVersion!, "audio.m4a")).exists()).toBe(true);
  });
});
