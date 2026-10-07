import { linearTiming, TransitionSeries } from "@remotion/transitions";
import { fade } from "@remotion/transitions/fade";
import { slide } from "@remotion/transitions/slide";
import { Audio } from "@remotion/media";
import { interpolate, staticFile, useVideoConfig } from "remotion";
import { AnalysisScene } from "./scenes/AnalysisScene";
import { CreateScene } from "./scenes/CreateScene";
import { HookScene } from "./scenes/HookScene";
import { LibraryScene } from "./scenes/LibraryScene";
import { OutroScene } from "./scenes/OutroScene";
import { ReadScene } from "./scenes/ReadScene";
import { StructureScene } from "./scenes/StructureScene";

export const TRANSITION = 12;

export const FabloPromo: React.FC = () => {
  const { fps, durationInFrames } = useVideoConfig();

  return (
    <>
      <Audio
        name="Background music"
        src={staticFile("bgm.mp3")}
        premountFor={fps}
        // Fade in briefly, sit under the click/ding effects, fade out over the outro.
        volume={(f) =>
          interpolate(
            f,
            [0, 0.5 * fps, durationInFrames - 2 * fps, durationInFrames],
            [0, 0.6, 0.6, 0],
            {
              extrapolateLeft: "clamp",
              extrapolateRight: "clamp",
            },
          )
        }
      />
      <TransitionSeries>
        <TransitionSeries.Sequence
          name="Hook"
          durationInFrames={80}
          premountFor={fps}
        >
          <HookScene />
        </TransitionSeries.Sequence>
        <TransitionSeries.Transition
          presentation={slide({ direction: "from-bottom" })}
          timing={linearTiming({ durationInFrames: 16 })}
        />
        <TransitionSeries.Sequence
          name="Create"
          durationInFrames={150}
          premountFor={fps}
        >
          <CreateScene />
        </TransitionSeries.Sequence>
        <TransitionSeries.Transition
          presentation={fade()}
          timing={linearTiming({ durationInFrames: TRANSITION })}
        />
        <TransitionSeries.Sequence
          name="Library"
          durationInFrames={110}
          premountFor={fps}
        >
          <LibraryScene />
        </TransitionSeries.Sequence>
        <TransitionSeries.Transition
          presentation={fade()}
          timing={linearTiming({ durationInFrames: TRANSITION })}
        />
        <TransitionSeries.Sequence
          name="Read"
          durationInFrames={165}
          premountFor={fps}
        >
          <ReadScene />
        </TransitionSeries.Sequence>
        <TransitionSeries.Transition
          presentation={fade()}
          timing={linearTiming({ durationInFrames: TRANSITION })}
        />
        <TransitionSeries.Sequence
          name="Structure"
          durationInFrames={150}
          premountFor={fps}
        >
          <StructureScene />
        </TransitionSeries.Sequence>
        <TransitionSeries.Transition
          presentation={fade()}
          timing={linearTiming({ durationInFrames: TRANSITION })}
        />
        <TransitionSeries.Sequence
          name="Analysis"
          durationInFrames={140}
          premountFor={fps}
        >
          <AnalysisScene />
        </TransitionSeries.Sequence>
        <TransitionSeries.Transition
          presentation={slide({ direction: "from-bottom" })}
          timing={linearTiming({ durationInFrames: 16 })}
        />
        <TransitionSeries.Sequence
          name="Outro"
          durationInFrames={95}
          premountFor={fps}
        >
          <OutroScene />
        </TransitionSeries.Sequence>
      </TransitionSeries>
    </>
  );
};
