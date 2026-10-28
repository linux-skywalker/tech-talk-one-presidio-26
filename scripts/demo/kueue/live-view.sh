#!/usr/bin/env bash
# One coloured frame for screen recording: GPU line and the pods of both teams. Use with: watch -c -n1 scripts/demo/kueue/live-view.sh
export KUBECONFIG=${KUBECONFIG:-/etc/rancher/k3s/k3s.yaml}
read -r util mem total < <(nvidia-smi --query-gpu=utilization.gpu,memory.used,memory.total --format=csv,noheader,nounits | tr -d ',')
c=32; [ "$util" -ge 50 ] && c=33; [ "$util" -ge 85 ] && c=31
printf '\033[1;36mGPU\033[0m  busy \033[1;%sm%s%%\033[0m   memory \033[1;%sm%s / %s MiB\033[0m\n\n' "$c" "$util" "$c" "$mem" "$total"
printf '\033[1m%-8s %-24s %-20s %s\033[0m\n' TEAM POD STATUS RESTARTS
kubectl get pods -A -l kq-kind --no-headers 2>/dev/null | sort | awk '
{ s=$4; col="37"
  if (s=="Running") col="1;32"; else if (s=="Completed") col="1;34"
  else if (s ~ /Pending|SchedulingGated|ContainerCreating|PodInitializing/) col="1;33"
  else if (s ~ /Error|OOMKilled|CrashLoopBackOff|ImagePull|Failed|Evicted|Terminating/) col="1;31"
  printf "%-8s %-24s \033[%sm%-20s\033[0m %s\n", $1, $2, col, s, $5 }'
