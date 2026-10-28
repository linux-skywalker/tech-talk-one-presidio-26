#!/usr/bin/env bash
# Switch how the GPU is shared. usage: 4-switch-sharing.sh time-slicing | mps
# Changes only the NVIDIA device plugin setting in the cluster; "time-slicing" puts back the setup used by the other demos (8 slices).
export KUBECONFIG=${KUBECONFIG:-/etc/rancher/k3s/k3s.yaml}
cd "$(dirname "$0")/../../../.." || exit 1
case $1 in
  mps) cfg=mps-config; want=mps; kubectl apply -f k8s/mps-config.yaml >/dev/null;;
  time-slicing) cfg=time-slicing-8; want=time-slicing;;
  *) echo "usage: $0 time-slicing | mps"; exit 1;;
esac
kubectl patch clusterpolicies.nvidia.com/cluster-policy --type merge -p "{\"spec\":{\"devicePlugin\":{\"config\":{\"name\":\"$cfg\",\"default\":\"any\"}}}}" >/dev/null
echo "Waiting for the GPU plugin to switch to $want ..."
for i in $(seq 1 90); do
  got=$(kubectl get node -l nvidia.com/gpu.present=true -o jsonpath='{.items[0].metadata.labels.nvidia\.com/gpu\.sharing-strategy}')
  [ "$got" = "$want" ] && [ "$want" != mps -o -n "$(kubectl get pods -n gpu-operator --no-headers | grep -i mps | grep Running)" ] && break; sleep 3
done
sleep 10; bash scripts/demo/mps/video/0-check-ready.sh
