# Slide changes needed (review of `TechTalk Presentation (3).pptx`, text only)

The numbers on slides 7 to 11 match our measurements except for the points below. Slides are the presenters' to edit; this file only lists what to change and the data to use. Layout was not checked.

## Slide 9 (CUDA MPS on our RTX 4070)
1. **"Memory limit ... (n = 1)"** should say **n = 2**. The test was re-run and gave the same result (each pod sees 5.9 GiB, greedy stops at 5 GiB, steady grows 3 to 5 GiB). Source: `results-mps.md`, `logs/techniques/memtest-mps2.txt`.
2. **"kill -9 on one of two jobs"** should say **"one of two jobs killed (SIGKILL)"**. A plain `kill -9` from our user fails because the training process is root-owned; the kill was a forced pod delete, which sends SIGKILL. Result unchanged: the other job finished in 2 of 2 runs (74 s under MPS, 60 s under time slicing).

## Slide 11 (Kueue)
3. **Left diagram, "Server needs 3 units, 2 are left"** is not why the server crashed. In the no-queue run every pod asked for one GPU slot, so slots were not short; GPU memory ran out. Reword to something like "not enough GPU memory, server crash-loops".
4. **"4 restarts, first answer at 208 s"** comes from one run. Label it **n = 1** (source: `results-kueue-4070.md`, scenario 1).
5. **Add the stronger data** from the 6-job comparison, 3 runs per arm (`results-kueue.md`, `logs/kueue/s5_all_jobs.csv`):

| Mean of 3 runs | No queue | Kueue |
|---|---|---|
| Jobs finished of 6 | 3 (range 2 to 4) | 6 (range 6 to 6) |
| Pods that ran out of GPU memory | 16 | 0 |
| Time until the last job finished | 209 s | 498 s |
| GPU busy (DCGM) | 87% | 95% |

Say the cost too: Kueue finished the work about 2.4 times later because jobs waited their turn.

## Missing from the deck (for later)
- No slide for **DRA** (listed on slide 7) and none for **time slicing** (the technique with the most data). Numbers: `results-time-slicing.md`, `results-dra.md`.
