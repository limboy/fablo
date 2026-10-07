import { AbsoluteFill, interpolate, useCurrentFrame } from "remotion";
import { Headline } from "../Headline";
import { ReaderScreen } from "../screens";
import { sentences, spokenCount } from "../story";
import { C, F } from "../theme";
import { Backdrop, clamp, easeOut, Phone, Tap } from "../ui";

const PLAY = 16;
const PER_WORD = 6;
const GAP = 6;

/** Which sentence/word the narration is on at a local frame, karaoke style. */
const narrationAt = (frame: number) => {
  let t = frame - (PLAY + 8);
  if (t < 0) return null;
  for (let i = 0; i < sentences.length; i++) {
    const len = spokenCount(sentences[i]) * PER_WORD;
    if (t < len + GAP) return { sentence: i, word: Math.min(Math.floor(t / PER_WORD), spokenCount(sentences[i]) - 1) };
    t -= len + GAP;
  }
  return { sentence: sentences.length - 1, word: null };
};

export const ReadScene: React.FC = () => {
  const frame = useCurrentFrame();
  const speaking = narrationAt(frame);
  // Follow the narration like the reader's auto-scroll.
  const scroll = interpolate(frame, [0, 70, 84, 116, 130], [380, 380, 400, 400, 420], { ...clamp, easing: easeOut });

  return (
    <AbsoluteFill style={{ fontFamily: F.ui, color: C.ink }}>
      <Backdrop />
      <Headline name="Headline" title="逐词高亮朗读" subtitle="假名 · 罗马音 · 逐字高亮" accentColor={C.accent} />
      <Phone>
        <ReaderScreen scroll={scroll} speaking={speaking} playing={frame >= PLAY} />
        <Tap x={42} y={788} at={PLAY} />
      </Phone>
    </AbsoluteFill>
  );
};
