#!/usr/bin/env bash
# Measurements for GPU sharing on one RTX 4070: baseline (no sharing), time slicing x2, x4 and MPS x2. Each test is repeated twice (run 1, 2).
# usage: bash scripts/techniques/run-sharing.sh none|ts2|ts4|mps2        Output: logs/techniques/measurements.csv (+ run.log)
source "$(dirname "$0")/lib.sh"
S=$1; REPS=${REPS:-2}
need_idle_host
log "=== setting $S: GPU $(nvidia-smi --query-gpu=name,compute_cap,driver_version --format=csv,noheader) ==="
set_sharing $S; echo "$ADV" > $TQ/advertised-$S.txt

solo() { # long|short: one training job alone (short: SmolLM batch16 epochs2; long: batch48 epochs4)
  local kind=$1 e=2 b=16; [ $kind = long ] && { e=4; b=48; }
  for r in $(seq 1 $REPS); do
    clean; sampler_start; mkjob alone $SMOL $e $b | kubectl apply -f - >/dev/null; wait_jobs 150 alone; sampler_stop
    read rt sps smp <<<"$(job_perf alone)"; read gb gm <<<"$(gpu_csv_stats)"
    log "$S train-alone-$kind run $r: $(job_status alone) runtime ${rt}s steps/s $sps GPU busy ${gb}% mem ${gm} MiB"
    row $S "$ADV" "train-alone-$kind" $r alone "$(job_status alone)" $rt $sps $smp $gb $gm "" "" "" "" "" "" ""; done; }

pair() { # two training jobs at once (short)
  for r in $(seq 1 $REPS); do
    clean; sampler_start; mkjob a $SMOL 2 16 | kubectl apply -f - >/dev/null; mkjob b $SMOL 2 16 | kubectl apply -f - >/dev/null
    wait_jobs 150 a b; sampler_stop; read gb gm <<<"$(gpu_csv_stats)"
    for j in a b; do read rt sps smp <<<"$(job_perf $j)"
      log "$S pair run $r job $j: $(job_status $j) runtime ${rt}s steps/s $sps (GPU busy ${gb}%, mem ${gm} MiB)"
      row $S "$ADV" pair $r $j "$(job_status $j)" $rt $sps $smp $gb $gm "" "" "" "" "" "" ""; done; done; }

serving() { # vLLM server; latency alone, then while a training job runs (long) on the same GPU
  clean; mkserve 0.4 | kubectl apply -f - >/dev/null
  if ! wait_serve; then log "$S serving: server did not become ready"; kubectl describe pod -l app=tq-serve | tail -15 | tee -a $TQ/run.log; row $S "$ADV" serve-alone 1 server not-ready "" "" "" "" "" "" "" "" "" 0 0 "server never ready"; clean; return; fi
  sleep 5; rm -f $TQ/stop-$S; python3 scripts/techniques/probe.py $TQ/probe-$S-alone.csv $TQ/stop-$S & PP=$!
  A0=$(date +%s); sleep 40; A1=$(date +%s); touch $TQ/stop-$S; wait $PP
  read ok bad p50 p95 t50 t95 <<<"$(python3 scripts/techniques/stats.py $TQ/probe-$S-alone.csv $A0 $A1)"
  log "$S serve alone: ok $ok fail $bad p50 ${p50}s p95 ${p95}s ttft p50 ${t50}s p95 ${t95}s"
  row $S "$ADV" serve-alone 1 server ok "" "" "" "" "" $p50 $p95 $t50 $t95 $ok $bad ""
  for r in $(seq 1 $REPS); do
    rm -f $TQ/stop-$S; kubectl delete job tqtrain --ignore-not-found --wait=true >/dev/null 2>&1; sleep 3
    python3 scripts/techniques/probe.py $TQ/probe-$S-train$r.csv $TQ/stop-$S & PP=$!
    sampler_start; T0=$(date +%s); mkjob tqtrain $SMOL 4 48 | kubectl apply -f - >/dev/null; wait_jobs 200 tqtrain; T1=$(date +%s); touch $TQ/stop-$S; sampler_stop; wait $PP
    read rt sps smp <<<"$(job_perf tqtrain)"; read gb gm <<<"$(gpu_csv_stats)"
    read ok bad p50 p95 t50 t95 <<<"$(python3 scripts/techniques/stats.py $TQ/probe-$S-train$r.csv $T0 $T1)"
    rs=$(kubectl get pods -l app=tq-serve -o jsonpath='{.items[*].status.containerStatuses[*].restartCount}')
    log "$S serve+train run $r: train $(job_status tqtrain) ${rt}s steps/s $sps | serve ok $ok fail $bad p50 ${p50}s p95 ${p95}s ttft p95 ${t95}s | restarts ${rs:-0} | GPU busy ${gb}% mem ${gm} MiB"
    row $S "$ADV" serve+train $r "server+train" "$(job_status tqtrain)" $rt $sps $smp $gb $gm $p50 $p95 $t50 $t95 $ok $bad "restarts ${rs:-0}"; done
  clean; }

case $S in
  none) solo short; solo long; serving;;
  *)    pair; serving;;
esac
set_sharing none
log "=== setting $S done ==="
