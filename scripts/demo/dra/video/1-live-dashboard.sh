#!/usr/bin/env bash
# Live dashboard for the "ask for GPU memory" demo: GPU memory and the three team pods. Redraws in place every 2 s.
# usage: 1-live-dashboard.sh        (leave it running in the top pane)
export KUBECONFIG=${KUBECONFIG:-/etc/rancher/k3s/k3s.yaml}
PODS="team-a-3gib team-b-5gib team-c-6gib"
phase() { kubectl get pod "$1" -o jsonpath='{.status.phase}' 2>/dev/null; }
scheduled() { kubectl get pod "$1" -o jsonpath='{.status.conditions[?(@.type=="PodScheduled")].status}' 2>/dev/null; }
say() { grep -v '^\[W' | sed -E 's/^needs ([0-9]+) GiB/Needs \1 GiB./; s/^got ([0-9]+) GiB/Gets its \1 GiB and works./; s/^OUT OF MEMORY/The GPU is full: OUT OF MEMORY./' \
        | sed -E "s/OUT OF MEMORY/\x1b[1;31m&\x1b[0m/; s/Gets its/\x1b[1;32m&\x1b[0m/"; }
frame() {
  read -r util mem total < <(nvidia-smi --query-gpu=utilization.gpu,memory.used,memory.total --format=csv,noheader,nounits | tr -d ',')
  if kubectl get resourceslices --no-headers 2>/dev/null | grep -q gpu.nvidia.com; then
    mode="WITH DRA: Each Pod Asks for the GPU Memory It Needs"; ask() { echo "$1 GiB of GPU memory"; }
  else
    mode="WITHOUT DRA (Device Plugin): Each Pod Asks for 1 GPU, Not for Memory"; ask() { echo "1 GPU slice (no size)"; }
  fi
  gb=$(( mem * 20 / total )); bar=$(printf '#%.0s' $(seq 1 $gb) 2>/dev/null)$(printf '.%.0s' $(seq 1 $((20-gb))) 2>/dev/null)
  printf '\033[1;36mGPU ACCESS\033[0m  \033[1m%s\033[0m\033[K\n\033[K\n' "$mode"
  printf '\033[1;36mGPU MEMORY\033[0m  [\033[1;33m%s\033[0m] %s of %s MiB\033[K\n\033[K\n' "$bar" "$mem" "$total"
  printf '\033[1m%-14s %-9s %-26s %s\033[0m\033[K\n' POD NEEDS "ASKS KUBERNETES FOR" STATUS
  for p in $PODS; do
    ph=$(phase $p); [ -n "$ph" ] || continue
    n=${p#team-?-}; n=${n%gib}
    case $ph in
      Running) st="\033[1;32mRunning\033[0m";;
      Succeeded) st="\033[1;34mFinished OK\033[0m";;
      Failed) st="\033[1;31mCrashed\033[0m";;
      Pending) if [ "$(scheduled $p)" = False ]; then st="\033[1;33mWaiting: no room on the GPU\033[0m"; else st="\033[1;33mStarting\033[0m"; fi;;
      *) st="$ph";;
    esac
    printf '%-14s %-9s %-26s %b\033[K\n' "$p" "$n GiB" "$(ask $n)" "$st"
  done
  printf '\033[K\n'
  for p in $PODS; do
    [ -n "$(phase $p)" ] || continue
    printf '\033[1m%-14s\033[0m %s\033[K\n' "$p" "$(kubectl logs $p 2>/dev/null | say | paste -sd' ')"
  done
  done_n=0; ok=0; bad=0
  for p in $PODS; do case $(phase $p) in Succeeded) ok=$((ok+1)); done_n=$((done_n+1));; Failed) bad=$((bad+1)); done_n=$((done_n+1));; esac; done
  if [ $done_n = 3 ]; then
    printf '\033[K\n\033[1;36mRESULT\033[0m\033[K\n'
    printf 'Pods that finished OK  \033[1;32m%s of 3\033[0m\033[K\n' "$ok"
    [ $bad = 0 ] && printf 'Pods that crashed      \033[1m0\033[0m\033[K\n' || printf 'Pods that crashed      \033[1;31m%s (the GPU ran out of memory)\033[0m\033[K\n' "$bad"
  fi
}
trap 'printf "\033[?25h"' EXIT
printf '\033[2J\033[?25l'
while true; do printf '\033[H'; frame; printf '\033[J'; sleep 2; done
