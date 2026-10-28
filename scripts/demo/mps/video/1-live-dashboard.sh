#!/usr/bin/env bash
# Live dashboard for the memory-limit demo: GPU memory and what each of the two pods reports. Redraws in place every 2 s.
# usage: 1-live-dashboard.sh        (leave it running in the top pane)
export KUBECONFIG=${KUBECONFIG:-/etc/rancher/k3s/k3s.yaml}
say() { # plain-English version of a pod's log lines
  sed -E 's/^.*sees free=([0-9.]+) total=([0-9.]+) GiB/Starts: it is told it has \1 of \2 GiB of GPU memory./;
          s/^steady holds 3 GiB/Holds 3 GiB./;
          s/^steady GREW by 2 GiB: OK/Asks for 2 GiB more: GRANTED. It grew to 5 GiB./;
          s/^steady could NOT grow by 2 GiB.*/Asks for 2 GiB more: REFUSED. Out of memory./;
          s/^greedy stopped at ([0-9]+) GiB.*/Grabs memory until it is refused. Stopped at \1 GiB./' | grep -v '^\[W'
}
paint() { sed -E "s/GRANTED/\x1b[1;32m&\x1b[0m/; s/REFUSED/\x1b[1;31m&\x1b[0m/; s/Stopped at [0-9]+ GiB/\x1b[1;33m&\x1b[0m/"; }
status() { kubectl get pod "$1" -o jsonpath='{.status.phase}' 2>/dev/null; }
frame() {
  read -r util mem total < <(nvidia-smi --query-gpu=utilization.gpu,memory.used,memory.total --format=csv,noheader,nounits | tr -d ',')
  mode=$(kubectl get node -l nvidia.com/gpu.present=true -o jsonpath='{.items[0].metadata.labels.nvidia\.com/gpu\.sharing-strategy}' 2>/dev/null)
  case $mode in mps) mode="WITH MPS: Each Pod Gets Its Own Memory Limit";; time-slicing) mode="WITHOUT MPS (Time Slicing): Every Pod Can Use the Whole GPU Memory";; *) mode="none";; esac
  gb=$(( mem * 20 / total )); bar=$(printf '#%.0s' $(seq 1 $gb) 2>/dev/null)$(printf '.%.0s' $(seq 1 $((20-gb))) 2>/dev/null)
  printf '\033[1;36mGPU SHARING\033[0m  \033[1m%s\033[0m\033[K\n\033[K\n' "$mode"
  printf '\033[1;36mGPU MEMORY\033[0m  [\033[1;33m%s\033[0m] %s of %s MiB\033[K\n\033[K\n' "$bar" "$mem" "$total"
  printf '\033[1m%-12s %-11s %s\033[0m\033[K\n' POD STATUS "WHAT IT DOES"
  for p in mem-steady mem-greedy; do
    s=$(status $p); [ -n "$s" ] || continue
    case $s in Running) c="1;32";; Succeeded) c="1;34"; s="Finished OK";; Failed) c="1;31"; s="Crashed";; *) c="1;33";; esac
    case $p in mem-steady) w="Team A, Steady Service: holds 3 GiB, later needs 2 GiB more.";; *) w="Team B, Greedy Job: grabs as much memory as it can.";; esac
    printf '%-12s \033[%sm%-11s\033[0m %s\033[K\n' "$p" "$c" "$s" "$w"
  done
  printf '\033[K\n'
  for p in mem-steady mem-greedy; do
    [ -n "$(status $p)" ] || continue
    printf '\033[1m%s says:\033[0m\033[K\n' "$p"
    kubectl logs $p 2>/dev/null | say | paint | sed 's/^/   /; s/$/\x1b[K/'
  done
  fin() { case $(status $1) in Succeeded|Failed) return 0;; *) return 1;; esac; }
  if fin mem-steady && fin mem-greedy; then
    r=$(kubectl logs mem-steady 2>/dev/null | grep -c "GREW")
    g=$(kubectl logs mem-greedy 2>/dev/null | grep -o 'stopped at [0-9]* GiB' | head -1); g=${g^}
    printf '\033[K\n\033[1;36mRESULT\033[0m\033[K\n'
    [ "$r" = 1 ] && printf 'Steady Service  \033[1;32mKept running and got its extra memory.\033[0m\033[K\n' || printf 'Steady Service  \033[1;31mRan out of memory\033[0m because the greedy pod had taken it.\033[K\n'
    printf 'Greedy Job      \033[1m%s.\033[0m\033[K\n' "${g:-Still grabbing}"
  fi
}
trap 'printf "\033[?25h"' EXIT
printf '\033[2J\033[?25l'
while true; do printf '\033[H'; frame; printf '\033[J'; sleep 2; done
