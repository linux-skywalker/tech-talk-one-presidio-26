# Kueue on one RTX 4070: findings so far (work in progress)

Machine: native Ubuntu 24.04.4, kernel 6.17.0-14-generic, driver 590.48.01, RTX 4070 (12 GB), k3s v1.36.5+k3s1, GPU Operator v26.7.2 (driver and toolkit installers off), Kueue v0.20.3, time slicing x8 on. Do not mix with the WSL2 or EKS tables. Hypothesis, not a result: device-aware admission may reduce pending/crashing work compared with device plugin + time slicing alone.

## Phase 0 (official docs, nothing changed)
| Question | Finding |
|---|---|
| Kueue on k3s v1.36.5 | README: "Officially supported and tested on Kubernetes 1.34 or newer"; e2e suites for 1.34 to 1.37. Installed v0.20.3 (newest on the releases page). |
| DRA in this Kubernetes | Stable since v1.35 (feature gate locked on). `resource.k8s.io/v1` is served here; no DeviceClass exists yet. |
| NVIDIA DRA driver | v0.5.1 chart. Prerequisites met on paper (k8s 1.34.2+, driver 565+, toolkit 1.18+, CDI on by default in containerd 2+). NVIDIA's guide installs the Operator with the device plugin DISABLED, so the plugin and DRA cannot be compared side by side. Prerequisites list "Data Center GPUs" for full-GPU and time slicing; the GeForce RTX 4070 is not listed, support is unverified. README says GPU allocation is "not yet officially supported". |
| Mock-device driver | kubernetes-sigs/dra-example-driver exists (8 fake 80Gi GPUs). Docs cover kind and GKE only; k3s untested. |
| Kueue + DRA | ResourceClaimTemplate path is beta (v0.18+); only ResourceClaimTemplate references and ExactCount supported. |

Phase 2 (DRA) and Phase 3 (mock devices) are NOT run yet. No DRA claim is made.

## Setup
- Quota unit = one time-sliced GPU replica, about 1.5 GB. Units are a memory-shaped convention, not isolation: serve 3 units, medium training 3, small training 1. Plain arm asks for 1 replica per pod like today.
- Two teams (`team-a`, `team-b`), ClusterQueues `cq-team-a`/`cq-team-b` (4 units each) in one cohort with borrowing, `reclaimWithinCohort: Any`. Priorities: `inference` 1000, `batch` 100. Files: `k8s/kueue/`.
- Workloads: Qwen2.5-1.5B vLLM (base model, `GPU_UTIL=0.4`) as inference; SmolLM2-135M LoRA training (batch 48, 4 epochs) as the competing jobs. Probe: one streaming chat request about every 1.5 s.
- Sizing finding (single probes): the 1.5B fine-tune plus the 1.5B server do not fit together on 12 GB. 4 of 4 co-runs hit CUDA out of memory, even with batch 1 and shorter sequences. That is why the competing jobs use the small model.
- Code: `scripts/demo/kueue/{lib.sh,run.sh,monitor.py,analyze.py,sweep.sh}`. Raw data per run: `logs/kueue/<scenario>_<arm>_<rep>/`.
- Runs were cut to one per arm by request. **Every number below is a single run (n=1), no spread.**

## Scenario 1: serve + 2 training jobs submitted together (single runs)
| | Plain (today) | Kueue |
|---|---|---|
| Inference server first answered | 208 s | 56 s |
| Server container restarts | 4 | 0 |
| Training wait, team A / team B | 0 / 0 s | 110 / 1 s |
| Both training jobs finished | 169 s | 236 s |
| Jobs per hour | 42.7 | 30.6 |
| GPU busy, average (DCGM) | 76% | 89% |
| Peak GPU memory | 9044 MiB | 9204 MiB |
| CUDA out-of-memory pods | 0 | 0 |
| Server answers recorded | 8 | 128 |
| Server p95 full-reply latency | 0.5 s | 1.07 s |

Reading, with limits:
- In the plain run the training jobs took GPU memory first; the server could not start and crash-looped until they finished. Kueue kept the server up from 56 s and made team A's job wait, so the batch finished about 67 s later.
- The latency rows are not comparable: the plain server only answered after training ended (8 samples). The 1.07 s is the only latency measured with the server and a training job sharing the card. No latency win is claimed.
- The memory-shaped units are our own convention. Without them, Kueue's quota on raw replica counts would not know memory.
- Not measured: how much of the gain comes from Kueue versus the memory-shaped requests alone (the "units" arm was dropped).

## Scenario 2: GPU busy with batch work, then inference arrives (Kueue with preemption, single run)
Submitted: team A training t1, team B training t2 and small job sm1, then 36 s later the inference server (team A, priority 1000).
| Measure (single run) | Kueue, preemption allowed |
|---|---|
| Server first answered | 87 s after t0 (about 51 s after it was submitted) |
| Training wait: t1 (team A) / t2 / sm1 (team B) | 144 / 0 / 0 s |
| All 3 batch jobs finished | 270 s |
| GPU busy, average (DCGM) | 93% |
| Peak GPU memory | 10436 MiB |
| Evictions (preemptions) | 0 |
| Out-of-memory pods, server restarts | 0, 0 |
| Server p95 full-reply latency | 1.08 s |

**Preemption was not exercised in this run.** Team A's t1 was never running when the server arrived: Kueue had admitted team B's jobs first (they were inside team B's own quota), so t1 was still queued. The server took t1's place in the queue without evicting anything, and t1 waited 144 s. So this run shows priority ordering at admission, not an eviction. Only a rerun where the low-priority job is already running when inference arrives can show preemption (for example submit t1 first and wait until it runs). Not done, and no "with versus without preemption" comparison exists. The plain and no-preemption arms of Scenario 2 and the flood scenario (3) were not run (run count cut by request).

## What we can claim so far
- Scenario 1 (n=1 each): Kueue kept the inference server up (56 s versus 208 s with 4 restarts on the plain setup) and raised average GPU busy (89% versus 76%), at the cost of a later batch finish (236 s versus 169 s).
- Scenario 2 (n=1): inference was admitted ahead of the waiting batch job. No preemption was observed.
## What we cannot claim
- Any spread or average (single runs). Any latency win. How much is Kueue versus the memory-shaped requests. Anything about DRA or mock devices (not run), MIG, other GPUs or fairness under a flood.
