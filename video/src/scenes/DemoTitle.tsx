import { AbsoluteFill } from "remotion";
import { C, Fade, useIn } from "./ui";

// Title slide that opens the demo section, in the deck's title style.
export const DEMO_TITLE_TOTAL = 4 * 30;

export const DemoTitle = () => {
  const p = useIn(4);
  return (
    <Fade dur={DEMO_TITLE_TOTAL} title>
      <AbsoluteFill style={{ justifyContent: "center", paddingLeft: 120, width: 1000 }}>
        <div style={{ opacity: p, transform: `translateY(${(1 - p) * 30}px)` }}>
          <div style={{ fontSize: 150, fontWeight: 700, lineHeight: 1.05, color: C.gold }}>Demo</div>
          <div style={{ fontSize: 42, color: C.dim, marginTop: 22 }}>Sharing and scheduling one GPU: MPS, Kueue and DRA</div>
        </div>
      </AbsoluteFill>
    </Fade>
  );
};
