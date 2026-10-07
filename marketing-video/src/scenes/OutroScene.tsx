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
import { C, F } from "../theme";
import { Backdrop, clamp, easeOut } from "../ui";

export const OutroScene: React.FC = () => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();

  return (
    <AbsoluteFill style={{ fontFamily: F.ui, color: C.ink }}>
      <Backdrop />
      <Audio src="https://remotion.media/ding.wav" volume={0.3} />
      <Img
        src={staticFile("icon.png")}
        style={{
          position: "absolute",
          left: (1080 - 360) / 2,
          top: 500,
          width: 360,
          height: 360,
          borderRadius: 80,
          boxShadow: "0 36px 80px rgba(150,70,30,0.25)",
          scale: interpolate(frame, [0, 0.6 * fps], [0.6, 1], {
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
          top: 910,
          textAlign: "center",
          fontFamily: F.display,
          fontSize: 170,
          fontWeight: 900,
          letterSpacing: -2,
          opacity: interpolate(frame, [8, 20], [0, 1], clamp),
          translate: interpolate(frame, [8, 28], ["0px 40px", "0px 0px"], { ...clamp, easing: easeOut }),
        }}
      >
        Fablo
      </div>
      <div
        style={{
          position: "absolute",
          left: 80,
          right: 80,
          top: 1160,
          textAlign: "center",
          fontSize: 76,
          fontWeight: 800,
          lineHeight: 1.25,
          opacity: interpolate(frame, [18, 30], [0, 1], clamp),
          translate: interpolate(frame, [18, 36], ["0px 40px", "0px 0px"], { ...clamp, easing: easeOut }),
        }}
      >
        读刚好读得懂的故事
      </div>
      <div
        style={{
          position: "absolute",
          left: 0,
          right: 0,
          top: 1330,
          display: "flex",
          justifyContent: "center",
          gap: 24,
          opacity: interpolate(frame, [28, 40], [0, 1], clamp),
        }}
      >
        {["English", "日本語"].map((l) => (
          <div
            key={l}
            style={{
              padding: "18px 40px",
              borderRadius: 99,
              background: C.accent,
              color: "#fff",
              fontSize: 48,
              fontWeight: 700,
            }}
          >
            {l}
          </div>
        ))}
      </div>
    </AbsoluteFill>
  );
};
