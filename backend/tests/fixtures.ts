import { mkdtempSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { loadConfig } from "../src/config";
import type { AIProvider } from "../src/gateway";
import type { Analysis, StoryContent, StoryRecord } from "../src/types";

export const request = { language: "en" as const, level: "A2", genre: "日常生活", length: "short" as const, topic: "morning" };
export const content: StoryContent = {
  title: "A Good Morning", titleZh: "美好的早晨", summaryZh: "问候新的一天。", coverPrompt: "A sunny morning",
  paragraphs: [{ sentences: [
    { text: "Hello world.", zh: "你好，世界。", c: [{ role: "predicate", w: [
      { s: "Hello", r: "", ro: "", p: "interjection", g: "你好" },
      { s: "world", r: "", ro: "", p: "noun", g: "世界" },
      { s: ".", r: "", ro: "", p: "punctuation", g: "" },
    ] }] },
    { text: "Good morning.", zh: "早上好。", c: [{ role: "other", w: [
      { s: "Good", r: "", ro: "", p: "adjective", g: "好的" },
      { s: "morning", r: "", ro: "", p: "noun", g: "早晨" },
      { s: ".", r: "", ro: "", p: "punctuation", g: "" },
    ] }] },
  ] }],
};
export const analysis: Analysis = { structure: "这是一个问候语。", grammar: [{ point: "问候", explanation: "用于打招呼。", example: "Hello, Tom.", exampleZh: "你好，汤姆。" }], vocabulary: [{ word: "world", reading: "/wɜːld/", meaning: "世界", note: "" }], nuance: "" };
export function config() {
  return loadConfig({ FABLO_API_TOKEN: "test-token-" + "a".repeat(40), AI_GATEWAY_KEY: "fake-key", DATA_DIR: mkdtempSync(join(tmpdir(), "fablo-test-")), PUBLIC_ORIGIN: "https://fablo.example.com", ALLOWED_ORIGINS: "https://web.example.com" });
}
export function record(id: string = crypto.randomUUID()): StoryRecord {
  const now = new Date().toISOString();
  return { id, createdAt: now, updatedAt: now, language: "en", level: "A2", genre: "日常生活", generationRequest: { ...request }, content: structuredClone(content), analyses: {}, coverStatus: "missing", audioStatus: "missing", coverVersion: null, audioVersion: null };
}
export function wav(): Uint8Array {
  const samples = 22050, data = Buffer.alloc(44 + samples * 2);
  data.write("RIFF", 0); data.writeUInt32LE(data.length - 8, 4); data.write("WAVEfmt ", 8);
  data.writeUInt32LE(16, 16); data.writeUInt16LE(1, 20); data.writeUInt16LE(1, 22);
  data.writeUInt32LE(22050, 24); data.writeUInt32LE(44100, 28); data.writeUInt16LE(2, 32); data.writeUInt16LE(16, 34);
  data.write("data", 36); data.writeUInt32LE(samples * 2, 40);
  return data;
}
export function provider(overrides: Partial<AIProvider> = {}): AIProvider {
  return {
    structured: async (_system, _user, name) => structuredClone(name === "story" ? content : analysis),
    image: async () => Buffer.from("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aY1cAAAAASUVORK5CYII=", "base64"),
    speech: async () => wav(),
    transcribe: async () => [
      { text: "Hello", offsetMilliseconds: 0, durationMilliseconds: 150 },
      { text: "world", offsetMilliseconds: 200, durationMilliseconds: 150 },
      { text: "Good", offsetMilliseconds: 500, durationMilliseconds: 150 },
      { text: "morning", offsetMilliseconds: 700, durationMilliseconds: 200 },
    ],
    ...overrides,
  };
}
