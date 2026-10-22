#!/usr/bin/env bash
# Metric 1 of 6, Kubernetes + NVIDIA: put 6 models on one GPU. Live: schedulable GPUs, pods starting one by one, GPU memory,
# then the SAME light traffic per model with one model alone and with six sharing the card (GPU busy from DCGM, latency from the clients).
# usage: bash scripts/demo/kube/1-sharing.sh        (SHARE_N=3 for fewer models; about 8 minutes with 6)
source "$(dirname "$0")/../common.sh"
N=${SHARE_N:-6}
need_idle_kube
step 1 "Sharing (Kubernetes + NVIDIA)"
fix "Tell Kubernetes the GPU may be shared, then run $N models as ordinary pods. Kubernetes starts them in order and keeps them running."
say "Schedulable GPUs before: $(gpu_node_alloc)  (one physical card)"
show kubectl apply -f k8s/time-slicing-8.yaml
kubectl patch clusterpolicies.nvidia.com/cluster-policy --type merge -p '{"spec":{"devicePlugin":{"config":{"name":"time-slicing-8","default":"any"}}}}' >/dev/null
for i in $(seq 1 40); do [ "$(gpu_node_alloc)" = 8 ] && break; sleep 3; done
say "Schedulable GPUs after:  $(gpu_node_alloc)  (same card, advertised 8 times; no memory isolation)"
kubectl apply -f k8s/serve-tiny-ports.yaml >/dev/null
sed "s/replicas: 6/replicas: 1/" k8s/serve-tiny.yaml | kubectl apply -f - >/dev/null
tl_start; sampler_start
echo "${B}One model alone${R}"
for t in $(seq 1 150); do [ "$(kubectl get statefulset serve-tiny -o jsonpath='{.status.readyReplicas}')" = 1 ] && break; sleep 2; done
tl "serve-tiny-0 ready, GPU $(gpu_now)"
sleep 3; ALONE=$(CLIENTS=1 PAUSE=0.5 scripts/loadtest-light.sh 20 0); echo "  $ALONE"
ALONE_BUSY=$(promf 'avg_over_time(max(DCGM_FI_DEV_GPU_UTIL)[20s:1s])'); ALONE_MS=$(echo "$ALONE" | grep -o 'mean *[0-9]*' | grep -o '[0-9]*')
tl "alone: GPU busy averaged ${ALONE_BUSY}% over the 20 s window (DCGM via Prometheus), mean answer ${ALONE_MS} ms"
echo "${B}Now scale to $N (Kubernetes starts them one at a time)${R}"
T0=$(date +%s); kubectl scale statefulset/serve-tiny --replicas=$N >/dev/null
for t in $(seq 1 600); do
  RDY=$(kubectl get statefulset serve-tiny -o jsonpath='{.status.readyReplicas}'); RDY=${RDY:-0}
  [ $((t % 10)) = 1 ] && tl "$RDY of $N ready, GPU memory $(gpu_used_mib) MiB, restarts $(kubectl get pods -l app=serve-tiny -o jsonpath='{range .items[*]}{.status.containerStatuses[0].restartCount}{"\n"}{end}' | awk '{s+=$1} END{print s+0}')"
  [ "$RDY" = "$N" ] && break; sleep 3; done
READY=$(( $(date +%s)-T0 )); show kubectl get pods -l app=serve-tiny -o wide
RST=$(kubectl get pods -l app=serve-tiny -o jsonpath='{range .items[*]}{.status.containerStatuses[0].restartCount}{"\n"}{end}' | awk '{s+=$1} END{print s+0}')
echo "${B}Every model answers${R}"
for i in $(seq 0 $((N-1))); do
  a=$(date +%s%N); A=$(curl -s -m 20 localhost:$((30090+i))/v1/chat/completions -H 'Content-Type: application/json' -d '{"model":"HuggingFaceTB/SmolLM2-135M-Instruct","messages":[{"role":"user","content":"Say hello."}],"max_tokens":12,"temperature":0}' | jq -r '.choices[0].message.content // "no answer"' | tr '\n' ' '); echo "  serve-tiny-$i: $A ($(( ($(date +%s%N)-a)/1000000 )) ms, idle)"; done
echo "${B}Same light traffic per model, all $N sharing the card${R}"
SH=$(CLIENTS=1 PAUSE=0.5 scripts/loadtest-light.sh 20 $(seq 0 $((N-1)))); echo "$SH" | sed 's/^/  /'
SH_BUSY=$(promf 'avg_over_time(max(DCGM_FI_DEV_GPU_UTIL)[20s:1s])'); SH_MS=$(echo "$SH" | grep -o 'mean *[0-9]*' | grep -o '[0-9]*' | awk '{s+=$1;n++} END{printf "%.0f", s/n}')
MEM=$(gpu_used_mib); TOTAL=$(nvidia-smi --query-gpu=memory.total --format=csv,noheader,nounits)
sampler_stop; sampler_stats "GPU over the whole step"
echo "${B}Scoreboard: $N models on 1 GPU, Kubernetes${R}"
echo "  ready:               $RDY of $N in ${READY} s after scaling, $RST restarts, no human"
echo "  GPU busy (same traffic per model):  1 model alone ${ALONE_BUSY}%  ->  $N sharing ${SH_BUSY}%   (this run)"
echo "  GPU memory:          ${MEM} of ${TOTAL} MiB used by $N models"
echo "  one card per model:  would be $N cards at about the 'alone' busy figure"
echo "  measured earlier:    plain Deployment of 6 had 4 of 6 up after 10 min; ordered start fixed it. Earlier sweeps: 38% alone vs 93% at moderate traffic. Runs of this step so far: 50%, 72% and 90% busy sharing (alone: 16 to 22%)"
echo "  one catch:                          answers ${ALONE_MS} ms -> ${SH_MS} ms because models take turns with no isolation. This RTX 4070 has no MIG; on A100/H100 MIG gives isolated slices (theory, not run). MPS adds memory limits per pod. Kubernetes lets you choose by setting"
note "GPU busy is not throughput: at saturation one copy alone does about the same total work as six sharing. Time slicing shares time, not memory."
result "Sharing" "$RDY of $N ready in ${READY} s, $RST restarts; GPU busy ${ALONE_BUSY}% alone to ${SH_BUSY}% sharing at the same per-model traffic; answers ${ALONE_MS} to ${SH_MS} ms"
kubectl delete -f k8s/serve-tiny-ports.yaml -f k8s/serve-tiny.yaml --ignore-not-found --wait=true >/dev/null 2>&1; need_idle_kube
