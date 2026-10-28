#!/usr/bin/env bash
# Check before every take: which sharing mode the GPU is in, GPU free, no leftover test pods. Prints READY or what is wrong.
export KUBECONFIG=${KUBECONFIG:-/etc/rancher/k3s/k3s.yaml}
L='{.items[0].metadata.labels.nvidia\.com/gpu\.sharing-strategy}'
mode=$(kubectl get node -l nvidia.com/gpu.present=true -o jsonpath="$L")
slices=$(kubectl get node -l nvidia.com/gpu.present=true -o jsonpath='{.items[0].status.allocatable.nvidia\.com/gpu}')
mem=$(nvidia-smi --query-gpu=memory.used --format=csv,noheader,nounits | tr -d ' ')
left=$(kubectl get pods -l app=memtest --no-headers 2>/dev/null | wc -l)
ok=1
[ "$mem" -lt 1500 ] || { echo "NOT READY: GPU memory in use is $mem MiB"; ok=0; }
[ "$left" = 0 ] || { echo "NOT READY: leftover test pods (run 5-clean.sh)"; ok=0; }
[ $ok = 1 ] && echo "READY  sharing mode: ${mode:-none}, GPU slices offered: $slices, GPU memory in use: $mem MiB"
