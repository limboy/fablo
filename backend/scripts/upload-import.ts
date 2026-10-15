import { parseArgs } from "node:util";
import { resolve, join, relative, isAbsolute } from "node:path";
import { rename } from "node:fs/promises";
import { IMPORT_BODY_LIMIT } from "../src/request-body";

export async function uploadBundle(directory: string, server: string, token: string) {
  const base = new URL(server);
  if (base.username || base.password || base.search || base.hash || (base.protocol !== "https:" && !(base.protocol === "http:" && ["127.0.0.1", "localhost", "[::1]"].includes(base.hostname)))) throw new Error("Use HTTPS or a loopback HTTP test server");
  if (!token) throw new Error("Set FABLO_API_TOKEN in backend/.env or the environment");
  const endpoint = new URL(base.href.replace(/\/$/, "") + "/v1/imports");
  const root = resolve(directory);
  const bundle = await Bun.file(join(root, "bundle.json")).json() as { format: string; errors: unknown[]; stories: { id: string; directory: string; title: string; audio: boolean; cover: boolean }[] };
  if (bundle.format !== "fablo-import-bundle-v1" || !Array.isArray(bundle.stories) || bundle.errors?.length) throw new Error("Bundle is invalid or contains preparation failures");
  const report = { server: base.href, imported: 0, existing: 0, stories: [] as { id: string; title: string; imported: boolean }[] };
  for (const [index, entry] of bundle.stories.entries()) {
    const path = resolve(root, entry.directory), rel = relative(root, path);
    if (!rel || rel.startsWith("..") || isAbsolute(rel)) throw new Error("Invalid bundle directory");
    const form = new FormData();
    form.set("story", await Bun.file(join(path, "story.json")).text());
    if (entry.cover) form.set("cover", Bun.file(join(path, "cover.jpg"), { type: "image/jpeg" }), "cover.jpg");
    if (entry.audio) {
      form.set("audio", Bun.file(join(path, "audio.m4a"), { type: "audio/mp4" }), "audio.m4a");
      form.set("timeline", await Bun.file(join(path, "timeline.json")).text());
    }
    const size = (await new Response(form).arrayBuffer()).byteLength;
    if (size > IMPORT_BODY_LIMIT) throw new Error(`Upload exceeds 20 MiB: ${entry.title}`);
    let result: { imported: boolean; story: { id: string } } | undefined;
    for (let attempt = 0; attempt < 4; attempt++) {
      try {
        const response = await fetch(endpoint, { method: "POST", headers: { Authorization: `Bearer ${token}` }, body: form, redirect: "error", signal: AbortSignal.timeout(120000) });
        if (!response.ok) {
          if ([429, 502, 503, 504].includes(response.status) && attempt < 3) { await response.body?.cancel(); await Bun.sleep(1000 * 2 ** attempt); continue; }
          const detail = await response.json().catch(() => null) as { error?: { message?: string } } | null;
          throw new Error(`HTTP ${response.status}: ${detail?.error?.message ?? "Import failed (check Nginx upload limits and service deployment)"}`);
        }
        result = await response.json() as typeof result;
        break;
      } catch (error) {
        if (attempt === 3 || (error instanceof Error && error.message.startsWith("HTTP "))) throw error;
        await Bun.sleep(1000 * 2 ** attempt);
      }
    }
    if (!result || result.story.id.toLowerCase() !== entry.id.toLowerCase()) throw new Error("Server returned an unexpected imported story");
    if (result.imported) report.imported++; else report.existing++;
    report.stories.push({ id: result.story.id, title: entry.title, imported: result.imported });
    const reportPath = join(root, "upload-report.json");
    await Bun.write(reportPath + ".tmp", JSON.stringify(report, null, 2) + "\n");
    await rename(reportPath + ".tmp", reportPath);
    console.info(`[${index + 1}/${bundle.stories.length}] ${result.imported ? "imported" : "already exists"}: ${entry.title}`);
  }
  console.info(JSON.stringify({ imported: report.imported, existing: report.existing, total: report.stories.length }));
  return report;
}

if (import.meta.main) {
  const { values, positionals } = parseArgs({ args: Bun.argv.slice(2), allowPositionals: true, options: { server: { type: "string" } } });
  if (positionals.length !== 1) throw new Error("Usage: bun run import:upload /path/to/prepared-bundle --server https://fablo.example.com");
  const server = values.server ?? process.env.PUBLIC_ORIGIN;
  if (!server) throw new Error("Pass --server or set PUBLIC_ORIGIN");
  await uploadBundle(positionals[0]!, server, process.env.FABLO_API_TOKEN ?? "");
}
