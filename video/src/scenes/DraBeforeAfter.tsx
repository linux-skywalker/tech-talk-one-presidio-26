import { C } from "./ui";
import { makeDemo } from "./SeqDemo";

// Every number comes from the two recordings in demo-vids/dra (one run each, RTX 4070) and the pod logs shown in them.
// Story seconds are seconds since the pods were Running (source second 2). Without DRA the run ends at about 38 s, with DRA at about 74 s.
const { Demo, total } = makeDemo({
  name: "DRA",
  subtitle: "Three teams share one GPU: without DRA, and with DRA",
  crop: { x: 0, y: 30, w: 890, h: 410 },
  a: {
    src: "demo/without-dra.mp4", base: 2, label: "Without DRA", color: C.red,
    segs: [{ from: 0, to: 16, rate: 4 }, { from: 16, to: 30, rate: 10 }, { from: 30, to: 49, rate: 4 }],
  },
  b: {
    src: "demo/with-dra.mp4", base: 2, label: "With DRA", color: C.gold,
    segs: [{ from: 0, to: 16, rate: 4 }, { from: 16, to: 30, rate: 10 }, { from: 30, to: 40, rate: 4 }, { from: 40, to: 68, rate: 12 }, { from: 68, to: 78, rate: 4 }],
  },
  outro: {
    left: [
      { v: "1", post: " pod crashes", color: C.red },
      { v: "2 of 3", post: " pods finish", color: C.gold },
    ],
    right: [
      { v: "0", post: " pods crash", color: C.gold },
      { v: "3 of 3", post: " pods finish", color: C.gold },
      { pre: "The 6 GiB pod ", v: "waits for room, then runs", color: C.gold },
    ],
    strength: { pre: "DRA lets a pod ask for ", v: "the GPU memory it needs" },
  },
});
export const DraBeforeAfter = Demo;
export const DRA_TOTAL = total;
