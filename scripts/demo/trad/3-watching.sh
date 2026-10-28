#!/usr/bin/env bash
# Metric 3 of 6, traditional way: what you can see. Live: a tiny model under light traffic, watched through nvidia-smi only.
# usage: bash scripts/demo/trad/3-watching.sh        (about 2 minutes)
source "$(dirname "$0")/../common.sh"
need_idle_host
step 3 "Watching (traditional)"
problem "You can see the GPU only from a terminal on that machine, only right now. No history, no alert, no link to who is using it."
say "Starting one tiny model and sending light traffic so there is something to watch..."
(MODEL=HuggingFaceTB/SmolLM2-135M-Instruct ADAPTER=/none GPU_UTIL=0.1 PORT=8101 scripts/serve.sh > logs/demo_trad_watch.log 2>&1 &)
tl_start; for t in $(seq 1 60); do curl -s -m 2 localhost:8101/v1/models | grep -q SmolLM2 && break; sleep 2; done; tl "server up"
body='{"model":"HuggingFaceTB/SmolLM2-135M-Instruct","messages":[{"role":"user","content":"Explain in two sentences why the sky is blue."}],"max_tokens":64}'
( end=$(( $(date +%s)+15 )); while [ $(date +%s) -lt $end ]; do curl -s -o /dev/null localhost:8101/v1/chat/completions -H 'Content-Type: application/json' -d "$body"; sleep 0.2; done ) &
show nvidia-smi --query-gpu=timestamp,utilization.gpu,memory.used,power.draw,temperature.gpu,clocks.sm --format=csv
echo "${B}The only live view: nvidia-smi sampled every second${R}"
nvidia-smi --query-gpu=timestamp,utilization.gpu,memory.used,power.draw,temperature.gpu --format=csv,noheader -l 1 & SM=$!; sleep 8; kill $SM 2>/dev/null; wait; 
show nvidia-smi --query-compute-apps=pid,process_name,used_memory --format=csv
say "Which workload is that? $(ps -o pid=,args= -p $(nvidia-smi --query-compute-apps=pid --format=csv,noheader | head -1 | tr -d ' ') 2>/dev/null | cut -c1-90)"
echo "${B}Now ask: what was the GPU doing 10 seconds ago?${R}"
say "nvidia-smi answers only: $(gpu_now)"
note "No history, no per-pod view, no restart counts, no alert. Kept only if you leave a terminal logging, and that log is yours to build."
killprocs 'vllm serve'; wait_gpu_free
result "Watching" "live view only, one terminal, one machine: no history, no alerts, no per-workload view"
