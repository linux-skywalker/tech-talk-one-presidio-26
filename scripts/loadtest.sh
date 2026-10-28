#!/usr/bin/env bash
# usage: loadtest.sh <port> <model> <seconds> <concurrency>   Sends chat requests in parallel, prints replies/sec and tokens/sec.
PORT=${1:-8000}; MODEL=${2:-Qwen/Qwen2.5-1.5B-Instruct}; SECS=${3:-60}; CONC=${4:-16}
body=$(jq -nc --arg m "$MODEL" '{model:$m,messages:[{role:"user",content:"Write a detailed paragraph about how GPUs work."}],max_tokens:256,temperature:0.7}')
end=$(( $(date +%s) + SECS ))
worker() { n=0; t=0; while [ $(date +%s) -lt $end ]; do r=$(curl -s localhost:$PORT/v1/chat/completions -H 'Content-Type: application/json' -d "$body"); k=$(echo "$r" | jq -r '.usage.completion_tokens // 0'); n=$((n+1)); t=$((t+k)); done; echo "$n $t"; }
for i in $(seq 1 $CONC); do worker & done | awk '{r+=$1;t+=$2}END{printf "requests=%d tokens=%d  %.1f req/s  %.0f tok/s\n",r,t,r/'$SECS',t/'$SECS'}'
