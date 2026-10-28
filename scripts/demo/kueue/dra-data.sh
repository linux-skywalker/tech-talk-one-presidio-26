#!/usr/bin/env bash
# DRA versus device-plugin time slicing, same workloads, single runs. usage: bash scripts/demo/kueue/dra-data.sh plugin|dra
# T1: two small training jobs at once.  T2: the vLLM server plus one training job at once.  (dra also runs T1 with an exclusive claim per job.)
MODE=$1; source "$(dirname "$0")/../common.sh"; OUTD=logs/dra; mkdir -p $OUTD; LOG=$OUTD/data-$MODE.txt; : > $LOG
HF=$HOME/.cache/huggingface
out() { echo "$*" | tee -a $LOG; }
gpuspec() { # $1 = claim source: plugin | shared | tmpl
  case $1 in
   plugin) printf '        resources: {limits: {nvidia.com/gpu: 1}}\n      runtimeClassName: nvidia\n';;
   shared) printf '        resources: {claims: [{name: g}]}\n      resourceClaims: [{name: g, resourceClaimName: ts-gpu}]\n';;
   tmpl)   printf '        resources: {claims: [{name: g}]}\n      resourceClaims: [{name: g, resourceClaimTemplateName: one-gpu}]\n';;
  esac; }
mkjob() { # name epochs batch model spec
  cat <<YAML
apiVersion: batch/v1
kind: Job
metadata: {name: $1}
spec:
  backoffLimit: 0
  template:
    spec:
      restartPolicy: Never
      containers:
      - name: train
        image: localhost:5000/gpu-train:v1
        args: ["--out", "/out/data-$MODE-$1-$RANDOM$RANDOM"]
        env:
        - {name: MODEL, value: $4}
        - {name: EPOCHS, value: "$2"}
        - {name: BATCH, value: "$3"}
        - {name: HF_HOME, value: /hf}
        - {name: HF_HUB_OFFLINE, value: "1"}
        - {name: HF_DATASETS_OFFLINE, value: "1"}
        volumeMounts: [{name: hf, mountPath: /hf}, {name: out, mountPath: /out}]
$(gpuspec $5)
      volumes:
      - {name: hf, hostPath: {path: $HF, type: Directory}}
      - {name: out, hostPath: {path: /tmp/kq-out, type: DirectoryOrCreate}}
YAML
}
mkserve() { # spec
  cat <<YAML
apiVersion: apps/v1
kind: Deployment
metadata: {name: serve}
spec:
  replicas: 1
  strategy: {type: Recreate}
  selector: {matchLabels: {app: serve}}
  template:
    metadata: {labels: {app: serve}}
    spec:
      containers:
      - name: vllm
        image: localhost:5000/gpu-serve:v1
        env:
        - {name: ADAPTER, value: /none}
        - {name: GPU_UTIL, value: "0.4"}
        - {name: HF_HOME, value: /hf}
        - {name: HF_HUB_OFFLINE, value: "1"}
        volumeMounts: [{name: hf, mountPath: /hf}]
        readinessProbe: {httpGet: {path: /v1/models, port: 8000}, periodSeconds: 2}
$(gpuspec $1)
      volumes:
      - {name: hf, hostPath: {path: $HF, type: Directory}}
YAML
}
jobs_done() { for j in "$@"; do [ -n "$(kubectl get job $j -o jsonpath='{.status.succeeded}{.status.failed}' 2>/dev/null)" ] || return 1; done; }
clean() { kubectl delete jobs,deploy --all --wait=true >/dev/null 2>&1; wait_gpu_free; }
report_jobs() { # t0 jobs...
  local t0=$1; shift; local last=0
  for j in "$@"; do
    local st=$(kubectl get job $j -o jsonpath='{.status.startTime}') ct=$(kubectl get job $j -o jsonpath='{.status.completionTime}') ok=$(kubectl get job $j -o jsonpath='{.status.succeeded}')
    local rt=$(kubectl logs job/$j 2>/dev/null | grep -o "'train_runtime': '[0-9.]*'" | grep -o "[0-9.]*'" | tr -d "'")
    local s=$(date -d "$st" +%s 2>/dev/null) c=$(date -d "$ct" +%s 2>/dev/null)
    out "  $j: succeeded=${ok:-0}  start +$((s-t0)) s  completed +$((c-t0)) s  train_runtime ${rt:-n/a} s"
  done; }
T1() { # label spec1 spec2
  clean; sampler_start; local t0=$(date +%s)
  mkjob a 2 16 HuggingFaceTB/SmolLM2-135M-Instruct $2 | kubectl apply -f - >/dev/null; mkjob b 2 16 HuggingFaceTB/SmolLM2-135M-Instruct $3 | kubectl apply -f - >/dev/null
  for i in $(seq 1 150); do jobs_done a b && break; sleep 2; done
  local tw=$(( $(date +%s)-t0 )); sampler_stop; out "T1 [$1] two training jobs (SmolLM2-135M, batch 16, 2 epochs), single run: both finished after ${tw} s (apply to last completion)"
  report_jobs $t0 a b; out "$(sampler_stats GPU)"; clean; }
T2() { # label spec
  clean; sampler_start; local t0=$(date +%s)
  mkserve $2 | kubectl apply -f - >/dev/null; mkjob c 4 48 HuggingFaceTB/SmolLM2-135M-Instruct $2 | kubectl apply -f - >/dev/null
  local rdy=""; for i in $(seq 1 200); do [ -z "$rdy" ] && kubectl get deploy serve -o jsonpath='{.status.readyReplicas}' | grep -q 1 && rdy=$(( $(date +%s)-t0 )); [ -n "$rdy" ] && jobs_done c && break; sleep 2; done
  local tw=$(( $(date +%s)-t0 )); sampler_stop; out "T2 [$1] vLLM server + one training job (SmolLM2-135M, batch 48, 4 epochs), single run: server ready after ${rdy:-never} s; run ended after ${tw} s; restarts: $(kubectl get pods -l app=serve -o jsonpath='{.items[*].status.containerStatuses[*].restartCount}')"
  report_jobs $t0 c; out "$(sampler_stats GPU)"; clean; }
out "== DRA data, mode $MODE, $(date '+%F %T'), RTX 4070, k3s $(kubectl version -o json | jq -r .serverVersion.gitVersion) =="
case $MODE in
 plugin) out "(device plugin, time slicing x8, each pod asks for 1 replica)"
   T1 "device plugin, time slicing" plugin plugin; T2 "device plugin, time slicing" plugin;;
 dra-excl) kubectl apply -f k8s/kueue/dra-claims.yaml >/dev/null
   out "(DRA, exclusive claim per job: one device; rerun with fresh output folders)"; T1 "DRA exclusive claim per job" tmpl tmpl;;
 dra)
   kubectl apply -f k8s/kueue/dra-claims.yaml >/dev/null
   out "(DRA driver 0.5.1, device plugin off; shared claim with TimeSlicing interval Long)"
   T1 "DRA shared claim, time slicing" shared shared; T2 "DRA shared claim, time slicing" shared
   out "(DRA, exclusive claim per job: one device)"; T1 "DRA exclusive claim per job" tmpl tmpl;;
esac
