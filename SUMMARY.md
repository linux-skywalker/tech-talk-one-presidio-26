# Progress summary (Phases 0 to 3)

Talk: "Beyond kubectl apply: Elevating GPU Workflows with NVIDIA on Kubernetes".
Machine: Windows PC, RTX 4070 (12 GB), WSL2 Ubuntu 22.04, Windows-supplied driver.

## Status at a glance

| Piece | Status | Evidence |
|---|---|---|
| GPU visible in WSL2 | Working | nvidia-smi: RTX 4070, driver 615.78 |
| Traditional fine-tune (LoRA, Qwen2.5-1.5B) | Working | 900 steps in about 10 min, GPU 66-79% avg |
| Traditional inference (vLLM, base + tuned adapter) | Working | Answers differ between base and tuned; GPU 81% under load |
| Traditional failure test | Working | Killed at step 362, resumed from step 350, 12 steps lost, 13 s to resume |
| Docker GPU access (NVIDIA Container Toolkit) | Working | `docker run --gpus all nvidia-smi -L` lists the 4070 |
| Single-node Kubernetes (k3s) | Working | Node Ready, v1.36.5 |
| GPU in Kubernetes (GPU Operator) | Working | `kubectl describe node` shows `nvidia.com/gpu: 1`; a pod runs nvidia-smi |
| Operator components | Working | Device plugin, GPU Feature Discovery, DCGM exporter, NFD, validator all Running |
| Training and serving images | Built | Train 8.6 GB (260 s), serve 12.8 GB (332 s), pushed to a local registry |
| Training Job on Kubernetes | Working | Checkpoints on a PVC, 900 steps in 13 min, pod delete resumed from checkpoint-75 |
| Inference Deployment + Service | Working | First answer 126 s after apply; deleted pod replaced, answering in 103 s |
| GPU sharing with time slicing | Working | Second pod Pending by default; with time slicing both ran, 10/10 requests answered |
| RUNBOOK.md and results.md | Done | Comparison table with measured numbers |

## What is left
Rehearse the runbook on camera. Optional: repeat on a native Linux GPU machine to check the WSL2 workarounds are not needed there (untested).

## Caveats to keep in mind for the talk
- WSL2 is not a supported target. It needed three workarounds: kubelet `fail-cgroupv1=false`, a manual PCI node label, and `mount --make-rshared /` after every WSL restart.
- The Operator ran with its driver and toolkit installers off. The driver comes from Windows and the toolkit from apt. I tried turning them on: the toolkit crashed (no /dev/nvidia* on WSL2) and the driver container never became Ready. Do not say the Operator installed the driver or toolkit here.
- The baseline hit three setup problems (missing python3-venv, vLLM memory 0.3 too small, FlashInfer needing nvcc). They are good demo material.
- The tuned model's loss of 0.11 is overfit. This is a timing demo, not a quality claim.
- Only WSL2 was tested. Native Linux behavior is untested.
- Setup times so far are warm (cached images and weights), not cold starts.

Details: logs/phase1_notes.md, logs/phase2a_notes.md, logs/steps.csv.
