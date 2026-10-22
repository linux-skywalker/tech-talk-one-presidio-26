#!/usr/bin/env bash
# The six metrics, traditional way (plain Python and vLLM on the host, no Kubernetes). Shows the problem at each step.
# usage: bash scripts/demo/trad.sh        (Enter between steps; AUTO=1 to run straight through). About 5 minutes.
source "$(dirname "$0")/common.sh"
if pgrep -f '[v]llm serve' >/dev/null || pgrep -f '[t]rain.py' >/dev/null || ! gpu_free; then
  echo "${RED}GPU is busy.${R} Stop other vLLM/training processes first (and delete Kubernetes workloads)."; exit 1; fi
rm -rf outputs/demo_trad

step 1 "Sharing"
problem "Several models on one GPU: start them by hand and they fight over memory."
say "Starting 6 copies of the smallest model (SmolLM2-135M) at the same time, each asking for 10% of the GPU..."
PIDS=(); mkdir -p logs
for i in 1 2 3 4 5 6; do
  (MODEL=HuggingFaceTB/SmolLM2-135M-Instruct ADAPTER=/none GPU_UTIL=0.1 PORT=$((8100+i)) scripts/serve.sh > logs/demo_trad_tiny$i.log 2>&1 &)
done
UP=0; for t in $(seq 1 60); do
  UP=0; for i in 1 2 3 4 5 6; do curl -s localhost:$((8100+i))/v1/models | grep -q SmolLM2 && UP=$((UP+1)); done
  ALIVE=$(pgrep -fc '[v]llm serve'); [ "$UP" = 6 ] || [ "$ALIVE" = 0 ] && break; printf '\r  %ss: %s up, %s processes alive ' $((t*2)) $UP $ALIVE; sleep 2; done; echo
say "Servers answering: $UP of 6. Processes still alive: $(pgrep -fc '[v]llm serve')"
grep -h "No available memory" logs/demo_trad_tiny*.log | sed "s/.*ValueError/ValueError/" | cut -c1-110 | sort | uniq -c | head -1
note "Nobody restarts the ones that died. You find out by looking."
pkill -f '[v]llm serve'; wait_gpu_free
echo "${B}Scoreboard: 6 models on 1 GPU, traditional${R}"
echo "  all at once, by hand:        $UP of 6 up   (this run)"
echo "  one at a time, by script:    5 of 6 up in 257 s, the 2nd failed and nothing retried   (measured earlier, results-ubuntu-4070.md)"
echo "  the usual habit, one card per model: 6 models need 6 cards, each about 14% busy at light traffic (one model alone, measured), so about 14% on average"
result "Sharing" "$UP of 6 up all at once; 5 of 6 one at a time (257 s); failed ones are never retried"
pause

step 2 "Failures"
problem "A training run dies (here: kill -9 at a checkpoint). Nothing notices."
EPOCHS=9 python scripts/train.py --out outputs/demo_trad > logs/demo_trad_train.log 2>&1 &
for t in $(seq 1 300); do [ -d outputs/demo_trad/checkpoint-75 ] && break; pgrep -f '[t]rain.py' >/dev/null || break; printf '\r  training... %ss ' $t; sleep 1; done; echo
LAST=$(ls outputs/demo_trad 2>/dev/null | grep checkpoint | sort -t- -k2 -n | tail -1)
show pkill -9 -f '[t]rain.py'; sleep 20
if pgrep -f '[t]rain.py' >/dev/null; then say "training is running again"; else say "${RED}20 s later: no training process. Nothing restarted it.${R} Last checkpoint on disk: $LAST"; fi
note "A person has to notice, log in and rerun the command."
rm -rf outputs/demo_trad; wait_gpu_free
result "Failures" "killed training stayed dead (checkpoint $LAST on disk, nothing restarted it)"
pause

step 3 "Watching"
problem "You see the GPU only if you are at a terminal on that machine, and only right now. No history, no alert."
show nvidia-smi --query-gpu=utilization.gpu,memory.used,temperature.gpu,power.draw --format=csv
note "A moving view means leaving a terminal open: nvidia-smi -l 1. Close it and the history is gone."
for i in 1 2 3; do nvidia-smi --query-gpu=utilization.gpu,memory.used --format=csv,noheader; sleep 1; done
result "Watching" "snapshot in one terminal; nothing stored, nothing alerts"
pause

step 4 "Moving"
problem "The setup is tied to this host: paths, environment and install steps."
show grep -nE 'venv-trad|\.cache/huggingface|localhost|outputs/' scripts/serve.sh scripts/ask.sh scripts/train.py
note "On another host or cloud you redo step 1 and fix whatever differs."
result "Moving" "tied to host paths and install steps; redo setup per host"
pause

step 5 "Setting up"
problem "Every machine is built by hand: driver, CUDA libraries, a Python environment, the model download."
show nvidia-smi --query-gpu=name,driver_version --format=csv,noheader
show python3 --version
say "Python packages pinned by hand for this one box: $(wc -l < scripts/requirements-trad.lock)"
show grep -E '^(torch|vllm|transformers|peft)==' scripts/requirements-trad.lock
say "Plus the model weights in $(du -sh ~/.cache/huggingface 2>/dev/null | cut -f1) of local cache."
result "Setting up" "by hand: driver, CUDA, $(wc -l < scripts/requirements-trad.lock) pinned packages, model cache, repeated on every machine"
pause

step 6 "Growing"
problem "A second machine means doing step 1 again by hand, then copying the adapter and building your own way to send traffic to both."
say "Checklist for machine 2: driver, CUDA, Python env ($(wc -l < scripts/requirements-trad.lock) packages), model cache, adapter files, a load balancer."
note "Not measured here: we have one machine."
result "Growing" "repeat all of step 1 per machine (not measured, one machine)"


summary "traditional"
