import { resolve } from "node:path";

export interface Config {
  host: string;
  port: number;
  dataDir: string;
  apiToken: string;
  gatewayKey: string;
  gatewayURL: string;
  models: { text: string; image: string; speech: string; transcription: string };
  origins: string[];
  publicOrigin: string | undefined;
  dailyJobLimit: number;
  maxQueuedJobs: number;
  ffmpeg: string;
  ffprobe: string;
}

export function loadConfig(env: Record<string, string | undefined> = process.env): Config {
  const apiToken = env.FABLO_API_TOKEN ?? "";
  if (apiToken.length < 32 || apiToken.startsWith("replace-")) throw new Error("Set FABLO_API_TOKEN to a random token of at least 32 characters");
  const gatewayKey = env.AI_GATEWAY_KEY ?? "";
  if (!gatewayKey || gatewayKey.startsWith("replace-")) throw new Error("Set AI_GATEWAY_KEY");
  const integer = (key: string, fallback: number, max = 100000) => {
    const value = Number(env[key] ?? fallback);
    if (!Number.isSafeInteger(value) || value < 1 || value > max) throw new Error(`Invalid ${key}`);
    return value;
  };
  const origin = (value: string) => {
    const url = new URL(value);
    if (!["https:", "http:"].includes(url.protocol) || url.origin !== value) throw new Error(`Expected an origin: ${value}`);
    return value;
  };
  const gatewayURL = new URL(env.AI_GATEWAY_URL || "https://ai-gateway.vercel.sh");
  if (gatewayURL.protocol !== "https:" && !["127.0.0.1", "localhost", "[::1]"].includes(gatewayURL.hostname)) throw new Error("AI_GATEWAY_URL requires HTTPS");
  return {
    host: env.HOST || "127.0.0.1", port: integer("PORT", 3000, 65535),
    dataDir: resolve(env.DATA_DIR || "./data"), apiToken, gatewayKey,
    gatewayURL: gatewayURL.href.replace(/\/$/, ""),
    models: {
      text: env.TEXT_MODEL || "google/gemini-3.8-flash",
      image: env.IMAGE_MODEL || "openai/gpt-image-2.5-sunburst",
      speech: env.SPEECH_MODEL || "google/gemini-3.8-flash-tts",
      transcription: env.TRANSCRIPTION_MODEL || "microsoft/mai-transcribe-2",
    },
    origins: (env.ALLOWED_ORIGINS || "").split(",").map(s => s.trim()).filter(Boolean).map(origin),
    publicOrigin: env.PUBLIC_ORIGIN ? origin(env.PUBLIC_ORIGIN) : undefined,
    dailyJobLimit: integer("DAILY_JOB_LIMIT", 100), maxQueuedJobs: integer("MAX_QUEUED_JOBS", 30),
    ffmpeg: env.FFMPEG_PATH || "ffmpeg", ffprobe: env.FFPROBE_PATH || "ffprobe",
  };
}
