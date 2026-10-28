#!/usr/bin/env bash
# Live dashboard for the before/after videos: GPU use and every pod's status. Redraws in place every 2 s without clearing, so it does not flicker.
# usage: 1-live-dashboard.sh        (leave it running in the top pane)
export KUBECONFIG=${KUBECONFIG:-/etc/rancher/k3s/k3s.yaml}
resultfile() { local f; f=$(ls -t "$ROOT"/logs/kueue/s5_*_9/summary.txt 2>/dev/null | head -1); [ -n "$f" ] && [ "$f" -nt "$MARK" ] && ! ps -eo args= | grep -q "[k]ueue/run.sh" && echo "$f"; }
result() { # after a take finishes: the run's own summary, shown under the pods
  local f; f=$(resultfile); [ -n "$f" ] || return 0
  local arm; arm=$(awk '$1=="arm"{print $2}' "$f")
  v() { awk -v k="$1" '$1==k{print $2}' "$f"; }
  printf '\033[K\n\033[1;36mRESULT\033[0m  (%s, this run)\033[K\n' "$arm"
  printf 'jobs finished      \033[1m%s of %s\033[0m\033[K\n' "$(v jobs_done)" "$(v jobs_total)"
  printf 'pods failed        \033[1;31m%s\033[0m  (out of memory: %s)\033[K\n' "$(python3 -c "import json;print(json.load(open('$(dirname "$f")/metrics.json')).get('pods_failed'))")" "$(python3 -c "import json;print(json.load(open('$(dirname "$f")/metrics.json')).get('pods_with_oom'))")"
  m=$(v makespan_s); [ "$m" = None ] && m="no job finished" || m="${m} s"
  printf 'last job done at   \033[1m%s\033[0m\033[K\n' "$m"
  printf 'server reply p95   \033[1m%s s\033[0m\033[K\n' "$(v latency_p95_s)"
}
waiting_jobs() { # workloads Kueue has not admitted yet (no pod exists for them)
  kubectl get workloads.kueue.x-k8s.io -A -o json 2>/dev/null | jq -r '.items[] | select(.status.admission==null) | select(([.status.conditions[]? | select(.type=="Finished" and .status=="True")] | length)==0) | "\(.metadata.namespace) \(.metadata.name)"'
}
frame() {
  read -r util mem total < <(nvidia-smi --query-gpu=utilization.gpu,memory.used,memory.total --format=csv,noheader,nounits | tr -d ',')
  c=32; [ "$util" -ge 50 ] && c=33; [ "$util" -ge 85 ] && c=31
  printf '\033[1;36mGPU\033[0m  busy \033[1;%sm%3s%%\033[0m   memory \033[1;%sm%5s / %s MiB\033[0m\033[K\n\033[K\n' "$c" "$util" "$c" "$mem" "$total"
  printf '\033[1m%-7s %-28s %-8s %-18s %-9s %s\033[0m\033[K\n' TEAM POD READY STATUS RESTARTS "WHAT IT IS"
  local wl; wl=$(waiting_jobs); local nw=0; [ -n "$wl" ] && nw=$(( $(echo "$wl" | wc -l) + 2 ))
  local room=$(( $(tput lines) - 5 - nw )); [ -n "$(resultfile)" ] && room=$(( room - 7 ))
  kubectl get pods -A -l 'app in (kq-train,serve)' --no-headers 2>/dev/null | awk '
  BEGIN { n["serve"]="inference server"
          n["a1"]="training, medium"; n["a2"]="training, small"; n["a3"]="training, medium"
          n["b1"]="training, small";  n["b2"]="training, medium"; n["b3"]="training, small" }
  { split($2, p, "-"); what=(p[1] in n) ? n[p[1]] : ""
    s=$4; col="37"; pr=1
    if (s=="Running") { col="1;32"; pr=0 }
    else if (s=="Completed") col="1;34"
    else if (s ~ /Pending|SchedulingGated|ContainerCreating|PodInitializing/) { col="1;33"; pr=0 }
    else if (s ~ /Error|OOMKilled|CrashLoopBackOff|ImagePull|Failed|Evicted|Terminating/) col="1;31"
    printf "%d\t%s\t%-7s %-28s %-8s \033[%sm%-18s\033[0m %-9s %s\033[K\n", pr, $2, $1, $2, $3, col, s, $5, what }' \
  | sort -t$'\t' -k1,1n -k2,2 > "$TMPF"
  total=$(wc -l < "$TMPF")
  head -n "$room" "$TMPF" | sort -t$'\t' -k2,2 | cut -f3-
  [ "$total" -gt "$room" ] && printf '\033[2m... %d older crashed pods not shown\033[0m\033[K\n' $(( total - room ))
  if [ -n "$wl" ]; then
    printf '\033[K\n\033[1;33mWAITING IN KUEUE'"'"'S QUEUE\033[0m (not started, no pod yet)\033[K\n'
    echo "$wl" | awk '
    BEGIN { n["a1"]="training, medium"; n["a2"]="training, small"; n["a3"]="training, medium"
            n["b1"]="training, small";  n["b2"]="training, medium"; n["b3"]="training, small" }
    { split($2, p, "-"); k=p[2]; what=(k in n) ? n[k] : $2
      printf "%-7s %-28s \033[1;33m%-18s\033[0m %s\033[K\n", $1, $2, "Waiting for room", what }'
  fi
  result
}
ROOT="$(cd "$(dirname "$0")/../../../.." && pwd)"; MARK=$(mktemp); TMPF=$(mktemp); trap 'rm -f "$MARK" "$TMPF"; printf "\033[?25h"' EXIT
printf '\033[?25l'; clear
while true; do printf '\033[H'; frame; printf '\033[J'; sleep 5; done
