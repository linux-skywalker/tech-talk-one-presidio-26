# Kueue on one RTX 4070

The full tables, versions, manifests and raw logs for Kueue are in `results-kueue-4070.md` (Kueue v0.20.3, k3s v1.36.5, quotas as memory-shaped GPU units). Raw data: `logs/kueue/`, runner: `scripts/demo/kueue/`.
Measured so far (single runs, n=1 per arm): server plus 2 training jobs (server answered at 56 s with Kueue against 208 s and 4 restarts without), inference arriving during batch work (87 s with preemption on against 206 s off), team A flood (7 of 7 jobs finished with Kueue, 3 of 7 without; share 70/30), and preemption observed (1 workload preempted in each of 3 Kueue runs).
NOT DONE YET: the 6-job workload (3 per team, mixed sizes) with per-job submit/admitted/start/finish CSV, run 3 times without Kueue and 3 times with it; and the combined DRA + Kueue test. The runner (`run.sh s5`) and the per-job CSV (`jobs.csv`) are written but have not been run.

## 6-job workload, partial (work in progress, pushed mid-run)
Setup: the Qwen2.5-1.5B server is already running, then 6 SmolLM2 training jobs arrive together (team A: a1 medium, a2 small, a3 medium; team B: b1 small, b2 medium, b3 small). Plain = device plugin with time slicing x8, every pod asks for 1 replica, no queue. Kueue = same cluster, jobs through the team queues (memory-shaped units: medium 3, small 1; quota 4 per team with borrowing). Per-job timelines: `logs/kueue/s5_*/jobs.csv`. The sweep alternates plain and Kueue for 3 runs each; finished so far: plain 1, Kueue 1, plain 2; Kueue 2 is running. Means and ranges are added when all six are in.
| Run (n=1 each) | Jobs finished | Pods failed / CUDA OOM | Time to last job | GPU busy (DCGM) | Server p95 | Preempted |
|---|---|---|---|---|---|---|
| Plain 1 | 4 of 6 | 16 / 15 | 268 s | 92% | 1.455 s | 0 |
| Kueue 1 | 6 of 6 | 0 / 0 | 498 s | 95% | 1.849 s | 1 (a1) |
Plain run 2 is finished but not summarised here yet (`logs/kueue/s5_plain_2/summary.txt`).
