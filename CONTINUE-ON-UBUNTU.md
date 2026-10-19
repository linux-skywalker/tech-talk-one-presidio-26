# Continue on native Ubuntu (RTX 4070)

Handoff for a fresh machine and a fresh Claude Code session with no prior context. Read this file first, then `SUMMARY.md`, `results.md`, `RUNBOOK.md`, `SLIDE-EVIDENCE.md`, `H100-CHECKLIST.md`.

## Project
A proof of concept for the tech talk "Beyond kubectl apply: Elevating GPU Workflows with NVIDIA on Kubernetes". Thesis: Kubernetes plus NVIDIA's tools improve the GPU experience compared with the traditional manual way. The POC takes one small model through fine-tuning and inference twice (traditional vs Kubernetes) and compares three things: GPU utilization, behavior on failure, time from nothing to serving. The result will be screen-recorded on the PC itself.

Repo: `git@github.com:linux-skywalker/tech-talk-one-presidio-26.git`. Everything so far is on branch `wsl` (`main` is behind). Make a new branch for this machine, for example `ubuntu-4070`, and do not mix its numbers with the WSL2 numbers.

## Why this machine
All work so far ran on WSL2 (Windows PC, RTX 4070, Windows driver 615.78). WSL2 is not a supported target for NVIDIA's Kubernetes stack and needed workarounds. The goal here is to see which of them disappear on native Ubuntu, and to repeat the comparison on a clean Linux box. The only GPU here is the same RTX 4070 (12 GB, no MIG).

## Chosen stack (keep it identical so results are comparable)
- Model: Qwen/Qwen2.5-1.5B-Instruct. LoRA fine-tune with transformers, PEFT, TRL on 800 Alpaca examples (tatsu-lab/alpaca), 900 steps (EPOCHS=9), about 10 min.
- Inference: vLLM 0.31.0, base model plus the tuned adapter (`tuned`).
- Kubernetes: single-node k3s, NVIDIA Container Toolkit, NVIDIA GPU Operator via helm.
- Versions used on WSL2: torch 2.13.0 (CUDA 13.0 wheel), trl 1.14.2, peft 0.21.2, transformers 5.17.0, k3s v1.36.5, toolkit 1.20.1, helm 3.19.0.

## What was done and measured on WSL2
- Traditional path works end to end. Training averaged 79% GPU (84% when active), vLLM 81% under load. Kill test: SIGKILL at step 362, last checkpoint 350, 12 steps lost, nothing restarted it, 13 s to resume by hand.
- Kubernetes path works: `kubectl describe node` shows `nvidia.com/gpu: 1`, a pod ran nvidia-smi, training Job on a PVC (13 min), serving Deployment plus NodePort (answer 109 to 126 s after apply), training pod deleted and Job resumed from checkpoint in 62 to 98 s, serve pod deleted and answering again in 103 to 107 s, training utilization 70% average.
- Sharing: with one GPU, the second pod stays Pending ("Insufficient nvidia.com/gpu"). After enabling time slicing (4 replicas) both ran, 10/10 inference requests answered during training, peak 11.9 of 12.3 GB (no memory isolation).
- First-time setup was slower on Kubernetes (about 30 min vs about 20 min), approximate.

## WSL2 problems that should disappear natively (verify each, record yes/no)
| WSL2 workaround | Expected on native Ubuntu |
|---|---|
| k3s 1.36 kubelet refused cgroup v1, needed `fail-cgroupv1=false` in `/etc/rancher/k3s/config.yaml` | Not needed on cgroup v2 (`stat -fc %T /sys/fs/cgroup` should print `cgroup2fs`) |
| Operator could not see the GPU (no PCI device), needed `kubectl label node <node> feature.node.kubernetes.io/pci-10de.present=true` | NFD should label it automatically |
| Operator pods failed with "path / is mounted on / but it is not a shared or slave mount", needed `sudo mount --make-rshared /` | Not needed |
| Operator `toolkit.enabled=true` crashed: "no NVIDIA devices found" (WSL2 has /dev/dxg, not /dev/nvidia*) | Should work |
| Operator `driver.enabled=true` pulled a driver container (595.91.07) that never became Ready | Open question. GeForce is not on the Operator's official support list, so this is untested and medium confidence |
| About 1.8 GB of the 12 GB VRAM was used by the Windows desktop | All 12 GB available. Re-check vLLM `GPU_UTIL` (0.3 failed on WSL2, 0.4 worked) |

## Task list for this machine
1. Prerequisites: Ubuntu 22.04 or 24.04, NVIDIA driver, `nvidia-smi` works, Docker. Record `uname -r`, cgroup type, driver version.
2. Phase 1 (traditional): follow `RUNBOOK.md` Phase 1. Python venv may need `python3-venv` (needs sudo; on WSL2 it was missing and `uv` was used instead). Re-measure times, GPU utilization, kill test.
3. Phase 2 (Kubernetes): follow `RUNBOOK.md` Phase 2, but first try WITHOUT the three WSL2 workarounds and record whether each is needed. Time every step with `scripts/log_step.sh`. Try the Operator with `driver.enabled=true` and `toolkit.enabled=true` (for k3s the toolkit needs these env vars: `CONTAINERD_CONFIG=/var/lib/rancher/k3s/agent/etc/containerd/config.toml.tmpl`, `CONTAINERD_SOCKET=/run/k3s/containerd/containerd.sock`, `CONTAINERD_RUNTIME_CLASS=nvidia`, `CONTAINERD_SET_AS_DEFAULT=true`; see `H100-CHECKLIST.md` for the helm flags). Only claim the Operator installed the driver or toolkit if it actually did.
4. Failure tests and sharing test as in the runbook (delete training pod, delete serve pod, second Job Pending, then time slicing).
5. Already done on WSL2, repeat here for comparison: serving load test (`scripts/loadtest.sh <port> <model> 60 16`, WSL2: 69% avg / 88% peak, 1433 tok/s traditional vs 69% / 89%, 1475 tok/s Kubernetes) and the Grafana + DCGM dashboard (`RUNBOOK.md`, "Monitoring"; WSL2 Operator rollout took 23 s warm). Set `DCGM_EXPORTER_INTERVAL=1000` or utilization lags by 30 s.
6. Do not run the Operator with `toolkit.enabled=true` on a host that already has the apt toolkit and k3s unless that is the thing being tested: on WSL2 it left `/usr/local/nvidia/toolkit` behind and k3s later switched to that broken runtime (see `logs/phase2c_notes.md`). If you test it natively, check `/usr/local/nvidia` afterwards.
7. Write a results table for this machine in a new file (for example `results-ubuntu-4070.md`) with the same rows as `results.md`, plus a column per workaround: needed yes/no.

## Working rules (from the original brief)
- Be concise, make decisions, keep moving. Do not use em dashes in anything written.
- Ask before system-wide installs (apt, toolkit, k3s, Docker config), before changing system settings, and before deleting anything outside this folder. `sudo` needs the user's password, so give them the exact command to run.
- Be honest and put real measured numbers in results. If the Kubernetes path is slower to set up, say so. Say plainly when something is uncertain or unsupported.
- Keep terminal output clean, commands copy-paste-able. The final run will be screen-recorded.

## Pitfalls already hit (save yourself the time)
- Both training scripts auto-resume from the latest checkpoint. A second run on old outputs ends in about 2 s ("done in 2s"). Reset between takes (`RUNBOOK.md`, "Reset between takes").
- vLLM: FlashInfer sampler JIT needs `nvcc`, so serve with `VLLM_USE_FLASHINFER_SAMPLER=0` (already in `scripts/serve.sh`). vLLM at `--gpu-memory-utilization 0.3` ran out of KV cache memory on WSL2.
- The default vLLM in a pod can take 75 to 125 s to be ready. Use a health check in wait loops (`curl localhost:PORT/v1/models` plus a liveness check on the process) so a dead server does not hang the loop.
- zsh aborts a whole command line on an unmatched glob (for example `rm -f logs/foo_*` with no matches).
- `pkill -f "scripts/train.py"` matches its own shell; use `pkill -f '[s]cripts/train.py'`.
- A deleted GPU pod stays Terminating for up to about 60 s and holds the GPU, so its replacement sits Pending until then. This is why recovery is 1 to 2 minutes.
- Image registry was a local `registry:2` on `localhost:5000`; k3s pulled from it without extra config. Images are large (train 8.6 GB, serve 12.8 GB).
- Time slicing has no memory isolation. Do not claim isolation. MIG is not available on the 4070.

## Do not claim in the talk
- WSL2 is a supported target, or that things "just work" there.
- The Operator installed the driver or toolkit (unless it did, on this machine).
- Kubernetes makes training faster or raises GPU utilization (it did not: 79% vs 70%).
- Time slicing isolates memory.
- Anything about MIG, multi-node, or second-machine portability until it is tested.
- Model quality (loss 0.11 is overfit, timing demo only).

## Files
- `scripts/`: `train.py`, `serve.sh`, `ask.sh`, `gpu_sample.sh`, `log_step.sh`, `phase2_install.sh` (sudo: container toolkit, docker runtime, k3s), `requirements-trad.lock`.
- `docker/`: `Dockerfile.train`, `Dockerfile.serve`.
- `k8s/`: `pvc.yaml`, `train-job.yaml`, `serve-deployment.yaml`, `train-share-job.yaml`, `time-slicing-config.yaml`, `smoke-nvidia-smi.yaml`.
- `logs/`: raw measurements and notes (`steps.csv`, `phase1_notes.md`, `phase2a_notes.md`, `phase2b_notes.md`, `rehearsal.md`).

## Prompt to paste into Claude Code on the new machine
```
Read CONTINUE-ON-UBUNTU.md in this repo and follow it. I am on native Ubuntu with an RTX 4070. Start with step 1 (verify the environment) and report before continuing. Work phase by phase, ask before system-wide installs, and give me exact sudo commands to run.
```
