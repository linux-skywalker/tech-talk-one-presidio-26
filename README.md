




# Beyond kubectl apply: Elevating GPU Workflows with NVIDIA on Kubernetes

Proof of concept for the tech talk of the same name (India Exchange 2026, Presidio). The same GPU workloads are run two ways on one consumer card, an RTX 4070 (12 GB) on Ubuntu 24.04 with k3s, so every claim in the talk is backed by a measured run.

## Demo video

https://github.com/user-attachments/assets/b2d6b8cd-3bdf-4615-9f7e-fa51db9bedfb

About 2 minutes. Each demo runs the same workload without and with the technique, one terminal after the other.

## What is in here

| Technique | What we ran | Results |
|---|---|---|
| Time slicing and MPS | Pair throughput, serving latency, memory limits, killing one client | `results-time-slicing.md`, `results-mps.md` |
| MIG | Checked: not supported on this card | `results-mig.md`, `MIG-THEORY.md` |
| Kueue | 6 jobs plus an inference server, with and without a queue | `results-kueue.md`, `results-kueue-4070.md` |
| DRA | Device claims, shared claims, memory-sized claims | `results-dra.md` |

Start with `FINAL-SUMMARY-techniques.md` (what ran, what failed, what can and cannot be claimed) and `SUMMARY-techniques.md` (one table).

## Layout

- `k8s/` manifests: GPU Operator values, sharing configs, workloads, Kueue and DRA tests, demo manifests (`mps-demo/`, `dra-demo/`).
- `scripts/` helpers, load tests, and the demo scripts (`scripts/demo/`, see its README). The live dashboards and record scripts for the before/after demos are in `scripts/demo/{kueue,mps,dra}/video/`.
- `docker/` images for the serving and training workloads.
- `logs/` raw run data behind every number in the result files.
- `video/` the Remotion project that cuts the before/after terminal recordings into one demo video. The finished video (about 2 minutes, 17 MB) is `video/final/all-demos.mp4`.

## Notes on the numbers

- All numbers come from one machine. Runs on the earlier setup (kernel 6.17, driver 590.48) and the later one (kernel 7.0, driver 595.99) are kept in separate tables.
- Most results are small samples (n=1 to 3). The result files say which.
- The GPU Operator manages the device plugin and monitoring here; the NVIDIA driver and container toolkit were installed on the host.
- The setup uses a GeForce card, so MIG and some data center features are out of reach. See the result files for what that means.

## Reproducing

Needs an NVIDIA GPU with a working driver, k3s, Helm and the NVIDIA GPU Operator. `RUNBOOK.md` and `RUNBOOK-UBUNTU-DEMO.md` walk through the setup. Some manifests mount the Hugging Face cache from the host and need your own home path (look for `YOUR_USER`).
