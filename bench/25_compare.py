#!/usr/bin/env python3
"""A/B two benchmark runs held in separate artifact folders."""
import argparse, csv, sys

ap = argparse.ArgumentParser()
ap.add_argument("csv_a"); ap.add_argument("csv_b")
ap.add_argument("--name-a", default="A"); ap.add_argument("--name-b", default="B")
ap.add_argument("--usd-per-hour", type=float, default=3.12)
ap.add_argument("--gpus", type=float, default=1.0)
a = ap.parse_args()

def num(r, *keys):
    for k in keys:
        v = r.get(k)
        if v not in (None, ""):
            try: return float(v)
            except ValueError: pass
    return None

def best_by_workload(path):
    out = {}
    for r in csv.DictReader(open(path)):
        tp = num(r, "out_tok_per_s_avg") or 0.0
        w = r["workload"]
        if w not in out or tp > (num(out[w], "out_tok_per_s_avg") or 0):
            out[w] = r
    return out

A, B = best_by_workload(a.csv_a), best_by_workload(a.csv_b)
if not A or not B: sys.exit("one of the CSVs has no usable rows")

rate = a.usd_per_hour * a.gpus
cpm = lambda tp: rate / 3600 / tp * 1e6 if tp else float("nan")

print(f"\nA = {a.name_a}   ({a.csv_a})\nB = {a.name_b}   ({a.csv_b})\ncost basis: ${rate:.2f}/h\n")
hdr = (f"{'workload':11}{'A c':>5}{'B c':>5}{'A tok/s':>10}{'B tok/s':>10}{'Δtp':>8}"
       f"{'A ttft':>9}{'B ttft':>9}{'A $/1M':>9}{'B $/1M':>9}{'Δ$':>8}")
print(hdr); print("-" * len(hdr))
deltas = []
for w in sorted(set(A) | set(B)):
    ra, rb = A.get(w), B.get(w)
    if not (ra and rb):
        print(f"{w:11}  only in {a.name_a if ra else a.name_b}"); continue
    ta, tb = num(ra,"out_tok_per_s_avg") or 0, num(rb,"out_tok_per_s_avg") or 0
    qa, qb = num(ra,"ttft_ms_p95") or 0, num(rb,"ttft_ms_p95") or 0
    ca, cb = cpm(ta), cpm(tb)
    d = (tb/ta-1)*100 if ta else 0; dc = (cb/ca-1)*100 if ca else 0
    deltas.append(d)
    print(f"{w:11}{ra['concurrency']:>5}{rb['concurrency']:>5}{ta:10.0f}{tb:10.0f}{d:+7.1f}%"
          f"{qa:9.0f}{qb:9.0f}{ca:9.2f}{cb:9.2f}{dc:+7.1f}%")
print("-" * len(hdr))
print(f"mean throughput change A→B: {sum(deltas)/len(deltas):+.1f}%  "
      f"({a.name_b} is {'better' if sum(deltas)>0 else 'worse'})")
print("Each row = that run's highest-throughput rung meeting its SLO; "
      "concurrency may differ (columns A c / B c).\n")
