#!/usr/bin/env bash
# Metric 2 of 6, Kubernetes + NVIDIA: the same simulated crash. Live: training step before, pod phases second by second, GPU, resume point.
# usage: bash scripts/demo/kube/2-failures.sh        (about 5 minutes)
source "$(dirname "$0")/../common.sh"
need_idle_kube
step 2 "Failures (Kubernetes + NVIDIA)"
fix "Kubernetes watches the Job. We simulate the crash by force-deleting the pod (no grace period, like kill -9); it starts a replacement and training resumes from its last checkpoint."
bash scripts/demo/seed_cache.sh >/dev/null && bash scripts/demo/seed_cache.sh --reset-outputs >/dev/null
kubectl apply -f k8s/pvc.yaml -f k8s/train-job.yaml >/dev/null; tl_start; sampler_start
for t in $(seq 1 600); do
  [ $((t % 10)) = 0 ] && tl "$(kubectl get pods -l app=train --no-headers | awk '{print $1, $3}'), checkpoints: $(kubectl exec job/train -- ls /work/outputs/k8s 2>/dev/null | grep -c checkpoint), GPU $(gpu_now)"
  kubectl exec job/train -- ls /work/outputs/k8s 2>/dev/null | grep -q 'checkpoint-75$' && break; sleep 1; done
OLD=$(kubectl get pods -l app=train -o name | head -1)
tl "before the crash: $OLD, checkpoint-75 written, GPU $(gpu_now)"
show kubectl delete pod -l app=train --grace-period=0 --force
T0=$(date +%s); RUNS=""; RESS=""; GPUS=""; NEW=""; RES=""; LASTPH=""
for t in $(seq 1 240); do
  E=$(( $(date +%s)-T0 )); PH=$(kubectl get pods -l app=train --no-headers 2>/dev/null | awk '{print $1":"$3}' | tr '\n' ' ')
  [ "$PH" != "$LASTPH" ] && { tl "pods: $PH"; LASTPH=$PH; }
  NEW=$(kubectl get pods -l app=train --no-headers 2>/dev/null | awk '$3=="Running"{print "pod/"$1}' | head -1)
  [ -z "$RUNS" ] && [ -n "$NEW" ] && [ "$NEW" != "$OLD" ] && { RUNS=$E; tl "replacement pod Running after ${E} s"; }
  if [ -n "$RUNS" ]; then
    [ -z "$RESS" ] && RES=$(kubectl logs "$NEW" 2>/dev/null | grep -o 'resume_from_checkpoint=[^ ]*' | tail -1) && [ -n "$RES" ] && { RESS=$E; tl "resume line after ${E} s: $RES"; }
    [ -n "$RESS" ] && [ "$(gpu_util_now)" -ge 50 ] && { GPUS=$E; tl "GPU busy again after ${E} s, GPU $(gpu_now)"; break; }
  fi; sleep 1; done
sleep 12; CK=$(kubectl exec "$NEW" -- ls /work/outputs/k8s 2>/dev/null | grep checkpoint | sort -t- -k2 -n | tail -1 | tr '\n' ' ')
tl "checkpoints now: $CK"; show kubectl get job train; show kubectl get pods -l app=train
sampler_stop; sampler_stats "GPU over the whole test"
echo "${B}Scoreboard: simulated crash, Kubernetes${R}"
echo "  replacement pod Running:       ${RUNS:-not seen} s after the kill"
echo "  resume line logged:            ${RESS:-not seen} s, ${RES:-none}"
echo "  GPU busy again (>= 50%):       ${GPUS:-not seen} s   <- training running again, nobody involved (headline)"
echo "  lost work:                     only the steps since the last checkpoint (written every 25 steps)"
echo "  serving (measured earlier):    answering again in 77 to 81 s with nobody there (28 s if a person restarts it by hand)"
echo "  users during a tiny-pod kill (measured earlier): 39 of 40 requests OK, 6 of 6 ready again in 72 s"
note "A graceful pod delete (30 s grace period) took 46 to 51 s to resume in earlier measurements. Recovery is mostly model startup, the same on both paths; the difference is that nobody has to be there."
result "Failures" "training running again ${GPUS:-?} s after the kill, resumed (${RES:-unknown}), no person involved"
kubectl delete -f k8s/train-job.yaml --ignore-not-found >/dev/null 2>&1; wait_gpu_free
