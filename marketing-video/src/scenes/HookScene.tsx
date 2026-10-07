import { Audio } from "@remotion/media";
import {
  AbsoluteFill,
  Easing,
  Img,
  interpolate,
  staticFile,
  useCurrentFrame,
  useVideoConfig,
} from "remotion";
import { C, F, posColor } from "../theme";
import { Backdrop, clamp, easeOut } from "../ui";

const floaters = [
  { text: "海", pos: "noun", x: 150, y: 330, delay: 6, ja: true },
  { text: "story", pos: "noun", x: 790, y: 300, delay: 10, ja: false },
  { text: "読む", pos: "verb", x: 820, y: 760, delay: 14, ja: true },
  { text: "beautiful", pos: "adjective", x: 60, y: 870, delay: 18, ja: false },
  { text: "ゆっくり", pos: "adverb", x: 30, y: 600, delay: 22, ja: true },
  { text: "は", pos: "particle", x: 880, y: 530, delay: 26, ja: true },
] as const;

export const HookScene: React.FC = () => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();

  return (
    <AbsoluteFill style={{ fontFamily: F.ui, color: C.ink }}>
      <Backdrop />
      <Audio src="https://remotion.media/whoosh.wav" volume={0.3} />
      {floaters.map((f) => (
        <div
          key={f.text}
          style={{
            position: "absolute",
            left: f.x,
            top: f.y,
            padding: "14px 26px 18px",
            borderRadius: 26,
            background: C.raised,
            boxShadow: "0 12px 30px rgba(90,50,20,0.12)",
            fontFamily: f.ja ? F.ja : F.serif,
            fontSize: 46,
            fontWeight: 700,
            opacity: interpolate(frame, [f.delay, f.delay + 12], [0, 1], clamp),
            translate: `0px ${interpolate(frame, [f.delay, f.delay + 20, 75], [40, 0, -24], {
              ...clamp,
              easing: Easing.out(Easing.quad),
            })}px`,
            rotate: `${(f.x % 7) - 3}deg`,
          }}
        >
          <span style={{ position: "relative" }}>
            <span
              style={{
                position: "absolute",
                left: -2,
                right: -2,
                bottom: 2,
                height: 14,
                borderRadius: 4,
                background: posColor[f.pos],
              }}
            />
            <span style={{ position: "relative" }}>{f.text}</span>
          </span>
        </div>
      ))}
      <Img
        src={staticFile("icon.png")}
        style={{
          position: "absolute",
          left: (1080 - 500) / 2,
          top: 330,
          width: 500,
          height: 500,
          borderRadius: 112,
          boxShadow: "0 40px 90px rgba(150,70,30,0.25)",
          scale: interpolate(frame, [0, 0.6 * fps], [0.5, 1], {
            ...clamp,
            easing: Easing.spring({ damping: 12 }),
            output: "perceptual-scale",
          }),
          opacity: interpolate(frame, [0, 6], [0, 1], clamp),
        }}
      />
      <div
        style={{
          position: "absolute",
          left: 0,
          right: 0,
          top: 950,
          textAlign: "center",
          fontFamily: F.display,
          fontSize: 190,
          fontWeight: 900,
          letterSpacing: -2,
          opacity: interpolate(frame, [12, 24], [0, 1], clamp),
          translate: interpolate(frame, [12, 32], ["0px 40px", "0px 0px"], { ...clamp, easing: easeOut }),
        }}
      >
        Fablo
      </div>
      <div
        style={{
          position: "absolute",
          left: 80,
          right: 80,
          top: 1220,
          textAlign: "center",
          fontSize: 76,
          fontWeight: 800,
          lineHeight: 1.25,
          opacity: interpolate(frame, [22, 34], [0, 1], clamp),
          translate: interpolate(frame, [22, 40], ["0px 40px", "0px 0px"], { ...clamp, easing: easeOut }),
        }}
      >
        AI 为你写的
        <br />
        外语小故事
      </div>
      <div
        style={{
          position: "absolute",
          left: 0,
          right: 0,
          top: 1470,
          textAlign: "center",
          fontSize: 48,
          fontWeight: 600,
          color: C.accent,
          opacity: interpolate(frame, [32, 44], [0, 1], clamp),
        }}
      >
        English · 日本語 分级阅读
      </div>
    </AbsoluteFill>
  );
};
