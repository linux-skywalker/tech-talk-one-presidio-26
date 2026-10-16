# Phase 2a: GPU on Kubernetes (2026-10-16)

RESULT: SUCCESS. `kubectl describe node` shows nvidia.com/gpu: 1 and a pod ran nvidia-smi (RTX 4070).
Used: k3s v1.36.5 + NVIDIA Container Toolkit 1.20.1 + GPU Operator (helm, driver.enabled=false, toolkit.enabled=false).
The Operator did NOT install a driver or toolkit. Driver = Windows. Toolkit = apt on the host. Operator supplied: NFD, device plugin, GFD, DCGM exporter, validator.

## Workarounds needed on WSL2 (all pain points, none are in NVIDIA docs for WSL)
1. System: sudo apt installs + docker runtime config + k3s install: 156 s (warm).
2. k3s 1.36 kubelet refuses cgroup v1 (WSL2 here uses v1). Fix: /etc/rancher/k3s/config.yaml `kubelet-arg: fail-cgroupv1=false`. Unsupported by upstream.
3. Operator NFD cannot detect the GPU (no PCI device in WSL2): "No GPU node in the cluster". Fix: manual label feature.node.kubernetes.io/pci-10de.present=true.
4. Operator pods failed: path "/" is mounted on "/" but it is not a shared or slave mount. Fix: sudo mount --make-rshared /  (NOT persistent, redo after every WSL restart).
Do not claim: "supported", "Operator installed the driver", "just works on WSL2".

## Retry with Operator toolkit and driver enabled (tested, reverted)
- toolkit.enabled=true (with documented k3s containerd env vars): daemonset crashes. "unable to install toolkit: error creating device nodes: failed to create library: failed to create devices info: no NVIDIA devices found". WSL2 exposes /dev/dxg, not /dev/nvidia*. The installer has no flag to skip this. Dead end on WSL2.
- driver.enabled=true: driver container pulled nvcr.io/nvidia/driver:595.91.07 and ran with --no-kernel-modules (it detected WSL2), installing userspace libs only. Never became Ready in ~5 min. Note it is a different version (595.91.07) than the Windows driver (615.78). Not completed, not pursued.
- Reverted to driver.enabled=false, toolkit.enabled=false. GPU pod verified working again.
