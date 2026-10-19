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

## Phase 2 (Kubernetes): not started
Workaround table (needed yes/no) to be filled in: kubelet cgroup v1 flag, PCI node label, `mount --make-rshared /`, Operator toolkit, Operator driver.
