#!/usr/bin/env bash
# Metric 1 of 6, traditional way: put 6 models on one GPU by hand. Live: servers up, processes alive, GPU memory, per-process memory, why they died.
# usage: bash scripts/demo/trad/1-sharing.sh        (SEQ=1 also runs the one-at-a-time start, about 5 more minutes)
source "$(dirname "$0")/../common.sh"
need_idle_host
step 1 "Sharing (traditional)"
TOTAL=$(nvidia-smi --query-gpu=memory.total --format=csv,noheader,nounits)
problem "Several models on one GPU. Start them by hand and they fight over memory; nothing retries the ones that die."
say "GPU: $(nvidia-smi --query-gpu=name --format=csv,noheader), ${TOTAL} MiB. Each tiny server asks for 10% (about $((TOTAL/10)) MiB), so 6 should need about $((TOTAL*6/10)) MiB and fit."
say "Starting 6 copies of SmolLM2-135M at the same time, one command each..."
mkdir -p logs; rm -f logs/demo_trad_tiny*.log; tl_start; sampler_start
for i in 1 2 3 4 5 6; do
  (MODEL=HuggingFaceTB/SmolLM2-135M-Instruct ADAPTER=/none GPU_UTIL=0.1 PORT=$((8100+i)) scripts/serve.sh > logs/demo_trad_tiny$i.log 2>&1 &)
done
UP=0; for t in $(seq 1 60); do
  UP=0; for i in 1 2 3 4 5 6; do curl -s -m 2 localhost:$((8100+i))/v1/models | grep -q SmolLM2 && UP=$((UP+1)); done
  ALIVE=$(nprocs 'vllm serve'); [ $((t % 5)) = 0 ] && tl "$UP up, $ALIVE processes alive, GPU memory $(gpu_used_mib) MiB"
  { [ "$UP" = 6 ] || [ "$ALIVE" = 0 ]; } && break; sleep 2; done
sampler_stop; tl "finished: $UP of 6 answering, $(nprocs 'vllm serve') processes alive"
echo "${B}What happened to each${R}"
for i in 1 2 3 4 5 6; do
  if curl -s -m 2 localhost:$((8100+i))/v1/models | grep -q SmolLM2; then echo "  server $i: up"; else
    echo "  server $i: DEAD  $(grep -h -o 'No available memory for the cache blocks\|CUDA out of memory\|Engine core initialization failed' logs/demo_trad_tiny$i.log | head -1)"; fi; done
nvidia-smi --query-compute-apps=pid,used_memory --format=csv,noheader 2>/dev/null | sed 's/^/  GPU process: /' | head -8
sampler_stats "GPU during the attempt"
note "Error shown above comes from vLLM's startup memory check. Likely cause (not proven): servers that start together see each other's allocations as 'used' and miscount free memory."
if [ -n "$SEQ" ]; then
  killprocs 'vllm serve'; wait_gpu_free; say "Now one at a time, by script, with no retry..."; tl_start; SU=0
  for i in 1 2 3 4 5 6; do
    (MODEL=HuggingFaceTB/SmolLM2-135M-Instruct ADAPTER=/none GPU_UTIL=0.1 PORT=$((8100+i)) scripts/serve.sh > logs/demo_trad_tiny$i.log 2>&1 &)
    for t in $(seq 1 60); do curl -s -m 2 localhost:$((8100+i))/v1/models | grep -q SmolLM2 && { SU=$((SU+1)); tl "server $i up"; break; }; sleep 2; done
    curl -s -m 2 localhost:$((8100+i))/v1/models | grep -q SmolLM2 || tl "server $i did NOT come up in 120 s"; done
  SEQLINE="$SU of 6 up one at a time (this run)"
else SEQLINE="5 of 6 up in 257 s, the 2nd failed and nothing retried (measured earlier, results-ubuntu-4070.md)"; fi
killprocs 'vllm serve'; wait_gpu_free
echo "${B}Scoreboard: 6 models on 1 GPU, traditional${R}"
echo "  one at a time, by script:  $SEQLINE"
echo "  all at once, by hand:      $UP of 6 up   (the naive attempt)"
echo "  one card per model:        6 models need 6 cards, each about 14% busy at light traffic (measured alone)"
echo "  retry on failure:          none; you find out by looking"
result "Sharing" "$UP of 6 up all at once; $SEQLINE; nothing retries failures"
