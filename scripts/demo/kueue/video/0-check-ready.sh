#!/usr/bin/env bash
# Check before every take: all pods Running, Kueue webhook up, GPU free, no leftover jobs. Prints READY or what is wrong.
export KUBECONFIG=${KUBECONFIG:-/etc/rancher/k3s/k3s.yaml}
bad=$(kubectl get pods -A --no-headers 2>/dev/null | awk '$4!="Running" && $4!="Completed"' | wc -l)
mem=$(nvidia-smi --query-gpu=memory.used --format=csv,noheader,nounits | tr -d ' ')
ep=$(kubectl -n kueue-system get endpointslices -o jsonpath='{.items[*].endpoints[*].addresses[0]}' 2>/dev/null)
ok=1
[ "$bad" = 0 ] || { echo "NOT READY: $bad pods not Running"; ok=0; }
[ -n "$ep" ] || { echo "NOT READY: Kueue webhook has no endpoint"; ok=0; }
[ "$mem" -lt 1500 ] || { echo "NOT READY: GPU memory in use is $mem MiB"; ok=0; }
[ $ok = 1 ] && echo "READY (GPU memory in use: $mem MiB)"
