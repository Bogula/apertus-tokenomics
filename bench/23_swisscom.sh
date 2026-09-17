#!/usr/bin/env bash
# 23_swisscom.sh - benchmark the hosted Apertus 1.5 70B endpoint.
#
# This is the comparator that makes the study airtight: THE SAME MODEL, same
# weights, self-hosted vs hosted. No "well, it's a different model" objection.
#
# Three hard constraints, all enforced here because blowing any of them wastes
# quota you cannot get back:
#   * 5 requests/second        -> concurrency is capped; higher just measures
#                                 their rate limiter, not the model
#   * 10M input / 2.5M output  -> finite total budget for the whole hackathon
#   * bearer expires in 60 min -> a long sweep dies mid-run with 401s
#
# Usage:
#   bench/23_swisscom.sh chat
#   LADDER="1 2 5" REQS=60 bench/23_swisscom.sh rag
set -euo pipefail
cd "$(dirname "$0")/.."
# shellcheck source=/dev/null
source .env

WL="${1:-chat}"
SCEN="bench/scenarios.json"
SYSTEM="${SYSTEM:-swisscom-hosted-v15-70b}"
LEDGER="$ARTIFACTS_DIR/swisscom_budget.json"
mkdir -p "$ARTIFACTS_DIR"

[ "${SWISSCOM_API_KEY:-CHANGE_ME}" != "CHANGE_ME" ] || {
  echo "SWISSCOM_API_KEY not set - get one from The Keymaker (see docs/APERTUS-1.5.md)"; exit 1; }

read -r ISL OSL <<EOF
$(python3 -c "
import json,sys
w=next(x for x in json.load(open('$SCEN'))['workloads'] if x['name']=='$WL')
print(w['isl'], w['osl'])")
EOF

# Respect the documented rate limit. Concurrency above ~RPS * latency buys nothing.
LADDER="${LADDER:-1 2 4 5}"
REQS="${REQS:-60}"

# ---- budget guard ---------------------------------------------------------
python3 - "$LEDGER" "$ISL" "$OSL" "$REQS" "$LADDER" "$SWISSCOM_INPUT_BUDGET" "$SWISSCOM_OUTPUT_BUDGET" <<'PY'
import json, os, sys
ledger, isl, osl, reqs, ladder, ib, ob = sys.argv[1:8]
isl, osl, reqs = int(isl), int(osl), int(reqs)
rungs = len(ladder.split())
used = json.load(open(ledger)) if os.path.exists(ledger) else {"input": 0, "output": 0}
plan_in, plan_out = isl * reqs * rungs, osl * reqs * rungs
print(f"  budget: used {used['input']:,} in / {used['output']:,} out")
print(f"  this run plans {plan_in:,} in / {plan_out:,} out over {rungs} rung(s)")
if used["output"] + plan_out > int(ob) * 0.9:
    sys.exit("  REFUSING: would exceed 90% of the OUTPUT budget. Lower REQS or LADDER.")
if used["input"] + plan_in > int(ib) * 0.9:
    sys.exit("  REFUSING: would exceed 90% of the INPUT budget. Lower REQS or LADDER.")
PY

# ---- auth freshness -------------------------------------------------------
code=$(curl -s -o /dev/null -w '%{http_code}' -X POST "$SWISSCOM_BASE_URL/chat/completions" \
  -H "Authorization: Bearer $SWISSCOM_API_KEY" -H 'Content-Type: application/json' \
  -d "{\"model\":\"$SWISSCOM_MODEL\",\"max_tokens\":1,\"messages\":[{\"role\":\"user\",\"content\":\"hi\"}]}")
[ "$code" = 200 ] || { echo "auth check returned $code - the bearer lives only 60 minutes. Refresh it and rerun."; exit 1; }

ROOT="$ARTIFACTS_DIR/bench/$SYSTEM/$WL"
mkdir -p "$ROOT"
echo "== hosted sweep: $WL (isl=$ISL osl=$OSL) rungs: $LADDER =="

for C in $LADDER; do
  echo "-- concurrency $C"
  OUTDIR="$ROOT/c$C"; mkdir -p "$OUTDIR"
  aiperf profile \
    --model "$SWISSCOM_MODEL" \
    --url "$SWISSCOM_BASE_URL" \
    --endpoint-type chat \
    --streaming \
    -H "Authorization: Bearer $SWISSCOM_API_KEY" \
    --synthetic-input-tokens-mean "$ISL" --synthetic-input-tokens-stddev 0 \
    --output-tokens-mean "$OSL" --output-tokens-stddev 0 \
    --extra-inputs "max_tokens:$OSL" \
    --request-rate "$SWISSCOM_MAX_RPS" \
    --concurrency "$C" \
    --request-count "$REQS" \
    --artifact-dir "$OUTDIR" \
    >"$OUTDIR/stdout.txt" 2>&1 || { echo "   failed - see $OUTDIR/stdout.txt"; break; }

  python3 - "$LEDGER" "$ISL" "$OSL" "$REQS" <<'PY'
import json, os, sys
ledger, isl, osl, reqs = sys.argv[1], int(sys.argv[2]), int(sys.argv[3]), int(sys.argv[4])
u = json.load(open(ledger)) if os.path.exists(ledger) else {"input": 0, "output": 0}
u["input"] += isl * reqs; u["output"] += osl * reqs
json.dump(u, open(ledger, "w"), indent=1)
print(f"   ledger: {u['input']:,} in / {u['output']:,} out consumed so far")
PY
done

cat <<EOF

Collect alongside the self-hosted runs:
  python3 bench/22_collect.py --root $ARTIFACTS_DIR/bench -o $ARTIFACTS_DIR/results.csv

Reading the result honestly: a hosted endpoint's latency includes network RTT
from LaunchPad to Swisscom, and its throughput reflects THEIR batching across
all hackathon teams, not a dedicated deployment. Say so. The number that
survives scrutiny is cost per token at a stated SLO, not raw tokens/sec.
EOF
