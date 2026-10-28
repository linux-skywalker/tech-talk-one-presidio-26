import { Sequence } from "remotion";
import { KueueBeforeAfter, KUEUE_TOTAL } from "./KueueBeforeAfter";
import { MpsBeforeAfter, MPS_TOTAL } from "./MpsBeforeAfter";
import { DraBeforeAfter, DRA_TOTAL } from "./DraBeforeAfter";
import { SystemSlide, SYSTEM_TOTAL } from "./SystemSlide";
import { DemoTitle, DEMO_TITLE_TOTAL } from "./DemoTitle";

// The demo title slide, the machine, then the three before/after demos one after the other: MPS, Kueue, DRA.
export const ALL_TOTAL = DEMO_TITLE_TOTAL + SYSTEM_TOTAL + MPS_TOTAL + KUEUE_TOTAL + DRA_TOTAL;

export const AllDemos = () => {
  const t1 = DEMO_TITLE_TOTAL;
  const t2 = t1 + SYSTEM_TOTAL;
  const t3 = t2 + MPS_TOTAL;
  const t4 = t3 + KUEUE_TOTAL;
  return (
    <>
      <Sequence  durationInFrames={DEMO_TITLE_TOTAL}><DemoTitle /></Sequence>
      <Sequence from={t1} durationInFrames={SYSTEM_TOTAL}><SystemSlide /></Sequence>
      <Sequence from={t2} durationInFrames={MPS_TOTAL}><MpsBeforeAfter /></Sequence>
      <Sequence from={t3} durationInFrames={KUEUE_TOTAL}><KueueBeforeAfter /></Sequence>
      <Sequence from={t4} durationInFrames={DRA_TOTAL}><DraBeforeAfter /></Sequence>
    </>
  );
};
