#!/usr/bin/env bash
# 26_remote_sweep.sh - benchmark a hosted, OpenAI-compatible endpoint using the
# same workload shapes as the self-hosted runs, writing into the same directory
# layout so bench/22_collect.py works on it unchanged.
#
#   bash bench/26_remote_sweep.sh --list
#   bash bench/26_remote_sweep.sh swisscom-apertus-70b chat
#   bash bench/26_remote_sweep.sh swisscom-apertus-70b all
#   REQ_COUNT=100 bash bench/26_remote_sweep.sh vendor-b rag
#   DRY_RUN=1 bash bench/26_remote_sweep.sh swisscom-apertus-70b all   # budget only
#
# WHAT THIS MEASURES
#   Latency (TTFT, ITL) and whether the endpoint meets your SLOs at your traffic
#   shape, plus how many tokens it actually bills you.
#
# WHAT THIS DOES NOT MEASURE
#   "Their throughput." You are one tenant on a shared, autoscaled system behind
#   a rate limiter. Output tok/s here is your slice at this moment, not their
#   capacity, and it is not comparable to a self-hosted tok/s figure.
#   Hosted cost comes from the rate card, never from measured throughput.
set -euo pipefail
cd "$(dirname "$0")/.."
# shellcheck source=/dev/null
source .env

CFG="bench/endpoints.json"
SCEN="bench/scenarios.json"
REQ_COUNT="${REQ_COUNT:-50}"     # far lower than local runs - every request costs quota
DRY_RUN="${DRY_RUN:-0}"

if [ "${1:-}" = "--list" ] || [ -z "${1:-}" ]; then
  python3 - "$CFG" <<'PY'
import json,sys
eps=json.load(open(sys.argv[1]))["endpoints"]
print("configured endpoints:")
for k,v in eps.items():
    print(f"  {k:26s} {v['model']:34s} cap={v['rate_limit_rps']} rps  key=${v['api_key_env']}")
PY
  exit 0
fi

EP="$1"; WL="${2:-chat}"

read -r BASE_URL MODEL TOKENIZER KEY_ENV RPS LADDER <<EOF
$(python3 - "$CFG" "$EP" <<'PY'
import json,sys
e=json.load(open(sys.argv[1]))["endpoints"][sys.argv[2]]
print(e["base_url"], e["model"], e.get("tokenizer") or e["model"],
      e["api_key_env"], e["rate_limit_rps"],
      ",".join(map(str, e.get("ladder") or [1,2,4])))
PY
)
EOF

API_KEY="${!KEY_ENV:-}"
if [ -z "$API_KEY" ]; then
  echo "ERROR: \$$KEY_ENV is empty. Put it in .env (which is gitignored)." >&2
  exit 1
fi

# ---- fan out over every workload -------------------------------------------
if [ "$WL" = "all" ]; then
  for w in $(python3 -c "import json;print(' '.join(x['name'] for x in json.load(open('$SCEN'))['workloads']))"); do
    "$0" "$EP" "$w"
  done
  exit 0
fi

read -r ISL OSL TTFT_SLO ITL_SLO FIXED_OUT NEED_LEN <<EOF
$(python3 - "$SCEN" "$WL" <<'PY'
import json,sys
s=json.load(open(sys.argv[1]))
w=next(x for x in s["workloads"] if x["name"]==sys.argv[2])
slo=w.get("slo") or {}
print(w["isl"], w["osl"], slo.get("ttft_ms_p95",0), slo.get("itl_ms_p95",0),
      int(w.get("fixed_output", True)), w.get("requires_max_model_len",0))
PY
)
EOF

SYSTEM="remote-$EP"
ROOT="$ARTIFACTS_DIR/bench/$SYSTEM/$WL"
LADDER_SP="${LADDER//,/ }"

# ---- quota budget, printed BEFORE anything is spent -------------------------
NRUNGS=$(echo "$LADDER_SP" | wc -w)
EST_IN=$(( ISL * REQ_COUNT * NRUNGS ))
EST_OUT=$(( OSL * REQ_COUNT * NRUNGS ))
printf "== remote sweep: %s / %s\n" "$EP" "$WL"
printf "   isl=%s osl=%s rungs=[%s] requests/rung=%s rate cap=%s rps\n" \
       "$ISL" "$OSL" "$LADDER_SP" "$REQ_COUNT" "$RPS"
printf "   BUDGET: ~%'d input tokens, ~%'d output tokens\n" "$EST_IN" "$EST_OUT"
python3 - "$CFG" "$EP" "$EST_IN" "$EST_OUT" <<'PY'
import json,sys
e=json.load(open(sys.argv[1]))["endpoints"][sys.argv[2]]
q=e.get("quota")
if q:
    fi=int(sys.argv[3])/1e6; fo=int(sys.argv[4])/1e6
    print(f"   quota: {fi:.2f}M / {q['input_mtok']}M input  |  "
          f"{fo:.2f}M / {q['output_mtok']}M output  for THIS workload alone")
    if fi > q["input_mtok"]*0.4 or fo > q["output_mtok"]*0.4:
        print("   !! this single workload eats >40% of the budget. "
              "Lower REQ_COUNT or trim the ladder.")
PY
[ "$DRY_RUN" = "1" ] && { echo "   (dry run, nothing sent)"; exit 0; }

mkdir -p "$ROOT"

OUT_ARGS=(--output-tokens-mean "$OSL" --output-tokens-stddev 0
          --extra-inputs "max_tokens:$OSL")
# ignore_eos is a vLLM extension. Most hosted APIs reject unknown fields, and a
# 400 here looks exactly like a slow endpoint, so it is deliberately omitted.

for C in $LADDER_SP; do
  echo "-- concurrency $C (rate capped at $RPS rps)"
  OUTDIR="$ROOT/c$C"; mkdir -p "$OUTDIR"
  aiperf profile \
    --model "$MODEL" \
    --tokenizer "$TOKENIZER" \
    --url "$BASE_URL" \
    --endpoint-type chat \
    --streaming \
    --api-key "$API_KEY" \
    --synthetic-input-tokens-mean "$ISL" \
    --synthetic-input-tokens-stddev 0 \
    "${OUT_ARGS[@]}" \
    --concurrency "$C" \
    --request-rate "$RPS" \
    --request-count "$REQ_COUNT" \
    --warmup-request-count 2 \
    --artifact-dir "$OUTDIR" \
    >"$OUTDIR/stdout.txt" 2>&1 || {
      echo "   FAILED - see $OUTDIR/stdout.txt"
      grep -iE "401|403|429|rate|quota|expired" "$OUTDIR/stdout.txt" | head -3 || true
      break; }

  if [ "$TTFT_SLO" != "0" ]; then
    VIOL=$(python3 bench/22_collect.py --check-slo "$OUTDIR" \
             --ttft-p95-ms "$TTFT_SLO" --itl-p95-ms "$ITL_SLO" || echo violated)
    echo "   slo: $VIOL"
    [ "$VIOL" = "violated" ] && { echo "   -> stopping ladder"; break; }
  fi
done

cat <<EOF

== done: $SYSTEM / $WL -> $ROOT
   collect:  python3 bench/22_collect.py --root \$ARTIFACTS_DIR/bench -o artifacts/results-all.csv

   Remember when you write this up: the tok/s column for a remote row is YOUR
   SLICE, not the provider's capacity. Cost for this row comes from
   bench/endpoints.json (the rate card), not from the throughput measured here.
EOF