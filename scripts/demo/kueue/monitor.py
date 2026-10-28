#!/usr/bin/env python3
"""Samples the experiment once per 2 s until <run>/stop exists: GPU util and memory (nvidia-smi), jobs waiting/running/done in the
team namespaces, and one streaming chat request to the serve Service (time to first token, total time). Stdlib only."""
import csv, json, os, subprocess, sys, threading, time, urllib.request

run = sys.argv[1]; stop = os.path.join(run, "stop")
env = dict(os.environ, KUBECONFIG="/etc/rancher/k3s/k3s.yaml")
def sh(*a):
    return subprocess.run(a, capture_output=True, text=True, env=env).stdout

def counts():
    w = r = d = 0; serve_ready = 0
    for ns in ("team-a", "team-b"):
        try: j = json.loads(sh("kubectl", "get", "jobs,deploy", "-n", ns, "-o", "json") or "{}").get("items", [])
        except Exception: continue
        for it in j:
            st = it.get("status", {})
            if it["kind"] == "Job":
                if st.get("succeeded"): d += 1
                elif any(c.get("type") == "Failed" and c.get("status") == "True" for c in st.get("conditions", [])): pass
                elif st.get("active"): r += 1
                else: w += 1
            else:
                if st.get("readyReplicas"): r += 1; serve_ready = 1
                else: w += 1
    return w, r, d, serve_ready

def sample():
    with open(os.path.join(run, "samples.csv"), "w", newline="") as f:
        wr = csv.writer(f); wr.writerow(["ts", "util", "mem_mib", "waiting", "running", "done", "serve_ready"])
        while not os.path.exists(stop):
            t0 = time.time()
            g = sh("nvidia-smi", "--query-gpu=utilization.gpu,memory.used", "--format=csv,noheader,nounits").strip().split(",")
            w, r, d, s = counts()
            wr.writerow([f"{t0:.2f}", g[0].strip(), g[1].strip(), w, r, d, s]); f.flush()
            time.sleep(max(0, 2 - (time.time() - t0)))

BODY = json.dumps({"model": "Qwen/Qwen2.5-1.5B-Instruct", "stream": True, "max_tokens": 64, "temperature": 0.7,
                   "messages": [{"role": "user", "content": "Write a short paragraph about how GPUs work."}]}).encode()
def probe():
    with open(os.path.join(run, "probe.csv"), "w", newline="") as f:
        wr = csv.writer(f); wr.writerow(["ts", "ok", "ttft_s", "total_s", "err"])
        while not os.path.exists(stop):
            t0 = time.time(); ttft = ""; ok = 0; err = ""
            try:
                req = urllib.request.Request("http://localhost:30085/v1/chat/completions", BODY, {"Content-Type": "application/json"})
                with urllib.request.urlopen(req, timeout=20) as resp:
                    for line in resp:
                        if line.startswith(b"data:") and not ttft and b"[DONE]" not in line and b'"content"' in line: ttft = f"{time.time()-t0:.3f}"
                    ok = 1 if ttft else 0
            except Exception as e:
                err = type(e).__name__
            if ok or err not in ("URLError", "ConnectionResetError", "RemoteDisconnected", "ConnectionRefusedError"):
                wr.writerow([f"{t0:.2f}", ok, ttft, f"{time.time()-t0:.3f}", err]); f.flush()
            time.sleep(max(0, 1.5 - (time.time() - t0)))

th = [threading.Thread(target=sample), threading.Thread(target=probe)]
[t.start() for t in th]; [t.join() for t in th]
