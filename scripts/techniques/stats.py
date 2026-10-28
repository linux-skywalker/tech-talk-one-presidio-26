#!/usr/bin/env python3
"""usage: stats.py <probe.csv> <t_start> <t_end>  -> prints: n_ok n_fail p50_total p95_total p50_ttft p95_ttft (seconds, nearest rank)"""
import csv, math, sys
f, a, b = sys.argv[1], float(sys.argv[2]), float(sys.argv[3])
rows = [r for r in csv.DictReader(open(f)) if a <= float(r["ts"]) <= b]
ok = [r for r in rows if r["ok"] == "1"]
def pct(v, q):
    v = sorted(v); return f"{v[max(0, math.ceil(q * len(v)) - 1)]:.3f}" if v else "n/a"
tot = [float(r["total_s"]) for r in ok]; tt = [float(r["ttft_s"]) for r in ok]
print(len(ok), len(rows) - len(ok), pct(tot, .5), pct(tot, .95), pct(tt, .5), pct(tt, .95))
