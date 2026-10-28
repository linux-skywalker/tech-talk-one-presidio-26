#!/usr/bin/env bash
# Check before every take: how the GPU is offered to pods (device plugin or DRA), GPU free, no leftover test pods. Prints READY or what is wrong.
export KUBECONFIG=${KUBECONFIG:-/etc/rancher/k3s/k3s.yaml}
slices=$(kubectl get node -l nvidia.com/gpu.present=true -o jsonpath='{.items[0].status.allocatable.nvidia\.com/gpu}' 2>/dev/null)
dra=$(kubectl get resourceslices --no-headers 2>/dev/null | grep -c gpu.nvidia.com)
mem=$(nvidia-smi --query-gpu=memory.used --format=csv,noheader,nounits | tr -d ' ')
left=$(kubectl get pods -l app=askdemo --no-headers 2>/dev/null | wc -l)
if [ "$dra" -gt 0 ]; then how="DRA (GPU memory claims)"; else how="device plugin ($slices GPU slices)"; fi
ok=1
[ "$mem" -lt 1500 ] || { echo "NOT READY: GPU memory in use is $mem MiB"; ok=0; }
[ "$left" = 0 ] || { echo "NOT READY: leftover test pods (run 5-clean.sh)"; ok=0; }
[ $ok = 1 ] && echo "READY  GPU is offered through: $how, GPU memory in use: $mem MiB"
