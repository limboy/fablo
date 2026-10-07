import { Composition, Folder } from "remotion";
import { FabloPromo } from "./FabloPromo";
import { Headline } from "./Headline";
import { AnalysisScene } from "./scenes/AnalysisScene";
import { CreateScene } from "./scenes/CreateScene";
import { HookScene } from "./scenes/HookScene";
import { LibraryScene } from "./scenes/LibraryScene";
import { OutroScene } from "./scenes/OutroScene";
import { ReadScene } from "./scenes/ReadScene";
import { StructureScene } from "./scenes/StructureScene";
import { C } from "./theme";

// Scene lengths sum to 890; two 16-frame slides and four 12-frame fades overlap → 810.
export const RemotionRoot: React.FC = () => {
  return (
    <>
      <Composition id="FabloPromo" component={FabloPromo} durationInFrames={810} fps={30} width={1080} height={1920} />
      <Folder name="Scenes">
        <Composition id="Hook" component={HookScene} durationInFrames={80} fps={30} width={1080} height={1920} />
        <Composition id="Create" component={CreateScene} durationInFrames={150} fps={30} width={1080} height={1920} />
        <Composition id="Library" component={LibraryScene} durationInFrames={110} fps={30} width={1080} height={1920} />
        <Composition id="Read" component={ReadScene} durationInFrames={165} fps={30} width={1080} height={1920} />
        <Composition id="Structure" component={StructureScene} durationInFrames={150} fps={30} width={1080} height={1920} />
        <Composition id="Analysis" component={AnalysisScene} durationInFrames={140} fps={30} width={1080} height={1920} />
        <Composition id="Outro" component={OutroScene} durationInFrames={95} fps={30} width={1080} height={1920} />
      </Folder>
      <Folder name="Elements">
        <Composition
          id="Headline"
          component={Headline}
          durationInFrames={45}
          fps={30}
          width={1080}
          height={1920}
          defaultProps={{ title: "选语言、难度、题材", subtitle: "A1–C1 · N5–N1 · 14 种类型", accentColor: C.accent }}
        />
      </Folder>
    </>
  );
};
