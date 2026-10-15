import { createHash, timingSafeEqual } from "node:crypto";
import { rm } from "node:fs/promises";
import { join } from "node:path";
import { loadConfig, type Config } from "./config";
import { assetPath } from "./assets";
import { Store } from "./store";
import { Worker } from "./worker";
import { importStory } from "./imports";
import { IMPORT_BODY_LIMIT, JSON_BODY_LIMIT, readBody } from "./request-body";
import { APIError, object, parseRequest, sentences, text, uuid, type StoryRecord } from "./types";

const hash = (value: string) => createHash("sha256").update(value).digest("hex");
const equals = (a: string, b: string) => timingSafeEqual(Buffer.from(hash(a)), Buffer.from(hash(b)));
const json = (value: unknown, status = 200) => Response.json(value, { status });
const summary = (story: StoryRecord) => {
  const { content, analyses, importedFrom, ...metadata } = story;
  return { ...metadata, generationRequest: story.generationRequest ?? null, readingStatus: story.readingStatus ?? "unread", readingStatusRevision: story.readingStatusRevision ?? 0, title: content.title, titleZh: content.titleZh, summaryZh: content.summaryZh, coverPrompt: content.coverPrompt };
};
const detail = (story: StoryRecord) => ({ ...summary(story), content: story.content, analyses: story.analyses, ...(story.importedFrom ? { importedFrom: story.importedFrom } : {}) });
const sessionCookie = (request: Request): string | null => request.headers.get("cookie")?.split(";").map(v => v.trim()).find(v => v.startsWith("fablo_session="))?.slice("fablo_session=".length) ?? null;
const routePath = (url: URL) => url.pathname.replace(/\/$/, "") || "/";
const isPublicRead = (path: string, method: string) => {
  if (method === "GET") return path === "/v1/stories" || /^\/v1\/stories\/[^/]+(?:\/(?:status|analyses\/\d+|assets\/(?:cover|audio|timeline)))?$/.test(path);
  return method === "HEAD" && /^\/v1\/stories\/[^/]+\/assets\/(?:cover|audio|timeline)$/.test(path);
};

async function body(request: Request): Promise<unknown> {
  if (!request.headers.get("content-type")?.toLowerCase().startsWith("application/json")) throw new APIError(415, "请使用 application/json");
  const data = await readBody(request, JSON_BODY_LIMIT);
  try { return JSON.parse(new TextDecoder().decode(data)); } catch { throw new APIError(400, "JSON 格式无效"); }
}
async function fileResponse(request: Request, path: string, type: string, version: string): Promise<Response> {
  const file = Bun.file(path);
  if (!await file.exists()) throw new APIError(404, "资源文件不存在");
  const headers = new Headers({ "Content-Type": type, "Cache-Control": "public, no-cache", ETag: `"${version}"`, "Accept-Ranges": "bytes" });
  if (request.headers.get("if-none-match") === headers.get("etag")) return new Response(null, { status: 304, headers });
  const range = request.headers.get("range");
  if (range && (!request.headers.has("if-range") || request.headers.get("if-range") === headers.get("etag"))) {
    const match = /^bytes=(\d*)-(\d*)$/.exec(range);
    let start = 0, end = file.size - 1;
    if (match && (match[1] || match[2])) {
      if (!match[1]) start = Math.max(0, file.size - Number(match[2]));
      else { start = Number(match[1]); if (match[2]) end = Math.min(end, Number(match[2])); }
    } else start = file.size;
    if (!Number.isSafeInteger(start) || !Number.isSafeInteger(end) || start < 0 || start > end || start >= file.size) {
      headers.set("Content-Range", `bytes */${file.size}`);
      return new Response(null, { status: 416, headers });
    }
    headers.set("Content-Range", `bytes ${start}-${end}/${file.size}`);
    headers.set("Content-Length", String(end - start + 1));
    return new Response(request.method === "HEAD" ? null : file.slice(start, end + 1), { status: 206, headers });
  }
  headers.set("Content-Length", String(file.size));
  return new Response(request.method === "HEAD" ? null : file, { headers });
}

export function createHandler(config: Config, store: Store) {
  let activeImports = 0;
  const allowedOrigin = (origin: string, url: URL) => config.origins.includes(origin) || origin === (config.publicOrigin ?? url.origin);
  const requireAuth = (request: Request) => {
    const bearer = request.headers.get("authorization");
    if (bearer?.startsWith("Bearer ") && equals(bearer.slice(7), config.apiToken)) return;
    const cookie = sessionCookie(request);
    if (cookie && cookie.length <= 128 && store.hasSession(hash(config.apiToken + ":" + cookie))) return;
    throw new APIError(401, "访问令牌无效或登录已过期");
  };
  const requiredStory = (id: string) => {
    const story = store.getStory(id);
    if (!story) throw new APIError(404, "短文不存在");
    return story;
  };
  async function route(request: Request, url: URL): Promise<Response> {
    const path = routePath(url), method = request.method;
    if (path === "/health" && method === "GET") return json({ status: "ok" });
    if (path === "/v1/session" && method === "POST") {
      const token = text(object(await body(request)).token, "token", 512, false);
      if (!equals(token, config.apiToken)) throw new APIError(401, "访问令牌无效");
      const session = crypto.randomUUID() + crypto.randomUUID();
      store.addSession(hash(config.apiToken + ":" + session));
      const response = json({ authenticated: true });
      const secure = (config.publicOrigin ?? url.origin).startsWith("https:");
      response.headers.set("Set-Cookie", `fablo_session=${session}; HttpOnly; SameSite=Strict; Path=/v1; Max-Age=604800${secure ? "; Secure" : ""}`);
      return response;
    }
    if (!isPublicRead(path, method)) requireAuth(request);
    if (path === "/v1/imports" && method === "POST") {
      if (activeImports >= 2) throw new APIError(503, "导入繁忙，请稍后重试");
      activeImports++;
      try {
        const result = await importStory(request, config, store);
        return json({ imported: result.imported, story: detail(result.story) }, result.imported ? 201 : 200);
      } finally { activeImports--; }
    }
    if (path === "/v1/session" && method === "DELETE") {
      const session = sessionCookie(request);
      if (session) store.deleteSession(hash(config.apiToken + ":" + session));
      return new Response(null, { status: 204, headers: { "Set-Cookie": "fablo_session=; HttpOnly; SameSite=Strict; Path=/v1; Max-Age=0" } });
    }
    if (path === "/v1/stories" && method === "GET") {
      const limit = Number(url.searchParams.get("limit") ?? 50);
      if (!Number.isInteger(limit) || limit < 1 || limit > 100) throw new APIError(400, "limit 必须在 1 到 100 之间");
      let cursor: { createdAt: string; id: string } | null = null;
      if (url.searchParams.has("cursor")) {
        try {
          const parsed = object(JSON.parse(Buffer.from(text(url.searchParams.get("cursor"), "cursor", 512), "base64url").toString()));
          cursor = { createdAt: text(parsed.createdAt, "createdAt", 40), id: uuid(parsed.id) };
          if (!Number.isFinite(Date.parse(cursor.createdAt))) throw new Error();
        } catch { throw new APIError(400, "无效的分页游标"); }
      }
      return store.db.transaction(() => {
        const rows = store.pageStories(limit + 1, cursor), stories = rows.slice(0, limit), last = stories.at(-1);
        return json({ stories: stories.map(summary), revision: store.revision(), nextCursor: rows.length > limit && last ? Buffer.from(JSON.stringify({ createdAt: last.createdAt, id: last.id })).toString("base64url") : null });
      })();
    }
    if (path === "/v1/jobs" && method === "GET") return json({ jobs: store.listJobs() });
    if (path === "/v1/generations" && method === "POST") {
      const requestBody = parseRequest(await body(request));
      const key = request.headers.get("idempotency-key");
      if (!key || !/^[A-Za-z0-9_-]{8,128}$/.test(key)) throw new APIError(400, "需要 8–128 位的 Idempotency-Key");
      return json(store.enqueue("story", crypto.randomUUID(), { request: requestBody }, `story:${key}`, config), 202);
    }
    const jobRoute = /^\/v1\/jobs\/([^/]+)(\/retry)?$/.exec(path);
    if (jobRoute) {
      const id = uuid(jobRoute[1]);
      if (method === "POST" && jobRoute[2]) return json(store.retry(id, config), 202);
      if (!jobRoute[2] && method === "GET") {
        const job = store.getJob(id);
        if (!job) throw new APIError(404, "任务不存在");
        return json(job);
      }
      if (!jobRoute[2] && method === "DELETE") { store.dismiss(id); return new Response(null, { status: 204 }); }
    }
    const storyRoute = /^\/v1\/stories\/([^/]+)(?:\/(.*))?$/.exec(path);
    if (storyRoute) {
      const id = uuid(storyRoute[1]), action = storyRoute[2], story = requiredStory(id);
      if (!action && method === "GET") return json(detail(story));
      if (action === "status" && method === "GET") return json(summary(story));
      if (action === "reading-status" && method === "POST") {
        const status = object(await body(request)).status;
        if (status !== "unread" && status !== "reading" && status !== "read") throw new APIError(400, "无效的阅读状态");
        return json(summary(store.setReadingStatus(id, status)));
      }
      if (!action && method === "DELETE") {
        store.deleteStory(id);
        // UUID directories are controlled by the server; never use a caller-supplied path.
        await rm(join(config.dataDir, "assets", id), { force: true, recursive: true });
        return new Response(null, { status: 204 });
      }
      if ((action === "cover" || action === "audio") && method === "POST") return json(store.enqueue(action, id, {}, undefined, config), 202);
      const asset = /^assets\/(cover|audio|timeline)$/.exec(action ?? "");
      if (asset && (method === "GET" || method === "HEAD")) {
        const name = asset[1] as "cover" | "audio" | "timeline";
        const requestedVersion = url.searchParams.get("version");
        const version = requestedVersion ? uuid(requestedVersion) : (name === "cover" ? story.coverVersion : story.audioVersion);
        const snapshot = { ...story, ...(name === "cover" ? { coverVersion: version } : { audioVersion: version }) };
        const file = assetPath(config.dataDir, snapshot, name);
        if (!file) throw new APIError(409, "资源尚未生成完成");
        return fileResponse(request, file, { cover: "image/jpeg", audio: "audio/mp4", timeline: "application/json" }[name], version!);
      }
      const analysis = /^analyses\/(\d+)$/.exec(action ?? "");
      if (analysis && (method === "GET" || method === "POST")) {
        const index = Number(analysis[1]);
        if (!Number.isSafeInteger(index) || index >= sentences(story.content).length) throw new APIError(400, "句子编号超出范围");
        const cached = story.analyses[String(index)];
        if (method === "GET") {
          if (!cached) throw new APIError(404, "句子解析尚未生成");
          return json({ analysis: cached });
        }
        return cached ? json({ analysis: cached }) : json({ job: store.enqueue("analysis", id, { index }, undefined, config) }, 202);
      }
    }
    throw new APIError(404, "接口不存在");
  }
  return async (request: Request): Promise<Response> => {
    const url = new URL(request.url), origin = request.headers.get("origin");
    const trustedOrigin = origin !== null && allowedOrigin(origin, url);
    const publicRead = isPublicRead(routePath(url), request.method === "OPTIONS" ? request.headers.get("access-control-request-method") ?? "" : request.method);
    let response: Response;
    try {
      if (origin && !trustedOrigin && !publicRead) throw new APIError(403, "不允许的网页来源");
      response = request.method === "OPTIONS" ? new Response(null, { status: 204 }) : await route(request, url);
    } catch (error) {
      if (!(error instanceof APIError)) console.error(JSON.stringify({ event: "request.failed", errorType: error instanceof Error ? error.name : "unknown" }));
      response = json({ error: { message: error instanceof APIError ? error.message : "服务暂时不可用" } }, error instanceof APIError ? error.status : 500);
    }
    response.headers.set("X-Content-Type-Options", "nosniff");
    if (!response.headers.has("Cache-Control")) response.headers.set("Cache-Control", "no-store");
    response.headers.set("Vary", request.method === "OPTIONS" ? "Origin, Access-Control-Request-Method" : "Origin");
    if (origin && (trustedOrigin || publicRead)) {
      response.headers.set("Access-Control-Allow-Origin", origin);
      if (trustedOrigin) response.headers.set("Access-Control-Allow-Credentials", "true");
      response.headers.set("Access-Control-Allow-Methods", trustedOrigin ? "GET,HEAD,POST,DELETE,OPTIONS" : "GET,HEAD,OPTIONS");
      response.headers.set("Access-Control-Allow-Headers", "Authorization,Content-Type,Idempotency-Key,Range,If-None-Match,If-Range");
      response.headers.set("Access-Control-Expose-Headers", "ETag,Content-Range,Accept-Ranges");
    }
    return response;
  };
}

if (import.meta.main) {
  const config = loadConfig(), store = new Store(config.dataDir);
  let server: ReturnType<typeof Bun.serve>;
  try {
    server = Bun.serve({ hostname: config.host, port: config.port, maxRequestBodySize: IMPORT_BODY_LIMIT, idleTimeout: 30, fetch: createHandler(config, store) });
  } catch (error) {
    store.close();
    throw error;
  }
  const controller = new AbortController();
  const worker = new Worker(store, config);
  const workerDone = worker.runLoop(controller.signal);
  console.info(JSON.stringify({ event: "service.started", hostname: config.host, port: server.port }));
  let stopping = false;
  const forceExit = (reason: "signal" | "timeout"): never => {
    console.error(JSON.stringify({ event: "service.shutdown_forced", reason }));
    process.exit(1);
  };
  const stop = async (signal: "SIGINT" | "SIGTERM"): Promise<void> => {
    if (stopping) forceExit("signal");
    stopping = true;
    console.info(JSON.stringify({ event: "service.stopping", signal }));
    const deadline = setTimeout(() => forceExit("timeout"), 10000);
    try {
      controller.abort();
      // Drain HTTP requests and settle the active job before closing their shared DB.
      await Promise.all([server.stop(), workerDone]);
      store.close();
      console.info(JSON.stringify({ event: "service.stopped" }));
      // --watch keeps its file watchers alive after the API and worker have stopped.
      process.exit(0);
    } catch (error) {
      console.error(JSON.stringify({ event: "service.shutdown_failed", errorType: error instanceof Error ? error.name : "unknown" }));
      process.exit(1);
    } finally { clearTimeout(deadline); }
  };
  process.on("SIGINT", () => { void stop("SIGINT"); });
  process.on("SIGTERM", () => { void stop("SIGTERM"); });
}
