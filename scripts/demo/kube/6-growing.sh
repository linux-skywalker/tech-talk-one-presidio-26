#!/usr/bin/env bash
# Metric 6 of 6, Kubernetes + NVIDIA: add machines one at a time. Live: Multipass VM workers join the running cluster and get pods;
# the GPU Operator gives them no GPU parts because they have no GPU. CPU replicas, not GPU. VMs are removed at the end unless KEEP=1.
# usage: bash scripts/demo/kube/6-growing.sh [N]        (N VMs, default 3; about 8 minutes; needs ~/.k3s-node-token and ~/multipass-images, see vm-grow.sh)
source "$(dirname "$0")/../common.sh"
N=${1:-3}
need_idle_kube
bash scripts/demo/vm-grow.sh "$N" || { echo "${RED}VM run failed; cleaning up${R}"; bash scripts/demo/vm-down.sh >/dev/null 2>&1; exit 1; }
echo "${B}What the GPU Operator put on the new nodes${R}"
for n in $(kubectl get nodes -o name | grep grow-); do
  echo "  $n: $(kubectl get pods -A -o wide --no-headers --field-selector spec.nodeName=${n#node/} | awk '{print $2}' | sed 's/-[a-z0-9]*$//' | sort | uniq -c | awk '{printf "%s x%s, ", $2, $1}')"; done
echo "  GPU nodes: $(kubectl get nodes -l nvidia.com/gpu.present=true --no-headers | wc -l) (only the host has a GPU, so only it got the device plugin and the metrics exporter)"
note "A GPU machine joining would get those parts automatically (by design, not tested: we have one GPU)."
if [ -z "$KEEP" ]; then bash scripts/demo/vm-down.sh >/dev/null 2>&1; say "VMs removed."; fi
