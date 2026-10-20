#!/usr/bin/env python3
"""Builds k8s/dashboards/project-review.json: one Grafana dashboard that is both the live view and the written report.
Live panels read Prometheus (DCGM exporter, kube-state-metrics, kubelet). Measured results are static tables and bars
(Grafana's built-in TestData CSV source) and every number comes from results-ubuntu-4070.md (RTX 4070, native Ubuntu, single runs).
usage: python3 scripts/build_review_dashboard.py && bash scripts/import_review_dashboard.sh
"""
import json, pathlib

PROM = {"type": "prometheus", "uid": "prometheus"}
TD = {"type": "grafana-testdata-datasource", "uid": "testdata"}
panels, pid, y = [], 0, 0


def nid():
    global pid
    pid += 1
    return pid


def csv_target(csv):
    return {"refId": "A", "datasource": TD, "scenarioId": "csv_content", "csvContent": csv}


def prom_target(expr, legend="", instant=False):
    return {"refId": "A", "datasource": PROM, "expr": expr, "legendFormat": legend, "instant": instant, "range": not instant}


def add(p, x, w, h):
    global y
    p.update({"id": nid(), "gridPos": {"x": x, "y": y, "w": w, "h": h}})
    panels.append(p)


def row(title):
    global y
    panels.append({"id": nid(), "type": "row", "title": title, "collapsed": False, "gridPos": {"x": 0, "y": y, "w": 24, "h": 1}, "panels": []})
    y += 1


def text(title, md, x, w, h):
    add({"type": "text", "title": title, "options": {"mode": "markdown", "content": md}}, x, w, h)


def stat(title, expr, unit, x, w=4, h=4, thresholds=None, decimals=None):
    d = {"unit": unit, "thresholds": {"mode": "absolute", "steps": thresholds or [{"color": "green", "value": None}]}}
    if decimals is not None:
        d["decimals"] = decimals
    add({"type": "stat", "title": title, "datasource": PROM, "targets": [prom_target(expr, instant=True)],
         "fieldConfig": {"defaults": d, "overrides": []},
         "options": {"colorMode": "value", "graphMode": "area", "reduceOptions": {"calcs": ["lastNotNull"]}}}, x, w, h)


def ts(title, targets, unit, x, w, h, ymax=None, ymin=0):
    d = {"unit": unit, "min": ymin, "custom": {"lineWidth": 2, "fillOpacity": 12}}
    if ymax is not None:
        d["max"] = ymax
    add({"type": "timeseries", "title": title, "datasource": PROM, "targets": targets,
         "fieldConfig": {"defaults": d, "overrides": []}, "options": {"legend": {"displayMode": "list", "placement": "bottom"}}}, x, w, h)


def table(title, csv, x, w, h):
    add({"type": "table", "title": title, "datasource": TD, "targets": [csv_target(csv)],
         "fieldConfig": {"defaults": {"custom": {"align": "left", "wrapText": True, "cellOptions": {"type": "auto"}}}, "overrides": []},
         "options": {"showHeader": True, "cellHeight": "md"}}, x, w, h)


def bars(title, csv, unit, x, w, h):
    add({"type": "barchart", "title": title, "datasource": TD, "targets": [csv_target(csv)],
         "fieldConfig": {"defaults": {"unit": unit, "min": 0, "color": {"mode": "palette-classic"}, "custom": {"fillOpacity": 85}}, "overrides": []},
         "options": {"orientation": "horizontal", "showValue": "always", "xTickLabelRotation": 0, "legend": {"showLegend": False}, "barWidth": 0.7}}, x, w, h)


# ---------------------------------------------------------------- report
text("Review: Kubernetes + NVIDIA for GPU workloads", """
**Goal.** Show that Kubernetes with NVIDIA's GPU Operator makes GPU work easier to run than the traditional manual way: same model (Qwen2.5-1.5B-Instruct, LoRA fine-tune, served with vLLM), done twice.

**Machine.** One RTX 4070 (12 GB), native Ubuntu 24.04, driver 590.48.01, k3s, GPU Operator v26.7.2. All numbers below are **single runs on this machine**.

**What we proved**
- **Self-healing:** a killed training job stays dead on the manual path; on Kubernetes it is training again in about 51 s with nobody involved. A killed server is back and answering in 77 to 81 s.
- **Sharing:** one GPU, six models. GPU busy 10 to 14% alone, 68% shared. Latency about 2x higher, all six still answer under 0.4 s.
- **Visibility:** live GPU and pod metrics (this dashboard) come with the stack.
- **No penalty:** speed and GPU utilization are the same as the manual way.

**What we did not prove:** Kubernetes is not faster, and the first-time setup took about twice as long (images). Growing (more nodes) and Moving (another cloud) were not tested. MIG is covered in theory only.
""", 0, 24, 9)

SIX = [
 ("Setting up", "By hand on every machine", "Set once, applied everywhere",
  "First time: 13.3 min by hand vs 27.8 min on Kubernetes (14 min of it image builds). Operator found the GPU in 33 s with no workarounds on native Ubuntu (WSL2 needed 3). One script (scripts/bootstrap.sh) sets up another Ubuntu box; only re-run on this machine was tested. The Operator did not install the driver or toolkit here.", "Partly"),
 ("Watching", "Check a terminal", "Live dashboards",
  "DCGM exporter, Prometheus and Grafana came up in 53 s: live GPU busy, memory, power, temperature, pod status and restarts (this dashboard). Metrics every 1 s. Panels confirmed showing live data.", "Proven"),
 ("Sharing", "One job blocks the GPU", "Jobs share it",
  "Default scheduler: second pod stays Pending. Time slicing: scheduled in 9 s; six tiny models ran on one card, GPU busy 10 to 14% alone vs 68% shared, answers about 2x slower (still under 0.4 s). MPS added per-pod memory limits. Limits: time slicing has no memory isolation (a second training job crashed twice); under heavy load six copies gave 5x less total throughput. MIG: theory only.", "Proven"),
 ("Failures", "Someone gets a message", "It restarts itself",
  "Training killed: by hand it stays dead (finished by a person in 325 s); on Kubernetes training again in about 51 s from its last checkpoint. Serving killed: by hand stays dead; on Kubernetes answering again in 77 to 81 s. A tiny-model pod: 72 s. Repeated in two full rehearsals (28 of 28 checks each).", "Proven"),
 ("Growing", "Rebuild a machine", "Add a machine",
  "Not tested. We only had one node. Nothing here is measured.", "Not tested"),
 ("Moving", "Rewrite for each cloud", "Same setup runs anywhere",
  "The same manifests ran unchanged on two different hosts (WSL2 and native Ubuntu): 0 changed lines in 4 files. An EKS version is prepared (2 to 6 lines differ per file) but never ran: no on-demand GPU capacity on AWS. Another cloud: not tested.", "Partly"),
]
def cell(v):
    return str(v).replace(",", "").replace("\n", " ")  # TestData CSV is comma separated, so cells cannot contain commas


rows = "\n".join(",".join(cell(c) for c in r) for r in SIX)
y += 0
table("The six metrics: traditional vs Kubernetes + NVIDIA", "Metric,Traditional,Kubernetes + NVIDIA,What we measured,Status\n" + rows, 0, 24, 15)
y += 15

# ---------------------------------------------------------------- live GPU
y += 9
row("Live GPU (NVIDIA DCGM exporter)")
stat("GPU busy", "DCGM_FI_DEV_GPU_UTIL", "percent", 0, thresholds=[{"color": "green", "value": None}, {"color": "orange", "value": 60}, {"color": "red", "value": 90}])
stat("GPU memory used", "DCGM_FI_DEV_FB_USED * 1024 * 1024", "bytes", 4)
stat("Power", "DCGM_FI_DEV_POWER_USAGE", "watt", 8, decimals=0)
stat("Temperature", "DCGM_FI_DEV_GPU_TEMP", "celsius", 12, thresholds=[{"color": "green", "value": None}, {"color": "orange", "value": 75}, {"color": "red", "value": 85}])
stat("Schedulable GPUs", 'sum(kube_node_status_allocatable{resource="nvidia_com_gpu"})', "none", 16)
stat("GPU pods Running", 'sum(kube_pod_status_phase{phase="Running",namespace="default"}) or vector(0)', "none", 20)
y += 4
ts("GPU busy %", [prom_target("DCGM_FI_DEV_GPU_UTIL", "GPU busy")], "percent", 0, 12, 8, ymax=100)
ts("GPU memory used", [prom_target("DCGM_FI_DEV_FB_USED * 1024 * 1024", "used"), prom_target("(DCGM_FI_DEV_FB_USED + DCGM_FI_DEV_FB_FREE) * 1024 * 1024", "total")], "bytes", 12, 12, 8)
y += 8

# ---------------------------------------------------------------- k8s behavior
row("Kubernetes behavior (kube-state-metrics and kubelet)")
ts("Pods Running in the default namespace, by app", [prom_target('count by (pod) (kube_pod_status_phase{phase="Running",namespace="default"} == 1)', "{{pod}}")], "none", 0, 8, 8, ymin=0)
ts("Container restarts (self-healing at work)", [prom_target('sum by (pod) (kube_pod_container_status_restarts_total{namespace="default"})', "{{pod}}")], "none", 8, 8, 8)
ts("Container memory (default namespace)", [prom_target('sum by (pod) (container_memory_working_set_bytes{namespace="default",container!=""})', "{{pod}}")], "bytes", 16, 8, 8)
y += 8

# ---------------------------------------------------------------- measured results
row("Measured results (RTX 4070, native Ubuntu, single runs)")
table("Failure: what happens when it is killed", """Event,Traditional (by hand),Kubernetes
Training process killed at step 362,Stays dead. A person restarts it. Resume to done 325 s,Replacement pod training again in about 51 s. No person
Serving process killed,Stays dead until restarted. Manual restart answered in 28 s (warm),Pod replaced and answering in 77 to 81 s. No person
Time slicing: second training job,n/a,Crashed twice with CUDA out of memory (no memory isolation)""", 0, 12, 7)
table("Sharing one GPU", """Setup,Memory per pod,Result
Default scheduler,1 GPU,Second pod stays Pending (Insufficient nvidia.com/gpu)
Time slicing x8,No limit (each sees 10.8 GiB),6 models running; steady pod could not grow (OutOfMemory)
MPS 2 replicas,Limit set per pod (5.9 of 11.6 GiB),Greedy pod stopped at 5 GiB; steady pod grew 3 to 5 GiB
MIG,Hardware partitions (NVIDIA docs),Not tested: RTX 4070 has no MIG; covered in theory""", 12, 12, 7)
table("Full rehearsal, 20 Oct 2026: 28 of 28 checks passed in 1448 s (earlier run 28 of 28, 1441 s)", """Step,This run,Earlier run
Training killed at step 362 (last checkpoint 350),12 steps lost; nothing restarted it,same
Manual resume to done,337 s,341 s
vLLM start to ready,34 s,44 s
Kubernetes training pod Running after apply,7 s,7 s
Training pod deleted to replacement Running,31 s (resumed from checkpoint-150),32 s
Serve Deployment apply to answering,79 s,78 s
Serve pod deleted to answering,77 s,77 s""", 0, 24, 8)
y += 8
y += 7
bars("GPU busy, equal measurement window (percent)", "Path,Percent\nTraditional,90.5\nKubernetes,89.1", "percent", 0, 6, 7)
bars("Serving throughput (tokens per second)", "Path,Tokens per second\nTraditional,1774\nKubernetes,1773", "none", 6, 6, 7)
bars("First-time setup (minutes, sudo install excluded)", "Path,Minutes\nTraditional,13.3\nKubernetes,27.8", "m", 12, 6, 7)
bars("Fine-tune run time (seconds)", "Path,Seconds\nTraditional,529\nKubernetes,529", "s", 18, 6, 7)
y += 7
bars("6 copies of a tiny model: GPU busy, light traffic (percent)", "Setup,Percent\n1 copy alone (10 to 14),12\n6 copies sharing,68", "percent", 0, 8, 7)
bars("Same traffic: mean answer time (ms)", "Setup,Milliseconds\n1 copy alone,85\n6 copies sharing,188", "ms", 8, 8, 7)
bars("Heavy load: total tokens per second", "Setup,Tokens per second\n1 copy,12814\n6 copies sharing,2474", "none", 16, 8, 7)
y += 7
text("Honest notes", """
- **Light traffic result:** sharing raised GPU busy from about 12% to 68% and doubled latency (85 ms to 177-197 ms mean, p95 99 ms to about 330 ms). Mean shown is the average of the six pods.
- **Heavy load result:** six copies delivered about 5x less total throughput than one copy, because one tiny server already fills the card. Sharing helps when many models each get light traffic, not when one model is saturated.
- **Equal speed:** utilization, throughput and training time did not differ between the two paths. Do not read the first-time setup bar as a Kubernetes win: it is the one-time cost.
- **Recovery times** are from pod logs and polling (about +/- 3 s). Not tested: Growing, Moving, MIG, the Operator installing the driver or toolkit.
- Source: `results-ubuntu-4070.md` in the repo, branch `ubuntu-4070`.
""", 0, 24, 6)
y += 6

dash = {
    "uid": "gpu-review", "title": "GPU on Kubernetes: Project Review", "tags": ["gpu", "review"], "timezone": "browser",
    "schemaVersion": 41, "version": 1, "refresh": "5s", "time": {"from": "now-15m", "to": "now"},
    "editable": True, "panels": panels, "templating": {"list": []}, "annotations": {"list": []},
}
out = pathlib.Path(__file__).resolve().parent.parent / "k8s" / "dashboards" / "project-review.json"
out.write_text(json.dumps(dash, indent=1))
print(f"wrote {out} with {len(panels)} panels")
