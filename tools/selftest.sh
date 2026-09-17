#!/usr/bin/env bash
# selftest.sh - exercise the analysis pipeline with synthetic benchmark data,
# without a GPU. Run this on your laptop the day before, so that the only thing
# that can break on LaunchPad is the serving, not the plumbing.
#
#   bash tools/selftest.sh          # writes to artifacts-selftest/, then cleans up
#   KEEP=1 bash tools/selftest.sh   # keep the output to eyeball the report
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT="artifacts-selftest"
rm -rf "$ROOT"; mkdir -p "$ROOT"

python3 - "$ROOT" <<'PY'
import json, os, sys
root = sys.argv[1]
shapes = json.load(open("bench/scenarios.json"))["workloads"]
for system, scale in [("nim-8b-tp1", 1.0), ("nim-8b-tp1-fp8", 1.6),
                      ("dynamo-disagg-p1d1-kv", 1.9)]:
    for w in shapes:
        isl, osl = w["isl"], w["osl"]
        for c in (1, 2, 4, 8, 16, 32, 64):
            d = f"{root}/bench/{system}/{w['name']}/c{c}"
            os.makedirs(d, exist_ok=True)
            per_user = 42 * scale / (1 + c / 48)      # decode slows as batch grows
            tp = per_user * c
            ttft = 45 + c * 3.2 + isl * 0.06          # prefill queueing
            itl = 1000 / per_user
            json.dump({
                "time_to_first_token": {"unit": "ms", "avg": ttft, "p95": ttft * 1.35},
                "inter_token_latency": {"unit": "ms", "avg": itl, "p95": itl * 1.3},
                "request_latency": {"unit": "ms", "avg": ttft + itl * osl},
                "request_throughput": {"unit": "req/s", "avg": tp / osl},
                "output_token_throughput": {"unit": "tok/s", "avg": tp},
                "output_token_throughput_per_user": {"unit": "tok/s/user", "avg": per_user},
            }, open(f"{d}/profile_export_aiperf.json", "w"), indent=1)
print("synthetic exports written")
PY

python3 bench/22_collect.py --root "$ROOT/bench" -o "$ROOT/results.csv"
python3 tokenomics/40_tokenomics.py --results "$ROOT/results.csv" \
        --gpu H100-80GB-SXM --gpus-per-replica 1 --out "$ROOT/tokenomics.md"

echo
echo "PIPELINE OK. Report: $ROOT/tokenomics.md"
echo "NOTE: those numbers are fabricated fixtures. They prove the plumbing works,"
echo "      nothing about Apertus. Never paste them into a slide."
[ -n "${KEEP:-}" ] || { rm -rf "$ROOT"; echo "cleaned up (KEEP=1 to retain)"; }
