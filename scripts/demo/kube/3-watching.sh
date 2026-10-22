#!/usr/bin/env bash
# Metric 3 of 6, Kubernetes + NVIDIA: what you can see. Live: one model under light traffic, then GPU, pod, restart and memory metrics
# from Prometheus (DCGM exporter, kube-state-metrics, cAdvisor), including history from before the traffic started.
# usage: bash scripts/demo/kube/3-watching.sh        (about 3 minutes)
source "$(dirname "$0")/../common.sh"
need_idle_kube
step 3 "Watching (Kubernetes + NVIDIA)"
fix "GPU, pod and restart metrics come included and wired to your workloads (DCGM exporter from the GPU Operator, kube-state-metrics, kubelet cAdvisor, Prometheus, Grafana). You could build the same on bare metal; here it is one Helm release plus the Operator."
say "Metric sources running now:"; kubectl get pods -n gpu-operator --no-headers | grep -E "dcgm" | awk '{print "  " $1, $3}'; kubectl get pods -n monitoring --no-headers | grep -E "kube-state|prometheus-monitoring|grafana" | awk '{print "  " $1, $3}'
sed "s/replicas: 6/replicas: 1/" k8s/serve-tiny.yaml | kubectl apply -f - >/dev/null; kubectl apply -f k8s/serve-tiny-ports.yaml >/dev/null
tl_start; for t in $(seq 1 150); do [ "$(kubectl get statefulset serve-tiny -o jsonpath='{.status.readyReplicas}')" = 1 ] && break; sleep 2; done; tl "serve-tiny-0 ready"
say "Light traffic for 30 s..."; CLIENTS=1 PAUSE=0.2 scripts/loadtest-light.sh 30 0 | sed 's/^/  /'
echo "${B}Now, from Prometheus (nothing was running in this terminal)${R}"
printf '  %-46s %s\n' "GPU busy now / last 30 s avg / last 5 min max" "$(promf 'max(DCGM_FI_DEV_GPU_UTIL)')% / $(promf 'avg_over_time(max(DCGM_FI_DEV_GPU_UTIL)[30s:1s])')% / $(promf 'max_over_time(max(DCGM_FI_DEV_GPU_UTIL)[5m:1s])')%"
printf '  %-46s %s\n' "GPU memory used (MiB) / total" "$(promf 'DCGM_FI_DEV_FB_USED') / $(promf 'DCGM_FI_DEV_FB_USED + DCGM_FI_DEV_FB_FREE')"
printf '  %-46s %s\n' "Power (W) / temperature (C)" "$(promf 'DCGM_FI_DEV_POWER_USAGE') / $(promf 'DCGM_FI_DEV_GPU_TEMP')"
printf '  %-46s %s\n' "GPU busy 3 minutes ago (history)" "$(promf 'max(DCGM_FI_DEV_GPU_UTIL offset 3m)')%"
printf '  %-46s %s\n' "Pods Running in default / container restarts" "$(promf 'sum(kube_pod_status_phase{phase="Running",namespace="default"})') / $(promf 'sum(kube_pod_container_status_restarts_total{namespace="default"})')"
printf '  %-46s %s\n' "serve-tiny-0 memory (MiB, cAdvisor)" "$(promf 'sum(container_memory_working_set_bytes{namespace="default",pod="serve-tiny-0",container!=""}) / 1048576')"
printf '  %-46s %s\n' "Metrics resolution" "DCGM exporter every 1 s, Prometheus retention 6 h"
echo "${B}Per-workload view (which GPU pod is which)${R}"; show kubectl get pods -o wide
say "Live dashboards: ${B}http://localhost:30300/d/six-metrics${R} and http://localhost:30300/d/gpu-review  (admin / admin)"
echo "${B}Scoreboard: watching, Kubernetes${R}"
echo "  history:      yes, Prometheus keeps 6 h and can answer for any past moment"
echo "  per workload: pod names, restarts and container memory next to GPU metrics"
echo "  alerts:       Prometheus can alert on any of these (not configured in this demo)"
result "Watching" "live and historical GPU, pod, restart and memory metrics from one place; GPU busy $(promf 'max_over_time(max(DCGM_FI_DEV_GPU_UTIL)[5m:1s])')% peak in the last 5 min"
kubectl delete -f k8s/serve-tiny-ports.yaml -f k8s/serve-tiny.yaml --ignore-not-found --wait=true >/dev/null 2>&1; wait_gpu_free
