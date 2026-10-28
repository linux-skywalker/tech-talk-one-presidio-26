#!/usr/bin/env bash
# One-screen recording view: runs the 6-job workload and shows GPU, pods and the run's own log on one screen.
# usage: record.sh plain|kueue [run-number]   (run number 9 keeps it apart from the measured runs 1 to 3)
cd "$(dirname "$0")/../../.."
export KUBECONFIG=${KUBECONFIG:-/etc/rancher/k3s/k3s.yaml}
arm=${1:?usage: record.sh plain|kueue [run]}; rep=${2:-9}
case $arm in plain) title="NO QUEUE";; kueue) title="WITH KUEUE";; *) echo "arm: plain or kueue"; exit 1;; esac
log=logs/kueue/run_s5_${arm}_${rep}.log
bash scripts/demo/kueue/run.sh s5 $arm $rep > "$log" 2>&1 &
pid=$!
start=$(date +%s)
frame() {
  printf '\033[1m%s\033[0m   %ss\n\n' "$title" "$(( $(date +%s) - start ))"
  printf 'GPU   %s\n\n' "$(nvidia-smi --query-gpu=utilization.gpu,memory.used,memory.total --format=csv,noheader | sed 's/,/ |/g')"
  printf '%-8s %-24s %-18s %s\n' TEAM POD STATUS RESTARTS
  kubectl get pods -A -l kq-kind --no-headers 2>/dev/null | awk '{printf "%-8s %-24s %-18s %s\n",$1,$2,$4,$5}' | sort
  printf '\n'; grep -E 'submitted|jobs done|finished|admitted|preempt' "$log" | tail -6 | cut -c1-110
}
while kill -0 $pid 2>/dev/null; do clear; frame; sleep 1; done
clear; frame; printf '\n\033[1mDONE\033[0m\n'; grep -E 'jobs_done|makespan_s|pods_failed|pods_with_oom|dcgm_avg_util' logs/kueue/s5_${arm}_${rep}/summary.txt 2>/dev/null
sleep 20
