#!/usr/bin/env bash
# Extra sharing tests: oom (time slicing x4, server + 1.5B fine-tune), fault (kill -9 one client, two jobs), memtest (greedy vs steady memory pods).
# usage: bash scripts/techniques/run-extra.sh oom|fault|memtest ts4|mps2
source "$(dirname "$0")/lib.sh"
T=$1; S=$2; REPS=${REPS:-2}; need_idle_host; set_sharing $S; echo "$ADV" > $TQ/advertised-$S.txt
log "=== extra test $T under $S ($ADV) ==="
case $T in
 oom) # one run: the 1.5B server holds about 5 GB, then the 1.5B fine-tune (batch 4) starts next to it
  clean; mkserve 0.4 | kubectl apply -f - >/dev/null; wait_serve || { log "server not ready"; exit 1; }; sleep 5
  FREE0=$(nvidia-smi --query-gpu=memory.free --format=csv,noheader); log "server up, GPU memory free before training: $FREE0"
  sampler_start; mkjob tqoom $QWEN 1 4 | kubectl apply -f - >/dev/null; wait_jobs 120 tqoom; sampler_stop
  ST=$(job_status tqoom); kubectl logs job/tqoom > $TQ/oom-$S.log 2>&1
  ERR=$(grep -m1 -o "OutOfMemoryError: CUDA out of memory.*" $TQ/oom-$S.log | cut -c1-330)
  log "oom test $S: training $ST; peak GPU memory $(awk -F, '{if($3>m)m=$3}END{print m}' $SAMPLES) MiB; error: ${ERR:-none}"
  row $S "$ADV" oom-test 1 "1.5B fine-tune next to 1.5B server" $ST "" "" "" "" $(awk -F, '{if($3>m)m=$3}END{print m}' $SAMPLES) "" "" "" "" "" "" "free before: $FREE0; ${ERR:-no OOM}"
  clean;;
 fault) # two 4-epoch jobs; 25 s after both run, kill -9 the python process of job a on the host; watch job b
  for r in $(seq 1 $REPS); do
   clean; mkjob fa $SMOL 4 16 | kubectl apply -f - >/dev/null; mkjob fb $SMOL 4 16 | kubectl apply -f - >/dev/null
   for i in $(seq 1 100); do [ "$(kubectl get pods -l 'tq in (fa,fb)' --no-headers 2>/dev/null | grep -c Running)" = 2 ] && break; sleep 2; done; sleep 25
   # the container's main process: the matching python whose parent is not itself a matching process (children share the command line)
   PID=$(ps -eo pid=,ppid=,args= | awk '/--out \/out\/tq-fa-/ && !/awk/ {pid[$1]=1; par[$1]=$2} END{for (p in pid) if (!(par[p] in pid)) print p}' | head -1); T0=$(date +%s)
   # The training process is root-owned, so a plain kill -9 from this user fails (EPERM). Delete the Job (keeping its pod, so nothing replaces it), then force-delete the pod with no grace period: the runtime SIGKILLs the container at once (a Job delete alone only sends SIGTERM, which PID 1 ignores for 30 s).
   log "fault $S run $r: killing job fa (container main process host pid ${PID:-none}) with a forced delete (SIGKILL, no grace period)"
   kubectl delete job fa --cascade=orphan --wait=true >/dev/null 2>&1; kubectl delete pod -l tq=fa --grace-period=0 --force >/dev/null 2>&1; sleep 5
   GONE=$([ -n "$PID" ] && [ ! -d /proc/$PID ] && echo yes || echo no); log "fault $S run $r: process $PID gone after kill (checked in /proc): $GONE"
   wait_jobs 200 fb; T1=$(( $(date +%s)-T0 ))
   kubectl logs job/fb > $TQ/fault-$S-$r-fb.log 2>&1; true
   read rt sps smp <<<"$(job_perf fb)"; ERRB=$(grep -m1 -iE "error|exception|illegal|CUDA" $TQ/fault-$S-$r-fb.log | cut -c1-200)
   log "fault $S run $r: job fa (killed) -> $(job_status fa); job fb -> $(job_status fb), runtime ${rt}s, $T1 s after the kill; error in fb log: ${ERRB:-none}"
   [ "$GONE" != yes ] && log "fault $S run $r: INVALID, job fa was not killed"
   row $S "$ADV" fault-kill-one-client $r "fa(killed)/fb" "fa=killed fb=$(job_status fb) killed_ok=$GONE" $rt $sps $smp "" "" "" "" "" "" "" "" "fb error: ${ERRB:-none}"; done
  clean;;
 memtest) # same pods as the earlier MPS vs time-slicing test (k8s/mps-memtest.yaml), re-run
  clean; kubectl apply -f k8s/mps-memtest.yaml >/dev/null; T0=$(date +%s)
  for i in $(seq 1 120); do p1=$(kubectl get pod mem-steady -o jsonpath='{.status.phase}' 2>/dev/null); p2=$(kubectl get pod mem-greedy -o jsonpath='{.status.phase}' 2>/dev/null)
    case "$p1$p2" in *Succeeded*Succeeded*|*Failed*Succeeded*|*Succeeded*Failed*|*Failed*Failed*) break;; esac; sleep 3; done
  { echo "memtest $S ($ADV)"; for p in mem-steady mem-greedy; do echo "-- $p"; kubectl logs $p 2>&1 | grep -v "^\[W"; done; } | tee $TQ/memtest-$S.txt
  row $S "$ADV" memtest 1 "steady/greedy pods" done "" "" "" "" "" "" "" "" "" "" "$(grep -h 'steady' $TQ/memtest-$S.txt | tr '\n' ';' | cut -c1-200) $(grep -h 'greedy stopped' $TQ/memtest-$S.txt)"
  kubectl delete pod mem-steady mem-greedy --ignore-not-found --wait=true >/dev/null 2>&1;;
esac
set_sharing none; log "=== extra test $T under $S done ==="
