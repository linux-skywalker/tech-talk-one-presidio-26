#!/usr/bin/env bash
# usage: [CLIENTS=1] [PAUSE=0.5] loadtest-light.sh <seconds> <ordinal...>   Traffic per serve-tiny pod (NodePort 3009N): CLIENTS clients per pod, each sends a 64-token request then waits PAUSE seconds.
# Defaults are the "light traffic" setting. Prints per-pod requests, mean and p95 latency.
SECS=$1; shift; CLIENTS=${CLIENTS:-1}; PAUSE=${PAUSE:-0.5}
M=HuggingFaceTB/SmolLM2-135M-Instruct; end=$(( $(date +%s) + SECS ))
body=$(jq -nc --arg m "$M" '{model:$m,messages:[{role:"user",content:"Explain in two sentences why the sky is blue."}],max_tokens:64,temperature:0.7}')
one() { for c in $(seq 1 $CLIENTS); do ( while [ $(date +%s) -lt $end ]; do curl -s -o /dev/null -w '%{time_total}\n' localhost:$((30090+$1))/v1/chat/completions -H 'Content-Type: application/json' -d "$body"; sleep $PAUSE; done ) & done | sort -n | awk -v o=$1 '{a[NR]=$1;s+=$1}END{k=int(NR*0.95); if(k<1)k=1; printf "pod %d: %3d requests  mean %4.0f ms  p95 %4.0f ms\n",o,NR,s/NR*1000,a[k]*1000}'; }
for o in "$@"; do one $o & done; wait
