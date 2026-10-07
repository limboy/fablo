import { Audio } from "@remotion/media";
import { AbsoluteFill, interpolate, Sequence, useCurrentFrame, useVideoConfig } from "remotion";
import { Headline } from "../Headline";
import { LibraryScreen } from "../screens";
import { C, F } from "../theme";
import { Backdrop, clamp, easeOut, Phone, Tap } from "../ui";

const READY = 48;

export const LibraryScene: React.FC = () => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  // The job timer runs faster than real time so the wait reads as "seconds".
  const seconds = Math.floor(interpolate(frame, [0, READY], [6, 21], clamp));

  return (
    <AbsoluteFill style={{ fontFamily: F.ui, color: C.ink }}>
      <Backdrop />
      <Headline name="Headline" title="AI 现写一篇专属短文" subtitle="配好插画封面，逐词标注" accentColor={C.accent} />
      <Sequence from={READY} durationInFrames={fps} layout="none">
        <Audio src="https://remotion.media/ding.wav" volume={0.25} />
      </Sequence>
      <Phone>
        <LibraryScreen
          jobSeconds={seconds}
          reveal={interpolate(frame, [READY, READY + 20], [0, 1], { ...clamp, easing: easeOut })}
        />
        <Tap x={195} y={270} at={92} />
      </Phone>
    </AbsoluteFill>
  );
};
