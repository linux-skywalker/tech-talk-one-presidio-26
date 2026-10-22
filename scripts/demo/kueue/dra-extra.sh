#!/usr/bin/env bash
# More DRA tests on the single RTX 4070 (single runs): (1) memory limits under a time-slicing claim vs an MPS claim, (2) Kueue managing a DRA device.
# Installs the NVIDIA DRA driver (device plugin off), runs the tests, then reverts. Output: logs/dra/extra.txt
source "$(dirname "$0")/../common.sh"; OUTD=logs/dra; mkdir -p $OUTD backups; LOG=$OUTD/extra.txt; : > $LOG
out() { echo "$*" | tee -a $LOG; }
NODE=$(kubectl get nodes -o name | head -1 | cut -d/ -f2)
revert() {
  kubectl delete jobs,pods --all -n default --wait=true >/dev/null 2>&1; kubectl delete resourceclaim --all -n default >/dev/null 2>&1
  kubectl delete -f k8s/kueue/kueue-dra.yaml --ignore-not-found >/dev/null 2>&1
  [ -f backups/kueue-config-before-dra.yaml ] && kubectl apply -f backups/kueue-config-before-dra.yaml >/dev/null 2>&1 && kubectl -n kueue-system rollout restart deploy/kueue-controller-manager >/dev/null 2>&1
  helm uninstall dra-driver-nvidia-gpu -n nvidia-dra-driver-gpu >/dev/null 2>&1; kubectl delete ns nvidia-dra-driver-gpu --wait=false >/dev/null 2>&1
  kubectl label node $NODE nvidia.com/dra-kubelet-plugin- >/dev/null 2>&1
  kubectl patch clusterpolicies.nvidia.com/cluster-policy --type merge -p '{"spec":{"devicePlugin":{"enabled":true}}}' >/dev/null
  for i in $(seq 1 60); do [ "$(gpu_node_alloc)" = 8 ] && kubectl get pods -n gpu-operator --no-headers | grep device-plugin | grep -q Running && break; sleep 3; done
  out "reverted: nvidia.com/gpu allocatable $(gpu_node_alloc), device plugin $(kubectl get pods -n gpu-operator --no-headers | grep device-plugin | awk '{print $3}')"; }
trap revert EXIT
need_idle_host
kubectl get clusterpolicy cluster-policy -o yaml > backups/clusterpolicy-before-dra-extra.yaml
kubectl -n kueue-system get cm kueue-manager-config -o yaml | grep -v "resourceVersion\|uid:\|creationTimestamp" > backups/kueue-config-before-dra.yaml
kubectl label node $NODE nvidia.com/dra-kubelet-plugin=true --overwrite >/dev/null
kubectl patch clusterpolicies.nvidia.com/cluster-policy --type merge -p '{"spec":{"devicePlugin":{"enabled":false}}}' >/dev/null
for i in $(seq 1 40); do kubectl get pods -n gpu-operator --no-headers | grep -q device-plugin || break; sleep 3; done
helm upgrade -i dra-driver-nvidia-gpu nvidia/dra-driver-nvidia-gpu --version=0.5.1 --namespace nvidia-dra-driver-gpu --create-namespace --set nvidiaDriverRoot=/ --set gpuResourcesEnabledOverride=true --set resources.computeDomains.enabled=false --set featureGates.TimeSlicingSettings=true --set featureGates.MPSSupport=true -f k8s/kueue/dra-values.yaml >/dev/null
for i in $(seq 1 60); do kubectl get resourceslice --no-headers 2>/dev/null | grep -q gpu.nvidia.com && break; sleep 3; done
out "== DRA extra tests, $(date '+%F %T'), RTX 4070, DRA driver 0.5.1 with TimeSlicingSettings and MPSSupport, device plugin off =="
kubectl apply -f k8s/kueue/dra-memclaims.yaml -f k8s/kueue/dra-claims.yaml >/dev/null

memtest() { # ts|mps
  local c=$1; kubectl delete pod -l app=memtest --wait=true >/dev/null 2>&1; wait_gpu_free
  kubectl apply -f k8s/kueue/dra-memtest-$c.yaml >/dev/null; local t0=$(date +%s)
  for i in $(seq 1 120); do
    s1=$(kubectl get pod mem-steady-$c -o jsonpath='{.status.phase}' 2>/dev/null); s2=$(kubectl get pod mem-greedy-$c -o jsonpath='{.status.phase}' 2>/dev/null)
    [ "$s1" = Succeeded -o "$s1" = Failed ] && [ "$s2" = Succeeded -o "$s2" = Failed ] && break; sleep 3; done
  out "Memory test, DRA claim with $c, single run (two pods, one claim, 11.6 GiB card), took $(( $(date +%s)-t0 )) s:"
  for p in mem-steady-$c mem-greedy-$c; do kubectl logs $p 2>&1 | sed 's/^/    /' | tee -a $LOG; done
  kubectl delete pod -l app=memtest --wait=true >/dev/null 2>&1; }
# the claims must be released between tests: MPS and time slicing need different GPU compute modes
memtest ts; kubectl delete resourceclaim mem-ts >/dev/null 2>&1; sleep 5; memtest mps

# --- Kueue managing the DRA device ---
kubectl -n kueue-system get cm kueue-manager-config -o json | jq '.data["controller_manager_config.yaml"] += "\nresources:\n  deviceClassMappings:\n  - name: nvidia.com/dra-gpu\n    deviceClassNames:\n    - gpu.nvidia.com\n"' | kubectl apply -f - >/dev/null
kubectl -n kueue-system rollout restart deploy/kueue-controller-manager >/dev/null; kubectl -n kueue-system rollout status deploy/kueue-controller-manager --timeout=120s >/dev/null; sleep 5
kubectl apply -f k8s/kueue/kueue-dra.yaml >/dev/null
HF=$HOME/.cache/huggingface
mkj() { # name queue(or -)
  local lbl="{}"; [ "$2" != - ] && lbl="{kueue.x-k8s.io/queue-name: $2}"
  cat <<YAML
apiVersion: batch/v1
kind: Job
metadata: {name: $1, labels: $lbl}
spec:
  backoffLimit: 0
  template:
    spec:
      restartPolicy: Never
      containers:
      - name: train
        image: localhost:5000/gpu-train:v1
        args: ["--out", "/out/dra-extra-$1-$RANDOM$RANDOM"]
        env:
        - {name: MODEL, value: HuggingFaceTB/SmolLM2-135M-Instruct}
        - {name: EPOCHS, value: "2"}
        - {name: BATCH, value: "16"}
        - {name: HF_HOME, value: /hf}
        - {name: HF_HUB_OFFLINE, value: "1"}
        - {name: HF_DATASETS_OFFLINE, value: "1"}
        volumeMounts: [{name: hf, mountPath: /hf}, {name: out, mountPath: /out}]
        resources: {claims: [{name: g}]}
      resourceClaims: [{name: g, resourceClaimTemplateName: one-gpu}]
      volumes:
      - {name: hf, hostPath: {path: $HF, type: Directory}}
      - {name: out, hostPath: {path: /tmp/kq-out, type: DirectoryOrCreate}}
YAML
}
arm() { # label queue prefix
  kubectl delete jobs --all --wait=true >/dev/null 2>&1; wait_gpu_free; local t0=$(date +%s) maxp=0 maxpods=0 gated=0
  for n in 1 2 3; do mkj $3$n $2 | kubectl apply -f - >/dev/null; done
  for i in $(seq 1 200); do
    pend=$(kubectl get pods --no-headers 2>/dev/null | grep -c Pending); np=$(kubectl get pods --no-headers 2>/dev/null | wc -l)
    [ "$pend" -gt "$maxp" ] && maxp=$pend; [ "$np" -gt "$maxpods" ] && maxpods=$np
    d=0; for n in 1 2 3; do [ -n "$(kubectl get job $3$n -o jsonpath='{.status.succeeded}' 2>/dev/null)" ] && d=$((d+1)); done; [ $d = 3 ] && break; sleep 1; done
  out "Three small training jobs on one DRA device, $1 (single run): all done after $(( $(date +%s)-t0 )) s; most pods existing at once $maxpods, most Pending pods at once $maxp"
  for n in 1 2 3; do local c=$(kubectl get job $3$n -o jsonpath='{.status.completionTime}'); out "    $3$n completed +$(( $(date -d "$c" +%s)-t0 )) s"; done; }
arm "through Kueue (quota nvidia.com/dra-gpu = 1)" dra k
kubectl get workloads.kueue.x-k8s.io 2>/dev/null | tee -a $LOG >/dev/null
arm "plain (no queue)" - p
