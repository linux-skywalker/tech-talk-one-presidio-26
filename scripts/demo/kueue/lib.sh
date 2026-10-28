#!/usr/bin/env bash
# Helpers for the Kueue experiments (sourced). Arms: plain (1 GPU replica per pod, no Kueue), units (memory-shaped replica
# requests, plain kube-scheduler), kueue (same requests through Kueue queues), kueue-nopreempt (Kueue with preemption off).
source "$(dirname "${BASH_SOURCE[0]}")/../common.sh"
HF_HOST=$HOME/.cache/huggingface
# GPU replicas a workload asks for: weights in memory-shaped units (about 1.5 GB each); the plain arm asks for 1 like today.
units() { [ "$ARM" = plain ] && { echo 1; return; }; case $1 in serve) echo 3;; trainm) echo 3;; trains) echo 1;; esac; }
weight() { case $1 in serve) echo 3;; trainm) echo 3;; trains) echo 1;; esac; }   # for the GPU-share metric, same in every arm
is_kueue() { [ "$ARM" = kueue ] || [ "$ARM" = kueue-nopreempt ] || [ "$ARM" = dra-kueue ]; }
is_dra() { [ "$ARM" = dra-kueue ]; }
rtc() { is_dra || echo "      runtimeClassName: nvidia"; }   # DRA injects the GPU through CDI, no runtime class
gpures() { if is_dra; then echo "resources: {claims: [{name: g}]}"; else echo "resources: {limits: {nvidia.com/gpu: $(units "$1")}}"; fi; }
podclaims() { is_dra && echo "      resourceClaims: [{name: g, resourceClaimTemplateName: gpu-$1}]"; }
qlabels() { is_dra && { printf 'kueue.x-k8s.io/queue-name: gpu-dra'; return; }; is_kueue && printf 'kueue.x-k8s.io/queue-name: gpu'; }
plabels() { is_kueue && printf 'kueue.x-k8s.io/priority-class: %s' "$1"; }

mk_train() { # name namespace kind(trainm|trains) priority
  local n=$1 ns=$2 kind=$3 prio=$4 batch=48 ep=4
  [ "$kind" = trains ] && { batch=4; ep=2; }
  cat <<YAML
apiVersion: batch/v1
kind: Job
metadata:
  name: $n
  namespace: $ns
  labels: {kq-kind: $kind, $(qlabels) $(is_kueue && printf ', '; plabels "$prio")}
spec:
  backoffLimit: 3
  template:
    metadata:
      labels: {app: kq-train, kq-job: $n}
    spec:
      restartPolicy: Never
$(rtc)
      containers:
      - name: train
        image: localhost:5000/gpu-train:v1
        args: ["--out", "/out/$RUNID/$n"]
        env:
        - {name: MODEL, value: HuggingFaceTB/SmolLM2-135M-Instruct}
        - {name: EPOCHS, value: "$ep"}
        - {name: BATCH, value: "$batch"}
        - {name: HF_HOME, value: /hf}
        - {name: HF_HUB_OFFLINE, value: "1"}
        - {name: HF_DATASETS_OFFLINE, value: "1"}
        volumeMounts: [{name: hf, mountPath: /hf}, {name: out, mountPath: /out}]
        $(gpures "$kind")
$(podclaims "$kind")
      volumes:
      - {name: hf, hostPath: {path: $HF_HOST, type: Directory}}
      - {name: out, hostPath: {path: /tmp/kq-out, type: DirectoryOrCreate}}
YAML
}

mk_serve() { # namespace priority
  local ns=$1 prio=$2
  cat <<YAML
apiVersion: apps/v1
kind: Deployment
metadata:
  name: serve
  namespace: $ns
  labels: {$(qlabels)}
spec:
  replicas: 1
  strategy: {type: Recreate}
  selector: {matchLabels: {app: serve}}
  template:
    metadata:
      labels: {app: serve, kq-kind: serve, $(plabels "$prio")}
    spec:
$(rtc)
      containers:
      - name: vllm
        image: localhost:5000/gpu-serve:v1
        env:
        - {name: ADAPTER, value: /none}
        - {name: GPU_UTIL, value: "0.4"}
        - {name: HF_HOME, value: /hf}
        - {name: HF_HUB_OFFLINE, value: "1"}
        ports: [{containerPort: 8000}]
        volumeMounts: [{name: hf, mountPath: /hf, readOnly: true}]
        readinessProbe: {httpGet: {path: /v1/models, port: 8000}, periodSeconds: 2}
        $(gpures serve)
$(podclaims serve)
      volumes:
      - {name: hf, hostPath: {path: $HF_HOST, type: Directory}}
---
apiVersion: v1
kind: Service
metadata: {name: serve, namespace: $ns}
spec:
  type: NodePort
  selector: {app: serve}
  ports: [{port: 8000, targetPort: 8000, nodePort: 30085}]
YAML
}

submit_train() { mk_train "$@" | kubectl apply -f - >/dev/null; echo "$1 $2 $3 $(date +%s.%N)" >> "$RUN/submits.txt"; tl "submitted $1 ($3, team ${2#team-}, $(units "$3") units)"; }
submit_serve() { mk_serve "$@" | kubectl apply -f - >/dev/null; echo "serve $1 serve $(date +%s.%N)" >> "$RUN/submits.txt"; tl "submitted serve (team ${1#team-}, $(units serve) units, priority $2)"; }

kq_reset() { # clean slate: no team workloads, GPU free; device plugin arms: time slicing x8 on; DRA arm: device plugin stays off
  for ns in team-a team-b; do kubectl delete jobs,deploy,svc --all -n $ns --wait=true >/dev/null 2>&1; done
  kubectl delete workloads.kueue.x-k8s.io --all -A --wait=true >/dev/null 2>&1
  local pol=LowerPriority; [ "$ARM" = kueue-nopreempt ] && pol=Never
  if is_dra; then
    for cq in cqd-team-a cqd-team-b; do kubectl patch clusterqueue $cq --type merge -p "{\"spec\":{\"preemption\":{\"withinClusterQueue\":\"$pol\"}}}" >/dev/null; done
  else
    kubectl apply -f k8s/time-slicing-8.yaml >/dev/null
    kubectl patch clusterpolicies.nvidia.com/cluster-policy --type merge -p '{"spec":{"devicePlugin":{"config":{"name":"time-slicing-8","default":"any"}}}}' >/dev/null
    for i in $(seq 1 60); do [ "$(gpu_node_alloc)" = 8 ] && break; sleep 3; done
    for cq in cq-team-a cq-team-b; do kubectl patch clusterqueue $cq --type merge -p "{\"spec\":{\"preemption\":{\"withinClusterQueue\":\"$pol\"}}}" >/dev/null; done
  fi
  wait_gpu_free || { echo "GPU not free"; return 1; }
}
