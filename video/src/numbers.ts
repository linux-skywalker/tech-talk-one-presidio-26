// Every number on screen comes from here. Source: results-ubuntu-4070.md and logs/demo_split_*.log (single runs, one RTX 4070, native Ubuntu).
export const N = {
  gpu: "RTX 4070, 12 GB",
  sharing: {
    models: 6,
    readySeconds: 278,
    restarts: 0,
    memUsedMiB: 8662,
    memTotalMiB: 12282,
    aloneBusy: 22,
    sharingBusyBest: 90,
    sweepAloneBusy: 38,
    sweepSharingBusy: 93,
    answersAloneMs: 85,
    answersSharingMs: 224,
  },
  failures: {
    podRunningSeconds: 10,
    resumeSeconds: 26,
    busyAgainSeconds: 27,
    checkpoint: 75,
  },
};
