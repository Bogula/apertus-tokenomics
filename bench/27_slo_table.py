#!/usr/bin/env python3
"""27_slo_table.py - aus EINER results.csv die Zeile je System und Workload
ziehen, die den SLO wirklich einhaelt.

    python3 bench/27_slo_table.py artifacts/results-all.csv
    python3 bench/27_slo_table.py artifacts/results-all.csv \\
        --gpus h100nvl-dynamo-pref-run-2gpu=2 --usd-per-hour 3.12

Warum es das gibt: die Liste, die 22_collect.py ausgibt, und die Auswahl in
25_compare.py nehmen den hoechsten Durchsatz. Der Sweep bricht aber erst NACH
der SLO-Verletzung ab - die verletzende Sprosse steht also in der CSV und ist
fast immer die schnellste. Damit vergleicht man systematisch Betriebspunkte,
die niemand ausliefern wuerde. Dieses Skript filtert vorher und sagt, wenn ein
System einen Workload ueberhaupt nicht SLO-konform bedienen kann.

$/1M wird pro GPU gerechnet. Ein Zwei-GPU-Lauf mit doppeltem Durchsatz ist
nicht billiger - er ist gleich teuer. Genau das macht --gpus sichtbar.
"""
from __future__ import annotations

import argparse
import csv
import json
import sys
from pathlib import Path

ORDER = ["chat", "rag", "summarize", "agent", "think", "batch", "longctx"]


def num(r, *keys):
    for k in keys:
        v = r.get(k)
        if v not in (None, ""):
            try:
                return float(v)
            except ValueError:
                pass
    return None


def main() -> int:
    ap = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("csv_path")
    ap.add_argument("--scenarios", default="bench/scenarios.json")
    ap.add_argument("--usd-per-hour", type=float, default=3.12)
    ap.add_argument("--gpus", action="append", default=[], metavar="SYSTEM=N",
                    help="GPU-Zahl fuer ein System (Default 1), mehrfach nutzbar")
    ap.add_argument("--baseline", help="System, gegen das die Prozente laufen")
    a = ap.parse_args()

    sc = Path(a.scenarios)
    if not sc.exists():
        sys.exit(f"{sc} fehlt - mit --scenarios zeigen.")
    slo = {}
    for w in json.load(sc.open())["workloads"]:
        s = w.get("slo") or {}
        slo[w["name"]] = (float(s.get("ttft_ms_p95") or 0),
                          float(s.get("itl_ms_p95") or 0))

    gpus = {}
    for spec in a.gpus:
        if "=" not in spec:
            sys.exit(f"--gpus braucht SYSTEM=N, bekam {spec!r}")
        k, v = spec.rsplit("=", 1)
        gpus[k] = float(v)

    # best[(system, workload)] = (row, tp) fuer konforme Sprossen
    best: dict[tuple[str, str], tuple[dict, float]] = {}
    miss: dict[tuple[str, str], tuple[dict, float]] = {}
    systems, workloads = [], []

    for r in csv.DictReader(open(a.csv_path)):
        s, w = r["system"], r["workload"]
        if s not in systems:
            systems.append(s)
        if w not in workloads:
            workloads.append(w)
        tp = num(r, "out_tok_per_s_avg") or 0.0
        t = num(r, "ttft_ms_p95", "ttft_ms_avg")
        i = num(r, "itl_ms_p95", "itl_ms_avg", "tpot_ms_p95")
        tmax, imax = slo.get(w, (0.0, 0.0))
        ok = not ((tmax and t and t > tmax) or (imax and i and i > imax))
        tgt = best if ok else miss
        if (s, w) not in tgt or tp > tgt[(s, w)][1]:
            tgt[(s, w)] = (r, tp)

    workloads.sort(key=lambda w: (ORDER.index(w) if w in ORDER else 99, w))
    systems.sort()

    def cell(s, w):
        e = best.get((s, w))
        if e is None:
            return "  —  " if (s, w) in miss else "  ·  "
        return f"{e[1]:.0f}@c{e[0]['concurrency']}"

    wid = max(len(s) for s in systems) + 2
    col = max(12, max(len(w) for w in workloads) + 2)

    print(f"\nSLO-konformer Bestwert  (schnellste Sprosse, die ttft_p95 UND "
          f"itl_p95 haelt)\nQuelle: {a.csv_path}   SLOs: {a.scenarios}\n")
    print(" " * wid + "".join(f"{w:>{col}}" for w in workloads))
    print("-" * (wid + col * len(workloads)))
    for s in systems:
        print(f"{s:<{wid}}" + "".join(f"{cell(s, w):>{col}}" for w in workloads))
    print("-" * (wid + col * len(workloads)))
    print("—  gemessen, aber keine Sprosse haelt den SLO      "
          "·  nicht gemessen\n")

    # --- $/1M Output-Token, pro GPU ----------------------------------------
    print(f"$/1M Output-Token, auf EINE GPU normiert  "
          f"(${a.usd_per_hour:.2f}/GPU-h)\n")
    print(" " * wid + "".join(f"{w:>{col}}" for w in workloads))
    print("-" * (wid + col * len(workloads)))
    cpm: dict[tuple[str, str], float] = {}
    for s in systems:
        row = ""
        n = gpus.get(s, 1.0)
        for w in workloads:
            e = best.get((s, w))
            if e is None:
                row += f"{'—' if (s, w) in miss else '·':>{col}}"
                continue
            per_gpu = e[1] / n
            c = a.usd_per_hour / 3600 / per_gpu * 1e6
            cpm[(s, w)] = c
            row += f"{c:>{col}.2f}"
        tag = f"{s} ({n:.0f} GPU)" if n != 1 else s
        print(f"{tag:<{wid}}" + row)
    print("-" * (wid + col * len(workloads)))

    if a.baseline:
        if a.baseline not in systems:
            sys.exit(f"--baseline {a.baseline!r} steht nicht in der CSV.")
        print(f"\nDurchsatz je GPU relativ zu {a.baseline}\n")
        print(" " * wid + "".join(f"{w:>{col}}" for w in workloads))
        print("-" * (wid + col * len(workloads)))
        for s in systems:
            row = ""
            for w in workloads:
                b, e = best.get((a.baseline, w)), best.get((s, w))
                if b is None or e is None:
                    row += f"{'·':>{col}}"
                    continue
                d = ((e[1] / gpus.get(s, 1.0)) /
                     (b[1] / gpus.get(a.baseline, 1.0)) - 1) * 100
                row += f"{d:>+{col - 1}.0f}%"
            print(f"{s:<{wid}}" + row)
        print("-" * (wid + col * len(workloads)))

    if miss:
        print("\nWorkloads ohne konforme Sprosse - bester Versuch:")
        for (s, w) in sorted(miss):
            if (s, w) in best:
                continue
            r, tp = miss[(s, w)]
            t = num(r, "ttft_ms_p95", "ttft_ms_avg") or 0
            i = num(r, "itl_ms_p95", "itl_ms_avg", "tpot_ms_p95") or 0
            st, si = slo.get(w, (0, 0))
            bad = []
            if st and t > st:
                bad.append(f"ttft {t:.0f}>{st:.0f}")
            if si and i > si:
                bad.append(f"itl {i:.1f}>{si:.0f}")
            print(f"  {s:<{wid}}{w:<12}c={r['concurrency']:<5}"
                  f"{tp:>8.0f} tok/s   {', '.join(bad)}")
    print()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

