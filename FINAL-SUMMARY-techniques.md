# Final summary: what ran, what failed, what we can and cannot claim

RTX 4070 12 GB, Ubuntu 24.04, k3s v1.36.5, GPU Operator v26.7.2 (driver and toolkit installed on the host, not by the Operator). All numbers are from this machine. Table: `SUMMARY-techniques.md`.

## What ran
- Time slicing (replicas 2 and 4), MPS (replicas 2): pair throughput, serving latency under training, memory behaviour, killing one client. n=2 per setting.
- MIG: checked, not supported (`nvidia-smi mig -lgip`: "No MIG-supported devices found"; enabling needed root, not available).
- Kueue v0.20.3: single-run scenarios (server plus training, inference arriving mid-batch, flood) and the 6-job workload, 3 runs per arm.
- DRA (driver 0.5.1): device published, claims, CEL selector, shared claim, time slicing and MPS via claim, consumable memory shares, pod startup (3 pods each).
- Combined: 6 jobs under (A) no queue, (Kueue units), (B) DRA + Kueue in GiB, 3 runs each.

## What failed or did not run
- MIG: not supported on this card. Mock-device simulation: not run (cancelled).
- First three fault-isolation kills were invalid (root-owned process); excluded to `logs/techniques/invalid/` and redone with a verified forced kill.
- First DRA exclusive-claim data was invalid (reused checkpoint dirs); rerun.
- A 1.5B fine-tune next to the 1.5B server ran out of memory in 4 of 4 co-runs.
- No-queue arm: 2 to 4 of 6 jobs finished; the rest crashed with out-of-memory after retries.
- Scenario 2 preemption was first miscounted; corrected in `results-kueue-4070.md`.
- GPU-level faults inside a client, 3 or more clients, borrowing beyond the cohort test: not tested.

## What we can claim
- On this card, MPS and time slicing give no speedup for two jobs over running them in sequence (about 49 s each vs 25 s alone), and replicas 2 vs 4 made no difference.
- MPS gave about 20% lower server latency next to training than time slicing (0.85 s vs 1.06 s, n=2); MPS enforced a per-pod memory limit, time slicing did not.
- Killing one client did not stop the other under either setting (n=2). The survivor took longer under MPS (74 s vs 60 s); cause untested.
- Without a queue, 6 jobs plus a server crashed pods with out-of-memory; with Kueue all 6 finished with no failed pod, at the cost of finishing the last job about 2.4 times later (n=3 per arm).
- DRA works on a GeForce RTX 4070: device published, claim by attribute, shared claim, per-claim sharing mode, and memory-sized claims (3 and 5 GiB together, 6 GiB Pending). Pod startup was the same as the device plugin.
- DRA + Kueue (GiB quota) gave the same outcome as unit-based Kueue (6 of 6, 507 s vs 498 s, n=3 each).

## What we cannot claim
- Any throughput gain from sharing, from DRA, or from DRA + Kueue.
- A latency win from Kueue (p95 was higher, 1.85 s vs 1.40 s) or a cause for DRA + Kueue's lower server p95 than unit Kueue (1.65 s vs 1.85 s).
- Why jobs waited longer with free memory under DRA + Kueue (429 vs 78 job-seconds), or that GiB quota is better than units.
- Anything about MIG, multiple GPUs, other GPU models or data center cards. The Kueue GiB quota is an alpha feature.
- That the Kueue "units" isolate memory: they are our own convention, about 1.5 GB each.
