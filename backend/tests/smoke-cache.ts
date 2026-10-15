import { mkdtemp, rm } from "node:fs/promises";
import { join, resolve } from "node:path";
import { tmpdir } from "node:os";
import { loadConfig } from "../src/config";
import { createHandler } from "../src/server";
import { Store } from "../src/store";
import { publishAssets } from "../src/assets";
import { record, analysis, wav } from "./fixtures";

if (!Bun.which("swiftc")) throw new Error("Swift is required for the native cache smoke test");
const directory = await mkdtemp(join(tmpdir(), "fablo-cache-smoke-"));
const project = resolve(import.meta.dir, "../..");
const token = "cache-test-" + crypto.randomUUID();
const settings = loadConfig({ FABLO_API_TOKEN: token, AI_GATEWAY_KEY: "unused", DATA_DIR: join(directory, "data") });
const store = new Store(settings.dataDir), route = createHandler(settings, store);
const story = record();
let timestamp = Date.now();
const requests: string[] = [];
const png = Buffer.from("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aY1cAAAAASUVORK5CYII=", "base64");
const timeline = JSON.stringify({ version: 3, duration: 1, sentenceStarts: [0, 0.5], sentenceEnds: [0.4, 1], wordStarts: [[0, 0.2, null], [0.5, 0.7, null]], isAligned: true });
async function assets() {
  story.coverVersion = await publishAssets(settings.dataDir, story.id, { "cover.jpg": png });
  story.audioVersion = await publishAssets(settings.dataDir, story.id, { "audio.m4a": wav(), "timeline.json": timeline });
  story.coverStatus = "ready";
  story.audioStatus = "ready";
  story.updatedAt = new Date(++timestamp).toISOString();
  store.saveStory(story);
}
async function handler(request: Request) {
  const url = new URL(request.url);
  requests.push(url.pathname + url.search);
  if (/\/analyses\/0$/.test(url.pathname) && request.method === "POST" && request.headers.get("authorization") === `Bearer ${token}`) {
    story.analyses["0"] = analysis;
    story.updatedAt = new Date(++timestamp).toISOString();
    store.saveStory(story);
    return Response.json({ analysis });
  }
  return route(request);
}
let server: ReturnType<typeof Bun.serve> | undefined;
async function command(args: string[], extra: Record<string, string> = {}) {
  const child = Bun.spawn(args, {
    cwd: directory,
    env: { PATH: process.env.PATH, HOME: process.env.HOME, ...extra }, stdout: "pipe", stderr: "pipe",
  });
  const [stdout, stderr, exit] = await Promise.all([new Response(child.stdout).text(), new Response(child.stderr).text(), child.exited]);
  if (exit !== 0) throw new Error(`Cache test command failed (${args[0]}):\n${stdout}\n${stderr}`);
  return stdout.trim();
}
const count = (name: string, version: string) => requests.filter(path => path.includes(`/assets/${name}?version=${version}`)).length;
function check(condition: boolean, message: string) { if (!condition) throw new Error(message); }
try {
  const binary = join(directory, "CacheContract");
  const sources = [
    "Fablo/Models/StoryContent.swift", "Fablo/Services/BackendCache.swift", "Fablo/Services/BackendClient.swift", "Fablo/Models/Story.swift",
    "Fablo/Models/LibraryEntry.swift", "Fablo/Models/ReadingStatus.swift", "Fablo/Services/BackendCredentials.swift",
    "Fablo/Services/StoryStudio.swift", "Fablo/Services/StoryAudio.swift", "backend/tests/CacheContract.swift",
  ];
  await command(["swiftc", "-swift-version", "5", "-module-cache-path", join(directory, "swift-cache"), ...sources.map(path => join(project, path)), "-o", binary]);
  await assets();
  const originalCover = story.coverVersion!, originalAudio = story.audioVersion!;
  server = Bun.serve({ hostname: "127.0.0.1", port: 0, fetch: handler });
  const port = server.port!;
  const env = { FABLO_TEST_URL: `http://127.0.0.1:${port}`, FABLO_TEST_TOKEN: token, FABLO_TEST_STORY: story.id, FABLO_TEST_CACHE: join(directory, "cache") };
  const phase = async (name: string) => console.info(await command([binary], { ...env, FABLO_TEST_PHASE: name }));
  await phase("populate");
  check(count("cover", originalCover) === 1 && count("audio", originalAudio) === 1 && count("timeline", originalAudio) === 1, "Repeated asset reads downloaded the same version again");
  check(!requests.some(path => path.endsWith("/status")), "Known audio versions unexpectedly requested server status");
  await server.stop(true);
  server = undefined;
  await phase("startup");
  await phase("offline");
  console.info("Fresh client process read the library, text, analysis, cover, audio and timeline with the server stopped");
  story.content = { ...story.content, title: "Updated Morning" };
  await assets();
  server = Bun.serve({ hostname: "127.0.0.1", port, fetch: handler });
  await phase("versions");
  check(count("cover", story.coverVersion!) === 1 && count("audio", story.audioVersion!) === 1, "Updated versions did not download exactly once");
  await phase("corruption");
  check(count("audio", story.audioVersion!) === 2 && count("timeline", story.audioVersion!) === 2, "A corrupt audio timeline was not repaired from the server");
  await phase("authorization");
  store.deleteStory(story.id);
  await phase("deletion");
  console.info("Version refresh, synchronized reading boards, offline reading state, credential isolation and deletion cleanup passed");
} finally {
  await server?.stop(true);
  store.close();
  await rm(directory, { recursive: true, force: true });
}
