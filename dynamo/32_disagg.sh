#!/usr/bin/env bash
# 32_disagg.sh - disaggregated prefill/decode. The hard-track payoff.
#
# The idea: prefill is compute-bound and bursty, decode is memory-bandwidth-bound
# and steady. Running them on the same GPU means one interferes with the other -
# a long prompt stalls everyone's token stream. Split them onto separate GPU
# pools, stream the KV cache across with NIXL, and each pool can be sized and
# batched for its own bottleneck.
#
# You will only see a win on prefill-heavy workloads. Benchmark the 'rag' and
# 'summarize' scenarios; if you only test 'chat' you will measure a regression
# and conclude the wrong thing.
#
#   dynamo/32_disagg.sh                     # 1 prefill + 1 decode
#   PREFILL=1 DECODE=2 ROUTER=kv dynamo/32_disagg.sh
set -euo pipefail
cd "$(dirname "$0")/.."
# shellcheck source=/dev/null
source .env

MODEL="${MODEL:-$APERTUS_8B}"
TP_SIZE="${TP_SIZE:-1}"
PREFILL="${PREFILL:-1}"
DECODE="${DECODE:-1}"
ROUTER="${ROUTER:-kv}"
CONNECTOR="${CONNECTOR:-nixl}"
PORT="${NIM_PORT:-8000}"
DISCOVERY="${DISCOVERY:-etcd}"   # KV routing wants etcd+NATS
LOGD="$ARTIFACTS_DIR/dynamo"; mkdir -p "$LOGD"
export PYTHONHASHSEED=0

NEED=$(( (PREFILL + DECODE) * TP_SIZE ))
HAVE=$(nvidia-smi --list-gpus | wc -l)
[ "$NEED" -le "$HAVE" ] || { echo "need $NEED GPUs, have $HAVE"; exit 1; }

pkill -f 'dynamo\.(frontend|vllm)' 2>/dev/null || true
sleep 2

echo "== frontend =="
python3 -m dynamo.frontend --http-port "$PORT" --router-mode "$ROUTER" \
  $( [ "$DISCOVERY" = file ] && echo --discovery-backend file ) \
  >"$LOGD/frontend.log" 2>&1 &
sleep 5

g=0
for i in $(seq 0 $((PREFILL-1))); do
  GPUS=$(seq -s, "$g" $((g+TP_SIZE-1))); g=$((g+TP_SIZE))
  echo "== PREFILL worker $i on GPU(s) $GPUS =="
  CUDA_VISIBLE_DEVICES="$GPUS" python3 -m dynamo.vllm \
    --model "$MODEL" --served-model-name apertus \
    --tensor-parallel-size "$TP_SIZE" \
    --max-model-len "${MAX_MODEL_LEN:-8192}" \
    --gpu-memory-utilization "${GPU_MEM_UTIL:-0.90}" \
    --is-prefill-worker \
    --connector "$CONNECTOR" \
    $( [ "$DISCOVERY" = file ] && echo --discovery-backend file ) \
    >"$LOGD/prefill-$i.log" 2>&1 &
done

for i in $(seq 0 $((DECODE-1))); do
  GPUS=$(seq -s, "$g" $((g+TP_SIZE-1))); g=$((g+TP_SIZE))
  echo "== DECODE worker $i on GPU(s) $GPUS =="
  CUDA_VISIBLE_DEVICES="$GPUS" python3 -m dynamo.vllm \
    --model "$MODEL" --served-model-name apertus \
    --tensor-parallel-size "$TP_SIZE" \
    --max-model-len "${MAX_MODEL_LEN:-8192}" \
    --gpu-memory-utilization "${GPU_MEM_UTIL:-0.90}" \
    --connector "$CONNECTOR" \
    --metrics-endpoint-port $((9200+i)) \
    $( [ "$DISCOVERY" = file ] && echo --discovery-backend file ) \
    >"$LOGD/decode-$i.log" 2>&1 &
done

echo "waiting for :$PORT ..."
for _ in $(seq 1 150); do
  curl -fs "http://localhost:$PORT/v1/models" >/dev/null 2>&1 && {
    cat <<EOF
ready.

Benchmark it on the PREFILL-HEAVY workloads, and compare against the
aggregated run that used THE SAME TOTAL GPU COUNT ($NEED):

  SYSTEM=dynamo-disagg-p${PREFILL}d${DECODE}-${ROUTER} bench/21_sweep.sh rag
  SYSTEM=dynamo-disagg-p${PREFILL}d${DECODE}-${ROUTER} bench/21_sweep.sh summarize

Then sweep the prefill:decode ratio (1:1, 1:2, 2:1). The optimal ratio is a
function of ISL/OSL - showing that curve is a strong result on its own.
EOF
    exit 0; }
  sleep 10
done
echo "timed out - tail $LOGD/*.log"; exit 1
