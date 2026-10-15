import { mkdtemp, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import { uploadBundle } from "../scripts/upload-import";
import { loadConfig } from "../src/config";
import { IMPORT_BODY_LIMIT } from "../src/request-body";
import { createHandler } from "../src/server";
import { Store } from "../src/store";

const bundlePath = Bun.argv[2];
if (!bundlePath) throw new Error("Usage: bun --no-env-file tests/smoke-import.ts /path/to/prepared-bundle");
const bundle = await Bun.file(join(bundlePath, "bundle.json")).json() as { stories: { audio: boolean }[] };
const directory = await mkdtemp(join(tmpdir(), "fablo-import-smoke-"));
const token = "local-import-test-" + crypto.randomUUID();
const settings = loadConfig({ FABLO_API_TOKEN: token, AI_GATEWAY_KEY: "unused", DATA_DIR: directory });
const store = new Store(directory);
const server = Bun.serve({ hostname: "127.0.0.1", port: 0, maxRequestBodySize: IMPORT_BODY_LIMIT, fetch: createHandler(settings, store) });
try {
  const url = `http://127.0.0.1:${server.port}`;
  const first = await uploadBundle(bundlePath, url, token);
  if (first.imported !== bundle.stories.length || store.countStories() !== bundle.stories.length || store.listJobs().length) throw new Error("Bulk import did not publish the expected library");
  const second = await uploadBundle(bundlePath, url, token);
  if (second.imported || second.existing !== first.imported || store.countStories() !== first.imported) throw new Error("Repeat upload was not idempotent");
  console.info("All prepared stories imported twice without duplicates or generation jobs");
  if (Bun.which("swiftc")) {
    const project = resolve(import.meta.dir, "../..");
    const sources = ["Fablo/Models/StoryContent.swift", "Fablo/Services/BackendCache.swift", "Fablo/Services/BackendClient.swift", "Fablo/Models/Story.swift", "Fablo/Services/StoryAudio.swift", "backend/tests/ImportContract.swift"];
    const binary = join(directory, "ImportContract");
    const compile = Bun.spawn(["swiftc", "-swift-version", "5", "-module-cache-path", join(directory, "swift-cache"), ...sources.map(path => join(project, path)), "-o", binary], { stdout: "pipe", stderr: "pipe" });
    const [stdout, stderr, code] = await Promise.all([new Response(compile.stdout).text(), new Response(compile.stderr).text(), compile.exited]);
    if (code) throw new Error(`Swift compile failed:\n${stdout}\n${stderr}`);
    const child = Bun.spawn([binary], { env: { PATH: process.env.PATH, HOME: process.env.HOME, FABLO_TEST_URL: url, FABLO_TEST_TOKEN: token, FABLO_TEST_OUTPUT: directory, FABLO_TEST_STORIES: String(bundle.stories.length), FABLO_TEST_AUDIO_COUNT: String(bundle.stories.filter(s => s.audio).length) }, stdout: "pipe", stderr: "pipe" });
    const [out, err, exit] = await Promise.all([new Response(child.stdout).text(), new Response(child.stderr).text(), child.exited]);
    if (exit) throw new Error(`Native import contract failed:\n${out}\n${err}`);
    console.info(out.trim());
  }
} finally {
  await server.stop(true);
  store.close();
  await rm(directory, { recursive: true, force: true });
}
