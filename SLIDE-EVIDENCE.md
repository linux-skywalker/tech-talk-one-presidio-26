# Slide "Run GPUs like the rest of your software": claim vs evidence

Status: Proven (measured on WSL2), Partial, Not proven.

| Row | Slide says | Status | Evidence we have | What is missing or contradicts |
|---|---|---|---|---|
| Setting up | By hand on every machine vs set once, applied everywhere | Not proven | Manifests and images are reusable | First-time setup was slower on Kubernetes (about 30 min vs about 20 min) and needed 3 WSL2 workarounds. Only one machine tested. Needs the H100 run or a second machine. |
| Watching | Check a terminal vs live dashboards | Partial | Prometheus and Grafana with the NVIDIA DCGM dashboard (localhost:30300) showing live GPU utilization, memory, temperature, power. Needed DCGM_EXPORTER_INTERVAL=1000, the default 30 s lag made utilization wrong under short loads | Dashboard visuals not screenshotted here. Compare honestly: nvidia-smi gives the same numbers in a terminal. |
| Sharing | One job blocks the GPU vs jobs share it | Proven, with a limit | Second pod Pending ("Insufficient nvidia.com/gpu"); after time slicing both ran, 10/10 inference requests answered during training, no OOM | No memory isolation: peak 11.9 of 12.3 GB. MIG (real isolation) is not possible on an RTX 4070 and cannot run on WSL2. In the traditional path nothing "blocks" the GPU, jobs just compete or OOM, so word the left side carefully. |
| Failures | Someone gets a message vs it restarts itself | Proven | Training: pod deleted, Job resumed from checkpoint in 62 to 98 s. Serving: pod deleted, answering again in 103 to 107 s. Traditional: killed training stayed dead until a human reran it | Recovery is about 1 to 2 min, not instant. Resume needs checkpoints, which we wrote into the script. |
| Growing | Rebuild a machine vs add a machine | Not proven | Nothing | Single node only. Would need a second node joined to the cluster. |
| Moving | Rewrite for each cloud vs same setup runs anywhere | Not proven | Same manifests and images carry over in principle | WSL2 needed workarounds that a "same setup" claim hides. Registry is local. Needs the H100 VM run. |

## Safe wording until the gaps are closed
- Say "restarts itself" and "jobs share it" with the numbers above.
- Watching: "live dashboards" is now backed by Grafana plus DCGM. Mention the exporter interval gotcha.
- Do not show "Set once, applied everywhere", "Add a machine" or "Same setup runs anywhere" as results. Present them as the goal, or as what the H100 run will test.
- Do not say MIG. It is unsupported on this GPU and on WSL2 (`nvidia-smi mig -lgip`: "No MIG-supported devices found").

## Cheapest ways to close gaps
1. Watching: done (Grafana and DCGM scraped and queryable, but dashboard panels were still empty in the browser, see logs/phase2c_notes.md).
2. Moving and Setting up: run the H100 checklist and record which workarounds vanish.
3. Growing: join a second node (needs a second machine or VM).


## Kueue and DRA on the RTX 4070 (Ubuntu, single runs; see results-kueue-4070.md)
| Row | Slide could say | Status | Evidence | Missing or limits |
|---|---|---|---|---|
| Admission keeps inference up | With Kueue the inference server answered at 56 s instead of 208 s with 4 restarts (scenario 1) | Partial | One run each, plain vs Kueue, `logs/kueue/s1_*` | n=1, no spread; quota units are our memory-shaped convention; batch finished later (236 s vs 169 s) |
| Priority and preemption | With preemption on, inference answered at 87 s instead of 206 s while batch work was running (scenario 4) | Partial | One run each, `logs/kueue/s4_*`; Kueue recorded one preempted workload | n=1; lost work of the preempted job not measured; batch finished 68 s later |
| Higher GPU use | GPU busy 87 to 93% with Kueue vs 73 to 76% plain | Partial | DCGM averages over each run | Single runs; the plain runs left the server down, so the gap is partly that |
| Fairness across teams under a flood | Not shown | Not proven | Scenario 3 was not run | Run needed |
| Latency | No latency win | Not proven | p95 1.07 s with training load, barely loaded otherwise | Do not claim |
| DRA exposes the card | NVIDIA DRA driver published the RTX 4070 as a device and ran a pod via a claim | Proven (this machine) | `logs/dra/resourceslice-rtx4070.yaml`, pod output | NVIDIA lists data center GPUs; one machine only |
| DRA selects by attribute, shares a claim, sets time slicing per claim | CEL memory filter, shared claim, time slicing via claim | Proven, with limits | Pending/Running results, two jobs finished sharing | Needed a driver feature gate; no isolation; device plugin had to be off |
| Mock devices / mixed GPU sizes | Not shown | Not proven | Phase 3 not run | Simulation only if done |
| MIG | Theory only | Not proven | RTX 4070 has no MIG | |
| Six jobs, no queue vs Kueue | Without a queue 3 of 6 jobs finished (range 2 to 4), 16 pods ran out of GPU memory; with Kueue 6 of 6, 0 failed | Proven (this machine, n=3 per arm) | `results-kueue.md`, `logs/kueue/s5_all_jobs.csv` | Kueue finished the last job about 2.4 times later (498 s vs 209 s); 43.4 vs 51.5 jobs per hour; units are our own memory-shaped convention |
| Kueue and server latency | Server p95 1.85 s with Kueue vs 1.40 s without | Proven (n=3 per arm) | `results-kueue.md` | Server shared the card with training for longer; do not claim a latency win |
| DRA + Kueue (GiB of GPU memory) | 6 of 6 jobs, 0 failed pods, last job at 507 s, 42.6 jobs per hour, server p95 1.65 s | Proven (n=3), same outcome as unit-based Kueue | `results-kueue.md`, `logs/dra/consumable-probe.txt` | Not faster than Kueue with units; jobs waited longer with free memory (429 vs 78 job-seconds, cause untested); Kueue capacity quota is alpha |
| DRA consumable memory | 3 and 5 GiB claims ran together on the one card, a 6 GiB claim stayed Pending | Proven (n=1) | `logs/dra/consumable-probe.txt` | Needs driver gate ConsumableShares and device plugin off; this is what the device plugin cannot express |
| DRA pod startup | 0 to 1 s for a claim pod, same as a device-plugin pod (3 pods each) | Proven, no difference | `logs/dra/startup.txt` | Whole-second timestamps; image already cached |
