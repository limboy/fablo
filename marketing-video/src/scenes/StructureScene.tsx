import { AbsoluteFill, interpolate, useCurrentFrame } from "remotion";
import { Headline } from "../Headline";
import { Dim, ReaderScreen, WordSheet } from "../screens";
import { C, F } from "../theme";
import { Backdrop, clamp, easeOut, Phone, Tap } from "../ui";

const SELECT = 14;
const WORD = 78;

export const StructureScene: React.FC = () => {
  const frame = useCurrentFrame();
  const annotate = interpolate(frame, [SELECT + 2, SELECT + 22], [0, 1], { ...clamp, easing: easeOut });
  const sheet = interpolate(frame, [WORD + 2, WORD + 16], [0, 1], { ...clamp, easing: easeOut });

  return (
    <AbsoluteFill style={{ fontFamily: F.ui, color: C.ink }}>
      <Backdrop />
      <Headline name="Headline" title="轻点一句，看懂结构" subtitle="成分配色 · 词性下划线 · 中文翻译" accentColor={C.accent} />
      <Phone
        style={{
          // Push in on the sentence once it is annotated.
          scale: String(interpolate(frame, [SELECT + 6, SELECT + 34], [1, 1.12], { ...clamp, easing: easeOut })),
          transformOrigin: "50% 40%",
        }}
      >
        <ReaderScreen scroll={380} selected={0} annotate={annotate} />
        <Dim amount={sheet} />
        <WordSheet offset={(1 - sheet) * 300} />
        <Tap x={230} y={215} at={SELECT} />
        <Tap x={174} y={213} at={WORD} />
      </Phone>
    </AbsoluteFill>
  );
};
