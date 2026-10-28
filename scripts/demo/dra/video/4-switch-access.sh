#!/usr/bin/env bash
# Switch how pods get the GPU. usage: 4-switch-access.sh dra | device-plugin
# dra: turns the NVIDIA device plugin off and installs the NVIDIA DRA driver (chart 0.5.1, consumable memory shares) with the cluster's node label.
# device-plugin: removes the DRA driver and turns the device plugin back on (the 8-slice setup used by the other demos). Reversible.
export KUBECONFIG=${KUBECONFIG:-/etc/rancher/k3s/k3s.yaml}
cd "$(dirname "$0")/../../../.." || exit 1
NODE=$(kubectl get nodes -o name | head -1 | cut -d/ -f2)
case $1 in
  dra)
    kubectl label node $NODE nvidia.com/dra-kubelet-plugin=true --overwrite >/dev/null
    kubectl patch clusterpolicies.nvidia.com/cluster-policy --type merge -p '{"spec":{"devicePlugin":{"enabled":false}}}' >/dev/null
    echo "Turning the device plugin off ..."
    for i in $(seq 1 40); do kubectl get pods -n gpu-operator --no-headers | grep -q device-plugin || break; sleep 3; done
    echo "Installing the DRA driver ..."
    helm upgrade -i dra-driver-nvidia-gpu nvidia/dra-driver-nvidia-gpu --version=0.5.1 --namespace nvidia-dra-driver-gpu --create-namespace \
      --set nvidiaDriverRoot=/ --set gpuResourcesEnabledOverride=true --set resources.computeDomains.enabled=false \
      --set featureGates.ConsumableShares=true --set consumableShares=memory -f k8s/kueue/dra-values.yaml >/dev/null
    for i in $(seq 1 60); do kubectl get resourceslice -o yaml 2>/dev/null | grep -q "allowMultipleAllocations: true" && break; sleep 3; done;;
  device-plugin)
    kubectl delete pod -l app=askdemo --ignore-not-found --grace-period=0 --force >/dev/null 2>&1
    kubectl delete resourceclaim --all -n default >/dev/null 2>&1
    helm uninstall dra-driver-nvidia-gpu -n nvidia-dra-driver-gpu >/dev/null 2>&1; kubectl delete ns nvidia-dra-driver-gpu --wait=false >/dev/null 2>&1
    kubectl label node $NODE nvidia.com/dra-kubelet-plugin- >/dev/null 2>&1
    kubectl patch clusterpolicies.nvidia.com/cluster-policy --type merge -p '{"spec":{"devicePlugin":{"enabled":true}}}' >/dev/null
    echo "Turning the device plugin back on ..."
    for i in $(seq 1 60); do [ "$(kubectl get node $NODE -o jsonpath='{.status.allocatable.nvidia\.com/gpu}')" = 8 ] && kubectl get pods -n gpu-operator --no-headers | grep device-plugin | grep -q Running && break; sleep 3; done;;
  *) echo "usage: $0 dra | device-plugin"; exit 1;;
esac
sleep 15; bash scripts/demo/dra/video/0-check-ready.sh
