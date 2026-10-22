# Results: native Ubuntu 24.04, RTX 4070 (Phase 1, traditional path)

Machine: Ubuntu 24.04.4, kernel 6.17.0-14-generic, cgroup v2, NVIDIA driver 590.48.01 (native), RTX 4070 12 GB, 31 GB RAM. Measured 2026-10-19. Same model, data and versions as WSL2 (`results.md`): torch 2.13.0+cu130, vLLM 0.31.0, trl 1.14.2, peft 0.21.2, transformers 5.17.0, Python 3.10 venv via uv. Do not mix these numbers with the WSL2 table. Single runs, not averages. Raw data: `logs/steps.csv` (rows labelled `ubuntu-trad`), `logs/ubuntu_*`.

## Phase 1: traditional

| | Ubuntu 4070 | WSL2 4070 (for reference) |
|---|---|---|
| Install vLLM + torch | 106 s, cold cache | 131 s, warm cache |
| Install training libs | 3 s | 4 s |
| Fine-tune, 900 steps | 529 s train, 639 s wall incl. cold model and dataset download | about 10 min |
| GPU utilization, training | 93% while active (75% over the whole window incl. startup) | 79% avg, 84% active |
| Peak GPU memory, training | 8.2 GB | 9.7 GB |
| vLLM `GPU_UTIL=0.3` | Fails: "Available KV cache memory: -0.97 GiB" | Fails |
| vLLM `GPU_UTIL=0.4` | Works, start to ready 48 s | Works, 65 to 75 s |
| Serving load (16 clients, 60 s) | 416 requests, 6.9 req/s, 1774 tok/s, GPU 100% while active (84% over the window) | 69% avg, 88% peak, 1433 tok/s |
| Kill test | SIGKILL at step 362, last checkpoint 350, 12 steps lost, nothing restarted it (checked 20+ s), finished by hand in 325 s | same steps, 13 s to resume |
| Final loss | 0.099 (overfit, timing demo only) | 0.11 |

## Setup problems on Ubuntu
- `python3-venv` missing, same as WSL2. Fixed here with `sudo apt install python3-venv docker.io`; `uv` was still used to keep the stack identical.
- `GPU_UTIL=0.3` still fails natively, so the extra free VRAM did not help.
- FlashInfer sampler disabled in `scripts/serve.sh`, as before (no nvcc).

## Caveats
- Different driver (590.48 vs 615.78), OS and kernel from WSL2, so the gains cannot be attributed to native Linux alone. The Windows desktop held about 1.8 GB VRAM on WSL2.
- "Time to resume" in the kill test is not comparable with WSL2's 13 s: here 325 s is time to finish the remaining 550 steps, time to first step was not measured.
- The kill test used a separate output dir (`outputs/trad_kill`).
- `logs/steps.csv` holds both machines; Ubuntu rows are labelled `ubuntu-trad`.

## Phase 2: Kubernetes (k3s v1.36.5 + GPU Operator v26.7.2)

### WSL2 workarounds, needed on native Ubuntu?
| WSL2 workaround | Needed here? | Evidence |
|---|---|---|
| kubelet `fail-cgroupv1=false` | **No** | No `/etc/rancher/k3s/config.yaml`, node Ready in 27 s (cgroup v2) |
| Manual PCI node label | **No** | NFD set `pci-10de.present=true` itself |
| `mount --make-rshared /` | **No** | `/` is already shared, no mount errors |
| Operator `driver.enabled=true` | **No-op, installs nothing** | Operator created a driver pod for under 1 s, then labelled the node `gpu.deploy.driver=pre-installed` and removed it. Host driver 590.48.01 untouched. This does NOT show whether the Operator could install a driver (not tested: needs unloading the host driver under a running desktop) |
| Operator `toolkit.enabled=true` | **Breaks the node (different failure from WSL2)** | Toolkit overwrote k3s's `config.toml` and `config.toml.tmpl` with a 56 byte stub (`imports = [...]`, `version = 3`). CNI settings were lost, node NotReady ("cni plugin not initialized"), GPU pods failed on a stale `/usr/local/nvidia/toolkit/nvidia-cdi-hook` path. The helm rollback hung because its hook job could not start on a NotReady node. The stub came back when the toolkit pod was removed. Needed sudo cleanup twice (`scripts/recover_after_toolkit_test.sh`). The apt toolkit was already installed, so this test does not show a clean install failing |
| About 1.8 GB VRAM used by the Windows desktop | Mostly gone | 257 to 600 MiB used at idle (the Ubuntu desktop). `GPU_UTIL=0.3` still fails |

The Operator ran with `driver.enabled=false` and `toolkit.enabled=false` for all workload tests. It did not install the driver or the container toolkit. Both came from the host (native driver 590.48.01, apt toolkit 1.20.1).

### Measurements (single runs)
| | Ubuntu 4070 | WSL2 4070 |
|---|---|---|
| k3s ready after install script | 27 s, no workaround | 156 s script plus 60 s cgroup fix |
| Operator helm install to `nvidia.com/gpu: 1` | 33 s, cold images, no workaround | 23 s warm, plus manual label and mount |
| Image builds, cold | 258 s (train), 601 s (serve) | 260 s, 332 s (warm) |
| Monitoring stack to Grafana up | 53 s | 63 s |
| Grafana NodePort 30300 from the host | HTTP 200, dashboard panels show live data in the browser (confirmed by the user, no screenshot taken) | not reachable, port-forward needed |
| Training Job: apply to pod Running | 23 s | 36 s |
| Training Job, 900 steps incl. one pod delete | 679 s (Job start to completion); resumed pod ran 750 steps at 2.03 steps/s | 13 min |
| GPU utilization, training (clean uninterrupted run) | 89.1% avg over the last 529 s (traditional 90.5%, same window rule). The earlier 83% figure included my pod delete and is superseded | 70% avg |
| Training pod deleted, replacement Running | 34 s, resumed from checkpoint-150 by itself | 62 to 98 s delete to training |
| Serve Deployment: apply to model answering | 101 s | 126 s |
| Serve pod deleted, answering again | 81 s, no human | 103 to 107 s |
| Serving load (16 clients, 60 s) | 416 requests, 1773 tok/s, GPU 100% while active | 1475 tok/s, 69% avg |
| Second pod on a busy GPU | Pending, "Insufficient nvidia.com/gpu" | same |
| After time slicing, second training Job | **CUDA out of memory, twice** (serve holds about 4.9 GB, training needs more than the rest) | both ran, peak 11.9 of 12.3 GB |
| After time slicing, second small model (Qwen2.5-0.5B) | Both servers answered; concurrent load 546 tok/s (1.5B) + 1046 tok/s (0.5B), 8 clients each, peak 8.4 GB, GPU 99% while active | n/a |

### Incidents on this machine
- **DiskPressure:** the root partition is 92 GB with about 25 GB free. Starting the two GPU pods used about 13 GB, the kubelet reported the image filesystem 95% full, and it evicted every pod (dozens of Evicted entries). It cleared by itself after a few minutes. Fixed by removing Docker's duplicate image copies (12 GB) and moving Docker and k3s storage to /home with bind mounts (`scripts/move_storage_to_home.sh`). The cause of the temporary 95% was not diagnosed (no root access to containerd's directory).
- **Toolkit test:** see the table above.

### Caveats
- Single runs on one machine, different driver and OS from the WSL2 numbers.
- Not tested: MIG, a second node, a real cloud registry.

## Closing the open comparisons (all single runs, this machine)

| Comparison | Traditional | Kubernetes | Reading |
|---|---|---|---|
| Training speed and utilization, uninterrupted, same 529 s window rule | 1.704 steps/s, 90.5% avg util, loss 0.4461, peak 8.2 GB | 1.701 steps/s, 89.1% avg util, loss 0.4473, peak 8.5 GB | No difference. Kubernetes neither speeds up nor slows training. Dips to 0 to 30% in both are the checkpoint saves |
| Serving throughput (16 clients, 60 s) | 1774 tok/s | 1773 tok/s | No difference |
| Training killed or pod deleted | Dead until a human reruns it. Resume by hand finished the remaining steps in 325 s | Pod replaced automatically; first training step logged about 51 s after the delete (pod created about 9.5 s, Running 31.6 s, resume line 47.5 s). WSL2: 62 to 98 s | Kubernetes wins on not needing a human. Recovery is not instant: the old pod holds the GPU while it terminates |
| Serving killed or pod deleted | `kill -9`: no process, no answer, nothing restarted it in 30+ s. Human restart then answered in 28 s (warm) | Pod deleted: answering again in 81 s, no human | Manual restart is faster once someone notices; Kubernetes removes the noticing. Detection time by a human is unbounded and was not measured |
| Nothing to first serving, first time | about 13.3 min: venv 1 s + installs 109 s + fine-tune 639 s (cold download) + vLLM 48 s. Excludes `apt install python3-venv` and one failed vLLM attempt at 0.3 (not timed) | about 27.8 min: Operator 33 s + image builds 859 s (258 + 601) + training Job 676 s + serve Deployment 101 s. Excludes the sudo install of toolkit, Docker runtime and k3s (untimed here; 156 s on WSL2), the helm install, and the stub-recovery incident | First-time setup is about twice as long on Kubernetes, dominated by the one-time image builds (14 of the 28 min). This is not a Kubernetes advantage |
| Second run of the same thing | Same commands again, 28 s to serve (warm), all flags remembered | `kubectl apply`: training pod Running in 23 s, serve answering in 101 s | Similar once everything exists. Kubernetes cost is paid once up front |

What these results do not show: Growing (second node), Moving (another cloud or registry), MIG, the Operator installing a driver or toolkit on a clean host. Do not claim them.

## MPS test (software memory limits, NOT MIG)

The RTX 4070 has no MIG (`nvidia-smi mig -lgip`: "No MIG-supported devices found"; MIG mode `N/A`). The closest feature that runs here is CUDA MPS through the Operator's device plugin (`k8s/mps-config.yaml`, 2 replicas). Test `k8s/mps-memtest.yaml`: a "greedy" pod allocates 1 GiB chunks until it fails and holds them; a "steady" pod holds 3 GiB and at t=60 s tries to grow by 2 GiB. Same pods, same GPU, 11.6 GiB total.

| | Time slicing (4 replicas) | MPS (2 replicas) |
|---|---|---|
| Memory each pod sees | free 10.8 of 11.6 GiB (everything) | free 5.9 of 11.6 GiB (its own limit) |
| Greedy pod stops at | 7 GiB (takes all that is left) | 5 GiB (its own limit) |
| Steady pod grows 3 to 5 GiB | **Fails: OutOfMemoryError** | **Succeeds** |
| Node advertises | `nvidia.com/gpu: 4`, strategy `time-slicing` | `nvidia.com/gpu: 2`, strategy `mps`, applied in 37 s |

Reading: MPS gives per-pod memory limits that time slicing does not, so a greedy neighbour cannot starve another pod. Single run each.

Limits, state plainly:
- This is MPS, not MIG. Do not call it MIG or hardware isolation. MPS clients share one fault domain, so a crash in one client can affect the others (from NVIDIA's MPS design, not tested here).
- Only memory limits were tested, not the compute (thread percentage) split, and not a crash in one client.
- The Operator was returned to no-sharing afterwards (`nvidia.com/gpu: 1`).

## Full rehearsal (sharing skipped), 2026-10-19

`scripts/rehearsal.sh` runs RUNBOOK-UBUNTU-DEMO.md sections 1 to 4 and 6 end to end with PASS or FAIL checks (log: `logs/rehearsal_ubuntu.log`). Result: 28 of 28 checks passed, 1441 s (24 min) in total, from a reset state, warm images and cached model.

| Step | Time |
|---|---|
| Traditional: kill at step 362, last checkpoint 350, nothing restarted it, manual resume to done | 341 s |
| Traditional: vLLM start to ready | 44 s |
| Kubernetes: training pod Running after apply | 7 s |
| Kubernetes: pod delete to replacement Running (resumed from checkpoint-150) | 32 s |
| Kubernetes: serve apply to tuned model answering | 78 s |
| Kubernetes: serve pod delete to answering | 77 s |

These warm numbers (images already on the node) are lower than the first-run numbers above (pod Running 23 s, serve 101 s). Quote them as warm. One run.


## Many tiny models on one GPU (SmolLM2-135M-Instruct, single runs, RTX 4070)

Model: HuggingFaceTB/SmolLM2-135M-Instruct, `GPU_UTIL=0.1`. One copy alone uses about 1.3 GB of GPU memory (ready in 41 s). Manifests: `k8s/serve-tiny.yaml` (StatefulSet, 6 replicas, NodePort 30082), `k8s/time-slicing-8.yaml`.

| Step | Traditional (6 vLLM processes, ports 8101-8106) | Kubernetes (6 pods, time slicing x8) |
|---|---|---|
| Start all 6 at once | All 6 died: "No available memory for the cache blocks" (each copy counted the others' memory) | Deployment with 6 replicas: crash-looped and retried by itself; 4 of 6 ready after 10 min, not settled |
| Start one at a time | 5 of 6 came up in 257 s; the 2nd failed with the same error, nothing retried it | StatefulSet, ordered start: 6 of 6 ready, 0 restarts, about 65 s per pod (about 7 min total) |
| GPU memory with all up | 7.3 GB (5 copies) | 8.5 GB (6 copies) |
| Kill one while serving | not tested here (earlier vLLM kill test: stays dead until a human restarts it) | pod delete: 39 of 40 requests OK during recovery, 1 failed, 6 of 6 ready again after 72 s |

Throughput, 24 concurrent clients, 30 s, through the Service (`scripts/loadtest.sh`):

| Setup | tokens/s | req/s | avg GPU util |
|---|---|---|---|
| 1 pod | 12814 | 50.3 | 94% |
| 6 pods (time slicing) | 2474 | 9.7 | 93% |

Findings, stated plainly:
- Six time-sliced copies were about 5x SLOWER in total than one copy. One tiny vLLM server with batching already saturates the GPU. Packing more copies does not add throughput; time slicing adds context-switch cost.
- So the case for many tiny models is not speed. It is that several different models or tenants can share one card, get restarted by themselves, and sit behind one Service address.
- The traditional way can also run several servers by hand. What we saw was the manual overhead (ports, memory fractions, a start order that must be found by trial) and that a failed one stays failed.
- A single load generator run per row; no repeats. 1 failed request during the pod delete is real.

### Light traffic: one tiny copy alone vs six sharing the card (SmolLM2-135M, single runs, RTX 4070)

Six-pod StatefulSet (`k8s/serve-tiny.yaml`, per-pod ports in `k8s/serve-tiny-ports.yaml`), time slicing x8. Each pod gets light traffic from `scripts/loadtest-light.sh`: one client, a 64-token request about every 0.5 s, 30 s per run. "Alone" means the other five pods were running but idle. `serve-tiny-0` had 1 restart during the ordered start (cause not checked).

| Run | Pods under load | Mean latency per pod | p95 latency per pod | Avg GPU util |
|---|---|---|---|---|
| A. pod 0 alone | 1 | 85 ms | 99 ms | 10% |
| B. all six together | 6 | 177 to 197 ms | 313 to 348 ms | 68% |
| C. pod 0 alone again | 1 | 84 ms | 99 ms | 14% |

- Sharing the card made each copy's latency about 2.2x higher on average and about 3.3x at p95. Everyone still answered in well under a second, and all six got the same service (spread of 20 ms in the mean).
- GPU busy went from 10 to 14% (one copy) to 68% (six copies) with the same per-copy traffic. That is the "less idle hardware" result, with a latency cost.
- Memory: 8.8 GB of 12 GB with six copies loaded.
- Not shown: any benefit from 6 cards vs 1 (not run, arithmetic only); heavier load (see the 5x throughput result above).

## Full rehearsal, second run (20 Oct 2026, RTX 4070, single run)

`scripts/rehearsal.sh` (runbook sections 1-4 and 6, sharing skipped): **28 of 28 checks passed, 1448 s total** (earlier run: 28 of 28, 1441 s). Log: `logs/rehearsal_ubuntu_run2.log`. A first attempt of this run was discarded because a leftover `serve-tiny` pod from a dashboard test was still on the GPU; the rehearsal's reset step now also deletes `k8s/serve-tiny.yaml`.

| Step | This run | Earlier run |
|---|---|---|
| Training killed at step 362 | last checkpoint 350, 12 steps lost, nothing restarted it | same |
| Manual resume to done | 337 s | 341 s |
| vLLM start to ready | 34 s | 44 s |
| Training pod Running after apply | 7 s | 7 s |
| Training pod delete to replacement Running | 31 s, resumed from checkpoint-150 | 32 s |
| Serve Deployment apply to answering | 79 s | 78 s |
| Serve pod delete to answering | 77 s | 77 s |

Repeatability: the two runs agree within a few seconds on every step except vLLM start (34 vs 44 s). Report: `reports/review-report.html`; Grafana: `/d/gpu-review`.

### GPU busy as traffic grows: one tiny copy alone vs six sharing (SmolLM2-135M, 30 s per level, single runs, RTX 4070)

Same six-pod setup as above (`k8s/serve-tiny.yaml`, time slicing x8). `CLIENTS` clients per model, each sends a 64-token request then waits `PAUSE` s (`scripts/loadtest-light.sh`). GPU busy is DCGM utilization sampled every 2 s over the run. Raw output: `logs/sweep_raw.txt`.

| Traffic per model | One copy: GPU busy, req/s, mean | Six sharing: GPU busy, total req/s, mean |
|---|---|---|
| Light (1 client, pause 0.5 s) | 14%, 1.7, 81 ms | 49 to 71% (3 runs: 68, 71, 49), 8.2 to 8.4, 214 ms |
| Moderate (1 client, pause 0.1 s) | 38%, 5.3, 81 ms | 93% (2 runs), 11.9, 396 ms (p95 474) |
| Busy (2 clients, pause 0.1 s) | 67%, 10.3, 88 ms | 93%, 19.0, 522 ms |
| Saturated (4 clients, no pause) | 92%, 40.5, 94 ms | 93%, 41.9, 562 ms |

- Six models sharing the card reach 93% GPU busy at moderate traffic; one model alone at the same per-model setting is 38% busy. The card stays at 93% as traffic grows, and answer time rises (396 to 562 ms mean).
- GPU busy is not useful work. At saturation one copy alone delivers about the same total requests per second as six sharing (40.5 vs 41.9), so sharing adds no throughput there. At the moderate level the six models together completed 11.9 req/s while the card showed 93% busy, whereas one copy at 92% busy completed 40.5 req/s: time slicing pays switching cost. The honest benefit of sharing is fitting several different models on one card, not more work per card.
- The lightest level varied between runs (49 to 71%) because of where the 2 s samples fell relative to the load; use the moderate level (93%, both sweeps) for a stable number.


## Growing: worker VMs joined one at a time (CPU replicas, not GPU)
Run: `bash scripts/demo/vm-grow.sh 3` (log `logs/demo_vm_run5.log`). Multipass VMs (2 vCPU, 3 GB each) join the running k3s cluster; one CPU-only copy of SmolLM2-135M (Q8_0 GGUF, llama.cpp server) per VM, `k8s/serve-cpu.yaml`. Load: 60 requests, 8 at a time, only HTTP 200 counted. Single run. The GPU stays on the host node; the VMs have no GPU, so this says nothing about GPU capacity.

| VMs | Node Ready after launch | Model serving after launch | Requests OK | Requests/s |
|---|---|---|---|---|
| 1 | 65 s | 73 s | 60 of 60 | 13.2 |
| 2 | 66 s | 74 s | 60 of 60 | 18.5 |
| 3 | 86 s | 95 s | 60 of 60 | 21.2 |

- Scaling is sub-linear (1.4x with 2 VMs, 1.6x with 3). Cause not investigated (shared host cores, one NodePort entry point, or load imbalance are possible).
- The k3s binary, the llama.cpp image (310 MB tar) and the model file were copied into each VM from local files. Cold, a single image pull took about 8 min and the k3s download from GitHub stalled, because downloads were slow that day. The 65 to 95 s figures exclude that.
- An earlier attempt (run 3) printed 2278 requests/s because failed requests were counted; that number is invalid and the script now counts only HTTP 200.
- Multipass could not download its own Ubuntu image on this machine (cause unknown), so the VMs launch from a local cloud image.
