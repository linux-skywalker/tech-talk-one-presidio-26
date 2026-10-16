# Results: traditional vs Kubernetes, same model, same machine

Model: Qwen2.5-1.5B-Instruct, LoRA on 800 Alpaca examples, vLLM serving. Machine: RTX 4070 12 GB under WSL2 (Windows driver 615.78). All numbers measured on 2026-10-16. Raw data: `logs/`.

## Comparison

| | Traditional (venv + scripts) | Kubernetes (k3s + GPU Operator) |
|---|---|---|
| **Setup before first workload** | venv + installs: 140 s of install time (131 s vLLM/torch, 4 s training libs). 1 workaround (uv instead of python3-venv). | Platform: 156 s install script + 60 s cgroup fix + Operator rollout (about 3 min, not timed) + image builds 592 s (260 s train, 332 s serve). Roughly 30 min wall clock including 3 WSL2 workarounds. |
| **Start fine-tune** | Run the script: seconds to first step | Apply Job: pod Running in 36 s (18 s image pull) |
| **Fine-tune 900 steps** | about 10 min (200 s for the 3-epoch smoke run) | 13 min including one deliberate pod deletion and resume |
| **Start serving (nothing to first answer)** | 75 s, after two failed attempts (about 10 min of debugging wall clock) | 126 s from `kubectl apply` including image pull |
| **Time, nothing to serving, first time** | about 20 min wall clock (approximate, from log timestamps), 3 failures | about 30 min for platform and images before the first Job, then 36 s + 126 s per workload |
| **Time, second deploy of same thing** | Same commands again, no failures if flags are remembered | `kubectl apply`: 126 s to serving |
| **Manual steps** | 10 commands, 3 of which failed | 12 steps (RUNBOOK K1 to K6, helm install, 3 image steps, 2 applies), 3 of them WSL2-only workarounds, 0 failed once the workarounds were known |
| **GPU utilization, training** | 79% avg (84% when active) | 70% avg (77% when active). No meaningful speedup from Kubernetes, same GPU, same code |
| **GPU utilization, serving** | 81% under load (vLLM alone) | Not separately measured under load; sharing run below |
| **Two workloads on one GPU** | Training (9.7 GB) plus vLLM (4.9 GB) cannot fit; would need to shrink by hand and run both yourself | Default: second pod stays Pending ("Insufficient nvidia.com/gpu"). With time slicing: both run, 10/10 inference requests answered during training, util 37% avg / 47% steady, memory peak 11.9 of 12.3 GB |
| **Behavior on failure: training** | SIGKILL at step 362, resumed from step 350 by hand, 12 steps lost, 13 s to resume. Nothing noticed or restarted it. | Pod deleted at about step 75: replacement created automatically, resumed from checkpoint-75, 98 s from delete to training (about 60 s waiting for the old pod to release the GPU) |
| **Behavior on failure: serving** | Process dies, stays dead until a human restarts it (my own wait loop sat 5 min on a dead server) | Pod deleted: Deployment replaced it, answering again in 103 s, no human |
| **Portability to a second machine** | Recreate the venv; versions in `scripts/requirements-trad.lock`; hit machine-specific problems here (no python3-venv, no nvcc, memory) | Images and manifests carry over. Needs a real registry (ours is localhost:5000), a cluster with the GPU exposed, and the host-specific platform setup again. Untested on a second machine |
| **Pain points** | Version and setup problems at install time, silent failure, manual restart, no easy way to share GPU | WSL2 workarounds (3), 13 GB of images, local registry, Operator driver and toolkit installers do not work on WSL2, no memory isolation under time slicing |

## Honest reading
- **The first-time setup is slower on Kubernetes.** About 30 min of platform work versus about 20 min for the baseline, and the Kubernetes work included four WSL2-specific workarounds. After that, deploying a workload is one `kubectl apply`.
- **Failure handling is the clear win.** Both Kubernetes workloads recovered with no human action. The baseline needed someone to notice and rerun. Note the training baseline resume also depends on checkpoints, which I wrote into the script in both paths.
- **Kubernetes did not make training faster or use the GPU harder.** Utilization was about the same (79% versus 70% average).
- **Sharing is the other win, with a limit.** Time slicing let two workloads run on one GPU, which the default scheduler refuses. It gives no memory isolation: we peaked 0.4 GB from OOM.
- **Recovery is not instant.** 98 to 103 s, mostly the old pod releasing the GPU and vLLM restarting, not scheduling.

## What worked
Fine-tune and serve both ways; GPU in Kubernetes via the Operator (device plugin, GFD, DCGM, validator); Job resume; Deployment self-heal; time slicing.

## What did not work
Operator `toolkit.enabled=true` crashes on WSL2 (no /dev/nvidia*). Operator `driver.enabled=true` pulled a 595.91.07 driver container that never became Ready and does not match the Windows driver. Operator does not detect the GPU without a manual node label. vLLM at gpu-memory-utilization 0.3 does not fit; 0.4 does.

## Do not claim in the talk
- That WSL2 is a supported target, or that the Operator "just works" here.
- That the Operator installed the driver or the container toolkit. It did not.
- That Kubernetes makes training faster or raises GPU utilization. It did not.
- That time slicing isolates memory, or that it is production-ready for training plus serving.
- Any model quality from the tuned model (loss 0.11 is overfit; this is a timing demo).
- Native Linux behavior. Only WSL2 was tested. The expectation that cgroup, PCI detection and mounts work better on native Ubuntu is untested.
- Cold-start numbers as clean. Docker, apt and Hugging Face caches were warm for the baseline; the Kubernetes model download happened once on the first Job.
- That the ~20 min and ~30 min totals are precise. They come from log timestamps and untimed steps (Operator rollout), and are approximate.
