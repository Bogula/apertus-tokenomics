#!/usr/bin/env bash
# 31_agg.sh - Dynamo, aggregated. This is your Dynamo BASELINE: same engine,
# same GPU count as the NIM run, just fronted by the Dynamo router. Without it
# you cannot attribute any later gain to disaggregation rather than to a
# different vLLM version.
#
#   dynamo/31_agg.sh              # 1 worker
#   REPLICAS=2 ROUTER=kv dynamo/31_agg.sh   # 2 workers + KV-aware routing
set -euo pipefail
cd "$(dirname "$0")/.."
# shellcheck source=/dev/null
source .env

MODEL="${MODEL:-$APERTUS15_8B}"
TP_SIZE="${TP_SIZE:-1}"
REPLICAS="${REPLICAS:-1}"
ROUTER="${ROUTER:-round-robin}"   # round-robin | kv
PORT="${NIM_PORT:-8000}"
DISCOVERY="${DISCOVERY:-file}"    # file | etcd
LOGD="$ARTIFACTS_DIR/dynamo"; mkdir -p "$LOGD"

# KV-aware routing hashes blocks across processes - hashing must be deterministic.
export PYTHONHASHSEED=0

pkill -f 'dynamo\.(frontend|vllm)' 2>/dev/null || true
sleep 2

echo "== frontend (router=$ROUTER) =="
python3 -m dynamo.frontend \
  --http-port "$PORT" \
  --router-mode "$ROUTER" \
  $( [ "$DISCOVERY" = file ] && echo --discovery-backend file ) \
  >"$LOGD/frontend.log" 2>&1 &

sleep 5
for i in $(seq 0 $((REPLICAS-1))); do
  GPUS=$(seq -s, $((i*TP_SIZE)) $(((i+1)*TP_SIZE-1)))
  echo "== decode worker $i on GPU(s) $GPUS =="
  CUDA_VISIBLE_DEVICES="$GPUS" python3 -m dynamo.vllm \
    --model "$MODEL" \
    --served-model-name apertus \
    --tensor-parallel-size "$TP_SIZE" \
    --max-model-len "${MAX_MODEL_LEN:-8192}" \
    --gpu-memory-utilization "${GPU_MEM_UTIL:-0.90}" \
    $( [ "$ROUTER" = kv ] && echo --metrics-endpoint-port $((9100+i)) ) \
    $( [ "$DISCOVERY" = file ] && echo --discovery-backend file ) \
    >"$LOGD/worker-$i.log" 2>&1 &
done

echo "waiting for :$PORT ..."
for _ in $(seq 1 120); do
  curl -fs "http://localhost:$PORT/v1/models" >/dev/null 2>&1 && {
    echo "ready. tag your benchmark: SYSTEM=dynamo-agg-r${REPLICAS}-${ROUTER} bench/21_sweep.sh all"
    exit 0; }
  sleep 10
done
echo "timed out - tail $LOGD/*.log"; exit 1
