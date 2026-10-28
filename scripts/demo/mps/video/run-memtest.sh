#!/usr/bin/env bash
# The demo itself: start the steady pod and the greedy pod on the one GPU, wait until the steady pod has made its request. Used by both recording scripts.
cd "$(dirname "$0")/../../../.." || exit 1
export KUBECONFIG=${KUBECONFIG:-/etc/rancher/k3s/k3s.yaml}
echo "Two teams share one 12 GB GPU. Team A runs a steady service; Team B runs a greedy job."
echo "GPU sharing: $(kubectl get node -l nvidia.com/gpu.present=true -o jsonpath='{.items[0].metadata.labels.nvidia\.com/gpu\.sharing-strategy}')"
echo; echo "Starting both pods ..."; kubectl apply -f k8s/mps-demo/memtest.yaml
for i in $(seq 1 150); do
  n=0; for p in mem-steady mem-greedy; do case "$(kubectl get pod $p -o jsonpath='{.status.phase}' 2>/dev/null)" in Succeeded|Failed) n=$((n+1));; esac; done
  [ $n = 2 ] && break; sleep 2
done
echo; echo "Done. The result is in the top pane."
