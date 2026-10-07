import { Audio } from "@remotion/media";
import type React from "react";
import {
  AbsoluteFill,
  Easing,
  interpolate,
  Sequence,
  useCurrentFrame,
  useVideoConfig,
} from "remotion";
import { C, chunkColor, F, posColor } from "./theme";
import type { Sentence, Word } from "./story";

export const clamp = { extrapolateLeft: "clamp", extrapolateRight: "clamp" } as const;
export const easeOut = Easing.bezier(0.16, 1, 0.3, 1);

/** 0→1 progress between two frames with a smooth ease-out. */
export const prog = (frame: number, from: number, to: number) =>
  interpolate(frame, [from, to], [0, 1], { ...clamp, easing: easeOut });

// ---------------------------------------------------------------- Phone

/** Screen is laid out in iPhone points (390×844) and scaled up by K. */
export const K = 1.7;
export const SCREEN_W = 390;
export const SCREEN_H = 844;
const BEZEL = 16;
export const PHONE_W = SCREEN_W * K + BEZEL * 2;
export const PHONE_H = SCREEN_H * K + BEZEL * 2;

export const Phone: React.FC<{
  children: React.ReactNode;
  style?: React.CSSProperties;
}> = ({ children, style }) => (
  <div
    style={{
      position: "absolute",
      left: (1080 - PHONE_W) / 2,
      top: 400,
      width: PHONE_W,
      height: PHONE_H,
      padding: BEZEL,
      borderRadius: 56 * K + BEZEL,
      background: "linear-gradient(145deg, #3a3a36, #121211)",
      boxShadow:
        "0 60px 120px rgba(90, 50, 20, 0.28), 0 18px 40px rgba(0,0,0,0.18), inset 0 0 0 3px #55554f",
      ...style,
    }}
  >
    <div
      style={{
        position: "relative",
        width: SCREEN_W * K,
        height: SCREEN_H * K,
        borderRadius: 56 * K,
        overflow: "hidden",
        background: C.paper,
      }}
    >
      <div
        style={{
          position: "absolute",
          left: 0,
          top: 0,
          width: SCREEN_W,
          height: SCREEN_H,
          transform: `scale(${K})`,
          transformOrigin: "0 0",
          fontFamily: F.ui,
          color: C.ink,
        }}
      >
        {children}
        <StatusBar />
        <div
          style={{
            position: "absolute",
            bottom: 8,
            left: (SCREEN_W - 134) / 2,
            width: 134,
            height: 5,
            borderRadius: 3,
            background: C.ink,
            zIndex: 100,
          }}
        />
      </div>
    </div>
  </div>
);

const StatusBar: React.FC = () => (
  <div
    style={{
      position: "absolute",
      top: 0,
      left: 0,
      right: 0,
      height: 54,
      zIndex: 100,
      display: "flex",
      alignItems: "center",
      justifyContent: "space-between",
      padding: "6px 34px 0 46px",
      fontSize: 17,
      fontWeight: 600,
    }}
  >
    <span>9:41</span>
    <div
      style={{
        position: "absolute",
        top: 11,
        left: (SCREEN_W - 124) / 2,
        width: 124,
        height: 36,
        borderRadius: 18,
        background: "#000",
      }}
    />
    <div style={{ display: "flex", alignItems: "flex-end", gap: 6 }}>
      <div style={{ display: "flex", alignItems: "flex-end", gap: 2 }}>
        {[4, 6, 8, 10].map((h) => (
          <div key={h} style={{ width: 3, height: h, borderRadius: 1, background: C.ink }} />
        ))}
      </div>
      <div
        style={{
          width: 25,
          height: 12,
          borderRadius: 4,
          border: `1.5px solid ${C.ink}`,
          padding: 1.5,
          opacity: 0.9,
        }}
      >
        <div style={{ width: "80%", height: "100%", borderRadius: 2, background: C.ink }} />
      </div>
    </div>
  </div>
);

// ---------------------------------------------------------------- Taps

/** A touch ripple at screen-point coordinates, with a click sound. */
export const Tap: React.FC<{ x: number; y: number; at: number }> = ({ x, y, at }) => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  const t = frame - at;
  if (t < -4 || t > 20) return null;
  const press = interpolate(t, [-4, 0, 6], [0, 1, 0.9], clamp);
  const ring = interpolate(t, [0, 18], [0.6, 1.8], { ...clamp, easing: easeOut });
  const fade = interpolate(t, [6, 20], [1, 0], clamp);
  return (
    <>
      <Sequence from={at} durationInFrames={fps} layout="none">
        <Audio src="https://remotion.media/mouse-click.wav" volume={0.35} />
      </Sequence>
      <div
        style={{
          position: "absolute",
          left: x - 22,
          top: y - 22,
          width: 44,
          height: 44,
          borderRadius: 22,
          background: "rgba(40,30,20,0.22)",
          scale: String(press),
          opacity: fade,
          zIndex: 200,
        }}
      />
      <div
        style={{
          position: "absolute",
          left: x - 22,
          top: y - 22,
          width: 44,
          height: 44,
          borderRadius: 22,
          border: "2px solid rgba(40,30,20,0.35)",
          scale: String(ring),
          opacity: fade,
          zIndex: 200,
        }}
      />
    </>
  );
};

// ---------------------------------------------------------------- Small pieces

export const TagLabel: React.FC<{ children: React.ReactNode; color?: string }> = ({
  children,
  color = C.card,
}) => (
  <span
    style={{
      fontSize: 12,
      fontWeight: 500,
      color: C.muted,
      padding: "4px 8px",
      borderRadius: 99,
      background: color,
      whiteSpace: "nowrap",
    }}
  >
    {children}
  </span>
);

export const Spinner: React.FC<{ size?: number }> = ({ size = 16 }) => {
  const frame = useCurrentFrame();
  const step = Math.floor(frame / 2) % 8;
  return (
    <svg width={size} height={size} viewBox="-10 -10 20 20">
      {Array.from({ length: 8 }).map((_, i) => (
        <rect
          key={i}
          x={-1.1}
          y={-9}
          width={2.2}
          height={5}
          rx={1.1}
          fill={C.muted}
          opacity={0.25 + 0.75 * (((i - step + 8) % 8) / 7)}
          transform={`rotate(${i * 45})`}
        />
      ))}
    </svg>
  );
};

export const Sparkle: React.FC<{ size?: number; color?: string }> = ({
  size = 16,
  color = "currentColor",
}) => (
  <svg width={size} height={size} viewBox="0 0 24 24">
    <path d="M12 2 L14.2 9.8 L22 12 L14.2 14.2 L12 22 L9.8 14.2 L2 12 L9.8 9.8 Z" fill={color} />
    <path d="M19.5 2.5 L20.3 4.7 L22.5 5.5 L20.3 6.3 L19.5 8.5 L18.7 6.3 L16.5 5.5 L18.7 4.7 Z" fill={color} />
  </svg>
);

// ---------------------------------------------------------------- Sentence rendering

type Cell = { word: Word; role: keyof typeof chunkColor; start: boolean; end: boolean; spoken: number };

const cellsOf = (sentence: Sentence): Cell[] => {
  const cells: Cell[] = [];
  let spoken = 0;
  for (const chunk of sentence.c) {
    chunk.w.forEach((word, i) => {
      cells.push({
        word,
        role: chunk.role,
        start: i === 0,
        end: i === chunk.w.length - 1,
        spoken: word.p === "punctuation" ? -1 : spoken++,
      });
    });
  }
  return cells;
};

/**
 * Japanese sentence laid out word by word like SentenceFlow in the app:
 * furigana above, romaji below, chunk-role backgrounds and part-of-speech underlines
 * fading in with `annotate` (0…1).
 */
export const SentenceFlow: React.FC<{
  sentence: Sentence;
  annotate?: number;
  activeWord?: number | null;
  scale?: number;
}> = ({ sentence, annotate = 0, activeWord = null }) => {
  const cells = cellsOf(sentence);
  // Punctuation never starts a line: group it with the word before.
  const groups: Cell[][] = [];
  for (const cell of cells) {
    if (cell.word.p === "punctuation" && groups.length) groups[groups.length - 1].push(cell);
    else groups.push([cell]);
  }
  return (
    <div style={{ display: "flex", flexWrap: "wrap", rowGap: 2 }}>
      {groups.map((group, gi) => (
        <div
          key={gi}
          style={{ display: "flex", marginLeft: gi > 0 && group[0].start ? 8 : 0 }}
        >
          {group.map((cell, ci) => (
            <WordCell
              key={ci}
              cell={cell}
              annotate={annotate}
              active={activeWord !== null && cell.spoken === activeWord}
            />
          ))}
        </div>
      ))}
    </div>
  );
};

const WordCell: React.FC<{ cell: Cell; annotate: number; active: boolean }> = ({
  cell,
  annotate,
  active,
}) => {
  const { word } = cell;
  const punct = word.p === "punctuation";
  const hasKanji = /[一-鿿々]/.test(word.s);
  const bg = chunkColor[cell.role];
  const ul = posColor[word.p];
  return (
    <div style={{ display: "flex", flexDirection: "column", alignItems: "center" }}>
      <div style={{ fontSize: 10, height: 13, color: C.muted, whiteSpace: "nowrap" }}>
        {hasKanji && word.r ? word.r : ""}
      </div>
      <div
        style={{
          position: "relative",
          alignSelf: "stretch",
          textAlign: "center",
          padding: punct ? "2px 2px" : "2px 4px",
        }}
      >
        {bg ? (
          <div
            style={{
              position: "absolute",
              inset: 0,
              background: bg,
              opacity: annotate,
              borderTopLeftRadius: cell.start ? 10 : 0,
              borderBottomLeftRadius: cell.start ? 10 : 0,
              borderTopRightRadius: cell.end ? 10 : 0,
              borderBottomRightRadius: cell.end ? 10 : 0,
            }}
          />
        ) : null}
        {ul ? (
          <div
            style={{
              position: "absolute",
              left: punct ? 1 : 3,
              right: punct ? 1 : 3,
              bottom: 2,
              height: 6,
              borderRadius: 2,
              background: ul,
              opacity: annotate,
              scale: `${interpolate(annotate, [0, 1], [0.3, 1])} 1`,
              transformOrigin: "left center",
            }}
          />
        ) : null}
        <span
          style={{
            position: "relative",
            fontFamily: F.ja,
            fontSize: 20,
            fontWeight: 700,
            color: active ? C.accent : C.ink,
            whiteSpace: "nowrap",
          }}
        >
          {word.s}
        </span>
      </div>
      <div style={{ fontSize: 11, height: 14, color: C.muted, whiteSpace: "nowrap" }}>
        {word.ro ?? ""}
      </div>
    </div>
  );
};

// ---------------------------------------------------------------- Covers

/** Stand-ins for the AI-generated cover illustrations. */
export const SeaCover: React.FC<{ style?: React.CSSProperties }> = ({ style }) => (
  <svg viewBox="0 0 300 200" preserveAspectRatio="xMidYMid slice" style={{ display: "block", ...style }}>
    <defs>
      <linearGradient id="sky" x1="0" y1="0" x2="0" y2="1">
        <stop offset="0" stopColor="#F9C9A4" />
        <stop offset="1" stopColor="#FCEBD8" />
      </linearGradient>
    </defs>
    <rect width="300" height="200" fill="url(#sky)" />
    <circle cx="205" cy="88" r="30" fill="#F09A6E" />
    <rect y="108" width="300" height="60" fill="#8FC3D3" />
    <path d="M0 118 Q25 110 50 118 T100 118 T150 118 T200 118 T250 118 T300 118 V128 H0Z" fill="#B7DCE5" />
    <path d="M0 138 Q25 130 50 138 T100 138 T150 138 T200 138 T250 138 T300 138 V148 H0Z" fill="#A6D2DE" />
    <path d="M0 160 Q80 146 160 156 T300 150 V200 H0Z" fill="#F2DDB9" />
    {/* the cat, sitting with its back to us */}
    <g transform="translate(92 136)" fill="#6B4430">
      <ellipse cx="0" cy="18" rx="15" ry="17" />
      <circle cx="0" cy="-4" r="11" />
      <path d="M-10 -9 L-9 -21 L-2 -13Z" />
      <path d="M10 -9 L9 -21 L2 -13Z" />
      <path d="M13 28 Q30 30 26 14" stroke="#6B4430" strokeWidth="5" fill="none" strokeLinecap="round" />
    </g>
  </svg>
);

export const LighthouseCover: React.FC<{ style?: React.CSSProperties }> = ({ style }) => (
  <svg viewBox="0 0 300 200" preserveAspectRatio="xMidYMid slice" style={{ display: "block", ...style }}>
    <defs>
      <linearGradient id="night" x1="0" y1="0" x2="0" y2="1">
        <stop offset="0" stopColor="#1F2A47" />
        <stop offset="1" stopColor="#46557A" />
      </linearGradient>
    </defs>
    <rect width="300" height="200" fill="url(#night)" />
    {[
      [30, 30], [80, 18], [140, 40], [250, 25], [270, 70], [60, 70], [200, 15],
    ].map(([x, y], i) => (
      <circle key={i} cx={x} cy={y} r="1.6" fill="#FFF6D8" />
    ))}
    <defs>
      <linearGradient id="beam" x1="0" y1="0" x2="1" y2="0">
        <stop offset="0" stopColor="#FFE9A8" stopOpacity="0.9" />
        <stop offset="1" stopColor="#FFE9A8" stopOpacity="0" />
      </linearGradient>
    </defs>
    <path d="M178 62 L300 20 L300 100Z" fill="url(#beam)" />
    <rect x="164" y="56" width="20" height="12" fill="#FFE9A8" />
    <path d="M160 70 L188 70 L194 160 L154 160Z" fill="#F4F0E6" />
    <path d="M157 100 L191 100 L192 114 L156 114Z" fill="#D9774B" />
    <path d="M155 130 L193 130 L194 144 L154 144Z" fill="#D9774B" />
    <path d="M160 56 L174 44 L188 56Z" fill="#D9774B" />
    <path d="M0 160 Q150 150 300 162 V200 H0Z" fill="#2B3655" />
  </svg>
);

export const RainCover: React.FC<{ style?: React.CSSProperties }> = ({ style }) => (
  <svg viewBox="0 0 300 200" preserveAspectRatio="xMidYMid slice" style={{ display: "block", ...style }}>
    <rect width="300" height="200" fill="#C8D4DB" />
    {[
      [10, 90, 40], [55, 60, 34], [92, 105, 30], [125, 40, 44], [172, 80, 36], [210, 55, 30], [244, 95, 56],
    ].map(([x, y, w], i) => (
      <rect key={i} x={x} y={y} width={w} height={200 - y} fill={i % 2 ? "#8496A3" : "#9AAAB6"} />
    ))}
    {Array.from({ length: 28 }).map((_, i) => (
      <line
        key={i}
        x1={(i * 37) % 300}
        y1={(i * 53) % 180}
        x2={((i * 37) % 300) - 5}
        y2={((i * 53) % 180) + 14}
        stroke="#F4F8FA"
        strokeWidth="1.5"
        opacity="0.8"
      />
    ))}
    <path d="M120 150 A30 22 0 0 1 180 150Z" fill="#D9774B" />
    <line x1="150" y1="150" x2="150" y2="182" stroke="#3A3A36" strokeWidth="2.5" />
  </svg>
);

// ---------------------------------------------------------------- Backdrop

/** Warm paper background with soft drifting color fields. */
export const Backdrop: React.FC = () => {
  const frame = useCurrentFrame();
  return (
    <AbsoluteFill style={{ background: C.paper, overflow: "hidden" }}>
      <div
        style={{
          position: "absolute",
          width: 900,
          height: 900,
          borderRadius: 450,
          left: -300 + Math.sin(frame / 60) * 30,
          top: 900,
          background: "radial-gradient(circle, rgba(217,119,75,0.22), rgba(217,119,75,0) 70%)",
        }}
      />
      <div
        style={{
          position: "absolute",
          width: 800,
          height: 800,
          borderRadius: 400,
          right: -320,
          top: 200 + Math.cos(frame / 70) * 30,
          background: "radial-gradient(circle, rgba(166,219,226,0.35), rgba(166,219,226,0) 70%)",
        }}
      />
    </AbsoluteFill>
  );
};
