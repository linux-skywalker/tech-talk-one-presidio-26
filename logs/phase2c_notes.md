# Phase 2c: extra WSL2 work (2026-10-19)

## Serving utilization under load, identical test (16 concurrent clients, 60 s, 256 max tokens, base model, vLLM 0.4)
| | Traditional | Kubernetes |
|---|---|---|
| Throughput | 1433 tok/s (5.6 req/s) | 1475 tok/s (5.8 req/s) |
| GPU util avg / peak | 69% / 88% | 69% / 89% |
| Peak memory | 6463 MiB | 6481 MiB |
No meaningful difference: Kubernetes adds no overhead and no speedup. (avg includes a few idle seconds at the edges of the window)

## Monitoring ("Live dashboards")
- kube-prometheus-stack (k8s/monitoring-values.yaml) plus the NVIDIA DCGM dashboard (grafana id 12239, JSON in k8s/dashboards/, imported with scripts/import_dashboard.sh). Grafana NodePort 30300 (admin/admin), up 63 s after helm install.
- The chart's gnetId download did not load the dashboard in this setup, so the JSON is stored in the repo and imported through the Grafana API.
- DCGM exporter default collect interval is 30 s: utilization lagged badly (reported 1% for several seconds under 87% load). Fixed with DCGM_EXPORTER_INTERVAL=1000 (Operator value dcgmExporter.env). After the fix DCGM tracked nvidia-smi (84-88% vs 85-87%).

## Operator rollout timing
helm install to nvidia.com/gpu=1: 23 s with images already cached (includes the manual PCI label). Cold image pulls not measured.

## Incident: GPU disappeared after a WSL restart (real-world failure, about 30 min to fix)
1. WSL restarted, root mount went back to private. Operator pods stuck. Fix: sudo mount --make-rshared /.
2. Old pods stayed Unknown. Restarted pods, then k3s.
3. Toolkit validator failed: nvidia-smi not found. Root cause: my earlier toolkit.enabled=true experiment (2026-10-16) left /usr/local/nvidia/toolkit on the host. k3s searches that path before /usr/bin when it detects the nvidia runtime, and on restart it switched the runtime to the half-installed copy (no working config). Found by reading /var/lib/rancher/k3s/agent/etc/containerd/config.toml.
4. After removing /usr/local/nvidia and restarting k3s, the old pod sandboxes could not be stopped (binary gone). sudo k3s-killall.sh then sudo systemctl start k3s cleared them. GPU allocatable again in 48 s.
Lesson for the talk: a failed Operator toolkit install can leave host files that bite later, and nothing warned about it. Do not run toolkit.enabled=true on a host with a working apt toolkit.

## Dashboard showed no data (2026-10-19), two causes
1. NodePort 30300 is not reachable from the Windows browser on WSL2 (iptables NodePort, no real listener). Fix: kubectl port-forward on 3000.
2. Dashboard 12239 references its datasource by the legacy string "prometheus". The datasource name is "Prometheus" and its uid is "prometheus", so Grafana 13 resolved nothing and every panel was empty, although Prometheus had the data. Fix: rewrite datasource refs as {"type":"prometheus","uid":"prometheus"} (already applied to k8s/dashboards/nvidia-dcgm-12239.json) and re-import.

## Dashboard still empty in the Windows browser (open item, not resolved on WSL2)
Verified: Prometheus scrapes DCGM (target up), a query through Grafana's /api/ds/query returns GPU utilization, datasource refs fixed. Panels were still empty in the browser. Last change: variables `instance` and `gpu` now default to All (allValue ".*"), since `current` was empty and the panel filter could resolve to nothing. Not confirmed visually. Next step on Ubuntu: open the dashboard, click a panel, Inspect > Query, and read the error. Fallback: build a minimal 3-panel dashboard (util, memory, power) with plain Prometheus queries.
