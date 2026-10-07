import type { ChunkRole, Pos } from "./theme";

export type Word = { s: string; r?: string; ro?: string; p: Pos; g?: string };
export type Chunk = { role: ChunkRole; w: Word[] };
export type Sentence = { zh: string; c: Chunk[] };

// The sample story the video "generates": JA · N4 · 童话寓言.
export const story = {
  title: "海を見に行った猫",
  titleZh: "去看海的小猫",
  summaryZh: "一只住在小镇上的猫，第一次走到海边。",
  tags: ["JA · N4", "童话寓言"],
};

export const sentences: Sentence[] = [
  {
    zh: "一只小猫去看海了。",
    c: [
      {
        role: "subject",
        w: [
          { s: "小さな", r: "ちいさな", ro: "chiisana", p: "adjective", g: "小小的" },
          { s: "猫", r: "ねこ", ro: "neko", p: "noun", g: "猫" },
          { s: "が", ro: "ga", p: "particle", g: "主格助词" },
        ],
      },
      {
        role: "adverbial",
        w: [
          { s: "海", r: "うみ", ro: "umi", p: "noun", g: "大海" },
          { s: "を", ro: "o", p: "particle", g: "宾格助词" },
          { s: "見", r: "み", ro: "mi", p: "verb", g: "看" },
          { s: "に", ro: "ni", p: "particle", g: "目的" },
        ],
      },
      {
        role: "predicate",
        w: [
          { s: "行きました", r: "いきました", ro: "ikimashita", p: "verb", g: "去了" },
          { s: "。", p: "punctuation" },
        ],
      },
    ],
  },
  {
    zh: "海浪的声音非常温柔。",
    c: [
      {
        role: "topic",
        w: [
          { s: "波", r: "なみ", ro: "nami", p: "noun" },
          { s: "の", ro: "no", p: "particle" },
          { s: "音", r: "おと", ro: "oto", p: "noun" },
          { s: "は", ro: "wa", p: "particle" },
        ],
      },
      { role: "adverbial", w: [{ s: "とても", ro: "totemo", p: "adverb" }] },
      {
        role: "predicate",
        w: [
          { s: "優しかった", r: "やさしかった", ro: "yasashikatta", p: "adjective" },
          { s: "。", p: "punctuation" },
        ],
      },
    ],
  },
  {
    zh: "小猫在沙滩上慢慢闭上了眼睛。",
    c: [
      {
        role: "topic",
        w: [
          { s: "猫", r: "ねこ", ro: "neko", p: "noun" },
          { s: "は", ro: "wa", p: "particle" },
        ],
      },
      {
        role: "adverbial",
        w: [
          { s: "砂", r: "すな", ro: "suna", p: "noun" },
          { s: "の", ro: "no", p: "particle" },
          { s: "上", r: "うえ", ro: "ue", p: "noun" },
          { s: "で", ro: "de", p: "particle" },
        ],
      },
      { role: "adverbial", w: [{ s: "ゆっくり", ro: "yukkuri", p: "adverb" }] },
      {
        role: "object",
        w: [
          { s: "目", r: "め", ro: "me", p: "noun" },
          { s: "を", ro: "o", p: "particle" },
        ],
      },
      {
        role: "predicate",
        w: [
          { s: "閉じました", r: "とじました", ro: "tojimashita", p: "verb" },
          { s: "。", p: "punctuation" },
        ],
      },
    ],
  },
];

export const roleLabel: Record<ChunkRole, string> = {
  topic: "主题",
  subject: "主语",
  object: "宾语",
  predicate: "谓语",
  complement: "补语",
  modifier: "修饰",
  adverbial: "状语",
  connector: "连接",
};

export const posLabel: Record<Pos, string> = {
  noun: "名词",
  verb: "动词",
  particle: "助词",
  adjective: "形容词",
  adverb: "副词",
  punctuation: "标点",
};

/** Number of spoken (non-punctuation) words in a sentence. */
export const spokenCount = (s: Sentence) =>
  s.c.flatMap((c) => c.w).filter((w) => w.p !== "punctuation").length;
