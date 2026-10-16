# Progress summary (Phases 0 to 2a)

Talk: "Beyond kubectl apply: Elevating GPU Workflows with NVIDIA on Kubernetes".
Machine: Windows PC, RTX 4070 (12 GB), WSL2 Ubuntu 22.04, Windows-supplied driver.

## Done
- Phase 0: environment verified. nvidia-smi works in WSL2. Docker could not see the GPU until the container toolkit was installed.
- Phase 1 (traditional): uv venv, vLLM + torch 2.13 (CUDA 13.0), TRL/PEFT. LoRA fine-tune of Qwen2.5-1.5B-Instruct on 800 Alpaca examples (900 steps, ~10 min). vLLM serves base + tuned adapter.
  - Kill test: SIGKILL at step 362, last checkpoint 350, 12 steps lost, nothing restarted it, manual resume took 13 s.
  - Problems: python3-venv missing (needs sudo), vLLM 0.3 memory too small (0.4 works), FlashInfer needs nvcc (disabled).
- Phase 2a (GPU on Kubernetes): k3s + NVIDIA Container Toolkit + GPU Operator. `kubectl describe node` shows nvidia.com/gpu: 1 and a pod ran nvidia-smi.
  - Operator did NOT install the driver or toolkit (both disabled). It supplied NFD, device plugin, GFD, DCGM, validator.
  - WSL2 workarounds: cgroup v1 kubelet flag, manual PCI node label, `mount --make-rshared /` (not persistent).

## Not done yet
Dockerfiles, training Job on a PVC, inference Deployment + Service, pod-delete failure tests, time-slicing sharing test, RUNBOOK.md, results.md.

## Do not claim
- That WSL2 is a supported target, or that the Operator "just works" here.
- That the Operator installed drivers.
- Model quality from the tuned model (loss 0.11 is overfit; timing demo only).
- Any native-Linux behavior; only WSL2 was tested.
- Setup times as cold starts (Docker images and model weights were cached).

See logs/phase1_notes.md, logs/phase2a_notes.md, logs/steps.csv.
