#!/usr/bin/env python3
"""Builds reports/review-report.html: one standalone page (inline CSS and SVG, works offline) with the rehearsal result and our measured numbers.
usage: python3 scripts/build_review_report.py [current_rehearsal_log] [previous_rehearsal_log]
Defaults: logs/rehearsal_ubuntu_run2.log (this run) and logs/rehearsal_ubuntu.log (earlier run, 28 of 28).
All measured numbers are single runs on the RTX 4070 / native Ubuntu machine and come from results-ubuntu-4070.md.
"""
import html, pathlib, re, sys, datetime

root = pathlib.Path(__file__).resolve().parent.parent
cur_path = pathlib.Path(sys.argv[1]) if len(sys.argv) > 1 else root / "logs" / "rehearsal_ubuntu_run2.log"
prev_path = pathlib.Path(sys.argv[2]) if len(sys.argv) > 2 else root / "logs" / "rehearsal_ubuntu.log"
e = html.escape


def parse(path):
    """Returns (rows, total_seconds, pass, fail). rows = [(status, text, [notes])]"""
    if not path.exists():
        return [], None, 0, 0
    txt = path.read_text(errors="replace")
    if "SUMMARY" not in txt:
        return [], None, 0, 0
    block = txt.split("SUMMARY", 1)[1]
    total = re.search(r"total (\d+) s", txt)
    rows = []
    for ln in block.splitlines()[1:]:
        if ln.startswith("PASS=") or not ln.strip():
            continue
        if ln.startswith(("PASS  ", "FAIL  ")):
            rows.append([ln[:4], ln[6:].strip(), []])
        elif ln.startswith("      ") and rows:
            rows[-1][2].append(ln.strip())
    m = re.search(r"PASS=(\d+) FAIL=(\d+)", block)
    return rows, int(total.group(1)) if total else None, int(m.group(1)) if m else 0, int(m.group(2)) if m else 0


cur, cur_total, cp, cf = parse(cur_path)
prev, prev_total, pp, pf = parse(prev_path)
pmap = {r[1]: r for r in prev}


def bars(title, unit, data, note=""):
    """data = [(label, value)] -> inline SVG horizontal bars"""
    mx = max(v for _, v in data) or 1
    h = 34 * len(data) + 8
    out = [f'<figure><figcaption>{e(title)}</figcaption><svg viewBox="0 0 560 {h}" role="img" aria-label="{e(title)}">']
    for i, (lab, v) in enumerate(data):
        y = 4 + 34 * i
        w = max(2, 330 * v / mx)
        out.append(f'<text x="0" y="{y+20}" class="lab">{e(lab)}</text><rect x="190" y="{y+4}" width="{w:.0f}" height="22" rx="3" class="bar b{i%2}"/>'
                   f'<text x="{196+w:.0f}" y="{y+20}" class="val">{v:g} {e(unit)}</text>')
    out.append("</svg>" + (f"<p class='note'>{e(note)}</p>" if note else "") + "</figure>")
    return "".join(out)


def table(head, rows, cls=""):
    t = [f"<table class='{cls}'><thead><tr>" + "".join(f"<th>{e(h)}</th>" for h in head) + "</tr></thead><tbody>"]
    for r in rows:
        t.append("<tr>" + "".join(f"<td>{c}</td>" for c in r) + "</tr>")
    t.append("</tbody></table>")
    return "".join(t)


def status(s):
    c = {"Proven": "ok", "Partly": "part", "Not tested": "nt"}[s]
    return f'<span class="badge {c}" style="min-width:5.5em">{s}</span>'


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


def badge(s):
    return f'<span class="badge {"ok" if s == "PASS" else "no"}">{s}</span>'


# rehearsal table: checks, with timing notes on the line under each
check_rows, timing_rows = [], []
for s, d, notes in cur:
    p = pmap.get(d)
    check_rows.append([badge(s), e(d), badge(p[0]) if p else "<span class='dim'>not in earlier run</span>"])
    for n in notes:
        if ":" in n:
            lab, val = n.split(":", 1)
        elif n.startswith("killed at step"):
            lab, val = "Kill point", n.replace("killed at step ", "step ")
        elif n.startswith("resume_from_checkpoint"):
            lab, val = "Pod resumed from", n.split("=", 1)[1]
        else:
            lab, val = "Note", n
        pn = ""
        if p:
            for q in p[2]:
                ql = q.split(":", 1)[0] if ":" in q else ("Kill point" if q.startswith("killed") else ("Pod resumed from" if q.startswith("resume_from") else "Note"))
                if ql == lab:
                    pn = e(q.split(":", 1)[1].strip() if ":" in q else (q.replace("killed at step ", "step ") if q.startswith("killed") else q.split("=", 1)[1]))
        timing_rows.append([e(lab), e(val.strip()), pn or "<span class='dim'>n/a</span>"])

if cur:
    verdict = f"{cp} of {cp+cf} checks passed" + ("" if cf == 0 else f", <b>{cf} FAILED</b>")
    run_line = f"This run: {verdict}, total {cur_total} s ({cur_total/60:.1f} min)."
else:
    verdict = "Rehearsal log not found or not finished"
    run_line = "The rehearsal summary is missing: run `bash scripts/rehearsal.sh 2>&1 | tee logs/rehearsal_ubuntu_run2.log` and rebuild this report."
prev_line = f"Earlier run: {pp} of {pp+pf} checks, total {prev_total} s." if prev else "No earlier run to compare."

css = """
:root{--bg:#fff;--fg:#1d2330;--dim:#667085;--line:#d9dee7;--card:#f6f8fb;--accent:#3b6fd4;--ok:#1a7f4b;--no:#b42318;--b0:#7a8aa6;--b1:#3b6fd4}
@media (prefers-color-scheme:dark){:root{--bg:#12151c;--fg:#e6e9f0;--dim:#9aa4b5;--line:#2a303c;--card:#1a1f29;--accent:#7ea2f0;--ok:#4cc38a;--no:#f97066;--b0:#6b7a96;--b1:#7ea2f0}}
*{box-sizing:border-box}body{margin:0;background:var(--bg);color:var(--fg);font:16px/1.55 system-ui,-apple-system,Segoe UI,Roboto,sans-serif}
main{max-width:980px;margin:0 auto;padding:32px 16px 64px}h1{font-size:1.9rem;margin:0 0 4px}h2{margin:2.2rem 0 .6rem;font-size:1.3rem;border-bottom:1px solid var(--line);padding-bottom:6px}
.sub{color:var(--dim);margin:0 0 20px}.card{background:var(--card);border:1px solid var(--line);border-radius:10px;padding:14px 18px;margin:14px 0}
table{width:100%;border-collapse:collapse;font-size:.93rem;margin:10px 0}th,td{text-align:left;padding:7px 10px;border-bottom:1px solid var(--line);vertical-align:top}th{color:var(--dim);font-weight:600}
.badge{display:inline-block;min-width:3.4em;text-align:center;font-weight:700;font-size:.78rem;padding:1px 8px;border-radius:99px;color:#fff}.badge.ok{background:var(--ok)}.badge.part{background:#b7791f}.badge.nt{background:var(--b0)}.wide td:nth-child(3){min-width:260px}.badge.no{background:var(--no)}
.dim{color:var(--dim)}.note{color:var(--dim);font-size:.85rem;margin:2px 0 0}figure{margin:12px 0;padding:0}figcaption{font-weight:600;margin-bottom:2px}
svg{width:100%;height:auto;max-width:560px}.lab{fill:var(--fg);font-size:13px}.val{fill:var(--fg);font-size:13px;font-weight:600}.bar.b0{fill:var(--b0)}.bar.b1{fill:var(--b1)}
.grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(300px,1fr));gap:8px 24px}ul{padding-left:1.2rem}li{margin:4px 0}
.kpis{display:grid;grid-template-columns:repeat(auto-fit,minmax(170px,1fr));gap:10px}.kpi{background:var(--card);border:1px solid var(--line);border-radius:10px;padding:12px 14px}.kpi b{display:block;font-size:1.5rem}.kpi span{color:var(--dim);font-size:.85rem}
@media print{body{background:#fff;color:#000}.card,.kpi{break-inside:avoid}}
"""

body = f"""
<h1>GPU on Kubernetes: project review</h1>
<p class="sub">Proof of concept for "Beyond kubectl apply: Elevating GPU Workflows with NVIDIA on Kubernetes" &middot; RTX 4070 (12 GB), native Ubuntu 24.04, driver 590.48.01, k3s, NVIDIA GPU Operator v26.7.2 &middot; generated {datetime.date.today().isoformat()}</p>

<div class="card"><b>Thesis.</b> Kubernetes with NVIDIA's tools makes GPU work easier to run than doing it by hand. The same model (Qwen2.5-1.5B-Instruct, LoRA fine-tune on 800 examples, served with vLLM) was done both ways. All numbers are single runs on this one machine.</div>

<div class="kpis">
<div class="kpi"><b>51 s</b><span>killed training job is training again, no person involved (manual: stays dead)</span></div>
<div class="kpi"><b>77 to 81 s</b><span>killed server is answering again on Kubernetes, no person involved</span></div>
<div class="kpi"><b>10% to 68%</b><span>GPU busy, one tiny model alone vs six sharing the card (light traffic)</span></div>
<div class="kpi"><b>Same</b><span>speed and GPU use as the manual way: 90.5% vs 89.1% busy, 1774 vs 1773 tok/s</span></div>
</div>


<h2>1. The six-metric comparison</h2>
<p class="sub">{sum(1 for r in SIX if r[4]=="Proven")} proven, {sum(1 for r in SIX if r[4]=="Partly")} partly, {sum(1 for r in SIX if r[4]=="Not tested")} not tested. Single runs on one RTX 4070 machine.</p>
{table(["Metric", "Traditional (by hand)", "Kubernetes + NVIDIA", "What we measured", "Status"], [[f"<b>{e(m)}</b>", e(t), e(k), e(ev), status(st)] for m, t, k, ev, st in SIX], "wide")}

<h2>2. Full rehearsal</h2>
<div class="card"><b>{verdict}.</b><br>{e(run_line)}<br><span class="dim">{e(prev_line)}</span><br>
<span class="dim">The rehearsal runs the demo end to end: reset, traditional fine-tune with a kill and manual resume, vLLM serving, the Kubernetes Job with a pod delete and automatic resume, the serve Deployment with a pod delete, and the Grafana checks. Sharing is not part of it.</span></div>
<h3>Timings</h3>
{table(["Step", "This run", "Earlier run"], timing_rows) if timing_rows else "<p class='dim'>No timings yet.</p>"}
<h3>All checks</h3>
{table(["Result", "Check", "Earlier run"], check_rows) if check_rows else ""}

<h2>3. What Kubernetes gave us</h2>
{table(["Event", "Traditional (by hand)", "Kubernetes"], [
 ["Training killed at step 362", "Stays dead. A person restarts it. Resume to done 325 s", "Replacement pod training again in about 51 s. No person"],
 ["Serving process killed", "Stays dead until restarted. Manual restart answered in 28 s (warm)", "Pod replaced and answering in 77 to 81 s. No person"],
 ["Second pod on a busy GPU", "Not applicable (no scheduler)", "Default: stays Pending. With time slicing: six tiny models ran on one card"],
])}
<div class="grid">
{bars("GPU busy, tiny model, light traffic", "%", [("1 copy alone (10 to 14)", 12), ("6 copies sharing", 68)], "Midpoint of the 10 to 14% measured for one copy.")}
{bars("Mean answer time, same traffic", "ms", [("1 copy alone", 85), ("6 copies sharing", 188)], "Mean of the six pods (177 to 197 ms). p95 99 ms alone, 313 to 348 ms shared.")}
</div>

<h2>4. What was the same</h2>
<div class="grid">
{bars("GPU busy, equal window", "%", [("Traditional", 90.5), ("Kubernetes", 89.1)])}
{bars("Serving throughput", "tok/s", [("Traditional", 1774), ("Kubernetes", 1773)])}
{bars("Fine-tune run time", "s", [("Traditional", 529), ("Kubernetes", 529)])}
{bars("First-time setup (sudo install excluded)", "min", [("Traditional", 13.3), ("Kubernetes", 27.8)], "One-time cost. About 14 of the 28 minutes are image builds.")}
</div>

<h2>5. Sharing one GPU</h2>
{table(["Setup", "Memory each pod can use", "Result"], [
 ["Default scheduler", "1 GPU", "Second pod stays Pending (Insufficient nvidia.com/gpu)"],
 ["Time slicing", "No limit (each sees 10.8 GiB)", "Models run together; a steady pod could not grow (out of memory); a second training job crashed twice"],
 ["MPS (2 replicas)", "Limit per pod (5.9 of 11.6 GiB)", "Greedy pod stopped at 5 GiB; steady pod grew 3 to 5 GiB"],
 ["MIG", "Hardware partitions (NVIDIA docs)", "<b>Not tested.</b> The RTX 4070 has no MIG. See MIG-THEORY.md"],
])}
<p class="note">Heavy load: six copies delivered about 5x less total throughput than one copy (2474 vs 12814 tok/s), because one tiny server already fills the card. Sharing helps when many models each get light traffic.</p>

<h2>6. Honest limits</h2>
<ul>
<li>Single runs on one machine. Recovery times come from pod logs and polling, about plus or minus 3 s.</li>
<li>Kubernetes was <b>not faster</b> and did <b>not</b> raise GPU utilization by itself. The gain is unattended recovery, sharing and visibility.</li>
<li>First-time setup was about twice as long on Kubernetes (image builds).</li>
<li>The GPU Operator did not install the driver or the container toolkit here (both were turned off). Turning its toolkit installer on broke the node.</li>
<li>Not tested: Growing (more nodes), Moving to another cloud, MIG, crash isolation between shared workloads.</li>
</ul>

<h2>7. Where to look</h2>
<ul>
<li>Live Grafana dashboard: <code>http://localhost:30300/d/gpu-review</code> (admin / admin), plus the NVIDIA DCGM dashboard.</li>
<li>Numbers and method: <code>results-ubuntu-4070.md</code>. Demo steps: <code>RUNBOOK-UBUNTU-DEMO.md</code>. MIG theory: <code>MIG-THEORY.md</code>.</li>
<li>Metrics packages: NVIDIA DCGM exporter (GPU), kube-state-metrics (pod status and restarts), kubelet cAdvisor (container CPU and memory), all scraped by Prometheus and shown in Grafana.</li>
</ul>
"""

out = root / "reports" / "review-report.html"
out.parent.mkdir(exist_ok=True)
out.write_text(f'<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">'
               f'<title>GPU on Kubernetes project review</title><style>{css}</style></head><body><main>{body}</main></body></html>')
print(f"wrote {out} ({out.stat().st_size} bytes); current log: {'ok' if cur else 'MISSING or unfinished'}, earlier log: {'ok' if prev else 'missing'}")
