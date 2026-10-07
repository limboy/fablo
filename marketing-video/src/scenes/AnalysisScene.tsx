import { AbsoluteFill, interpolate, useCurrentFrame } from "remotion";
import { Headline } from "../Headline";
import { AnalysisSheet, Dim, ReaderScreen } from "../screens";
import { C, F } from "../theme";
import { Backdrop, clamp, easeOut, Phone, Tap } from "../ui";

const OPEN = 12;

export const AnalysisScene: React.FC = () => {
  const frame = useCurrentFrame();
  const sheet = interpolate(frame, [OPEN + 2, OPEN + 20], [0, 1], { ...clamp, easing: easeOut });

  return (
    <AbsoluteFill style={{ fontFamily: F.ui, color: C.ink }}>
      <Backdrop />
      <Headline name="Headline" title="AI 老师逐句讲解" subtitle="语法点 · 词汇 · 语感提示" accentColor={C.accent} />
      <Phone>
        <ReaderScreen scroll={380} selected={0} annotate={1} />
        <Dim amount={sheet} />
        <AnalysisSheet
          offset={(1 - sheet) * 800}
          ready={interpolate(frame, [48, 60], [0, 1], clamp)}
          scroll={interpolate(frame, [82, 112], [0, 210], { ...clamp, easing: easeOut })}
        />
        <Tap x={127} y={366} at={OPEN} />
      </Phone>
    </AbsoluteFill>
  );
};
