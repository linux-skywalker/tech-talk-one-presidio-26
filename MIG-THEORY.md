# MIG: covered in theory (NOT tested by us)

We could not get on-demand H100 or A100 capacity on AWS, so MIG was not run. This page is what NVIDIA and AWS document, kept apart from what we measured on the RTX 4070. On the slides, label MIG as "per NVIDIA documentation" and never as our result. The ready-to-run EKS session exists on branch `eks-h100` (untested).

## Three ways to share one GPU in Kubernetes
| | Time slicing | MPS | MIG |
|---|---|---|---|
| How | Pods take turns on the GPU | Pods run at once, each with a memory limit we configured | The GPU is cut into hardware partitions, each looks like a small GPU |
| Memory isolation | None. "no memory or fault-isolation between replicas" (NVIDIA) | Per-pod memory limit (we measured it) | In hardware (NVIDIA) |
| Fault isolation | None (NVIDIA) | Not tested by us | In hardware (NVIDIA) |
| Hardware | Any NVIDIA GPU | Any NVIDIA GPU (we used an RTX 4070) | Ampere or newer datacenter GPUs, e.g. A100, H100. Not the RTX 4070 (we checked: "No MIG-supported devices found") |
| Our evidence | Six models on one card, GPU busy 10% to 68%, latency about 2x (light traffic). A second training job crashed with out of memory | Each pod saw 5.9 of 11.6 GiB, greedy pod stopped at 5 GiB, steady pod could grow 3 to 5 GiB | None |

NVIDIA's own wording: time slicing "trades the memory and fault-isolation that is provided by MIG for the ability to share a GPU by a larger number of users".

## How MIG works (NVIDIA MIG user guide)
- It partitions the compute (streaming multiprocessors, copy engines, decoders) and the memory system (L2 cache banks, memory controllers, DRAM paths). Each instance gets "separate and isolated paths through the entire memory system".
- Up to seven instances per GPU. NVIDIA lists memory isolation, fault isolation for "VMs, containers or processes" and a defined quality of service, so one client cannot affect another's work.
- H100 80GB profiles: 1g.10gb (up to 7), 1g.20gb (4), 2g.20gb (3), 3g.40gb (2), 4g.40gb (1), 7g.80gb (1, the whole GPU).
- The Kubernetes side: the NVIDIA GPU Operator's MIG manager applies a layout when you label a node (`nvidia.com/mig.config=all-1g.10gb`). Pods then request a slice like any GPU.

## Limits to say out loud (AWS EKS documentation)
- Partitions are predefined profiles, not arbitrary sizes.
- Changing the layout needs a GPU reset, which the Operator does by rebooting the node.
- MIG slices do not give proportional compute for every workload, so benchmark before choosing sizes.
- Time slicing does not apply to MIG slices; to share one slice use MPS.
- No NCCL or GPU-to-GPU peer-to-peer on MIG slices, so multi-GPU training should use whole GPUs.
- On EKS, MIG is documented only for 8-GPU instances (p4d, p4de, p5.48xlarge, p5e, p5en, p6, g7). Not on g5, g6, g6e, or EKS Auto Mode. The single-GPU p5.4xlarge is not in AWS's table, so it is unconfirmed.

## Safe slide wording
- Yes: "On data center GPUs, MIG splits one card into hardware-isolated slices, so a noisy neighbor cannot take your memory or crash you (per NVIDIA)."
- Yes: "Kubernetes applies it with one node label."
- Yes: "We measured the cheaper options: time slicing (no isolation) and MPS (memory limits)."
- No: any MIG number, "we tested MIG", or that MIG is faster or gives proportional performance.

## Sources
- NVIDIA MIG User Guide: https://docs.nvidia.com/datacenter/tesla/mig-user-guide/introduction.html and https://docs.nvidia.com/datacenter/tesla/mig-user-guide/supported-mig-profiles.html
- NVIDIA GPU Operator, GPU sharing: https://docs.nvidia.com/datacenter/cloud-native/gpu-operator/latest/gpu-sharing.html
- AWS, MIG on EKS: https://docs.aws.eu/eks/latest/userguide/device-management-nvidia-mig.html
