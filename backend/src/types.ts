export class APIError extends Error {
  constructor(public status: number, message: string) { super(message); }
}

export const genres = ["日常生活", "童话寓言", "奇幻冒险", "科幻", "悬疑推理", "旅行见闻", "美食", "校园", "职场", "历史人物", "自然科普", "新闻报道", "对话", "演讲"];
export const levels = { en: ["A1", "A2", "B1", "B2", "C1"], ja: ["N5", "N4", "N3", "N2", "N1"] };
export const roles = ["topic", "subject", "object", "predicate", "complement", "modifier", "adverbial", "connector", "other"];
export const partsOfSpeech = ["noun", "pronoun", "verb", "adjective", "adverb", "particle", "auxiliary", "conjunction", "determiner", "preposition", "interjection", "number", "punctuation", "other"];
export type Language = keyof typeof levels;
export interface GenerationRequest { language: Language; level: string; genre: string; length: "short" | "medium" | "long"; topic: string }
export interface Word { s: string; r: string; ro: string; p: string; g: string }
export interface Sentence { text: string; zh: string; c: { role: string; w: Word[] }[] }
export interface StoryContent { title: string; titleZh: string; summaryZh: string; coverPrompt: string; paragraphs: { sentences: Sentence[] }[] }
export interface Analysis {
  structure: string;
  grammar: { point: string; explanation: string; example: string; exampleZh: string }[];
  vocabulary: { word: string; reading: string; meaning: string; note: string }[];
  nuance: string;
}
export type AssetStatus = "missing" | "queued" | "running" | "ready" | "failed";
export interface StoryRecord {
  id: string; createdAt: string; updatedAt: string; language: Language; level: string; genre: string;
  generationRequest: GenerationRequest | null;
  content: StoryContent; analyses: Record<string, Analysis>;
  coverStatus: AssetStatus; audioStatus: AssetStatus;
  coverVersion: string | null; audioVersion: string | null;
}
export interface Timeline {
  version: number; duration: number; wordStarts: (number | null)[][];
  sentenceStarts: number[]; sentenceEnds: number[]; isAligned: boolean;
}
export type JobKind = "story" | "cover" | "audio" | "analysis";
export interface Job {
  id: string; kind: JobKind; storyId: string; status: "queued" | "running" | "completed" | "failed";
  request: GenerationRequest | null; sentenceIndex: number | null;
  createdAt: string; updatedAt: string; error: string | null; attempts: number;
}

export function object(value: unknown): Record<string, unknown> {
  if (typeof value !== "object" || value === null || Array.isArray(value)) throw new APIError(400, "需要 JSON 对象");
  return value as Record<string, unknown>;
}
export function text(value: unknown, field: string, max = 10000, empty = true): string {
  if (typeof value !== "string" || value.length > max || (!empty && !value.trim())) throw new APIError(400, `无效的 ${field}`);
  return value;
}
function list(value: unknown, field: string, max: number, min = 0): unknown[] {
  if (!Array.isArray(value) || value.length > max || value.length < min) throw new APIError(400, `无效的 ${field}`);
  return value;
}
export function uuid(value: unknown): string {
  const id = text(value, "id", 36);
  if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(id)) throw new APIError(400, "无效的 UUID");
  return id.toLowerCase();
}
export function parseRequest(value: unknown): GenerationRequest {
  const r = object(value);
  if (r.language !== "en" && r.language !== "ja") throw new APIError(400, "仅支持英语和日语");
  if (!levels[r.language].includes(String(r.level)) || !genres.includes(String(r.genre))) throw new APIError(400, "无效的等级或类型");
  if (r.length !== "short" && r.length !== "medium" && r.length !== "long") throw new APIError(400, "无效的篇幅");
  return { language: r.language, level: String(r.level), genre: String(r.genre), length: r.length, topic: text(r.topic ?? "", "topic", 2000).trim() };
}
export function parseContent(value: unknown): StoryContent {
  const c = object(value);
  let wordCount = 0;
  const content: StoryContent = {
    title: text(c.title, "title", 500, false), titleZh: text(c.titleZh, "titleZh", 500),
    summaryZh: text(c.summaryZh, "summaryZh", 2000), coverPrompt: text(c.coverPrompt, "coverPrompt", 5000),
    paragraphs: list(c.paragraphs, "paragraphs", 100, 1).map(p => ({
      sentences: list(object(p).sentences, "sentences", 500, 1).map(v => {
        const s = object(v);
        return {
          text: text(s.text, "text", 10000, false), zh: text(s.zh, "zh", 10000),
          c: list(s.c, "chunks", 1000, 1).map(v => {
            const chunk = object(v);
            if (!roles.includes(String(chunk.role))) throw new APIError(400, "无效的成分");
            return { role: String(chunk.role), w: list(chunk.w, "words", 1000, 1).map(v => {
              const w = object(v);
              if (++wordCount > 30000 || !partsOfSpeech.includes(String(w.p))) throw new APIError(400, "词数过多或词性无效");
              return { s: text(w.s, "surface", 1000, false), r: text(w.r, "reading", 1000), ro: text(w.ro, "romaji", 1000), p: String(w.p), g: text(w.g, "gloss", 2000) };
            }) };
          }),
        };
      }),
    })),
  };
  if (sentences(content).length > 1000) throw new APIError(400, "句数过多");
  return content;
}
export function parseAnalysis(value: unknown): Analysis {
  const a = object(value);
  return {
    structure: text(a.structure, "structure"), nuance: text(a.nuance, "nuance"),
    grammar: list(a.grammar, "grammar", 30).map(v => {
      const g = object(v);
      return { point: text(g.point, "point"), explanation: text(g.explanation, "explanation"), example: text(g.example, "example"), exampleZh: text(g.exampleZh, "exampleZh") };
    }),
    vocabulary: list(a.vocabulary, "vocabulary", 100).map(v => {
      const w = object(v);
      return { word: text(w.word, "word"), reading: text(w.reading, "reading"), meaning: text(w.meaning, "meaning"), note: text(w.note, "note") };
    }),
  };
}
export function sentences(content: StoryContent): Sentence[] { return content.paragraphs.flatMap(p => p.sentences); }
export function words(content: StoryContent): string[][] { return sentences(content).map(s => s.c.flatMap(c => c.w.map(w => w.s))); }
export function parseTimeline(value: unknown, content: StoryContent): Timeline {
  const t = object(value), count = sentences(content).length;
  if (!Number.isInteger(t.version) || Number(t.version) < 1 || typeof t.duration !== "number" || !Number.isFinite(t.duration) || t.duration <= 0 || t.duration > 86400 || typeof t.isAligned !== "boolean") throw new APIError(400, "无效的音频时间轴");
  const duration = t.duration;
  const time = (v: unknown) => { if (typeof v !== "number" || !Number.isFinite(v) || v < 0 || v > duration) throw new APIError(400, "时间轴超出音频范围"); return v; };
  const starts = list(t.sentenceStarts, "sentenceStarts", count, count).map(time);
  const ends = list(t.sentenceEnds, "sentenceEnds", count, count).map(time);
  const surfaces = words(content);
  const wordStarts = list(t.wordStarts, "wordStarts", count, count).map((v, i) => list(v, "wordStarts[]", surfaces[i]!.length, surfaces[i]!.length).map(v => v === null ? null : time(v)));
  starts.forEach((start, i) => {
    if ((i > 0 && start < starts[i - 1]!) || ends[i]! < start || (i + 1 < count && ends[i]! > starts[i + 1]!)) throw new APIError(400, "句子时间轴顺序无效");
    let previous = start;
    for (const word of wordStarts[i]!) {
      if (word === null) continue;
      if (word < previous || word > ends[i]!) throw new APIError(400, "单词时间轴顺序无效");
      previous = word;
    }
  });
  return { version: Number(t.version), duration, sentenceStarts: starts, sentenceEnds: ends, wordStarts, isAligned: t.isAligned };
}
