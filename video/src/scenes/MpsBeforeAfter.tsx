import { C } from "./ui";
import { makeDemo } from "./SeqDemo";

// Every number comes from the two recordings in demo-vids/mps (one run each, RTX 4070, MPS replicas 2) and the pod logs shown in them.
// Story seconds are seconds since the pods were Running (source second 2): the greedy pod stops at about 18, the steady request is answered at about 63.
const segs = [
  { from: 0, to: 22, rate: 4 },
  { from: 22, to: 56, rate: 16 },
  { from: 56, to: 78, rate: 4 },
];
const { Demo, total } = makeDemo({
  name: "MPS",
  subtitle: "Two teams share one GPU: without MPS, and with MPS",
  crop: { x: 0, y: 30, w: 940, h: 470 },
  a: { src: "demo/without-mps.mp4", base: 2, segs, label: "Without MPS", color: C.red },
  b: { src: "demo/with-mps.mp4", base: 2, segs, label: "With MPS", color: C.gold },
  outro: {
    left: [
      { pre: "Greedy job takes ", v: "7 GiB", color: C.gold },
      { pre: "Steady service ", v: "crashes", color: C.red },
    ],
    right: [
      { pre: "Greedy job limited to ", v: "5 GiB", color: C.gold },
      { pre: "Steady service ", v: "keeps working", color: C.gold },
    ],
    strength: { pre: "MPS gives every pod ", v: "its own memory limit" },
  },
});
export const MpsBeforeAfter = Demo;
export const MPS_TOTAL = total;
