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
| Grafana NodePort 30300 from the host | HTTP 200 (curl only, browser panels not confirmed) | not reachable, port-forward needed |
| Training Job: apply to pod Running | 23 s | 36 s |
| Training Job, 900 steps incl. one pod delete | 679 s (Job start to completion); resumed pod ran 750 steps at 2.03 steps/s | 13 min |
| GPU utilization, training | 83% while active (sample includes the restart gap) | 70% avg |
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
- Time to first training step after a pod restart was not measured (only delete to pod Running), so it cannot be compared with WSL2's 62 to 98 s.
- Grafana panels filling in was not confirmed in a browser.
- Not tested: MIG, a second node, a real cloud registry.
