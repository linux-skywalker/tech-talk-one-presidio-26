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

Phase 2 (DRA) was run, see the DRA section. Phase 3 (mock devices) was NOT run.

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

## Scenario 2 (first attempt): batch jobs and inference submitted close together, Kueue with preemption (single run)
Submitted: team A t1, team B t2 and sm1, then 36 s later the inference server (team A, priority 1000).
| Measure (single run) | Kueue |
|---|---|
| Server first answered | 87 s after t0 (about 51 s after it was submitted) |
| Training wait: t1 (team A) / t2 / sm1 (team B) | 144 / 0 / 0 s |
| All 3 batch jobs finished | 270 s |
| GPU busy, average (DCGM) | 93% |
| Peak GPU memory | 9995 to 10436 MiB |
| Out-of-memory pods, server restarts | 0, 0 |
| Server p95 full-reply latency | 1.08 s |

CORRECTION to an earlier version of this file: it said no preemption happened here. That was wrong. The Workload record of t1 shows `Requeued: Preempted to accommodate a workload ... due to priority`. My first metric only counted evictions whose status was still True, and t1 had already been re-admitted. This run did not capture whether t1's pod had started before it was preempted, so it is not a clean preemption test. The same record shows t1 preempted in Scenario 1 ("due to reclamation": team B took back its own quota from team A's borrowed units).

## Scenario 4: batch work already RUNNING when inference arrives (single runs, clean preemption test)
Team A submits two training jobs (3 units each, 6 of 8 units). After both are Running, inference (3 units, priority 1000) arrives at about 13 s.
| Measure (single run each) | Kueue, preemption off | Kueue, preemption on |
|---|---|---|
| Server first answered (after t0) | 206 s | 87 s |
| Batch jobs finished | 2 of 2, both at 170 s | 2 of 2, all done at 238 s |
| What happened | server waited for the batch jobs (SchedulingGated) | Kueue preempted `t2` to admit the server; `t2` was re-admitted later |
| Preempted workloads | 0 | 1 (`t2`, message "due to priority") |
| GPU busy, average (DCGM) | 73% | 87% |
| Server answers recorded | 6 | 100 |
| Server p95 full-reply latency | 0.50 s (barely under load) | 1.07 s (under training load) |
| Out-of-memory pods, server restarts | 0, 0 | 0, 0 |

Limits: `t2`'s 112 s queue wait in the summary is for its restarted pod. Whether it resumed from a checkpoint was not captured (pod logs were not kept). The tool counted preemptions wrongly before the fix in `analyze.py`; all summaries were regenerated with the corrected count.

## What we can claim so far (single runs, no spread)
- Scenario 1: Kueue kept the inference server up (56 s versus 208 s and 4 restarts on the plain setup) and raised average GPU busy (89% versus 76%), at the cost of a later batch finish (236 s versus 169 s).
- Scenario 4: with preemption on, inference answered at 87 s instead of 206 s while the batch work was running; the price was one training job being preempted and re-run (batch finished 68 s later).
## What we cannot claim
- Any average or spread. Any latency win. How much is Kueue versus the memory-shaped requests. Anything about mock devices (not run), MIG, Kueue together with DRA (not tested), other GPUs or fairness under a flood (Scenario 3 not run). Preempted-job lost work.

## Phase 2: DRA on the RTX 4070 (single attempts, nothing averaged)
Setup: NVIDIA DRA driver chart 0.5.1 (`nvidiaDriverRoot=/`, host-installed driver, GPU allocation only), GPU Operator device plugin DISABLED by patching the ClusterPolicy (reversible), node labelled `nvidia.com/dra-kubelet-plugin=true`. Manifests: `k8s/kueue/dra-*.yaml`, evidence: `logs/dra/`. Configs were backed up first (`backups/`, git-ignored).
| Test | Result |
|---|---|
| Does the driver accept a GeForce card? | **Yes.** It published one device `gpu-0` in a ResourceSlice: productName "NVIDIA GeForce RTX 4070", brand GeForce, Ada Lovelace, capacity 12282Mi, driver 590.48.1. NVIDIA's prerequisites page lists "Data Center GPUs", so this goes beyond the documented hardware list; it is one machine, not a support statement. |
| Pod with a ResourceClaimTemplate (1 GPU, no `runtimeClassName`) | Running; `nvidia-smi -L` inside lists the RTX 4070. |
| Second pod, its own claim | **Pending**: "cannot allocate all claims"; the GPU is exclusive per claim, so with one device a second claim waits. |
| Two pods sharing ONE ResourceClaim | Both Running on the same GPU. No memory isolation was tested. |
| CEL selector on memory | `>= 10Gi` Running; `>= 20Gi` Pending (the card has 12 GiB). Selecting by attribute works, with one device it can only accept or reject. |
| Time slicing in the claim (opaque `GpuConfig`, `strategy: TimeSlicing`, interval Long) | First try failed: the pod stuck in ContainerCreating with `"TimeSlicing" is selected as the GPU sharing strategy, but the "TimeSlicingSettings" feature gate is not enabled`. After enabling the driver feature gate (`helm --set featureGates.TimeSlicingSettings=true`), two SmolLM training jobs using one claim both succeeded, 50 s each, concurrently. |
| Revert | Chart uninstalled, node label removed, device plugin re-enabled; allocatable `nvidia.com/gpu` back to 8, DCGM exporter and device plugin Running. |

What DRA can and cannot express with one device (from these tests only):
- Can: ask for a device by attribute (memory, product), share one claim between pods, set time-slicing per claim instead of a node-wide replica count.
- Cannot (here): more than one claimant exclusively, any isolation between sharers, and anything about MIG/MPS (not tested). The device plugin and DRA could not be used side by side (plugin disabled while DRA ran), so there is no concurrent comparison. Time slicing gave no memory limits, same as the device-plugin version.
- Not tested: Kueue with DRA (ResourceClaimTemplate path), vLLM under DRA, behaviour over upgrades.
