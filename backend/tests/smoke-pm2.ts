import { cp, mkdtemp, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { resolve, join } from "node:path";
import { Store } from "../src/store";
import { content, analysis, request, wav } from "./fixtures";

// This never touches the user's PM2 daemon, credentials or AI provider.
const directory = await mkdtemp(join(tmpdir(), "fablo-pm2-smoke-"));
const backend = resolve(import.meta.dir, ".."), project = resolve(backend, "..");
const serviceDirectory = join(directory, "backend"), dataDir = join(directory, "data");
await cp(join(backend, "src"), join(serviceDirectory, "src"), { recursive: true });
await cp(join(backend, "ecosystem.config.cjs"), join(serviceDirectory, "ecosystem.config.cjs"));
const pm2 = Bun.which("pm2");
if (!pm2) throw new Error("Install PM2 to run this smoke test");
const imageProcess = Bun.spawn(["ffmpeg", "-v", "error", "-f", "lavfi", "-i", "color=c=orange:s=16x16", "-frames:v", "1", "-f", "image2pipe", "-c:v", "png", "pipe:1"], { stdout: "pipe", stderr: "pipe" });
const image = await new Response(imageProcess.stdout).arrayBuffer();
if (await imageProcess.exited !== 0) throw new Error("FFmpeg could not produce a test image");
let analysisGate: Promise<void> | null = null;
let releaseAnalysis: (() => void) | undefined;
let analysisStarted = false;
const gateway = Bun.serve({ hostname: "127.0.0.1", port: 0, async fetch(incoming) {
  if (incoming.headers.get("authorization") !== "Bearer mock-key") return new Response(null, { status: 401 });
  const body = await incoming.json() as any, path = new URL(incoming.url).pathname;
  if (path === "/v1/chat/completions") {
    if (body.response_format.json_schema.name === "analysis" && analysisGate) {
      analysisStarted = true;
      await analysisGate;
    }
    return Response.json({ choices: [{ message: { content: JSON.stringify(body.response_format.json_schema.name === "story" ? content : analysis) } }] });
  }
  if (path === "/v1/images/generations") return Response.json({ data: [{ b64_json: Buffer.from(image).toString("base64") }] });
  if (path === "/v4/ai/speech-model") return Response.json({ audio: Buffer.from(wav()).toString("base64") });
  if (path === "/v4/ai/transcription-model") return Response.json({ providerMetadata: { azure: { phrases: [{ words: [
    { text: "Hello", offsetMilliseconds: 0, durationMilliseconds: 150 },
    { text: "world", offsetMilliseconds: 200, durationMilliseconds: 150 },
    { text: "Good", offsetMilliseconds: 500, durationMilliseconds: 150 },
    { text: "morning", offsetMilliseconds: 700, durationMilliseconds: 200 },
  ] }] } } });
  return new Response(null, { status: 404 });
} });
const reservation = Bun.serve({ hostname: "127.0.0.1", port: 0, fetch: () => new Response() });
const port = reservation.port!;
await reservation.stop(true);
const token = "smoke-" + crypto.randomUUID();
// Exercise Bun's production .env loading rather than injecting service settings
// into PM2's environment. The real backend/.env is never loaded by the service.
await writeFile(join(serviceDirectory, ".env"), Object.entries({
  FABLO_API_TOKEN: token, AI_GATEWAY_KEY: "mock-key", AI_GATEWAY_URL: `http://127.0.0.1:${gateway.port}`,
  DATA_DIR: dataDir, HOST: "127.0.0.1", PORT: String(port), PUBLIC_ORIGIN: `http://127.0.0.1:${port}`,
}).map(([key, value]) => `${key}=${JSON.stringify(value)}`).join("\n") + "\n");
const env = { PATH: process.env.PATH, HOME: process.env.HOME, USER: process.env.USER, TMPDIR: process.env.TMPDIR, PM2_HOME: join(directory, "pm2"), BUN_BIN: process.execPath };
async function command(args: string[], customEnv: Record<string, string | undefined> = env) {
  const process = Bun.spawn(args, { cwd: serviceDirectory, env: customEnv, stdout: "pipe", stderr: "pipe" });
  const [stdout, stderr, exit] = await Promise.all([new Response(process.stdout).text(), new Response(process.stderr).text(), process.exited]);
  if (exit !== 0) throw new Error(`Command failed: ${args[0]}\n${stdout.slice(-3000)}\n${stderr.slice(-3000)}`);
  return stdout;
}
const base = `http://127.0.0.1:${port}`;
async function api(path: string, options: RequestInit = {}) {
  const response = await fetch(base + path, { ...options, headers: { Authorization: `Bearer ${token}`, "Content-Type": "application/json", ...options.headers } });
  if (!response.ok) throw new Error(`API failed: ${path} (${response.status})`);
  return response;
}
async function until(check: () => Promise<boolean>) {
  for (let i = 0; i < 240; i++) { if (await check().catch(() => false)) return; await new Promise(resolve => setTimeout(resolve, 250)); }
  throw new Error("Smoke service did not become ready");
}
try {
  await command([pm2, "start", "ecosystem.config.cjs"]);
  await until(async () => (await fetch(base + "/health")).ok);
  const job = await (await api("/v1/generations", { method: "POST", headers: { "Idempotency-Key": "pm2-smoke-story" }, body: JSON.stringify(request) })).json() as any;
  await until(async () => {
    const response = await api(`/v1/stories/${job.storyId}`);
    const story = await response.json() as any;
    return story.coverStatus === "ready" && story.audioStatus === "ready";
  });
  console.info("Single PM2 service generated text, cover, AAC and word timings");
  // Hold an AI call open, then verify HTTP responsiveness and shared-process shutdown.
  analysisGate = new Promise<void>(resolve => { releaseAnalysis = resolve; });
  const blocked = await (await api(`/v1/stories/${job.storyId}/analyses/1`, { method: "POST" })).json() as any;
  await until(async () => analysisStarted);
  await api("/v1/jobs", { signal: AbortSignal.timeout(2000) });
  const queued = await (await api(`/v1/stories/${job.storyId}/analyses/0`, { method: "POST" })).json() as any;
  await command([pm2, "stop", "fablo"]);
  releaseAnalysis!();
  analysisGate = null;
  const persisted = new Store(dataDir);
  try {
    if (persisted.getJob(blocked.job.id)?.status !== "failed") throw new Error("Shutdown did not settle the interrupted job");
    if (persisted.getJob(queued.job.id)?.status !== "queued") throw new Error("Shutdown lost queued work");
  } finally { persisted.close(); }
  await command([pm2, "restart", "fablo"]);
  await until(async () => Boolean((await (await api(`/v1/stories/${job.storyId}`)).json() as any).analyses["0"]));
  await api(`/v1/jobs/${blocked.job.id}/retry`, { method: "POST" });
  await until(async () => Boolean((await (await api(`/v1/stories/${job.storyId}`)).json() as any).analyses["1"]));
  console.info("HTTP stayed responsive; shutdown and restart preserved queued work and retries");
  if (Bun.which("swiftc")) {
    const binary = join(directory, "ClientContract");
    await command(["swiftc", "-swift-version", "5", "-module-cache-path", join(directory, "swift-cache"), join(project, "Fablo/Models/StoryContent.swift"), join(project, "Fablo/Services/BackendClient.swift"), join(project, "Fablo/Models/Story.swift"), join(project, "Fablo/Models/LibraryEntry.swift"), join(backend, "tests/ClientContract.swift"), "-o", binary]);
    const output = await command([binary], { ...env, FABLO_TEST_URL: base, FABLO_TEST_TOKEN: token, FABLO_TEST_OUTPUT: directory });
    console.info(output.trim());
  }
} finally {
  releaseAnalysis?.();
  // PM2_HOME is set explicitly for every command, including cleanup.
  await command([pm2, "delete", "all"]).catch(() => {});
  await command([pm2, "kill"]).catch(() => {});
  await gateway.stop(true);
  await rm(directory, { recursive: true, force: true });
}
