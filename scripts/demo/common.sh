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

# Process helpers that match real python/vllm processes only (pgrep -f also matches shells whose command line merely mentions the name)
procs()     { ps -eo pid=,comm=,args= | awk -v p="$1" '$2 ~ /^(python|python3|vllm|VLLM)/ && $0 ~ p {print $1}'; }
nprocs()    { procs "$1" | wc -l; }
killprocs() { procs "$1" | xargs -r kill -"${2:-TERM}" 2>/dev/null; }

# ---- live data helpers (used by the per-metric scripts in trad/ and kube/) ----
tl_start() { TL0=$(date +%s); }
tl()       { printf '  [%s +%3ss] %s\n' "$(date +%T)" $(( $(date +%s)-${TL0:-$(date +%s)} )) "$*"; }
sampler_start() { SAMPLES=$(mktemp); ( while :; do echo "$(date +%s),$(nvidia-smi --query-gpu=utilization.gpu,memory.used,power.draw,temperature.gpu --format=csv,noheader,nounits | tr -d ' ')" >> "$SAMPLES"; sleep 1; done ) & SAMPLER=$!; SAMPLE_T0=$(date +%s); }
sampler_stop()  { kill "$SAMPLER" 2>/dev/null; wait "$SAMPLER" 2>/dev/null; }
sampler_stats() { # sampler_stats [label]: busy avg/max, memory max, power avg/max, temperature max since sampler_start
  awk -F, -v l="${1:-GPU}" '{n++;u+=$2;if($2>um)um=$2;if($3>mm)mm=$3;p+=$4;if($4>pm)pm=$4;if($5>tm)tm=$5} END{if(n)printf "  %s over %d s: busy avg %.0f%% max %d%%, memory max %d MiB, power avg %.0f W max %.0f W, temp max %d C\n",l,n,u/n,um,mm,p/n,pm,tm}' "$SAMPLES"; }
gpu_now() { nvidia-smi --query-gpu=utilization.gpu,memory.used,power.draw,temperature.gpu --format=csv,noheader | awk -F, '{printf "busy %s, mem%s, power%s, temp%s C",$1,$2,$3,$4}'; }
gpu_util_now() { nvidia-smi --query-gpu=utilization.gpu --format=csv,noheader,nounits; }
prom()  { curl -s -u admin:admin -G "localhost:30300/api/datasources/proxy/uid/prometheus/api/v1/query" --data-urlencode "query=$1" | jq -r '.data.result[0].value[1] // "n/a"'; }
promf() { printf '%.0f' "$(prom "$1" | sed 's/n\/a/0/')"; }
gpu_node_alloc() { kubectl get node -l nvidia.com/gpu.present=true -o jsonpath='{.items[0].status.allocatable.nvidia\.com/gpu}'; }
need_idle_host() { if [ "$(nprocs 'vllm serve')" != 0 ] || [ "$(nprocs 'train[.]py')" != 0 ] || ! gpu_free; then echo "${RED}GPU is busy.${R} Stop other vLLM/training processes and Kubernetes GPU pods first."; exit 1; fi; }
reset_kube() { kubectl delete -f k8s/train-job.yaml -f k8s/serve-tiny.yaml -f k8s/serve-tiny-ports.yaml --ignore-not-found --wait=true >/dev/null 2>&1
  kubectl patch clusterpolicies.nvidia.com/cluster-policy --type json -p '[{"op":"remove","path":"/spec/devicePlugin/config"}]' >/dev/null 2>&1; kubectl delete -f k8s/time-slicing-8.yaml --ignore-not-found >/dev/null 2>&1
  for i in $(seq 1 40); do [ "$(gpu_node_alloc)" = 1 ] && break; sleep 3; done
  for i in $(seq 1 40); do [ "$(kubectl get node -l nvidia.com/gpu.present=true -o jsonpath='{.items[0].metadata.labels.nvidia\.com/gpu\.product}')" = "${GPU_PRODUCT_NAME:-NVIDIA-GeForce-RTX-4070}" ] && break; sleep 3; done
  wait_gpu_free; }
need_idle_kube() { reset_kube; need_idle_host; }
tstep() { tail -c 600 "$1" 2>/dev/null | tr '\r' '\n' | grep -oE '[0-9]+/900' | tail -1 | cut -d/ -f1; }
