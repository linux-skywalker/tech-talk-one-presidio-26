# Kueue on one RTX 4070

The full tables, versions, manifests and raw logs for Kueue are in `results-kueue-4070.md` (Kueue v0.20.3, k3s v1.36.5, quotas as memory-shaped GPU units). Raw data: `logs/kueue/`, runner: `scripts/demo/kueue/`.
Measured so far (single runs, n=1 per arm): server plus 2 training jobs (server answered at 56 s with Kueue against 208 s and 4 restarts without), inference arriving during batch work (87 s with preemption on against 206 s off), team A flood (7 of 7 jobs finished with Kueue, 3 of 7 without; share 70/30), and preemption observed (1 workload preempted in each of 3 Kueue runs).
NOT DONE YET: the 6-job workload (3 per team, mixed sizes) with per-job submit/admitted/start/finish CSV, run 3 times without Kueue and 3 times with it; and the combined DRA + Kueue test. The runner (`run.sh s5`) and the per-job CSV (`jobs.csv`) are written but have not been run.
