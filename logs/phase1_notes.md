# Phase 1 notes (traditional path), measured 2026-10-16

## Timings (wall clock)
- uv install (user-level) + venv: ~5 s (after `python3 -m venv` failed)
- pip install vllm (pulls torch 2.13+cu130): 131 s
- pip install trl peft datasets accelerate: 4 s
- Fine-tune smoke run, 3 epochs / 300 steps: 206 s train time
- Fine-tune main run, 9 epochs / 900 steps: ~10 min total (kill at step 362, resume 350->900 = 375 s)
- vLLM start to ready: 75 s (after two failures, each ~40 s to 5 min of debugging)

## Problems hit (demo material)
1. `python3 -m venv` failed: python3.10-venv missing, fix needs sudo. Worked around with `pip install --user uv`.
2. vLLM `--gpu-memory-utilization 0.3` failed: "No available memory for the cache blocks" (negative KV cache, -0.84 GiB). Weights 3 GiB + profiling exceed 0.3 x 12 GB. 0.4 works. Windows desktop already holds ~1.8 GB VRAM.
3. vLLM then crashed in warmup: FlashInfer sampler JIT needs `nvcc` ("Could not find nvcc"). Fix: VLLM_USE_FLASHINFER_SAMPLER=0.
4. My own wait loop blocked 5 min on a server that had already died (no health check). Real-world version of "nothing told me it failed".
5. Loss 0.11 after 9 epochs on 800 examples is overfit. Fine for a timing demo, do not claim model quality.

## Break test
- SIGKILL at step 362. Last checkpoint step 350 (save_steps=25). Lost 12 steps (~8 s) of work, but ONLY because checkpointing was on.
- Nothing restarted the job. A human had to notice and rerun. Resume took 13 s to be training again. Script auto-resumes from latest checkpoint (that logic is mine, not free).
- Without checkpointing, the whole run would be lost.

## GPU utilization (nvidia-smi, 2 s samples, includes model load)
- 3-epoch run: avg 66%; 9-epoch run: avg 79%. Memory ~9.7 GB used total incl. 1.8 GB Windows desktop.
- vLLM at 0.4 alone: 6.7 GB used, 81% util during requests.
- Training (9.7 GB) + vLLM (4.9 GB) cannot both fit in 12 GB as configured. Sharing test in Phase 2 needs smaller training batch (e.g. batch 2, ~6 GB) .

## Manual steps (count)
1 create venv (failed) 2 install uv 3 create venv 4 install vllm 5 install trl stack 6 run training 7 start server (failed) 8 retry 0.4 (failed) 9 disable flashinfer, start 10 query. ~10 commands, 3 failures.
