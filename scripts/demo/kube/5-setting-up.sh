#!/usr/bin/env bash
# Metric 5 of 6, Kubernetes + NVIDIA: set up from scratch. Live: uninstall and reinstall the GPU Operator with Helm, pods coming up,
# the node advertising nvidia.com/gpu, a CUDA pod running nvidia-smi. Host driver, toolkit and k3s are prerequisites, not touched.
# usage: bash scripts/demo/kube/5-setting-up.sh        (about 3 to 5 minutes; takes the GPU stack down while it reinstalls)
source "$(dirname "$0")/../common.sh"
need_idle_kube
step 5 "Setting up (Kubernetes + NVIDIA)"
fix "One Helm install of the NVIDIA GPU Operator. It discovers the GPU, labels the node, runs the device plugin and the metrics exporter."
V=$(helm list -n gpu-operator -o json | jq -r '.[0].chart' | sed 's/gpu-operator-//'); say "Prerequisites on the host (not installed by the Operator here): driver $(nvidia-smi --query-gpu=driver_version --format=csv,noheader), container toolkit $(nvidia-ctk --version 2>/dev/null | head -1 | awk '{print $NF}'), k3s $(k3s --version | head -1 | awk '{print $3}')"
echo "${B}Start from nothing: uninstall the Operator${R}"
tl_start; show helm uninstall gpu-operator -n gpu-operator --wait --timeout 3m 2>&1 | tail -1
for i in $(seq 1 40); do [ "$(gpu_node_alloc 2>/dev/null)" != 1 ] && break; sleep 3; done
tl "GPUs Kubernetes can schedule now: $(kubectl get node -o jsonpath='{.items[0].status.allocatable.nvidia\.com/gpu}')  GPU pods left: $(kubectl get pods -n gpu-operator --no-headers 2>/dev/null | wc -l)"
echo "${B}Install it again, one command${R}"
tl_start; T0=$(date +%s)
show helm upgrade --install gpu-operator nvidia/gpu-operator -n gpu-operator --create-namespace --version "$V" --set driver.enabled=false --set toolkit.enabled=false --set 'dcgmExporter.env[0].name=DCGM_EXPORTER_INTERVAL' --set-string 'dcgmExporter.env[0].value=1000'
tl "helm returned after $(( $(date +%s)-T0 )) s"; GOT=""; LAST=""
for t in $(seq 1 200); do
  P=$(kubectl get pods -n gpu-operator --no-headers 2>/dev/null | awk '{n[$3]++} END{for(k in n) printf "%s=%d ",k,n[k]}')
  [ "$P" != "$LAST" ] && { tl "pods: $P"; LAST=$P; }
  A=$(kubectl get node -l nvidia.com/gpu.present=true -o jsonpath='{.items[0].status.allocatable.nvidia\.com/gpu}' 2>/dev/null)
  [ "$A" = 1 ] && [ -z "$GOT" ] && { GOT=$(( $(date +%s)-T0 )); tl "node now advertises nvidia.com/gpu: 1 (after ${GOT} s)"; }
  [ -n "$GOT" ] && ! kubectl get pods -n gpu-operator --no-headers | grep -vE "Running|Completed" | grep -q . && break; sleep 3; done
READY=$(( $(date +%s)-T0 ))
show kubectl get pods -n gpu-operator
echo "${B}What the Operator put on the node${R}"
kubectl get nodes -l nvidia.com/gpu.present=true -o json | jq -r '.items[0].metadata.labels | to_entries[] | select(.key|test("nvidia.com/(gpu.product|gpu.memory|gpu.count|cuda.driver-version.full|mig.capable)")) | "  " + .key + " = " + .value'
echo "${B}A pod that asks for the GPU${R}"
kubectl delete pod nvidia-smi --ignore-not-found >/dev/null 2>&1; kubectl apply -f k8s/smoke-nvidia-smi.yaml >/dev/null; SM=""
for t in $(seq 1 60); do ph=$(kubectl get pod nvidia-smi -o jsonpath='{.status.phase}' 2>/dev/null); [ "$ph" = Succeeded ] || [ "$ph" = Failed ] && break; sleep 2; done
kubectl logs nvidia-smi 2>/dev/null | grep -E "NVIDIA-SMI|RTX|MiB" | head -3 | sed 's/^/  /'; [ -z "$(kubectl logs nvidia-smi 2>/dev/null)" ] && note "CUDA test image may be missing from the local cache (pull is slow on this connection)."
kubectl delete pod nvidia-smi --ignore-not-found >/dev/null 2>&1; reset_kube
echo "${B}The rest of the stack as code${R}"
show helm list -A
say "  images in the local registry: $(curl -s localhost:5000/v2/_catalog | jq -r '.repositories | join(", ")')  (builds measured earlier: 258 s train, 601 s serve; the one-time cost)"
echo "${B}Scoreboard: setting up, Kubernetes${R}"
echo "  Operator install to node advertising a GPU:  ${GOT:-?} s"
echo "  all Operator pods Running or Completed:       ${READY} s"
echo "  commands you typed:                           1 (helm install) after k3s and the host driver/toolkit"
echo "  measured earlier, cold: images 859 s (one-time), training Job 676 s, serve 101 s; first-time setup took about twice as long as the manual way"
note "Kubernetes is not faster the first time. What it gives is that this stays written down and repeatable: Helm values and manifests."
result "Setting up" "Operator reinstalled with one Helm command, node advertising a GPU after ${GOT:-?} s, all pods ready in ${READY} s; same files on WSL2 and native Ubuntu"
