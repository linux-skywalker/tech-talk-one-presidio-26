#!/usr/bin/env python3
"""Turns one run directory into metrics (printed, and written to <run>/metrics.json). Stdlib only."""
import csv, json, os, sys, datetime as dt

run = sys.argv[1]
def ts(s): return dt.datetime.fromisoformat(s.replace("Z", "+00:00")).timestamp()
meta = {}
for l in open(f"{run}/meta.txt"):
    k, *v = l.split(); meta[k] = v
t0 = float(meta["t0"][0]); tend = float(meta["end"][0]); sc, arm, rep = meta["t0"][1:4]
W = {"serve": 3, "trainm": 3, "trains": 1}
subs = {}
for l in open(f"{run}/submits.txt"):
    n, ns, kind, t = l.split(); subs[n] = dict(ns=ns, kind=kind, sub=float(t), team=ns[-1].upper())
objs = []
for ns in ("team-a", "team-b"):
    objs += json.load(open(f"{run}/objects-{ns}.json"))["items"]
pods = [o for o in objs if o["kind"] == "Pod"]
for p in pods:
    lab = p["metadata"]["labels"]; n = lab.get("kq-job") or ("serve" if lab.get("app") == "serve" else None)
    cs = (p["status"].get("containerStatuses") or [{}])[0]; st = cs.get("state", {})
    a = st.get("running") or st.get("terminated") or {}
    p["_n"] = n; p["_start"] = ts(a["startedAt"]) if a.get("startedAt") else None
    p["_end"] = ts(st["terminated"]["finishedAt"]) if st.get("terminated") else None
    p["_fail"] = p["status"].get("phase") == "Failed"
oom = sum(int(l.split()[2]) > 0 for l in open(f"{run}/oom.txt"))
samples = list(csv.DictReader(open(f"{run}/samples.csv")))
samples = [s for s in samples if t0 <= float(s["ts"]) <= tend]
probe = [r for r in csv.DictReader(open(f"{run}/probe.csv")) if t0 <= float(r["ts"]) <= tend]
m = dict(scenario=sc, arm=arm, rep=int(rep), duration_s=round(tend - t0))
jobs = {o["metadata"]["name"]: o for o in objs if o["kind"] == "Job"}
wait = {}; unit_s = {"A": 0.0, "B": 0.0}; done_t = []; failed_jobs = 0
for n, s in subs.items():
    mine = [p for p in pods if p["_n"] == n and p["_start"]]
    first = min((p["_start"] for p in mine), default=None)
    if n == "serve":
        ok = [float(r["ts"]) for r in probe if r["ok"] == "1"]
        wait[n] = round(min(ok) - s["sub"]) if ok else None
    else:
        wait[n] = round(first - s["sub"]) if first else None
        j = jobs.get(n); c = (j or {}).get("status", {})
        if c.get("succeeded"): done_t.append(ts(c["completionTime"]))
        elif any(x.get("type") == "Failed" for x in c.get("conditions", [])): failed_jobs += 1
    for p in mine: unit_s[s["team"]] += W[s["kind"]] * ((p["_end"] or tend) - p["_start"])
m["queue_wait_s"] = wait
tw = [v for k, v in wait.items() if k != "serve" and v is not None]
m["wait_train_median_s"] = sorted(tw)[len(tw) // 2] if tw else None
m["wait_train_max_s"] = max(tw) if tw else None
for team in "AB":
    w = [v for k, v in wait.items() if subs[k]["team"] == team and k != "serve" and v is not None]
    m[f"wait_team_{team}_max_s"] = max(w) if w else None
m["jobs_total"] = len([k for k in subs if k != "serve"]); m["jobs_done"] = len(done_t); m["jobs_failed"] = failed_jobs
m["makespan_s"] = round(max(done_t) - t0) if done_t else None
m["jobs_per_hour"] = round(len(done_t) / (max(done_t) - t0) * 3600, 1) if done_t else 0
m["pods_failed"] = sum(p["_fail"] for p in pods); m["pods_with_oom"] = oom
m["restarts_serve"] = sum((p["status"].get("containerStatuses") or [{}])[0].get("restartCount", 0) for p in pods if p["_n"] == "serve")
try:
    wl = json.load(open(f"{run}/workloads.json"))["items"]
    pre = lambda c: c["type"] in ("Evicted", "Preempted") and (c["status"] == "True" or "Preempted" in c.get("message", ""))
    m["preempted_workloads"] = sorted(w["metadata"]["name"] for w in wl if any(pre(c) for c in w.get("status", {}).get("conditions", [])))
    m["evictions"] = len(m["preempted_workloads"])
except Exception: m["evictions"] = None
if samples:
    u = [float(s["util"]) for s in samples]; mem = [float(s["mem_mib"]) for s in samples]
    m["gpu_util_avg"] = round(sum(u) / len(u)); m["gpu_mem_max_mib"] = round(max(mem))
    m["dcgm_avg_util"] = round(float(meta["dcgm_avg_util"][0])) if meta.get("dcgm_avg_util") and meta["dcgm_avg_util"][0] != "n/a" else None
    m["waiting_job_seconds"] = round(sum(float(s["waiting"]) * 2 for s in samples))
    m["waiting_while_mem_below_9GB_s"] = round(sum(float(s["waiting"]) * 2 for s in samples if float(s["mem_mib"]) < 9000))
    m["waiting_while_util_below_50_s"] = round(sum(float(s["waiting"]) * 2 for s in samples if float(s["util"]) < 50))
tot = unit_s["A"] + unit_s["B"]
m["unit_seconds_A"] = round(unit_s["A"]); m["unit_seconds_B"] = round(unit_s["B"])
m["share_A_pct"] = round(100 * unit_s["A"] / tot) if tot else None
ok = [r for r in probe if r["ok"] == "1"]
def pct(v, q): v = sorted(v); return v[min(len(v) - 1, int(q * len(v)))] if v else None
tt = [float(r["ttft_s"]) for r in ok]; tl = [float(r["total_s"]) for r in ok]
m["probe_ok"] = len(ok); m["probe_err"] = len(probe) - len(ok)
m["ttft_p50_s"] = pct(tt, .5); m["ttft_p95_s"] = pct(tt, .95); m["latency_p95_s"] = pct(tl, .95)
# per-job timeline CSV: submit, admitted (Kueue Workload condition), first start, finish, status
adm = {}
try:
    for w in json.load(open(f"{run}/workloads.json"))["items"]:
        for c in w.get("status", {}).get("conditions", []):
            if c["type"] == "Admitted" and c["status"] == "True": adm[w["metadata"]["name"]] = ts(c["lastTransitionTime"])
except Exception: pass
with open(f"{run}/jobs.csv", "w") as f:
    f.write("scenario,arm,rep,job,team,kind,submit_s,admitted_s,start_s,finish_s,status,wait_to_start_s\n")
    for n, s in sorted(subs.items()):
        if n == "serve": continue
        j = jobs.get(n, {}); c = j.get("status", {})
        a = next((v for k, v in adm.items() if k.startswith(f"job-{n}-")), None)
        mine = [p["_start"] for p in pods if p["_n"] == n and p["_start"]]
        fin = ts(c["completionTime"]) if c.get("completionTime") else None
        st = "ok" if c.get("succeeded") else ("failed" if any(x.get("type") == "Failed" for x in c.get("conditions", [])) else "unfinished")
        r = lambda v: "" if v is None else f"{v - t0:.0f}"
        f.write(f"{sc},{arm},{rep},{n},{s['team']},{s['kind']},{s['sub'] - t0:.0f},{r(a)},{r(min(mine) if mine else None)},{r(fin)},{st},{wait.get(n) if wait.get(n) is not None else ''}\n")
json.dump(m, open(f"{run}/metrics.json", "w"), indent=1)
for k, v in m.items(): print(f"  {k:32s} {v}")
