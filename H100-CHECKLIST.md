# Checklist: repeat on a native Linux GPU VM (H100)

Goal: find out which WSL2 workarounds disappear, and run the same comparison. Everything here is untested expectation until you record it. Use the same scripts, manifests and RUNBOOK, and write results in a separate table (do not mix with the RTX 4070 numbers).

## Before you start
- Ubuntu 22.04 or 24.04, NVIDIA datacenter driver installed, `nvidia-smi` works on the host. Decide up front: let the Operator install the driver (cleanest demo, but only if no driver is pre-installed) or use the host driver.
- Note `uname -r`, `stat -fc %T /sys/fs/cgroup` (cgroup2fs means v2), driver version, CUDA version.
- Start a timer. Log each step with `scripts/log_step.sh`.

## What to check (each was a WSL2 workaround)
| Check | WSL2 result | Record on the VM |
|---|---|---|
| k3s starts with no `fail-cgroupv1` setting | Needed the flag | yes/no |
| Operator labels the node by itself (`kubectl get node --show-labels \| grep pci-10de`) | Needed a manual label | yes/no |
| Operator pods start without `mount --make-rshared /` | Needed it | yes/no |
| Operator `driver.enabled=true` installs and loads the driver | Never became Ready | yes/no, time taken |
| Operator `toolkit.enabled=true` installs the toolkit | Crashed, no /dev/nvidia* | yes/no |
| `kubectl describe node` shows `nvidia.com/gpu` | Yes after workarounds | count |

## Operator install on k3s (native)
For the toolkit to configure k3s's containerd, set:
```bash
helm install gpu-operator nvidia/gpu-operator -n gpu-operator --create-namespace \
  --set 'toolkit.env[0].name=CONTAINERD_CONFIG' --set 'toolkit.env[0].value=/var/lib/rancher/k3s/agent/etc/containerd/config.toml.tmpl' \
  --set 'toolkit.env[1].name=CONTAINERD_SOCKET' --set 'toolkit.env[1].value=/run/k3s/containerd/containerd.sock' \
  --set 'toolkit.env[2].name=CONTAINERD_RUNTIME_CLASS' --set 'toolkit.env[2].value=nvidia' \
  --set 'toolkit.env[3].name=CONTAINERD_SET_AS_DEFAULT' --set-string 'toolkit.env[3].value=true'
```
Add `--set driver.enabled=false` if the host driver is already installed. Skip the apt `nvidia-container-toolkit` step in `scripts/phase2_install.sh` if you want the Operator to install the toolkit (then the apt step is not "pre-done"). Note: this exact k3s env set was only tried here with `toolkit.enabled=true` and failed for a WSL2 reason, so on a real box it is still unproven.

## Tuning for 80 GB
- vLLM: `GPU_UTIL=0.3` fits easily now; set 0.15 to 0.3 to leave room. Remove the FlashInfer workaround only if `nvcc` is present.
- Training: raise `BATCH` (e.g. 16) and shorten `EPOCHS` so a run is still about 10 minutes; check `nvidia-smi` shows it is actually using the card.
- Time slicing: there is room for both workloads, so the sharing story is about scheduling, not memory pressure. Time slicing still has no memory isolation.
- H100 supports MIG, which does give real isolation and is the natural next slide. Untested here. Do not claim it without running it.

## Images and portability
- The images use a local registry (`localhost:5000`). On the VM either rebuild there (about 10 minutes) or push to a real registry and change the image names in `k8s/*.yaml`. Record which one you did, and how long it took: this is your portability number.
- Model weights download again on a fresh PVC.

## Record
Fill a copy of the results.md table with: setup time, manual steps, which workarounds were needed (count), failure recovery times, utilization. Commit to a branch named for the machine (for example `h100`).
