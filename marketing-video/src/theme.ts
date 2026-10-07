import { loadFont as loadFraunces } from "@remotion/google-fonts/Fraunces";

// Mirrors Fablo/Views/Theme.swift (light mode).
export const C = {
  paper: "#F9F9F0",
  card: "#F0F0E3",
  raised: "#FFFFFC",
  ink: "#1D1D1B",
  muted: "#5F5F58",
  accent: "#D9774B",
  accentDeep: "#B85A32",
};

export const chunkColor = {
  subject: "#E6F0FB",
  object: "#E6F0FB",
  topic: "#E6F0FB",
  predicate: "#FCE2D0",
  modifier: "#F6F6F2",
  complement: "#EEE7F8",
  adverbial: "#E4F3E6",
  connector: null,
} as const;

export const posColor = {
  noun: "#FFF27A",
  verb: "#BFE09A",
  particle: "#A6DBE2",
  adjective: "#F8C3D1",
  adverb: "#D6C8F2",
  punctuation: null,
} as const;

export type ChunkRole = keyof typeof chunkColor;
export type Pos = keyof typeof posColor;

const { fontFamily: fraunces } = loadFraunces("normal", {
  weights: ["600", "700", "900"],
  subsets: ["latin"],
});

// CJK comes from the system (PingFang / Hiragino on macOS), like the app itself.
export const F = {
  ui: `-apple-system, "SF Pro Text", "PingFang SC", "Hiragino Sans", "Helvetica Neue", sans-serif`,
  ja: `"Hiragino Sans", "Hiragino Kaku Gothic ProN", "PingFang SC", sans-serif`,
  serif: `${fraunces}, "New York", Georgia, serif`,
  display: `${fraunces}, "PingFang SC", serif`,
};
