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

---

# Extra context (everything decided or discussed in the WSL2 session)

## The demo (what is being recorded)
Recorded on the PC itself, screen capture, terminal output must be clean. Flow, all commands in `RUNBOOK.md`:
1. Traditional path: train, serve, ask base vs tuned, then kill training mid-run. It stays dead until rerun by hand (WSL2: 13 s to resume, 12 steps lost).
2. Kubernetes path: apply Job and Deployment, delete the training pod and the serve pod. They recover on their own (WSL2: 62 to 98 s training, 103 to 107 s serving).
3. Sharing: second GPU pod stays Pending ("Insufficient nvidia.com/gpu"), then enable time slicing and both run, capture GPU utilization before and after.
4. Comparison table (`results.md`) with the honest points: first-time setup is slower on Kubernetes, utilization about the same, failure handling and sharing are the wins.
Needs before recording: platform already installed and `nvidia.com/gpu: 1` visible, both images built and pushed to the local registry (`localhost:5000`, `registry:2` container), model weights already downloaded, the "Reset between takes" section run (otherwise training finishes in 2 s because it resumes), a GPU monitor visible (Grafana dashboard or `watch -n1 nvidia-smi`), a rehearsal done on the recording machine. Cut or speed up the 10 min training and the 1 to 2 min recovery waits in the edit. Setup is too long to do live: show it as a timed segment with the real problems.

## The slide this demo must support
Slide "03 THE SOLUTION: Run GPUs like the rest of your software. NVIDIA GPU Operator automates the full stack to run GPU workloads on Kubernetes." Table (Area: Regular way vs Kubernetes way): Setting up: by hand on every machine vs set once, applied everywhere. Watching: check a terminal vs live dashboards. Sharing: one job blocks the GPU vs jobs share it. Failures: someone gets a message vs it restarts itself. Growing: rebuild a machine vs add a machine. Moving: rewrite for each cloud vs same setup runs anywhere.
Evidence status per row is in `SLIDE-EVIDENCE.md`. Proven on WSL2: Failures, Sharing (with the no-memory-isolation limit). Partial: Watching (Prometheus scrapes DCGM and Grafana can query it, but the dashboard panels were still empty in the browser). Not proven: Setting up (first time was slower), Growing (single node), Moving (WSL2 needed workarounds, registry is local). Safe wording and caveats are in that file.

## Open item: Grafana dashboard panels empty
Stack installed with `helm install monitoring prometheus-community/kube-prometheus-stack -f k8s/monitoring-values.yaml`; dashboard JSON `k8s/dashboards/nvidia-dcgm-12239.json` imported by `scripts/import_dashboard.sh`. Verified: scrape target up, `/api/ds/query` returns GPU util, datasource refs fixed to `{type:prometheus, uid:prometheus}`, variables default to All. Panels were still empty in the Windows browser on WSL2 (port-forward on 3000, NodePort not reachable from Windows). Debug on Ubuntu with panel Inspect > Query, or build a minimal 3-panel dashboard. DCGM exporter must run with `DCGM_EXPORTER_INTERVAL=1000` (default 30 s makes utilization lag).

## Plans for other environments (not done)
- Native Ubuntu 4070 (this machine): see the task list above. The user may install Docker Desktop or another UI for Kubernetes to watch pods.
- H100 or A100 VM on Linux, or AWS EKS: see `H100-CHECKLIST.md` and `k8s/eks/` (ECR image names, gp3 StorageClass, LoadBalancer Service, `mig-config-note.md`). MIG can only be tested there (4070 has no MIG; WSL2 cannot either). EKS accelerated AMI ships driver and toolkit, so use `driver.enabled=false --set toolkit.enabled=false`. Risk: images use torch CUDA 13.0, the AMI driver may be older than R580, rebuild with a CUDA 12.x wheel if so. Needs EBS CSI add-on. Weekend slot of 4 to 5 hours was requested from a teammate.
- Instance request sent to the provisioning teammate: smallest MIG-capable GPU, 1x H100 80 GB (AWS p5.4xlarge, about $6.88/hr on-demand us-east-1, per price aggregators, verify) or 1x A100 40 GB (GCP a2-highgpu-1g), Ubuntu 22.04 or 24.04 plain VM, 8+ vCPU, 64 GB RAM, 200 GB disk, public SSH, 4 to 5 hours, GPU quota must be checked (new accounts often have 0). Estimated cost for a 5 hour session about $35 to $50 on p5.4xlarge (p4d.24xlarge about $21.96/hr, 8 GPUs, overkill). Tear down immediately after recording.
- Predictions for EKS (untested): cgroup, PCI detection and mount problems vanish, Operator does not install the driver because the AMI has it, new problems are quota and capacity, CUDA version vs AMI driver, EBS storage, ECR and LoadBalancer. A 1.5B model barely loads an H100, utilization percentages will be lower unless batch size is raised.

## Decisions made (do not re-litigate)
- Model Qwen2.5-1.5B-Instruct, vLLM 0.31.0, LoRA 800 Alpaca examples, EPOCHS=9, checkpoints every 25 steps, auto-resume in `scripts/train.py`.
- k3s (not minikube), local registry on `localhost:5000` instead of importing images into containerd (no sudo needed).
- GPU Operator via helm with `driver.enabled=false` and `toolkit.enabled=false` on WSL2. Do not run `toolkit.enabled=true` casually: on WSL2 it crashed and left `/usr/local/nvidia/toolkit` behind, which later broke k3s's runtime selection (`logs/phase2c_notes.md`).
- Time slicing with 4 replicas via ConfigMap plus ClusterPolicy patch. No memory isolation, say so.
- Baseline GPU memory: vLLM `--gpu-memory-utilization 0.4` on WSL2 (0.3 failed), `VLLM_USE_FLASHINFER_SAMPLER=0` because there is no nvcc.
- Phase 2 failure demo uses Job `backoffLimit: 6` and Deployment `strategy: Recreate` (one GPU).
- The user prefers the walkthrough in phases with a short summary and a go-ahead between phases, and wants "what works" first and caveats last in summaries.

## Reference numbers from WSL2 (RTX 4070, Windows driver 615.78)
Traditional: install vLLM+torch 131 s, training libs 4 s, 900-step fine-tune about 10 min (3-epoch smoke 206 s), vLLM start 65 to 75 s, training 79% avg GPU, vLLM load test 69% avg / 88% peak / 1433 tok/s.
Kubernetes: platform install script 156 s, k3s cgroup fix 60 s, image builds 260 s (train 8.6 GB) and 332 s (serve 12.8 GB), Operator rollout 23 s warm, training pod Running 36 s, cold first training step 128 s, training 70% avg, serve first answer 81 to 126 s, load test 69% avg / 89% peak / 1475 tok/s, training pod delete recovery 62 to 98 s, serve pod delete recovery 103 to 107 s, sharing: Pending then 10 s to both running, 10/10 requests answered, peak 11.9 of 12.3 GB.
Incident on WSL2: after a WSL restart the GPU disappeared for about 30 min (private root mount, then a leftover toolkit directory), see `RUNBOOK.md` "If the GPU vanishes after a WSL restart".

## Branch and repo state
Remote `git@github.com:linux-skywalker/tech-talk-one-presidio-26.git` (SSH works for the user). Branch `wsl` holds all WSL2 work; `main` is behind and was deliberately not merged. Large or regenerable things are git-ignored: `.venv-trad/` (rebuild from `scripts/requirements-trad.lock` or the runbook), `outputs/` (checkpoints), `logs/*.log`.
