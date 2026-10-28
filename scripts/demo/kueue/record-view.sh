#!/usr/bin/env bash
# One live pane for screen recording: GPU line and the pods of both teams, refreshed every second.
# usage: record-view.sh "No queue"   or   record-view.sh "Kueue"
export KUBECONFIG=${KUBECONFIG:-/etc/rancher/k3s/k3s.yaml}
title=${1:-run}
while true; do
  clear
  printf '\033[1m%s\033[0m   %s\n\n' "$title" "$(date +%T)"
  printf 'GPU   %s\n\n' "$(nvidia-smi --query-gpu=utilization.gpu,memory.used,memory.total --format=csv,noheader | sed 's/,/ |/g')"
  printf '%-8s %-22s %-18s %s\n' TEAM POD STATUS RESTARTS
  kubectl get pods -A -l 'kq-kind' --no-headers 2>/dev/null | awk '{printf "%-8s %-22s %-18s %s\n",$1,$2,$4,$5}' | sort
  sleep 1
done
