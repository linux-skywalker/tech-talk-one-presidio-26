#!/usr/bin/env python3
"""Builds k8s/dashboards/six-metrics.json: the six metrics side by side on one screen (for the demo recording).
Six columns, each Traditional vs Kubernetes + NVIDIA with one headline number, then a thin live strip.
Numbers come from results-ubuntu-4070.md (RTX 4070, native Ubuntu, single runs), same as the review dashboard.
usage: python3 scripts/build_sixmetrics_dashboard.py && bash scripts/import_review_dashboard.sh k8s/dashboards/six-metrics.json
"""
import json, pathlib

PROM = {"type": "prometheus", "uid": "prometheus"}
COLS = [
 ("1 Setting up", "PROVEN", "2 hosts, 0 changed lines",
  "By hand on every machine", "Same Helm install and manifests on WSL2 and native Ubuntu. Operator found the GPU in 33 s."),
 ("2 Watching", "PROVEN", "Live, every 1 s",
  "Check a terminal", "GPU busy, memory, power, pod status and restarts. Up in 53 s. See the live strip below."),
 ("3 Sharing", "PROVEN", "6 cards become 1",
  "One card per model: 6 cards, each about 14% busy at light traffic. Started together by hand: 0 of 6 up.", "6 models on 1 card: 49 to 71% busy at light traffic, 93% at moderate. 6 of 6 ready, 0 restarts. Price: answers 214 to 396 ms instead of 81 ms."),
 ("4 Failures", "PROVEN", "back in ~51 s, no person",
  "Stays dead until a person acts", "Simulated crash: training is back about 51 s after the delete from its last checkpoint, nobody involved. Serving: 77 to 81 s (28 s if a person restarts it by hand). 39 of 40 requests OK during a pod kill."),
 ("5 Growing", "BY DESIGN", "Node joins in ~65 s",
  "Rebuild a machine", "3 CPU-only VMs joined one at a time and got pods automatically. The GPU Operator gave them no GPU parts (no GPU). A GPU node would get them by design. Not tested: one GPU."),
 ("6 Moving", "BY DESIGN", "0 changed lines",
  "Rewrite for each cloud", "Kubernetes is a standard API. The same manifests ran on two different hosts."),
]
ORDER = ["Sharing", "Failures", "Watching", "Moving", "Setting up", "Growing"]
COLS = sorted(COLS, key=lambda c: ORDER.index(c[0][2:]))
panels, pid = [], 0


def nid():
    global pid
    pid += 1
    return pid


for i, (name, status, big, trad, k8s) in enumerate(COLS):
    md = f"### {big}\n\n**Traditional:** {trad}\n\n**Kubernetes + NVIDIA:** {k8s}"
    color = {"PROVEN": "green", "BY DESIGN": "blue", "NOT TESTED": "orange"}[status]
    panels.append({"id": nid(), "type": "text", "title": f"{i + 1} {name[2:]}  |  {status}", "transparent": False,
                   "options": {"mode": "markdown", "content": md},
                   "fieldConfig": {"defaults": {"color": {"mode": "fixed", "fixedColor": color}}, "overrides": []},
                   "gridPos": {"x": i * 4, "y": 0, "w": 4, "h": 11}})


def stat(title, expr, unit, x, thresholds=None):
    panels.append({"id": nid(), "type": "stat", "title": title, "datasource": PROM,
                   "targets": [{"refId": "A", "datasource": PROM, "expr": expr, "instant": True, "range": False}],
                   "fieldConfig": {"defaults": {"unit": unit, "thresholds": {"mode": "absolute", "steps": thresholds or [{"color": "green", "value": None}]}}, "overrides": []},
                   "options": {"colorMode": "value", "graphMode": "area", "reduceOptions": {"calcs": ["lastNotNull"]}},
                   "gridPos": {"x": x, "y": 11, "w": 4, "h": 4}})


stat("GPU busy", "DCGM_FI_DEV_GPU_UTIL", "percent", 0, [{"color": "green", "value": None}, {"color": "orange", "value": 60}, {"color": "red", "value": 90}])
stat("GPU memory used", "DCGM_FI_DEV_FB_USED * 1024 * 1024", "bytes", 4)
stat("Schedulable GPUs", 'sum(kube_node_status_allocatable{resource="nvidia_com_gpu"})', "none", 8)
stat("Pods Running", 'sum(kube_pod_status_phase{phase="Running",namespace="default"}) or vector(0)', "none", 12)
stat("Container restarts", 'sum(kube_pod_container_status_restarts_total{namespace="default"}) or vector(0)', "none", 16)
stat("Power", "DCGM_FI_DEV_POWER_USAGE", "watt", 20)

dash = {"uid": "six-metrics", "title": "Six metrics: traditional vs Kubernetes + NVIDIA", "tags": ["gpu", "demo"], "schemaVersion": 39,
        "refresh": "5s", "time": {"from": "now-15m", "to": "now"}, "timezone": "browser", "panels": panels, "editable": True}
out = pathlib.Path(__file__).resolve().parent.parent / "k8s/dashboards/six-metrics.json"
out.write_text(json.dumps(dash, indent=1))
print("wrote", out)
