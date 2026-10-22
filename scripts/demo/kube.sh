#!/usr/bin/env bash
# The six metrics, Kubernetes + NVIDIA GPU Operator way. Shows what is fixed at each step.
# usage: bash scripts/demo/kube.sh        (Enter between steps; AUTO=1 to run straight through; SHARE_N=3 for fewer models). About 12 minutes with 6 models.
source "$(dirname "$0")/common.sh"
N=${SHARE_N:-6}
if pgrep -f '[v]llm serve' >/dev/null || pgrep -f '[t]rain.py' >/dev/null || ! gpu_free; then
  echo "${RED}GPU is busy.${R} Stop the traditional-path processes first."; exit 1; fi
cleanup_sharing() {
  kubectl delete -f k8s/serve-tiny-ports.yaml -f k8s/serve-tiny.yaml --ignore-not-found --wait=true >/dev/null 2>&1
  kubectl patch clusterpolicies.nvidia.com/cluster-policy --type json -p '[{"op":"remove","path":"/spec/devicePlugin/config"}]' >/dev/null 2>&1
  kubectl delete -f k8s/time-slicing-8.yaml --ignore-not-found >/dev/null 2>&1
  for i in $(seq 1 40); do [ "$(kubectl get node -l nvidia.com/gpu.present=true -o jsonpath='{.items[0].status.allocatable.nvidia\.com/gpu}')" = 1 ] && break; sleep 3; done
}
kubectl delete -f k8s/train-job.yaml --ignore-not-found >/dev/null 2>&1
bash scripts/demo/seed_cache.sh || exit 1
bash scripts/demo/seed_cache.sh --reset-outputs >/dev/null
cleanup_sharing; wait_gpu_free

step 1 "Sharing"
fix "Tell Kubernetes the GPU may be shared (time slicing), then run $N models as ordinary pods."
show kubectl apply -f k8s/time-slicing-8.yaml
kubectl patch clusterpolicies.nvidia.com/cluster-policy --type merge -p '{"spec":{"devicePlugin":{"config":{"name":"time-slicing-8","default":"any"}}}}' >/dev/null
for i in $(seq 1 40); do [ "$(kubectl get node -l nvidia.com/gpu.present=true -o jsonpath='{.items[0].status.allocatable.nvidia\.com/gpu}')" = 8 ] && break; sleep 3; done
say "GPUs Kubernetes can now schedule: $(kubectl get node -l nvidia.com/gpu.present=true -o jsonpath='{.items[0].status.allocatable.nvidia\.com/gpu}')  (one physical card)"
sed "s/replicas: 6/replicas: $N/" k8s/serve-tiny.yaml | kubectl apply -f - >/dev/null; kubectl apply -f k8s/serve-tiny-ports.yaml >/dev/null
T0=$(date +%s)
for t in $(seq 1 900); do
  RDY=$(kubectl get statefulset serve-tiny -o jsonpath='{.status.readyReplicas}' 2>/dev/null); RDY=${RDY:-0}
  printf '\r  %ss: %s of %s models ready (started one at a time, retries handled by Kubernetes) ' $(( $(date +%s)-T0 )) "$RDY" "$N"
  [ "$RDY" = "$N" ] && break; sleep 3; done; echo
show kubectl get pods -l app=serve-tiny
MS=0; for i in $(seq 0 $((N-1))); do
  a=$(date +%s%N)
  A=$(curl -s -m 20 localhost:$((30090+i))/v1/chat/completions -H 'Content-Type: application/json' -d '{"model":"HuggingFaceTB/SmolLM2-135M-Instruct","messages":[{"role":"user","content":"Say hello."}],"max_tokens":12,"temperature":0}' | jq -r '.choices[0].message.content // "no answer"' | tr '\n' ' ')
  m=$(( ($(date +%s%N)-a)/1000000 )); MS=$((MS+m))
  echo "  serve-tiny-$i: $A (${m} ms)"; done
MEAN=$((MS/N)); RST=$(kubectl get pods -l app=serve-tiny -o jsonpath='{range .items[*]}{.status.containerStatuses[0].restartCount}{"\n"}{end}' | awk '{s+=$1} END{print s+0}')
say "GPU memory used with $N models: $(gpu_used_mib) MiB of $(nvidia-smi --query-gpu=memory.total --format=csv,noheader,nounits) MiB"
echo "${B}Scoreboard: $N models on 1 GPU, Kubernetes${R}"
echo "  ready:            $RDY of $N in $(( $(date +%s)-T0 )) s, $RST restarts"
echo "  answers:          mean $MEAN ms per request (while sharing)"
echo "  GPU memory:       $(gpu_used_mib) MiB used"
echo "  utilization (measured earlier, same traffic per model): one model alone 14% busy at light traffic, 38% at moderate"
echo "                    six sharing one card: 49 to 71% busy at light traffic, 93% at moderate. 6 cards of hardware become 1"
echo "  the price:        answers take longer when shared: 81 ms alone vs 214 ms (light) and 396 ms (moderate)"
echo "  measured earlier: a plain Deployment of 6 had 4 of 6 up after 10 min; ordered start (StatefulSet) fixed it"
note "Time slicing shares time, not memory: no isolation. Sharing fits more models on a card, it does not add throughput."
result "Sharing" "$RDY of $N models ready on one card in $(( $(date +%s)-T0 )) s, $RST restarts, mean answer $MEAN ms"
cleanup_sharing; wait_gpu_free
pause

step 2 "Failures"
fix "Kubernetes watches the Job. We simulate the crash by force-deleting the pod (no grace period, like kill -9); it starts a replacement and training resumes from its last checkpoint."
kubectl apply -f k8s/pvc.yaml -f k8s/train-job.yaml >/dev/null
for t in $(seq 1 600); do kubectl exec job/train -- ls /work/outputs/k8s 2>/dev/null | grep -q 'checkpoint-75$' && break; printf '\r  training in a pod... %ss ' $t; sleep 1; done; echo
OLD=$(kubectl get pods -l app=train -o name | head -1)
show kubectl delete pod -l app=train --grace-period=0 --force
T0=$(date +%s); RUNSECS=""; RESSECS=""; GPUSECS=""; NEW=""; RES=""
for t in $(seq 1 240); do
  E=$(( $(date +%s)-T0 ))
  NEW=$(kubectl get pods -l app=train --no-headers 2>/dev/null | awk '$3=="Running"{print "pod/"$1}' | head -1)
  [ -z "$RUNSECS" ] && [ -n "$NEW" ] && [ "$NEW" != "$OLD" ] && RUNSECS=$E
  if [ -n "$RUNSECS" ]; then
    [ -z "$RESSECS" ] && RES=$(kubectl logs "$NEW" 2>/dev/null | grep -o 'resume_from_checkpoint=[^ ]*' | tail -1) && [ -n "$RES" ] && RESSECS=$E
    [ -n "$RESSECS" ] && [ "$(nvidia-smi --query-gpu=utilization.gpu --format=csv,noheader,nounits)" -ge 50 ] && { GPUSECS=$E; break; }
  fi
  sleep 1; done
show kubectl get pods -l app=train
echo "${B}Scoreboard: simulated crash (force delete, like kill -9), Kubernetes${R}"
echo "  replacement pod Running:       ${RUNSECS:-not seen} s"
echo "  resume line logged:            ${RESSECS:-not seen} s, ${RES:-none}"
echo "  GPU busy again (>= 50%):       ${GPUSECS:-not seen} s   <- training running again, nobody involved (headline)"
echo "  serving (measured earlier):    answering again in 77 to 81 s with nobody there; a person restarting by hand takes 28 s"
echo "  users during a tiny-pod kill (measured earlier): 39 of 40 requests OK, 6 of 6 ready again in 72 s"
note "A graceful pod delete (30 s grace period) took 46 to 51 s to resume in earlier measurements. Recovery time is mostly model startup, the same on both paths. The difference is that nobody has to be there."
result "Failures" "simulated crash: training running again ${GPUSECS:-?} s after the kill, resumed (${RES:-unknown}), no person involved"
kubectl delete -f k8s/train-job.yaml --ignore-not-found >/dev/null 2>&1
pause

step 3 "Watching"
wait_gpu_free; sleep 5
fix "GPU, pod and restart metrics are collected for you (DCGM exporter, Prometheus, kube-state-metrics, Grafana)."
Q='DCGM_FI_DEV_GPU_UTIL'
say "GPU busy right now, asked from Prometheus through Grafana: $(curl -s -u admin:admin "localhost:30300/api/datasources/proxy/uid/prometheus/api/v1/query" --data-urlencode "query=$Q" -G | jq -r '.data.result[0].value[1] // "no data"')%"
say "Live view: ${B}http://localhost:30300/d/six-metrics${R}  (admin / admin)"
result "Watching" "live dashboards with history, no terminal needed"
pause

step 4 "Moving"
fix "Kubernetes is a standard API, so the same manifests apply on any conformant cluster."
say "Lines changed in the manifests between the WSL2 branch and this native Ubuntu branch:"
show git diff --stat wsl ubuntu-4070 -- k8s/train-job.yaml k8s/serve-deployment.yaml k8s/pvc.yaml k8s/time-slicing-config.yaml
say "(no output above means 0 changed lines)"
result "Moving" "same manifests on WSL2 and native Ubuntu (0 changed lines in 4 files); another cloud not run"
pause

step 5 "Setting up"
fix "One Helm install of the NVIDIA GPU Operator. It discovers the GPU, labels the node, runs the device plugin and the metrics exporter."
show helm list -n gpu-operator
show kubectl get pods -n gpu-operator
say "GPUs Kubernetes can schedule: $(kubectl get node -l nvidia.com/gpu.present=true -o jsonpath='{.items[0].status.allocatable.nvidia\.com/gpu}')"
show bash -c "kubectl get nodes -l nvidia.com/gpu.present=true -o json | jq -r '.items[0].metadata.labels | to_entries[] | select(.key|test(\"nvidia.com/(gpu.product|gpu.memory|cuda.driver-version.full)\")) | \"  \" + .key + \" = \" + .value'"
note "The driver and container toolkit come from the host. The Operator does not install them here."
result "Setting up" "one Helm install; GPU found and labeled automatically; same manifests on WSL2 and native Ubuntu"
pause

step 6 "Growing"
fix "A new machine joins the cluster with one command, and the scheduler places pods on it."
show kubectl get nodes
IP=$(hostname -I | awk '{print $1}')
say "On the new machine (not run in this script; scripts/demo/vm-grow.sh does it live with VMs):"
say "  curl -sfL https://get.k3s.io | K3S_URL=https://$IP:6443 K3S_TOKEN=<token from /var/lib/rancher/k3s/server/node-token> sh -"
result "Growing" "by design: nodes join in about 65 to 86 s and get pods automatically (3 CPU-only VMs, scripts/demo/vm-grow.sh); the Operator adds GPU parts only to GPU nodes; GPU capacity not tested, one GPU"


summary "Kubernetes + NVIDIA"
