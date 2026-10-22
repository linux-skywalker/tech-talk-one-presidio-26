#!/usr/bin/env bash
# Metric 2 of 6, traditional way: a training run dies (simulated with kill -9). Live: training step, GPU while dead, then a person restarts it and we time that too.
# usage: bash scripts/demo/trad/2-failures.sh        (about 4 minutes)
source "$(dirname "$0")/../common.sh"
need_idle_host
step 2 "Failures (traditional)"
problem "A training run dies. We simulate the crash with kill -9. Nothing notices; the GPU sits idle until a person does."
rm -rf outputs/demo_trad; mkdir -p logs; tl_start; sampler_start
EPOCHS=9 python scripts/train.py --out outputs/demo_trad > logs/demo_trad_train.log 2>&1 &
for t in $(seq 1 300); do
  [ $((t % 10)) = 0 ] && tl "training step $(tstep logs/demo_trad_train.log)/900, GPU $(gpu_now)"
  [ -d outputs/demo_trad/checkpoint-75 ] && break; [ "$(nprocs 'train[.]py')" != 0 ] || break; sleep 1; done
STEP=$(tstep logs/demo_trad_train.log); LAST=$(ls outputs/demo_trad | grep checkpoint | sort -t- -k2 -n | tail -1)
tl "checkpoint on disk: $LAST, log at step ${STEP:-?}, GPU $(gpu_now)"
TK=$(date +%s); echo "${YEL}\$ pkill -9 -f train.py${R}"; killprocs 'train[.]py' KILL; sleep 2; tl "training process alive: $(nprocs 'train[.]py')"
for t in 1 2 3 4; do sleep 5; tl "still dead, nobody restarted it. GPU $(gpu_now)"; done
echo "${B}A person finally notices and reruns the command${R}"
T1=$(date +%s); EPOCHS=9 python scripts/train.py --out outputs/demo_trad > logs/demo_trad_resume.log 2>&1 &
RS=""; GS=""; for t in $(seq 1 120); do
  [ -z "$RS" ] && grep -q resume_from_checkpoint logs/demo_trad_resume.log 2>/dev/null && RS=$(( $(date +%s)-T1 ))
  [ -n "$RS" ] && [ "$(gpu_util_now)" -ge 50 ] && { GS=$(( $(date +%s)-T1 )); break; }; sleep 1; done
RES=$(grep -o 'resume_from_checkpoint=[^ ]*' logs/demo_trad_resume.log | tail -1)
tl "resume line after ${RS:-?} s ($RES), GPU busy again after ${GS:-?} s from the rerun"
killprocs 'train[.]py'; sleep 2; sampler_stop; sampler_stats "GPU over the whole test"
IDLE=$(awk -F, -v k="$TK" -v r="$((T1))" '$1>k && $1<r && $2<10{n++} END{print n+0}' "$SAMPLES")
rm -rf outputs/demo_trad; wait_gpu_free
echo "${B}Scoreboard: simulated crash, traditional${R}"
echo "  restarted by itself:        no (checked for $(( T1-TK )) s)"
echo "  GPU idle while dead:        $IDLE s of the $(( T1-TK )) s before a person acted"
echo "  once a person restarts it:  training running again ${GS:-?} s after the command ($RES)"
echo "  not measured here:          how long a person takes to notice; a retry loop would be code you write and maintain"
echo "  serving (measured earlier): stays dead; a person restarting by hand answers in 28 s (warm)"
result "Failures" "killed training stayed dead for $(( T1-TK )) s with the GPU idle $IDLE s; a person's rerun was training again after ${GS:-?} s"
