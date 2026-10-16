#!/usr/bin/env bash
# usage: gpu_sample.sh <outfile> ; samples util % and mem MiB every 2s until killed
echo "ts,util_pct,mem_mib" > "$1"
while true; do echo "$(date +%s),$(nvidia-smi --query-gpu=utilization.gpu,memory.used --format=csv,noheader,nounits | tr -d ' ')" >> "$1"; sleep 2; done
