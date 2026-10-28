#!/usr/bin/env bash
# Shared helpers for the technique measurements (time slicing, MPS, ...). Sourced. Raw CSVs go to logs/techniques/.
source "$(dirname "${BASH_SOURCE[0]}")/../demo/common.sh"
TQ=logs/techniques; mkdir -p $TQ /tmp/kq-out
HF=$HOME/.cache/huggingface
CSV=${CSV:-$TQ/measurements.csv}
[ -f "$CSV" ] || echo "technique,setting,test,run,item,status,train_runtime_s,steps_per_s,samples_per_s,gpu_busy_avg,gpu_mem_max_mib,p50_total_s,p95_total_s,p50_ttft_s,p95_ttft_s,n_ok,n_fail,note" > $CSV
row() { local IFS=,; echo "$*" >> $CSV; }
log() { echo "[$(date +%T)] $*" | tee -a $TQ/run.log; }

set_sharing() { # none | ts2 | ts4 | mps2: configure the device plugin, wait until it advertises the new setting
  local want_n want_s
  case $1 in
    none) want_n=1; want_s=none; kubectl patch clusterpolicies.nvidia.com/cluster-policy --type json -p '[{"op":"remove","path":"/spec/devicePlugin/config"}]' >/dev/null 2>&1;;
    ts2)  want_n=2; want_s=time-slicing; kubectl apply -f k8s/techniques/ts-2.yaml >/dev/null; kubectl patch clusterpolicies.nvidia.com/cluster-policy --type merge -p '{"spec":{"devicePlugin":{"config":{"name":"time-slicing-2","default":"any"}}}}' >/dev/null;;
    ts4)  want_n=4; want_s=time-slicing; kubectl apply -f k8s/time-slicing-config.yaml >/dev/null; kubectl patch clusterpolicies.nvidia.com/cluster-policy --type merge -p '{"spec":{"devicePlugin":{"config":{"name":"time-slicing-config","default":"any"}}}}' >/dev/null;;
    mps2) want_n=2; want_s=mps; kubectl apply -f k8s/mps-config.yaml >/dev/null; kubectl patch clusterpolicies.nvidia.com/cluster-policy --type merge -p '{"spec":{"devicePlugin":{"config":{"name":"mps-config","default":"any"}}}}' >/dev/null;;
  esac
  for i in $(seq 1 80); do
    [ "$(gpu_node_alloc)" = "$want_n" ] && [ "$(kubectl get node -l nvidia.com/gpu.present=true -o jsonpath='{.items[0].metadata.labels.nvidia\.com/gpu\.sharing-strategy}')" = "$want_s" ] && break; sleep 3; done
  [ "$want_s" = mps ] && for i in $(seq 1 40); do kubectl get pods -n gpu-operator --no-headers | grep -i mps | grep -q Running && break; sleep 3; done
  sleep 8; wait_gpu_free
  ADV="nvidia.com/gpu=$(gpu_node_alloc) strategy=$(kubectl get node -l nvidia.com/gpu.present=true -o jsonpath='{.items[0].metadata.labels.nvidia\.com/gpu\.sharing-strategy}') replicas=$(kubectl get node -l nvidia.com/gpu.present=true -o jsonpath='{.items[0].metadata.labels.nvidia\.com/gpu\.replicas}')"
  log "sharing $1 -> node advertises $ADV"; }

clean() { kubectl delete jobs,deploy,svc,pods -l tq --wait=true >/dev/null 2>&1; kubectl delete jobs,deploy,svc,pods --all --wait=true >/dev/null 2>&1; wait_gpu_free; }

mkjob() { # name model epochs batch [gpus]
  cat <<YAML
apiVersion: batch/v1
kind: Job
metadata: {name: $1, labels: {tq: "$1"}}
spec:
  backoffLimit: 0
  template:
    metadata: {labels: {tq: "$1"}}
    spec:
      restartPolicy: Never
      runtimeClassName: nvidia
      containers:
      - name: train
        image: localhost:5000/gpu-train:v1
        args: ["--out", "/out/tq-$1-$RANDOM$RANDOM"]
        env:
        - {name: MODEL, value: $2}
        - {name: EPOCHS, value: "$3"}
        - {name: BATCH, value: "$4"}
        - {name: HF_HOME, value: /hf}
        - {name: HF_HUB_OFFLINE, value: "1"}
        - {name: HF_DATASETS_OFFLINE, value: "1"}
        volumeMounts: [{name: hf, mountPath: /hf}, {name: out, mountPath: /out}]
        resources: {limits: {nvidia.com/gpu: ${5:-1}}}
      volumes:
      - {name: hf, hostPath: {path: $HF, type: Directory}}
      - {name: out, hostPath: {path: /tmp/kq-out, type: DirectoryOrCreate}}
YAML
}
SMOL=HuggingFaceTB/SmolLM2-135M-Instruct
QWEN=Qwen/Qwen2.5-1.5B-Instruct
mkserve() { # gpu_util
  cat <<YAML
apiVersion: apps/v1
kind: Deployment
metadata: {name: tq-serve, labels: {tq: serve}}
spec:
  replicas: 1
  strategy: {type: Recreate}
  selector: {matchLabels: {app: tq-serve}}
  template:
    metadata: {labels: {app: tq-serve, tq: serve}}
    spec:
      runtimeClassName: nvidia
      containers:
      - name: vllm
        image: localhost:5000/gpu-serve:v1
        env:
        - {name: ADAPTER, value: /none}
        - {name: GPU_UTIL, value: "${1:-0.4}"}
        - {name: HF_HOME, value: /hf}
        - {name: HF_HUB_OFFLINE, value: "1"}
        ports: [{containerPort: 8000}]
        volumeMounts: [{name: hf, mountPath: /hf}]
        readinessProbe: {httpGet: {path: /v1/models, port: 8000}, periodSeconds: 2}
        resources: {limits: {nvidia.com/gpu: 1}}
      volumes:
      - {name: hf, hostPath: {path: $HF, type: Directory}}
---
apiVersion: v1
kind: Service
metadata: {name: tq-serve, labels: {tq: serve}}
spec:
  type: NodePort
  selector: {app: tq-serve}
  ports: [{port: 8000, targetPort: 8000, nodePort: 30086}]
YAML
}

job_state() { kubectl get job $1 -o jsonpath='{.status.succeeded}{.status.failed}' 2>/dev/null; }  # "1" ok, "1"+fail digit
job_done() { local s; s=$(kubectl get job $1 -o jsonpath='ok={.status.succeeded} bad={.status.failed}' 2>/dev/null); case "$s" in *ok=1*|*bad=[1-9]*) return 0;; esac; return 1; }
job_status() { local s; s=$(kubectl get job $1 -o jsonpath='ok={.status.succeeded} bad={.status.failed}' 2>/dev/null); case "$s" in *ok=1*) echo ok;; *bad=[1-9]*) echo failed;; *) echo unfinished;; esac; }
job_perf() { # name -> "runtime steps_per_s samples_per_s" from the trainer's own log line
  kubectl logs job/$1 2>/dev/null | grep -o "'train_runtime'.*" | tail -1 | python3 -c "
import re,sys
t=sys.stdin.read(); g=lambda k:(re.search(\"'\"+k+\"': '([0-9.]+)'\",t) or [None,'n/a'])[1]
print(g('train_runtime'),g('train_steps_per_second'),g('train_samples_per_second'))"; }
gpu_csv_stats() { awk -F, '{n++;u+=$2;if($3>mm)mm=$3} END{if(n)printf "%.0f %d",u/n,mm; else printf "n/a n/a"}' "$SAMPLES"; }
wait_jobs() { local limit=$1; shift; for i in $(seq 1 $limit); do local d=1; for j in "$@"; do job_done $j || d=0; done; [ $d = 1 ] && return 0; sleep 2; done; return 1; }
wait_serve() { for i in $(seq 1 150); do kubectl get deploy tq-serve -o jsonpath='{.status.readyReplicas}' 2>/dev/null | grep -q 1 && return 0; sleep 2; done; return 1; }
