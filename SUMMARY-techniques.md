# Sharing and scheduling techniques on one RTX 4070: summary

RTX 4070 12 GB, Ubuntu 24.04, k3s v1.36.5, GPU Operator v26.7.2. Numbers are from `logs/techniques/measurements.csv` and the per-technique files. n = runs. Workloads: SmolLM2-135M LoRA training and the Qwen2.5-1.5B vLLM server. Where a cell says PENDING the test is running or not yet run.

| Technique | Supported on 4070 | Isolation (memory / fault) | Throughput impact (n) | Latency impact (n) |
|---|---|---|---|---|
| MPS | Yes (device plugin, replicas 2) | Memory: per-pod limit applied (earlier n=1; re-run PENDING). Fault: SIGKILL of one client did not stop the other (n=2); GPU faults not tested | Two jobs 49 s each against 25 s alone, pair no faster than running in sequence (n=2). Long training 117.7 s against 75.9 s alone (n=2) | Server reply 0.847 s next to training against 0.481 s alone (n=2), about 20% lower than time slicing |
| MIG | NO: `nvidia-smi mig -lgip` reports "No MIG-supported devices found", mode `[N/A]` | not applicable | not applicable | not applicable |
| Time slicing | Yes (replicas 2 and 4 gave the same results) | Memory: none, out-of-memory crash when the sum does not fit (n=1 plus 4 earlier). Fault: SIGKILL of one client did not stop the other (n=2) | Two jobs 48 to 49 s each against 25 s alone, no gain over sequential (n=2 per setting). Long training 116 s against 75.9 s alone (n=2) | Server reply 1.06 s next to training against 0.475 s alone (n=2 per setting) |
| Kueue | Yes (v0.20.3) | Admission and quota only, no memory or fault isolation | 6-job comparison PENDING. Earlier single runs: batch finished later with Kueue (236 s against 169 s) but all jobs finished (flood: 7 of 7 against 3 of 7) | Server answered at 56 s against 208 s (n=1); latency under load not improved (1.07 s p95) |
| DRA | Yes (driver 0.5.1 accepts the GeForce card; needs device plugin off and driver feature gates for sharing) | Time slicing and MPS claims behave like their device-plugin versions in single runs | No difference from the device plugin (61 s against 62 s for two jobs, n=1 each) | Not separately measured |
| DRA + Kueue combined (3 runs each) | PENDING | PENDING | PENDING | PENDING |

Null results worth saying out loud: sharing the card did not make two jobs finish sooner than running them one after the other, replicas 2 versus 4 made no difference, and DRA was not faster than the device plugin.
