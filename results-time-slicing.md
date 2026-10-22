# Time slicing on one RTX 4070 (measured)

Environment: Ubuntu 24.04.4, kernel 6.17.0-14-generic, driver 590.48.01, RTX 4070 12 GB (compute capability 8.9), k3s v1.36.5+k3s1, GPU Operator v26.7.2 (driver and toolkit installers off), device plugin v0.20.1. Config files: `k8s/techniques/ts-2.yaml` (replicas 2), `k8s/time-slicing-config.yaml` (replicas 4). Workloads: SmolLM2-135M LoRA training (short: batch 16, 2 epochs; long: batch 48, 4 epochs) and the Qwen2.5-1.5B vLLM server (`GPU_UTIL=0.4`). The 1.5B fine-tune used in earlier phases does not fit next to the 1.5B server (see the out-of-memory row), so the competing jobs use the small model. Harness: `scripts/techniques/`. Raw data: `logs/techniques/measurements.csv`, `probe-*.csv`, `run.log`. Every number is labelled with its run count (n).

## What Kubernetes advertises
| Setting | `nvidia.com/gpu` allocatable | Strategy label | n |
|---|---|---|---|
| No sharing | 1 | none | 1 |
| Time slicing, replicas 2 | 2 | time-slicing | 1 |
| Time slicing, replicas 4 | 4 | time-slicing | 1 |

## Two training jobs on one GPU (short job)
| Case | Training time per job | Steps/s per job | GPU busy avg | Peak GPU memory | n |
|---|---|---|---|---|---|
| One job alone | 25.35 s, 25.08 s | 1.972, 1.994 | 61, 62% | 2498 MiB | 2 |
| Two jobs, replicas 2 | 48.36/48.47 s, 48.55/48.65 s | 1.03 | 81, 79% | 4298 MiB | 2 |
| Two jobs, replicas 4 | 48.50/48.59 s, 49.34/49.23 s | 1.01 to 1.03 | 81, 78% | 4282 to 4298 MiB | 2 |
Reading: each job takes about 1.9 times as long as alone, so the pair finishes in about the time of two jobs run one after the other (about 49 s against 50 s). Replicas 2 and 4 gave the same result. Time slicing raised GPU busy from about 61% to about 80%; it did not raise throughput.

## Inference server and a training job on the same GPU
| Case | Server reply time p50 / p95 | Server first token p95 | Requests ok / failed | Training time (long job) | GPU busy / memory | n |
|---|---|---|---|---|---|---|
| Server alone (no sharing) | 0.475 / 0.483 s | 0.013 s | 27 / 0 | | | 1 |
| Server alone, replicas 2 | 0.475 / 0.485 s | 0.013 s | 26 / 0 | | | 1 |
| Server alone, replicas 4 | 0.474 / 0.475 s | 0.014 s | 27 / 0 | | | 1 |
| Training alone (no sharing) | | | | 75.87 s, 76.02 s (0.474 steps/s) | 85% / 4.7 GB | 2 |
| Server and training, replicas 2 | 1.057 / 1.071 s, 1.058 / 1.072 s | 0.023 s | 85 / 0 | 116.0 s, 115.8 s (0.31 steps/s) | 94, 93% / 9.2 GB | 2 |
| Server and training, replicas 4 | 1.056 / 1.071 s, 1.056 / 1.072 s | 0.023 s | 85 / 0 | 115.9 s, 115.9 s (0.311 steps/s) | 93% / 9.2 GB | 2 |
| No sharing, server running | training job stayed Pending: `0/1 nodes are available: 1 Insufficient nvidia.com/gpu` | | | | | 1 |
Reading: sharing let both run at once. The training job slowed about 53% (76 s to 116 s) and the server's reply time went from 0.475 s to 1.06 s (about 2.2 times). No request failed and the server did not restart. The latency cost is steady, p95 sits next to p50.

## Memory isolation (out of memory)
Test: the Qwen2.5-1.5B server (`GPU_UTIL=0.4`) is running with 6851 MiB free; a Qwen2.5-1.5B fine-tune (batch 4) is started next to it (replicas 4). n=1.
Result: the training job failed. Error: `OutOfMemoryError: CUDA out of memory. Tried to allocate 76.00 MiB. GPU 0 has a total capacity of 11.59 GiB of which 45.06 MiB is free. Including non-PyTorch memory, this process has 6.64 GiB memory in use.` Peak GPU memory 11828 MiB. Log: `logs/techniques/oom-ts4.log`. Earlier co-runs in this session (4 of 4, other batch sizes) failed the same way.
Earlier greedy/steady memory test (single run, `results-ubuntu-4070.md`): under time slicing the steady pod could not grow from 3 to 5 GiB. In the DRA time-slicing re-run (single run) it could, because the greedy pod stopped at 7 GiB first; that outcome depends on who allocates first, so time slicing gives no guarantee.

## Fault isolation (kill -9 one client)
Two 4-epoch jobs share the GPU (replicas 4); 25 s after both run, job A's container is killed with SIGKILL (confirmed gone in `/proc`).
| | Job B outcome | Job B training time | n |
|---|---|---|---|
| Time slicing | finished ok, no error in its log | 60.05 s, 59.9 s | 2 |
Job B sped up once A died (a full shared run takes about 97 s). A first attempt was invalid (the kill did not take effect because the process is root-owned); those logs are in `logs/techniques/invalid/` and are excluded.

## What this shows
Time slicing lets a training job and an inference server share one 12 GB card, at about 2.2 times the server latency and 1.5 times the training time, with no throughput gain over running the jobs one after the other, no memory isolation (an out-of-memory crash occurs when the sum does not fit) and no spread of a SIGKILL crash to the neighbour in 2 of 2 runs. Not measured: training tokens per second (only steps/s and samples/s are logged), a GPU-level fault inside a client, 3 or more sharers.
