#!/usr/bin/env bash
# Live dashboard for the before/after videos: GPU use and every pod's status. Redraws in place every 2 s without clearing, so it does not flicker.
# usage: 1-live-dashboard.sh        (leave it running in the top pane)
export KUBECONFIG=${KUBECONFIG:-/etc/rancher/k3s/k3s.yaml}
result() { # after a take finishes: the run's own summary, shown under the pods
  local f; f=$(ls -t "$ROOT"/logs/kueue/s5_*_9/summary.txt 2>/dev/null | head -1)
  [ -n "$f" ] && [ "$f" -nt "$MARK" ] || return 0
  local arm; arm=$(awk '$1=="arm"{print $2}' "$f")
  v() { awk -v k="$1" '$1==k{print $2}' "$f"; }
  printf '\033[K\n\033[1;36mRESULT\033[0m  (%s, this run)\033[K\n' "$arm"
  printf 'jobs finished      \033[1m%s of %s\033[0m\033[K\n' "$(v jobs_done)" "$(v jobs_total)"
  printf 'pods failed        \033[1;31m%s\033[0m  (out of memory: %s)\033[K\n' "$(python3 -c "import json;print(json.load(open('$(dirname "$f")/metrics.json')).get('pods_failed'))")" "$(python3 -c "import json;print(json.load(open('$(dirname "$f")/metrics.json')).get('pods_with_oom'))")"
  m=$(v makespan_s); [ "$m" = None ] && m="no job finished" || m="${m} s"
  printf 'last job done at   \033[1m%s\033[0m\033[K\n' "$m"
  printf 'server reply p95   \033[1m%s s\033[0m\033[K\n' "$(v latency_p95_s)"
}
frame() {
  read -r util mem total < <(nvidia-smi --query-gpu=utilization.gpu,memory.used,memory.total --format=csv,noheader,nounits | tr -d ',')
  c=32; [ "$util" -ge 50 ] && c=33; [ "$util" -ge 85 ] && c=31
  printf '\033[1;36mGPU\033[0m  busy \033[1;%sm%3s%%\033[0m   memory \033[1;%sm%5s / %s MiB\033[0m\033[K\n\033[K\n' "$c" "$util" "$c" "$mem" "$total"
  printf '\033[1m%-8s %-26s %-20s %s\033[0m\033[K\n' TEAM POD STATUS RESTARTS
  kubectl get pods -A -l kq-kind --no-headers 2>/dev/null | sort | awk '
  { s=$4; col="37"
    if (s=="Running") col="1;32"; else if (s=="Completed") col="1;34"
    else if (s ~ /Pending|SchedulingGated|ContainerCreating|PodInitializing/) col="1;33"
    else if (s ~ /Error|OOMKilled|CrashLoopBackOff|ImagePull|Failed|Evicted|Terminating/) col="1;31"
    printf "%-8s %-26s \033[%sm%-20s\033[0m %s\033[K\n", $1, $2, col, s, $5 }'
  result
}
ROOT="$(cd "$(dirname "$0")/../../../.." && pwd)"; MARK=$(mktemp); trap 'rm -f "$MARK"; printf "\033[?25h"' EXIT
printf '\033[?25l'; clear
while true; do printf '\033[H'; frame; printf '\033[J'; sleep 2; done
