# Shared helpers for demo-trad.sh and demo-kube.sh. Sourced, not run.
cd "$(dirname "${BASH_SOURCE[0]}")/../.." || exit 1
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml PATH=$HOME/.local/bin:$PWD/.venv-trad/bin:$PATH
B=$'\e[1m'; D=$'\e[2m'; RED=$'\e[31m'; GRN=$'\e[32m'; YEL=$'\e[33m'; CYN=$'\e[36m'; R=$'\e[0m'
declare -a RESULTS
step()    { echo; echo "${B}${CYN}=== $1. $2 ===${R}"; }
problem() { echo "${RED}PROBLEM:${R} $*"; }
fix()     { echo "${GRN}FIX:${R} $*"; }
say()     { echo "$*"; }
note()    { echo "${D}$*${R}"; }
show()    { echo "${YEL}\$ $*${R}"; "$@"; }
result()  { RESULTS+=("$1|$2"); echo "${B}RESULT:${R} $2"; }
pause()   { [ -n "$AUTO" ] && return; echo; read -r -p "${D}[Enter] next step${R} " _; }
gpu_used_mib() { nvidia-smi --query-gpu=memory.used --format=csv,noheader,nounits; }
gpu_free()     { [ "$(gpu_used_mib)" -lt 1500 ]; }
wait_gpu_free() { for i in $(seq 1 60); do gpu_free && return 0; sleep 2; done; return 1; }
summary() { echo; echo "${B}=== Summary ($1) ===${R}"; for r in "${RESULTS[@]}"; do printf '%-12s %s\n' "${r%%|*}" "${r#*|}"; done; }
