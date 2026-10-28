#!/usr/bin/env bash
# After each take: remove the two test pods so the next take starts clean.
export KUBECONFIG=${KUBECONFIG:-/etc/rancher/k3s/k3s.yaml}
kubectl delete pod mem-steady mem-greedy --ignore-not-found --grace-period=0 --force >/dev/null 2>&1
echo "Waiting for the GPU memory to free ..."
for i in $(seq 1 60); do [ "$(nvidia-smi --query-gpu=memory.used --format=csv,noheader,nounits | tr -d ' ')" -lt 1500 ] && break; sleep 3; done
bash "$(dirname "$0")/0-check-ready.sh"
