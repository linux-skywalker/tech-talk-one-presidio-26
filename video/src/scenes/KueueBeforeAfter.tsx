import { C } from "./ui";
import { makeDemo } from "./SeqDemo";

// Every number comes from the two recordings in demo-vids/kueue (one run each, RTX 4070, kernel 7.0.0-38, driver 595.99.02)
// and the run folders logs/kueue/s5_plain_9 and logs/kueue/s5_kueue_9. Source seconds: jobs are submitted at about 63 s; the run summary shows at 253.8 s and 596.3 s.
const RATE = 35;
const { Demo, total } = makeDemo({
  name: "Kueue",
  subtitle: "Same jobs on one GPU: without a queue, and with Kueue",
  crop: { x: 0, y: 20, w: 1040, h: 500 },
  a: { src: "demo/without-kueue.mp4", base: 58, segs: [{ from: 0, to: 195.8, rate: RATE }], label: "Without a queue", color: C.red },
  b: { src: "demo/with-kueue.mp4", base: 58, segs: [{ from: 0, to: 538.3, rate: RATE }], label: "With Kueue", color: C.gold },
  outro: {
    left: [
      { v: "3 of 6", post: " jobs finish", color: C.gold },
      { v: "15", post: " pods crash", color: C.red },
    ],
    right: [
      { v: "6 of 6", post: " jobs finish", color: C.gold },
      { v: "0", post: " pods crash", color: C.gold },
      { pre: "Jobs ", v: "wait for room, then run", color: C.gold },
    ],
    strength: { pre: "Kueue makes jobs ", v: "wait for their turn", post: " instead of crashing" },
  },
});
export const KueueBeforeAfter = Demo;
export const KUEUE_TOTAL = total;
