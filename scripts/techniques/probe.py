#!/usr/bin/env python3
"""Serving latency probe: one streaming chat request about every 1.5 s until <stopfile> exists. usage: probe.py <csv> <stopfile> [port]
Columns: ts, ok, ttft_s (time to first token), total_s, err. Failed requests are kept (ok=0)."""
import csv, json, os, sys, time, urllib.request
out, stop = sys.argv[1], sys.argv[2]; port = sys.argv[3] if len(sys.argv) > 3 else "30086"
BODY = json.dumps({"model": "Qwen/Qwen2.5-1.5B-Instruct", "stream": True, "max_tokens": 64, "temperature": 0.7,
                   "messages": [{"role": "user", "content": "Write a short paragraph about how GPUs work."}]}).encode()
with open(out, "w", newline="") as f:
    w = csv.writer(f); w.writerow(["ts", "ok", "ttft_s", "total_s", "err"])
    while not os.path.exists(stop):
        t0 = time.time(); ttft = ""; ok = 0; err = ""
        try:
            req = urllib.request.Request(f"http://localhost:{port}/v1/chat/completions", BODY, {"Content-Type": "application/json"})
            with urllib.request.urlopen(req, timeout=30) as r:
                for line in r:
                    if line.startswith(b"data:") and not ttft and b"[DONE]" not in line and b'"content"' in line: ttft = f"{time.time()-t0:.3f}"
                ok = 1 if ttft else 0
        except Exception as e:
            err = type(e).__name__
        w.writerow([f"{t0:.2f}", ok, ttft, f"{time.time()-t0:.3f}", err]); f.flush()
        time.sleep(max(0, 1.5 - (time.time() - t0)))
