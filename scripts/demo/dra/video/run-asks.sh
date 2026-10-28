#!/usr/bin/env bash
# The demo itself: three teams start their pod on the one GPU; wait until all three have finished or crashed. $1 = plugin | dra
cd "$(dirname "$0")/../../../.." || exit 1
export KUBECONFIG=${KUBECONFIG:-/etc/rancher/k3s/k3s.yaml}
echo "Three teams share one 12 GB GPU. They need 3, 5 and 6 GiB of GPU memory: 14 GiB in total."
echo; echo "Starting the three pods ..."
kubectl apply -f k8s/dra-demo/ask-memory-$1.yaml | grep -i pod
for i in $(seq 1 200); do
  n=0; for p in team-a-3gib team-b-5gib team-c-6gib; do case "$(kubectl get pod $p -o jsonpath='{.status.phase}' 2>/dev/null)" in Succeeded|Failed) n=$((n+1));; esac; done
  [ $n = 3 ] && break; sleep 2
done
echo; echo "Done. The result is in the top pane."
