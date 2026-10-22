# CUDA MPS on one RTX 4070 (measured)

Environment: as in `results-time-slicing.md`. Config: `k8s/mps-config.yaml` (device plugin MPS, replicas 2; each replica gets a memory limit and a thread share). The node advertised `nvidia.com/gpu=2`, strategy label `mps`. Harness: `scripts/techniques/`; raw data in `logs/techniques/`. n = number of runs.

## Two training jobs on one GPU (short job)
| Case | Training time per job | Steps/s per job | GPU busy avg | Peak GPU memory | n |
|---|---|---|---|---|---|
| One job alone (no sharing) | 25.35 s, 25.08 s | 1.972, 1.994 | 61, 62% | 2498 MiB | 2 |
| Two jobs under MPS | 49.31/49.31 s, 48.82/48.80 s | 1.014, 1.025 | 75, 80% | 4149 to 4165 MiB | 2 |
Reading: the same as time slicing (about 49 s per job, pair finishes in about the time of two sequential runs). MPS gave no throughput gain here.

## Inference server and a training job on the same GPU
| Case | Server reply time p50 / p95 | Server first token p95 | Requests ok / failed | Training time (long job) | GPU busy / memory | n |
|---|---|---|---|---|---|---|
| Server alone, MPS | 0.481 / 0.481 s | 0.013 s | 27 / 0 | | | 1 |
| Server and training, MPS | 0.847 / 0.875 s, 0.847 / 0.873 s | 0.021 s | 86 / 0 | 117.8 s, 117.7 s (0.306 steps/s) | 93% / 9.07 GB | 2 |
| For comparison, time slicing | 1.057 / 1.071 s | 0.023 s | 85 / 0 | 116.0 s | 93 to 94% / 9.2 GB | 2 |
Reading: under MPS the server's reply time while training ran was about 20% lower than under time slicing (0.85 s against 1.06 s), at a training time about 1.5% longer (117.8 s against 116.0 s). Alone, the server is 0.481 s (0.475 s without sharing).

## Memory limit
Earlier single run on this machine (`results-ubuntu-4070.md`, MPS replicas 2): each pod saw 5.9 of 11.6 GiB free; greedy stopped at 5 GiB; the steady pod grew from 3 to 5 GiB. Time slicing, same pods: steady failed with an out-of-memory error.
Re-run for this report (n=1, so n=2 with the earlier run; `logs/techniques/memtest-mps2.txt`): each pod saw 5.9 of 11.6 GiB free; greedy stopped at 5 GiB; the steady pod grew from 3 to 5 GiB (OK). Same result as the earlier run.
DRA MPS claim with a 5 GiB pinned limit (single run, `logs/dra/extra.txt`): each pod saw 4.9 GiB free; greedy stopped at 4 GiB; steady could not grow from 3 to 5 GiB.

## Fault isolation (kill -9 one client)
Two 4-epoch jobs share the GPU under MPS; job A's container is killed with SIGKILL 25 s after both run (process confirmed gone in `/proc`).
| | Job B outcome | Job B training time | Time from kill to B finishing | n |
|---|---|---|---|---|
| MPS | finished ok, no error in its log | 74.14 s, 74.04 s | 59 s, 59 s | 2 |
| Time slicing, for comparison | finished ok | 60.05 s, 59.9 s | 44 s, 44 s | 2 |
Reading: the surviving job was not killed by the crash, but it finished about 14 s (23%) later than under time slicing in both runs. Cause not tested.

## What this shows
MPS gave the server about 20% lower latency next to a training job than time slicing did, with the same training throughput and per-pod memory limits (earlier runs). A killed client did not take the other down in 2 of 2 runs. Not measured: a GPU-level fault inside a client (NVIDIA documents that MPS clients share one fault domain), the compute (thread percentage) split, 3 or more clients.
