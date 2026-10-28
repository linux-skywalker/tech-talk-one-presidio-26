# Phase 2b: workloads on Kubernetes (2026-10-16), all measured on WSL2

## Works
- Training Job (GPU limit 1, PVC for checkpoints+HF cache): pod Running 36 s after apply (image pull 18 s). 900 steps, GPU ~66% in first samples.
- Delete training pod at ~step 75: Job created a replacement automatically. It stayed Pending ~60 s while the old pod Terminating still held the GPU, then resumed from checkpoint-75. 98 s from delete to training again, no human action. Job finished: 13 min total.
- Serving Deployment + NodePort Service (localhost:30080): apply to first answer 126 s (image pull + vLLM start), base+tuned adapter served from PVC.
- Delete serve pod: Deployment replaced it, answering again in 103 s, no human action. (Recreate strategy because one GPU.)
- Sharing test: with vLLM holding the only GPU, second Job stayed Pending: "0/1 nodes are available: 1 Insufficient nvidia.com/gpu". After enabling time slicing (ConfigMap + ClusterPolicy patch, 4 replicas), node allocatable became 4 and the training pod started alongside vLLM. 10/10 inference requests answered during training; training (1 epoch, batch 1) finished in 270 s with no OOM.

## Numbers (nvidia-smi, includes ~1.8 GB Windows desktop)
- Before (vLLM alone, training Pending): util 29-35%, mem ~6.8 GB.
- After (both running): util avg 37% (incl. model load) / 47% steady, peak mem 11.9 GB of 12.3 GB (very close to the limit).

## Caveats
- Time slicing gives no memory isolation. Both pods share VRAM; we were ~0.4 GB from OOM with batch 1. The value shown is "both workloads run", not "higher utilization". Training batch 1 is lighter than the batch-4 baseline so utilizations are not directly comparable.
- Cold start for the first Job included a fresh model download to the PVC; times for pod Running only cover scheduling and image pull from a local registry.
- Image registry is local (localhost:5000). A second machine would need images pushed to a real registry.
- Delete-to-recover times are dominated by the 30 s termination grace plus GPU release and vLLM start (~75 s), not by Kubernetes scheduling.
