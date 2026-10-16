# Progress summary (Phases 0 to 2a)

Talk: "Beyond kubectl apply: Elevating GPU Workflows with NVIDIA on Kubernetes".
Machine: Windows PC, RTX 4070 (12 GB), WSL2 Ubuntu 22.04, Windows-supplied driver.

## What works
- **Traditional path, end to end.** LoRA fine-tune of Qwen2.5-1.5B-Instruct (800 examples, 900 steps, ~10 min) and vLLM serving of the base model plus the tuned adapter. GPU use: training 66-79% average, vLLM 81% under load.
- **Failure behavior measured (traditional).** Training killed at step 362, resumed from checkpoint 350: 12 steps lost, 13 s to resume. Nothing restarted it automatically.
- **GPU on Kubernetes.** k3s with the NVIDIA GPU Operator: `kubectl describe node` shows `nvidia.com/gpu: 1`, and a pod runs `nvidia-smi` and sees the RTX 4070. The Operator deployed the device plugin, GPU Feature Discovery, DCGM exporter, Node Feature Discovery and validator, all Running.
- **Docker GPU access** via the NVIDIA Container Toolkit.
- **Container images and manifests** written: two Dockerfiles, PVC, training Job, serving Deployment + Service, time-slicing config.

## Next
Run the training Job and serving Deployment, pod-delete failure tests, time-slicing sharing test, RUNBOOK.md, results.md.

## Caveats (for the talk)
- WSL2 is not a supported target. It needed three workarounds: kubelet `fail-cgroupv1=false`, a manual PCI node label (Operator cannot detect the GPU on WSL2), and `mount --make-rshared /` after every WSL restart.
- The Operator ran with `driver.enabled=false` and `toolkit.enabled=false`. Driver comes from Windows, toolkit from apt. Re-enabling the toolkit crashed (no /dev/nvidia* on WSL2). The driver container did not become Ready. So do not say the Operator installed the driver or toolkit here.
- Baseline setup hit three problems: missing python3-venv, vLLM 0.3 memory too small (0.4 works), FlashInfer needing nvcc.
- Tuned model loss 0.11 is overfit; this is a timing demo, not a quality claim.
- Only WSL2 was tested; claims about native Linux are untested.
- Setup times are warm (cached images and weights), not cold starts.

See logs/phase1_notes.md, logs/phase2a_notes.md, logs/steps.csv.
