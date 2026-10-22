# Kueue on one RTX 4070

The full tables, versions, manifests and raw logs for Kueue are in `results-kueue-4070.md` (Kueue v0.20.3, k3s v1.36.5, quotas as memory-shaped GPU units). Raw data: `logs/kueue/`, runner: `scripts/demo/kueue/`.
Measured so far (single runs, n=1 per arm): server plus 2 training jobs (server answered at 56 s with Kueue against 208 s and 4 restarts without), inference arriving during batch work (87 s with preemption on against 206 s off), team A flood (7 of 7 jobs finished with Kueue, 3 of 7 without; share 70/30), and preemption observed (1 workload preempted in each of 3 Kueue runs).
NOT DONE YET: the 6-job workload (3 per team, mixed sizes) with per-job submit/admitted/start/finish CSV, run 3 times without Kueue and 3 times with it; and the combined DRA + Kueue test. The runner (`run.sh s5`) and the per-job CSV (`jobs.csv`) are written but have not been run.

## 6-job workload, runs so far (work in progress, each row is one run, n=1)
Setup: the Qwen2.5-1.5B server is already running, then 6 SmolLM2 training jobs arrive together (team A: a1 medium, a2 small, a3 medium; team B: b1 small, b2 medium, b3 small). Plain = device plugin with time slicing x8, every pod asks for 1 replica, no queue. Kueue = same cluster, jobs through the team queues (memory-shaped units: medium 3, small 1; quota 4 per team with borrowing). Per-job timelines: `logs/kueue/s5_*/jobs.csv`. Kueue run 3 was still running when this was pushed; means and ranges are added when it finishes.
| Arm | Run | Jobs finished | Pods failed / CUDA OOM | Time to last job (s) | Longest start wait A / B (s) | GPU busy DCGM | Server p95 (s) | Server answers | Preempted |
|---|---|---|---|---|---|---|---|---|---|
| plain | 1 | 4 of 6 | 16 / 15 | 268 | 0 / 0 | 92% | 1.455 | 179 | 0 |
| plain | 2 | 2 of 6 | 18 / 16 | 185 | 0 / 0 | 89% | 1.462 | 125 | 0 |
| plain | 3 | 3 of 6 | 17 / 17 | 174 | 0 / 0 | 80% | 1.273 | 117 | 0 |
| kueue | 1 | 6 of 6 | 0 / 0 | 498 | 372 / 127 | 95% | 1.849 | 320 | 1 |
| kueue | 2 | 6 of 6 | 0 / 0 | 497 | 372 / 126 | 95% | 1.847 | 320 | 1 |
