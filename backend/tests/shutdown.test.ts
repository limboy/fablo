import { expect, test } from "bun:test";
import { cpSync, mkdtempSync, rmSync } from "node:fs";
import { appendFile } from "node:fs/promises";
import { once } from "node:events";
import { connect } from "node:net";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import { setTimeout as delay } from "node:timers/promises";
import { Store } from "../src/store";
import { request } from "./fixtures";

async function startService(watch: boolean, gatewayURL = "http://127.0.0.1:9") {
  const directory = mkdtempSync(join(tmpdir(), "fablo-shutdown-"));
  // Only copy source: never load the developer's .env or use their database.
  cpSync(resolve(import.meta.dir, "../src"), join(directory, "src"), { recursive: true });
  const reservation = Bun.serve({ hostname: "127.0.0.1", port: 0, fetch: () => new Response() });
  const port = reservation.port!;
  await reservation.stop(true);
  const token = "shutdown-test-" + crypto.randomUUID();
  const child = Bun.spawn([process.execPath, "--no-env-file", ...(watch ? ["--watch", "--no-clear-screen"] : []), join(directory, "src/server.ts")], {
    cwd: directory,
    env: { PATH: process.env.PATH, HOST: "127.0.0.1", PORT: String(port), DATA_DIR: join(directory, "data"), FABLO_API_TOKEN: token, AI_GATEWAY_KEY: "mock-key", AI_GATEWAY_URL: gatewayURL },
    stdout: "pipe", stderr: "pipe",
  });
  let output = "";
  const collect = async (stream: ReadableStream<Uint8Array>) => {
    for await (const chunk of stream) output += Buffer.from(chunk).toString();
  };
  const collected = Promise.all([collect(child.stdout), collect(child.stderr)]);
  const until = async (check: () => boolean) => {
    for (let i = 0; i < 150; i++) {
      if (check()) return;
      if (child.exitCode !== null) break;
      await delay(20);
    }
    throw new Error(`Service did not reach the expected state:\n${output}`);
  };
  const close = async () => {
    if (child.exitCode === null) child.kill("SIGKILL");
    await child.exited;
    await collected;
    rmSync(directory, { recursive: true, force: true });
  };
  const exited = async (timeout = 2000) => {
    let timer: ReturnType<typeof setTimeout> | undefined;
    try {
      return await Promise.race([child.exited, new Promise<never>((_, reject) => {
        timer = setTimeout(() => reject(new Error(`Service did not exit:\n${output}`)), timeout);
      })]);
    } finally { clearTimeout(timer); }
  };
  try { await until(() => output.includes('"event":"service.started"')); }
  catch (error) { await close(); throw error; }
  const api = (path: string, options: RequestInit = {}) => fetch(`http://127.0.0.1:${port}${path}`, {
    ...options, headers: { Authorization: `Bearer ${token}`, "Content-Type": "application/json", ...options.headers },
  });
  return { child, directory, port, token, until, exited, close, api, logs: () => output };
}

for (const watch of [false, true]) {
  for (const signal of ["SIGINT", "SIGTERM"] as const) {
    test(`${signal} exits cleanly with watch=${watch}`, async () => {
      const service = await startService(watch);
      try {
        service.child.kill(signal);
        expect(await service.exited()).toBe(0);
        expect(service.logs()).toContain('"event":"service.stopped"');
      } finally { await service.close(); }
    });
  }
}

test("watch mode still reloads source and can then be stopped", async () => {
  const service = await startService(true);
  try {
    await appendFile(join(service.directory, "src/server.ts"), "\n// Trigger a watch restart.\n");
    await service.until(() => service.logs().split('"event":"service.started"').length === 3);
    expect((await service.api("/health")).status).toBe(200);
    service.child.kill("SIGINT");
    expect(await service.exited()).toBe(0);
  } finally { await service.close(); }
});

test("Ctrl+C in watch mode settles the active job and preserves queued work", async () => {
  let entered = false, release!: () => void;
  const blocked = new Promise<void>(resolve => { release = resolve; });
  const gateway = Bun.serve({ hostname: "127.0.0.1", port: 0, async fetch() {
    entered = true;
    await blocked;
    return Response.json({});
  } });
  let service: Awaited<ReturnType<typeof startService>> | undefined;
  try {
    service = await startService(true, `http://127.0.0.1:${gateway.port}`);
    const generate = async () => {
      const response = await service!.api("/v1/generations", { method: "POST", headers: { "Idempotency-Key": crypto.randomUUID() }, body: JSON.stringify(request) });
      expect(response.status).toBe(202);
      return response.json() as Promise<{ id: string }>;
    };
    const active = await generate();
    await service.until(() => entered);
    const queued = await generate();
    service.child.kill("SIGINT");
    expect(await service.exited()).toBe(0);
    const store = new Store(join(service.directory, "data"));
    try {
      expect(store.getJob(active.id)?.status).toBe("failed");
      expect(store.getJob(queued.id)?.status).toBe("queued");
    } finally { store.close(); }
  } finally {
    release();
    await service?.close();
    await gateway.stop(true);
  }
});

for (const force of ["signal", "timeout"] as const) {
  test(`a stalled HTTP request cannot block shutdown: ${force}`, async () => {
    const service = await startService(true);
    const socket = connect(service.port, "127.0.0.1");
    socket.on("error", () => {});
    try {
      await once(socket, "connect");
      // An incomplete JSON body keeps a request in flight while HTTP drains.
      socket.write(`POST /v1/generations HTTP/1.1\r\nHost: localhost\r\nAuthorization: Bearer ${service.token}\r\nContent-Type: application/json\r\nContent-Length: 1024\r\n\r\n{`);
      await delay(100);
      service.child.kill("SIGINT");
      await service.until(() => service.logs().includes('"event":"service.stopping"'));
      expect(service.child.exitCode).toBeNull();
      if (force === "signal") service.child.kill("SIGINT");
      expect(await service.exited(force === "timeout" ? 12000 : 2000)).toBe(1);
      expect(service.logs()).toContain(`"event":"service.shutdown_forced","reason":"${force}"`);
    } finally {
      socket.destroy();
      await service.close();
    }
  }, 15000);
}
