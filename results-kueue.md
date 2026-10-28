# Kueue on one RTX 4070

The full tables, versions, manifests and raw logs for Kueue are in `results-kueue-4070.md` (Kueue v0.20.3, k3s v1.36.5, quotas as memory-shaped GPU units). Raw data: `logs/kueue/`, runner: `scripts/demo/kueue/`.
Measured so far (single runs, n=1 per arm): server plus 2 training jobs (server answered at 56 s with Kueue against 208 s and 4 restarts without), inference arriving during batch work (87 s with preemption on against 206 s off), team A flood (7 of 7 jobs finished with Kueue, 3 of 7 without; share 70/30), and preemption observed (1 workload preempted in each of 3 Kueue runs).
NOT DONE YET: the 6-job workload (3 per team, mixed sizes) with per-job submit/admitted/start/finish CSV, run 3 times without Kueue and 3 times with it; and the combined DRA + Kueue test. The runner (`run.sh s5`) and the per-job CSV (`jobs.csv`) are written but have not been run.

## 6-job workload, three runs per arm (n=3 each)
Setup: the Qwen2.5-1.5B server is already running, then 6 SmolLM2 training jobs arrive together (team A: a1 medium, a2 small, a3 medium; team B: b1 small, b2 medium, b3 small). Plain = device plugin with time slicing x8, every pod asks for 1 replica, no queue (baseline A). Kueue = same cluster, jobs through the team queues (memory-shaped units: medium 3, small 1; quota 4 per team with borrowing, preemption on). Runs alternated plain, Kueue, plain, Kueue, plain, Kueue. Per-job timeline CSV for all 36 jobs: `logs/kueue/s5_all_jobs.csv` (submit, admitted, start, finish, status). Per-run folders: `logs/kueue/s5_<arm>_<run>/`.
| Measure (mean of 3 runs, with range) | No queue (plain) | Kueue |
|---|---|---|
| Jobs finished of 6 | 3 (range 2 to 4) | 6 (range 6 to 6) |
| Pods failed | 17 (range 16 to 18) | 0 (range 0 to 0) |
| Pods with CUDA out-of-memory | 16 (range 15 to 17) | 0 (range 0 to 0) |
| Time until the last finished job (s) | 209 (range 174 to 268) | 498 (range 497 to 499) |
| Jobs finished per hour | 51.5 (range 38.8 to 62.0) | 43.4 (range 43.3 to 43.4) |
| Longest wait to start, team A (s) | 0 (range 0 to 0) | 372 (range 372 to 372) |
| Longest wait to start, team B (s) | 0 (range 0 to 0) | 127 (range 126 to 127) |
| Jobs waiting while GPU memory under 9 GB (job-seconds) | 179 (range 44 to 248) | 78 (range 76 to 80) |
| Jobs waiting while GPU busy under 50% (job-seconds) | 31 (range 28 to 32) | 31 (range 30 to 32) |
| GPU busy, DCGM 1 s average (%) | 87 (range 80 to 92) | 95 (range 94 to 95) |
| GPU time share of team A (%) | 73 (range 60 to 83) | 75 (range 75 to 75) |
| Server reply time p95 (s) | 1.40 (range 1.27 to 1.46) | 1.85 (range 1.84 to 1.85) |
| Server first token p95 (s) | 0.032 (range 0.032 to 0.032) | 0.038 (range 0.037 to 0.039) |
| Server requests answered | 140 (range 117 to 179) | 320 (range 320 to 321) |
| Server restarts | 0 (range 0 to 0) | 0 (range 0 to 0) |
| Preempted workloads | 0 (range 0 to 0) | 1 (range 1 to 1) |

What this shows: across 3 runs per arm, without a queue only 2 to 4 of the 6 jobs finished (the rest crashed with CUDA out-of-memory after retries), and with Kueue all 6 finished every time with no crashed pod and almost identical timings. Kueue's cost was time: the last job finished about 2.5 to 3 times later, because jobs waited for room. The server's p95 was higher with Kueue because the server was serving next to training for much longer. Limits: jobs per hour for the plain arm counts only the jobs that finished; "memory-shaped units" are our own sizing; the quota counts units, not real memory; one machine.

## Combined test: A (no queue) vs Kueue (units) vs B (DRA + Kueue in GiB), 3 runs each
Same 6-job workload, same machine, server already running. B = NVIDIA DRA driver 0.5.1 with consumable shares (memory), jobs ask for GiB of GPU memory through ResourceClaimTemplates (server 5 Gi, medium 4.5 Gi, small 2 Gi), Kueue 0.20.3 capacity-based quota (alpha gate KueueDRAIntegrationConsumableCapacity), 5.5 Gi per team with borrowing. Device plugin off during B. B trial run 0 not counted. Raw: `logs/kueue/s5_dra-kueue_<n>/`, `logs/dra/consumable-probe.txt`, manifests `k8s/kueue/queues-dra.yaml`, `claim-templates-dra.yaml`, `dra-capacity.yaml`.

| Mean of 3 runs (range) | A: no queue | Kueue (units) | B: DRA + Kueue (GiB) |
|---|---|---|---|
| Jobs finished of 6 | 3 (2 to 4) | 6 (6 to 6) | 6 (6 to 6) |
| Pods failed | 17 (16 to 18) | 0 (0 to 0) | 0 (0 to 0) |
| Pods with CUDA out-of-memory | 16 (15 to 17) | 0 (0 to 0) | 0 (0 to 0) |
| Time to last finished job (s) | 209 (174 to 268) | 498 (497 to 499) | 507 (499 to 519) |
| Jobs finished per hour | 51.5 (38.8 to 62.0) | 43.4 (43.3 to 43.4) | 42.6 (41.6 to 43.3) |
| Longest wait to start, team A (s) | 0 (0 to 0) | 372 (372 to 372) | 381 (373 to 393) |
| Longest wait to start, team B (s) | 0 (0 to 0) | 127 (126 to 127) | 128 (120 to 141) |
| Jobs waiting while GPU memory under 9 GB (job-s) | 179 (44 to 248) | 78 (76 to 80) | 429 (426 to 430) |
| GPU busy, DCGM (%) | 87 (80 to 92) | 95 (94 to 95) | 94 (92 to 95) |
| GPU time share of team A (%) | 73 (60 to 83) | 75 (75 to 75) | 81 (81 to 82) |
| Server reply p95 (s) | 1.40 (1.27 to 1.46) | 1.85 (1.84 to 1.85) | 1.65 (1.62 to 1.67) |
| Server requests answered | 140 (117 to 179) | 320 (320 to 321) | 334 (327 to 344) |

Preempted workloads in B: 1, 2, 1 (runs 1 to 3).

What this shows: B matched the unit-based Kueue arm on outcome (6 of 6, 0 failed pods) with about the same time to finish (507 s vs 498 s, ranges overlap in part) and jobs per hour (42.6 vs 43.4). Both beat the no-queue arm on finishing jobs and lost on speed. B did not finish faster, and jobs waited longer while GPU memory sat under 9 GB (429 vs 78 job-seconds); we did not test why, a likely factor is that the GiB requests are fixed sizes and the quota is whole-claim. Server p95 was 1.65 s in B vs 1.85 s with unit Kueue (n=3 each, ranges do not overlap), not tested whether claim sizing caused it. What the device plugin cannot do and DRA did here: three pods asking for 3, 5 and 6 GiB of the one card: 3 and 5 ran together, 6 stayed Pending (`logs/dra/consumable-probe.txt`, n=1). Limits: one machine, one workload, alpha Kueue feature, DRA pod startup time not measured.
