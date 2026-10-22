#!/usr/bin/env bash
# One scenario run. usage: bash scripts/demo/kueue/run.sh <s1|s2|s3> <plain|units|kueue|kueue-nopreempt> <rep>
# s1: serve + 2 training jobs submitted together.  s2: GPU full of batch work, then inference arrives (priority + preemption).
# s4: team A's batch jobs are RUNNING when inference arrives (preemption test).  s3: team A floods the queue, team B submits two jobs later.  Raw data goes to logs/kueue/<s>_<arm>_<rep>/.
SC=$1; ARM=$2; REP=${3:-1}; export ARM
source "$(dirname "$0")/lib.sh"
RUNID=$(date +%H%M%S)-$SC-$ARM-$REP; RUN=logs/kueue/${SC}_${ARM}_${REP}; rm -rf "$RUN"; mkdir -p "$RUN"; export RUNID RUN
TIMEOUT=${TIMEOUT:-$([ $SC = s3 ] && echo 600 || echo 420)}
echo "=== $SC / $ARM / run $REP ($RUNID) ==="
kq_reset || exit 1
[ "$(nprocs 'vllm serve')" != 0 ] && { echo "host vLLM running"; exit 1; }
python3 scripts/demo/kueue/monitor.py "$RUN" & MON=$!
sleep 4; T0=$(date +%s.%N); echo "t0 $T0 $SC $ARM $REP" > "$RUN/meta.txt"; tl_start
case $SC in
 s1) submit_serve team-a inference; submit_train t1 team-a trainm batch; submit_train t2 team-b trainm batch; NJOBS=2;;
 s2) submit_train t1 team-a trainm batch; submit_train t2 team-b trainm batch; submit_train sm1 team-b trains batch; sleep 35
     submit_serve team-a inference; NJOBS=3;;
 s4) submit_train t1 team-a trainm batch; submit_train t2 team-a trainm batch   # batch work fills the GPU, then inference arrives
     for i in $(seq 1 120); do [ "$(kubectl get pods -n team-a -l app=kq-train --no-headers 2>/dev/null | grep -c Running)" = 2 ] && break; sleep 1; done
     sleep 12; tl "both batch jobs running; inference arrives now"; submit_serve team-a inference; NJOBS=2;;
 s3) for i in 1 2 3 4 5; do submit_train a$i team-a trainm batch; done; sleep 25
     for i in 1 2; do submit_train b$i team-b trainm batch; done; NJOBS=7;;
esac
echo "njobs $NJOBS" >> "$RUN/meta.txt"
for t in $(seq 1 $TIMEOUT); do
  done_n=0; fail_n=0
  for ns in team-a team-b; do
    done_n=$((done_n + $(kubectl get jobs -n $ns -o jsonpath='{range .items[*]}{.status.succeeded}{"\n"}{end}' 2>/dev/null | grep -c 1)))
    fail_n=$((fail_n + $(kubectl get jobs -n $ns -o jsonpath='{range .items[*]}{.status.conditions[?(@.type=="Failed")].status}{"\n"}{end}' 2>/dev/null | grep -c True)))
  done
  [ $((t % 20)) = 0 ] && tl "jobs done $done_n, failed $fail_n of $NJOBS; $(kubectl get pods -A -l 'kq-kind' --no-headers 2>/dev/null | awk '{c[$4]++}END{for(k in c)printf "%s=%d ",k,c[k]}') GPU $(gpu_now)"
  [ $((done_n + fail_n)) -ge $NJOBS ] && break; sleep 1
done
[ $SC != s3 ] && { # let the probe see serve under load / alone for a short while after the batch work
  for i in $(seq 1 40); do kubectl get deploy serve -n team-a -o jsonpath='{.status.readyReplicas}' 2>/dev/null | grep -q 1 && break; sleep 3; done; sleep 10; }
echo "end $(date +%s.%N)" >> "$RUN/meta.txt"
# the DCGM exporter view of the same window (max over series, subquery form as in the Watching step)
DUR=$(awk '/^t0/{t=$2}/^end/{e=$2}END{printf "%d", e-t}' "$RUN/meta.txt")
echo "dcgm_avg_util $(prom "avg_over_time(max(DCGM_FI_DEV_GPU_UTIL)[${DUR}s:1s])")" >> "$RUN/meta.txt"
touch "$RUN/stop"; wait $MON 2>/dev/null
for ns in team-a team-b; do kubectl get jobs,pods,deploy -n $ns -o json > "$RUN/objects-$ns.json"; done
kubectl get workloads.kueue.x-k8s.io -A -o json > "$RUN/workloads.json" 2>/dev/null
: > "$RUN/oom.txt"; for ns in team-a team-b; do for p in $(kubectl get pods -n $ns -o name 2>/dev/null); do
  echo "$ns $p $(kubectl logs -n $ns $p 2>/dev/null | grep -ci 'out of memory\|OutOfMemory\|No available memory')" >> "$RUN/oom.txt"; done; done
python3 scripts/demo/kueue/analyze.py "$RUN" | tee "$RUN/summary.txt"
for ns in team-a team-b; do kubectl delete jobs,deploy,svc --all -n $ns --wait=true >/dev/null 2>&1; done
wait_gpu_free
