import { Composition } from "remotion";
import { KueueBeforeAfter, KUEUE_TOTAL } from "./scenes/KueueBeforeAfter";
import { MpsBeforeAfter, MPS_TOTAL } from "./scenes/MpsBeforeAfter";
import { DraBeforeAfter, DRA_TOTAL } from "./scenes/DraBeforeAfter";
import { AllDemos, ALL_TOTAL } from "./scenes/AllDemos";

export const MyComposition = () => {
  return (
    <>
      <Composition id="KueueBeforeAfter" component={KueueBeforeAfter} durationInFrames={KUEUE_TOTAL} fps={30} width={1920} height={1080} />
      <Composition id="AllDemos" component={AllDemos} durationInFrames={ALL_TOTAL} fps={30} width={1920} height={1080} />
      <Composition id="DraBeforeAfter" component={DraBeforeAfter} durationInFrames={DRA_TOTAL} fps={30} width={1920} height={1080} />
      <Composition id="MpsBeforeAfter" component={MpsBeforeAfter} durationInFrames={MPS_TOTAL} fps={30} width={1920} height={1080} />
    </>
  );
};
