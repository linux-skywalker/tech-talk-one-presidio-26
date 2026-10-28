# MIG on EKS with an H100

Superseded by `k8s/eks/MIG-SESSION.md`, which has the full timed plan. Corrections to the earlier version of this note:
- Use `--set mig.strategy=single` (slices appear as `nvidia.com/gpu`, so the existing manifests work unchanged). `mixed` is only needed when one node mixes MIG slices with whole GPUs.
- Profile names come from the `default-mig-parted-config` ConfigMap (`kubectl get cm -n gpu-operator default-mig-parted-config -o yaml | grep -E "^  *all-"`). NVIDIA's guide gives `all-1g.10gb`, `all-3g.40gb`, `all-balanced` for an H100 80 GB, and `all-disabled` to turn MIG off.
- Apply with `kubectl label node <node> nvidia.com/mig.config=<profile> --overwrite` and wait for `nvidia.com/mig.config.state=success`.
- Still untested. Do not claim MIG results until the session has run.
