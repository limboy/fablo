import type React from "react";
import { C, chunkColor, F, posColor } from "./theme";
import { posLabel, roleLabel, sentences, story } from "./story";
import { LighthouseCover, RainCover, SeaCover, SentenceFlow, Sparkle, Spinner, TagLabel } from "./ui";

// Recreations of Fablo's SwiftUI screens, in iPhone points.

const NavBar: React.FC<{ title?: string; left?: React.ReactNode; right?: React.ReactNode }> = ({
  title,
  left,
  right,
}) => (
  <div
    style={{
      position: "absolute",
      top: 54,
      left: 0,
      right: 0,
      height: 44,
      display: "flex",
      alignItems: "center",
      justifyContent: "space-between",
      padding: "0 16px",
      zIndex: 50,
    }}
  >
    <div style={{ minWidth: 44 }}>{left}</div>
    <div style={{ fontSize: 17, fontWeight: 600 }}>{title}</div>
    <div style={{ minWidth: 44, display: "flex", justifyContent: "flex-end" }}>{right}</div>
  </div>
);

const GlassCircle: React.FC<{ children: React.ReactNode }> = ({ children }) => (
  <div
    style={{
      width: 40,
      height: 40,
      borderRadius: 20,
      background: "rgba(255,255,252,0.85)",
      boxShadow: "0 1px 6px rgba(0,0,0,0.08), inset 0 0 0 0.5px rgba(0,0,0,0.08)",
      display: "flex",
      alignItems: "center",
      justifyContent: "center",
      fontSize: 18,
      fontWeight: 600,
      color: C.ink,
    }}
  >
    {children}
  </div>
);

// ---------------------------------------------------------------- New story

const genres = [
  "日常生活", "童话寓言", "奇幻冒险", "科幻", "悬疑推理", "旅行见闻", "美食",
  "校园", "职场", "历史人物", "自然科普", "新闻报道", "对话", "演讲",
];

const levels = {
  en: [["A1", "入门 · 常用词、简单现在时"], ["A2", "初级 · 日常话题、过去时"], ["B1", "中级 · 复合句、常见短语"], ["B2", "中高级 · 从句、丰富词汇"], ["C1", "高级 · 地道表达、复杂结构"]],
  ja: [["N5", "入门 · 基础汉字、です/ます"], ["N4", "初级 · て形、简单复句"], ["N3", "中级 · 日常文章、常用句型"], ["N2", "中高级 · 报刊随笔、书面语"], ["N1", "高级 · 复杂文体、细腻表达"]],
};

const Section: React.FC<{ title: string; children: React.ReactNode }> = ({ title, children }) => (
  <div style={{ display: "flex", flexDirection: "column", gap: 12 }}>
    <div style={{ fontSize: 15, fontWeight: 700, color: C.muted }}>{title}</div>
    {children}
  </div>
);

const Chip: React.FC<{ selected: boolean; fill?: boolean; children: React.ReactNode }> = ({
  selected,
  fill,
  children,
}) => (
  <div
    style={{
      fontSize: 15,
      fontWeight: selected ? 600 : 400,
      color: selected ? "#fff" : C.ink,
      background: selected ? C.accent : C.raised,
      padding: "9px 12px",
      borderRadius: 99,
      textAlign: "center",
      flex: fill ? 1 : undefined,
      whiteSpace: "nowrap",
    }}
  >
    {children}
  </div>
);

export const NewStoryScreen: React.FC<{
  lang: "en" | "ja";
  level: string;
  genre: string;
  topic: string;
  caret: boolean;
  scroll: number;
}> = ({ lang, level, genre, topic, caret, scroll }) => {
  const levelSummary = levels[lang].find(([id]) => id === level)?.[1] ?? "";
  const tile = (option: "en" | "ja") => {
    const selected = option === lang;
    return (
      <div
        style={{
          flex: 1,
          padding: 16,
          borderRadius: 20,
          background: selected ? "rgba(217,119,75,0.14)" : C.raised,
          boxShadow: selected ? `inset 0 0 0 2px ${C.accent}` : "none",
          display: "flex",
          flexDirection: "column",
          gap: 6,
        }}
      >
        <div style={{ fontFamily: F.serif, fontSize: 28, fontWeight: 700, color: selected ? C.accent : C.muted }}>
          {option === "en" ? "Aa" : "あ"}
        </div>
        <div style={{ fontSize: 17, fontWeight: 600 }}>{option === "en" ? "English" : "日本語"}</div>
        <div style={{ fontSize: 12, color: C.muted }}>{option === "en" ? "英语" : "日语"}</div>
      </div>
    );
  };
  return (
    <div style={{ position: "absolute", inset: 0, background: C.paper }}>
      <div style={{ position: "absolute", top: 0, left: 0, right: 0, height: 98, background: C.paper, zIndex: 40 }} />
      <NavBar title="新短文" left={<GlassCircle>✕</GlassCircle>} />
      <div
        style={{
          position: "absolute",
          top: 98 - scroll,
          left: 0,
          right: 0,
          padding: 20,
          display: "flex",
          flexDirection: "column",
          gap: 28,
        }}
      >
        <Section title="语言">
          <div style={{ display: "flex", gap: 12 }}>
            {tile("en")}
            {tile("ja")}
          </div>
        </Section>
        <Section title="难度">
          <div style={{ display: "flex", gap: 8 }}>
            {levels[lang].map(([id]) => (
              <Chip key={id} selected={id === level}>{id}</Chip>
            ))}
          </div>
          <div style={{ fontSize: 13, color: C.muted, marginTop: -2 }}>{levelSummary}</div>
        </Section>
        <Section title="类型">
          <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr 1fr", gap: 8 }}>
            {genres.map((g) => (
              <Chip key={g} selected={g === genre} fill>{g}</Chip>
            ))}
          </div>
        </Section>
        <Section title="篇幅">
          <div style={{ display: "flex", background: "rgba(120,120,110,0.12)", borderRadius: 99, padding: 2 }}>
            {["短篇 · 约6句", "中篇 · 约12句", "长篇 · 约20句"].map((l, i) => (
              <div
                key={l}
                style={{
                  flex: 1,
                  textAlign: "center",
                  fontSize: 13,
                  fontWeight: i === 0 ? 600 : 400,
                  padding: "7px 0",
                  borderRadius: 99,
                  background: i === 0 ? "#fff" : "transparent",
                  boxShadow: i === 0 ? "0 2px 6px rgba(0,0,0,0.1)" : "none",
                }}
              >
                {l}
              </div>
            ))}
          </div>
        </Section>
        <Section title="主题（可选）">
          <div style={{ padding: 14, borderRadius: 14, background: C.raised, fontSize: 17, minHeight: 22 }}>
            {topic ? (
              <span>
                {topic}
                <span style={{ color: C.accent, opacity: caret ? 1 : 0 }}>|</span>
              </span>
            ) : (
              <span style={{ color: "#B5B5AC" }}>例如：一只想学游泳的猫、东京的雨天</span>
            )}
          </div>
        </Section>
      </div>
      {/* safeAreaInset(edge: .bottom) start button */}
      <div style={{ position: "absolute", left: 20, right: 20, bottom: 42, zIndex: 40 }}>
        <div
          style={{
            height: 52,
            borderRadius: 26,
            background: C.accent,
            color: "#fff",
            fontSize: 17,
            fontWeight: 600,
            display: "flex",
            alignItems: "center",
            justifyContent: "center",
            gap: 8,
            boxShadow: "0 6px 18px rgba(217,119,75,0.35), inset 0 1px 0 rgba(255,255,255,0.35)",
          }}
        >
          <Sparkle size={17} color="#fff" />
          开始创作
        </div>
      </div>
    </div>
  );
};

// ---------------------------------------------------------------- Library

const StoryCard: React.FC<{
  cover: React.ReactNode;
  title: string;
  titleZh: string;
  tags: string[];
  date: string;
  serif?: boolean;
}> = ({ cover, title, titleZh, tags, date, serif }) => (
  <div
    style={{
      borderRadius: 24,
      overflow: "hidden",
      background: C.raised,
      boxShadow: "0 4px 10px rgba(0,0,0,0.06)",
    }}
  >
    <div style={{ height: 180, overflow: "hidden" }}>{cover}</div>
    <div style={{ padding: 16, display: "flex", flexDirection: "column", gap: 6 }}>
      <div style={{ fontFamily: serif ? F.serif : F.ja, fontSize: 20, fontWeight: 700 }}>{title}</div>
      <div style={{ fontSize: 15, color: C.muted }}>{titleZh}</div>
      <div style={{ display: "flex", gap: 6, alignItems: "center", marginTop: 4 }}>
        {tags.map((t) => (
          <TagLabel key={t}>{t}</TagLabel>
        ))}
        <div style={{ flex: 1 }} />
        <span style={{ fontSize: 12, color: C.muted }}>{date}</span>
      </div>
    </div>
  </div>
);

export const LibraryScreen: React.FC<{
  /** Seconds shown on the in-progress job. */
  jobSeconds: number;
  /** 0…1 reveal of the freshly generated story card. */
  reveal: number;
}> = ({ jobSeconds, reveal }) => (
  <div style={{ position: "absolute", inset: 0, background: C.paper }}>
    <div
      style={{
        position: "absolute",
        top: 54,
        left: 16,
        right: 16,
        height: 52,
        display: "flex",
        alignItems: "center",
        justifyContent: "space-between",
      }}
    >
      <div style={{ fontSize: 34, fontWeight: 800 }}>Fablo</div>
      <div
        style={{
          height: 38,
          padding: "0 16px",
          borderRadius: 19,
          background: C.accent,
          color: "#fff",
          fontSize: 15,
          fontWeight: 600,
          display: "flex",
          alignItems: "center",
          gap: 4,
        }}
      >
        <span style={{ fontSize: 20, fontWeight: 500, marginTop: -2 }}>＋</span> 新短文
      </div>
    </div>
    <div style={{ position: "absolute", top: 116, left: 16, right: 16, display: "flex", flexDirection: "column", gap: 18 }}>
      <div style={{ display: "flex", background: "rgba(120,120,110,0.12)", borderRadius: 99, padding: 2, marginBottom: 4 }}>
        {["全部", "English", "日本語"].map((l, i) => (
          <div
            key={l}
            style={{
              flex: 1,
              textAlign: "center",
              fontSize: 13,
              fontWeight: i === 0 ? 600 : 400,
              padding: "7px 0",
              borderRadius: 99,
              background: i === 0 ? "#fff" : "transparent",
              boxShadow: i === 0 ? "0 2px 6px rgba(0,0,0,0.1)" : "none",
            }}
          >
            {l}
          </div>
        ))}
      </div>
      {/* The job card grows into the finished story card. */}
      <div style={{ position: "relative", height: 87 + (302 - 87) * reveal, overflow: "hidden", borderRadius: 24 }}>
        <div
          style={{
            position: "absolute",
            left: 0,
            right: 0,
            top: 0,
            display: "flex",
            gap: 14,
            padding: 16,
            borderRadius: 24,
            background: C.raised,
            opacity: 1 - reveal,
          }}
        >
          <div
            style={{
              width: 56,
              height: 56,
              borderRadius: 16,
              background: C.card,
              display: "flex",
              alignItems: "center",
              justifyContent: "center",
            }}
          >
            <Sparkle size={26} color={C.accent} />
          </div>
          <div style={{ display: "flex", flexDirection: "column", gap: 8, paddingTop: 4 }}>
            <div style={{ fontSize: 15, fontWeight: 600 }}>日本語 N4 · 童话寓言 · 短篇</div>
            <div style={{ display: "flex", alignItems: "center", gap: 6, fontSize: 12, color: C.muted }}>
              <Spinner size={14} />
              正在创作并逐词标注… {jobSeconds}s
            </div>
          </div>
        </div>
        <div style={{ position: "absolute", left: 0, right: 0, top: 0, opacity: reveal }}>
          <StoryCard
            cover={<SeaCover style={{ width: "100%", height: "100%" }} />}
            title={story.title}
            titleZh={story.titleZh}
            tags={story.tags}
            date="10月7日"
          />
        </div>
      </div>
      <StoryCard
        cover={<LighthouseCover style={{ width: "100%", height: "100%" }} />}
        title="The Lighthouse Keeper's Secret"
        titleZh="灯塔守护人的秘密"
        tags={["EN · B1", "悬疑推理"]}
        date="10月6日"
        serif
      />
      <StoryCard
        cover={<RainCover style={{ width: "100%", height: "100%" }} />}
        title="東京の雨の日"
        titleZh="东京的雨天"
        tags={["JA · N3", "日常生活"]}
        date="10月5日"
      />
    </div>
  </div>
);

// ---------------------------------------------------------------- Reader

export const ReaderScreen: React.FC<{
  scroll: number;
  speaking?: { sentence: number; word: number | null } | null;
  selected?: number | null;
  annotate?: number;
  playing?: boolean;
}> = ({ scroll, speaking = null, selected = null, annotate = 0, playing = false }) => {
  const status = speaking ? `正在朗读第 ${speaking.sentence + 1} 句` : selected !== null ? `从第 ${selected + 1} 句开始朗读` : "朗读全文";
  return (
    <div style={{ position: "absolute", inset: 0, background: C.paper }}>
      <div style={{ position: "absolute", top: 0, left: 0, right: 0, height: 118, background: "linear-gradient(#F9F9F0 80%, rgba(249,249,240,0))", zIndex: 40 }} />
      <NavBar
        left={<GlassCircle><span style={{ fontSize: 22, marginTop: -2 }}>‹</span></GlassCircle>}
        right={<GlassCircle><span style={{ fontFamily: F.serif, fontSize: 16 }}>Aa</span></GlassCircle>}
      />
      <div style={{ position: "absolute", top: 106 - scroll, left: 12, right: 12 }}>
        <div style={{ padding: "0 6px 30px", display: "flex", flexDirection: "column", gap: 10 }}>
          <div style={{ borderRadius: 24, overflow: "hidden", aspectRatio: "3 / 2", marginBottom: 8 }}>
            <SeaCover style={{ width: "100%", height: "100%" }} />
          </div>
          <div style={{ fontFamily: F.ja, fontSize: 28, fontWeight: 700 }}>{story.title}</div>
          <div style={{ fontSize: 20, color: C.muted }}>{story.titleZh}</div>
          <div style={{ display: "flex", gap: 6 }}>
            {story.tags.map((t) => (
              <TagLabel key={t}>{t}</TagLabel>
            ))}
          </div>
          <div style={{ fontSize: 15, color: C.muted, marginTop: 2 }}>{story.summaryZh}</div>
        </div>
        {sentences.map((s, i) => {
          const isSel = selected === i;
          const isSpeaking = speaking?.sentence === i;
          return (
            <div
              key={i}
              style={{
                position: "relative",
                padding: isSel ? 18 : "0 18px",
                marginBottom: i === 1 ? 52 : 32,
                borderRadius: 26,
                background: isSel ? `rgba(240,240,227,${Math.min(1, annotate * 1.5)})` : "transparent",
              }}
            >
              {isSpeaking ? (
                <div
                  style={{
                    position: "absolute",
                    inset: -6,
                    borderRadius: 18,
                    background: "rgba(217,119,75,0.10)",
                  }}
                />
              ) : null}
              <div style={{ position: "relative" }}>
                <SentenceFlow
                  sentence={s}
                  annotate={isSel ? annotate : 0}
                  activeWord={isSpeaking ? speaking!.word : null}
                />
              </div>
              {isSel ? (
                <div style={{ opacity: annotate, overflow: "hidden", maxHeight: annotate * 120 }}>
                  <div style={{ fontSize: 17, color: C.muted, marginTop: 14 }}>{s.zh}</div>
                  <div style={{ display: "flex", gap: 10, marginTop: 14 }}>
                    <div style={{ fontSize: 13, fontWeight: 600, color: C.accent, background: "rgba(217,119,75,0.13)", padding: "6px 12px", borderRadius: 99 }}>
                      ▶︎ 朗读
                    </div>
                    <div style={{ fontSize: 13, fontWeight: 600, color: "#fff", background: C.accent, padding: "6px 12px", borderRadius: 99 }}>
                      ⌕ 解析
                    </div>
                  </div>
                </div>
              ) : null}
            </div>
          );
        })}
      </div>
      {/* playback bar */}
      <div
        style={{
          position: "absolute",
          left: 16,
          right: 16,
          bottom: 30,
          padding: 6,
          borderRadius: 99,
          display: "flex",
          alignItems: "center",
          gap: 12,
          background: "rgba(255,255,252,0.82)",
          backdropFilter: "blur(12px)",
          boxShadow: "0 6px 24px rgba(0,0,0,0.10), inset 0 0 0 0.5px rgba(0,0,0,0.1)",
          zIndex: 45,
        }}
      >
        <div
          style={{
            width: 40,
            height: 40,
            borderRadius: 20,
            background: C.accent,
            color: "#fff",
            display: "flex",
            alignItems: "center",
            justifyContent: "center",
            fontSize: 15,
          }}
        >
          {playing ? "❚❚" : "▶"}
        </div>
        <div style={{ display: "flex", flexDirection: "column", gap: 2, flex: 1 }}>
          <div style={{ fontSize: 15, fontWeight: 600 }}>{status}</div>
          <div style={{ fontSize: 12, color: C.muted }}>6 句</div>
        </div>
        <div style={{ width: 40, height: 40, borderRadius: 20, background: C.card, color: C.muted, display: "flex", alignItems: "center", justifyContent: "center", fontSize: 17 }}>
          ↻
        </div>
        <div style={{ minWidth: 56, height: 40, borderRadius: 20, background: C.card, display: "flex", alignItems: "center", justifyContent: "center", fontSize: 15, fontWeight: 600 }}>
          1×
        </div>
      </div>
    </div>
  );
};

// ---------------------------------------------------------------- Sheets

export const Dim: React.FC<{ amount: number }> = ({ amount }) => (
  <div style={{ position: "absolute", inset: 0, background: `rgba(20,16,10,${0.3 * amount})`, zIndex: 60 }} />
);

/** WordDetailView in a 220pt sheet. */
export const WordSheet: React.FC<{ offset: number }> = ({ offset }) => (
  <div
    style={{
      position: "absolute",
      left: 8,
      right: 8,
      bottom: 8,
      height: 250,
      borderRadius: 40,
      background: C.paper,
      boxShadow: "0 -6px 30px rgba(0,0,0,0.12)",
      translate: `0px ${offset}px`,
      zIndex: 70,
      padding: 24,
      display: "flex",
      flexDirection: "column",
      gap: 10,
    }}
  >
    <div style={{ display: "flex", alignItems: "baseline", gap: 10 }}>
      <span style={{ fontFamily: F.ja, fontSize: 34, fontWeight: 700 }}>海</span>
      <span style={{ fontFamily: F.ja, fontSize: 20, color: C.muted }}>うみ</span>
    </div>
    <div style={{ fontSize: 17, color: C.muted }}>umi</div>
    <div style={{ display: "flex", alignItems: "center", gap: 8 }}>
      <TagLabel color={posColor.noun}>名词</TagLabel>
      <span style={{ fontSize: 20 }}>大海</span>
    </div>
  </div>
);

const SheetTitle: React.FC<{ children: React.ReactNode }> = ({ children }) => (
  <div style={{ fontSize: 15, fontWeight: 700, color: C.muted }}>{children}</div>
);

/** AnalysisView for sentence 1. `ready` fades the AI result in; `scroll` moves the content. */
export const AnalysisSheet: React.FC<{ offset: number; ready: number; scroll: number }> = ({
  offset,
  ready,
  scroll,
}) => {
  const s = sentences[0];
  const usedPos = (["noun", "verb", "particle", "adjective"] as const).filter((p) => posColor[p]);
  return (
    <div
      style={{
        position: "absolute",
        left: 0,
        right: 0,
        top: 64,
        bottom: 0,
        borderTopLeftRadius: 38,
        borderTopRightRadius: 38,
        background: C.paper,
        boxShadow: "0 -6px 30px rgba(0,0,0,0.15)",
        translate: `0px ${offset}px`,
        zIndex: 70,
        overflow: "hidden",
      }}
    >
      <div style={{ position: "absolute", top: 0, left: 0, right: 0, height: 56, background: C.paper, zIndex: 2, display: "flex", alignItems: "center", justifyContent: "center", fontSize: 17, fontWeight: 600 }}>
        <div style={{ position: "absolute", top: 6, width: 36, height: 5, borderRadius: 3, background: "#D3D3C8" }} />
        第 1 句解析
      </div>
      <div style={{ position: "absolute", top: 60 - scroll, left: 16, right: 16, display: "flex", flexDirection: "column", gap: 22 }}>
        <div style={{ padding: 18, borderRadius: 26, background: C.card, display: "flex", flexDirection: "column", gap: 14 }}>
          <SentenceFlow sentence={s} annotate={1} />
          <div style={{ fontSize: 16, color: C.muted }}>{s.zh}</div>
        </div>
        <div style={{ display: "flex", flexDirection: "column", gap: 10 }}>
          <SheetTitle>句子成分</SheetTitle>
          <div style={{ display: "flex", flexWrap: "wrap", gap: 8 }}>
            {s.c.map((chunk, i) => (
              <div
                key={i}
                style={{
                  display: "flex",
                  gap: 6,
                  alignItems: "baseline",
                  padding: "6px 10px",
                  borderRadius: 10,
                  background: chunkColor[chunk.role] ?? C.card,
                }}
              >
                <span style={{ fontSize: 12, fontWeight: 700, color: C.muted }}>{roleLabel[chunk.role]}</span>
                <span style={{ fontFamily: F.ja, fontSize: 15, fontWeight: 500 }}>{chunk.w.map((w) => w.s).join("")}</span>
              </div>
            ))}
          </div>
          <div style={{ display: "flex", gap: 12 }}>
            {usedPos.map((p) => (
              <div key={p} style={{ display: "flex", alignItems: "center", gap: 5 }}>
                <div style={{ width: 16, height: 6, borderRadius: 2, background: posColor[p]! }} />
                <span style={{ fontSize: 12, color: C.muted }}>{posLabel[p]}</span>
              </div>
            ))}
          </div>
        </div>
        {ready < 1 ? (
          <div style={{ display: "flex", alignItems: "center", justifyContent: "center", gap: 10, padding: "30px 0", color: C.muted, fontSize: 17, opacity: 1 - ready }}>
            <Spinner size={18} />
            AI 老师正在解析这句话…
          </div>
        ) : null}
        <div style={{ display: "flex", flexDirection: "column", gap: 22, opacity: ready, translate: `0px ${(1 - ready) * 20}px` }}>
          <div style={{ display: "flex", flexDirection: "column", gap: 10 }}>
            <SheetTitle>结构</SheetTitle>
            <div style={{ fontSize: 17, lineHeight: 1.6 }}>
              「小さな猫が」是主语，「海を見に」说明去的目的，句尾「行きました」是「行きます」的过去式。
            </div>
          </div>
          <div style={{ display: "flex", flexDirection: "column", gap: 12 }}>
            <SheetTitle>语法点</SheetTitle>
            <div style={{ padding: 14, borderRadius: 18, background: C.raised, display: "flex", flexDirection: "column", gap: 8 }}>
              <div style={{ fontFamily: F.ja, fontSize: 17, fontWeight: 600, color: C.accent }}>动词ます形 + に行く</div>
              <div style={{ fontSize: 17, lineHeight: 1.5 }}>表示"去做某事"，に 前面是移动的目的。</div>
              <div style={{ padding: 10, borderRadius: 12, background: C.paper }}>
                <div style={{ fontFamily: F.ja, fontSize: 16, fontWeight: 500 }}>本を買いに行きます。</div>
                <div style={{ fontSize: 16, color: C.muted }}>去买书。</div>
              </div>
            </div>
          </div>
          <div style={{ display: "flex", flexDirection: "column", gap: 10 }}>
            <SheetTitle>语感提示</SheetTitle>
            <div style={{ padding: 14, borderRadius: 18, background: "rgba(217,119,75,0.10)", fontSize: 17, lineHeight: 1.5 }}>
              用「小さな」而不是「小さい」，读起来更像童话里的口吻，带一点可爱。
            </div>
          </div>
        </div>
      </div>
    </div>
  );
};
