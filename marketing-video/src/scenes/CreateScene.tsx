import { AbsoluteFill, interpolate, useCurrentFrame } from "remotion";
import { Headline } from "../Headline";
import { NewStoryScreen } from "../screens";
import { C, F } from "../theme";
import { Backdrop, clamp, easeOut, Phone, Tap } from "../ui";

const TOPIC = "一只想去看海的猫";

// Local frames of each tap in the new-story sheet.
const T = { language: 22, level: 42, genre: 60, typeStart: 86, start: 128 };

export const CreateScene: React.FC = () => {
  const frame = useCurrentFrame();
  const lang = frame >= T.language ? "ja" : "en";
  const level = lang === "en" ? "B1" : frame >= T.level ? "N4" : "N5";
  const genre = frame >= T.genre ? "童话寓言" : "日常生活";
  const typed = Math.max(0, Math.min(TOPIC.length, Math.floor((frame - T.typeStart) / 3)));
  const scroll = interpolate(frame, [68, 82], [0, 190], { ...clamp, easing: easeOut });

  return (
    <AbsoluteFill style={{ fontFamily: F.ui, color: C.ink }}>
      <Backdrop />
      <Headline name="Headline" title="选语言、难度、题材" subtitle="A1–C1 · N5–N1 · 14 种类型" accentColor={C.accent} />
      <Phone
        style={{
          translate: interpolate(frame, [0, 18], ["0px 500px", "0px 0px"], { ...clamp, easing: easeOut }),
        }}
      >
        <NewStoryScreen
          lang={lang}
          level={level}
          genre={genre}
          topic={TOPIC.slice(0, typed)}
          caret={Math.floor(frame / 8) % 2 === 0}
          scroll={scroll}
        />
        <Tap x={284} y={208} at={T.language} />
        <Tap x={95} y={355} at={T.level} />
        <Tap x={195} y={485} at={T.genre} />
        <Tap x={195} y={776} at={T.start} />
      </Phone>
    </AbsoluteFill>
  );
};
