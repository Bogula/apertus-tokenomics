#!/usr/bin/env bash
# 11_serve.sh - launch Apertus under NIM. One config per invocation; the
# benchmark sweep restarts this script with different knobs.
#
# Usage:
#   nim/11_serve.sh                                  # 8B, TP=1, defaults
#   MODEL=$APERTUS10_70B TP_SIZE=4 nim/11_serve.sh
#   TP_SIZE=2 MAX_MODEL_LEN=32768 RUN_TAG=long-ctx nim/11_serve.sh
#
# Env knobs (all optional, all recorded into the run tag):
#   MODEL, TP_SIZE, MAX_MODEL_LEN, NIM_PORT, NIM_MODEL_PROFILE,
#   GPU_MEM_UTIL, MAX_NUM_SEQS, EXTRA_ARGS, RUN_TAG
set -euo pipefail
cd "$(dirname "$0")/.."
# shellcheck source=/dev/null
source .env

MODEL="${MODEL:-$APERTUS10_8B}"
TP_SIZE="${TP_SIZE:-1}"
MAX_MODEL_LEN="${MAX_MODEL_LEN:-8192}"
GPU_MEM_UTIL="${GPU_MEM_UTIL:-0.90}"
MAX_NUM_SEQS="${MAX_NUM_SEQS:-256}"
NIM_PORT="${NIM_PORT:-8000}"
RUN_TAG="${RUN_TAG:-$(basename "$MODEL")-tp${TP_SIZE}-len${MAX_MODEL_LEN}-seqs${MAX_NUM_SEQS}}"
NAME="nim-${RUN_TAG}"

mkdir -p "$ARTIFACTS_DIR/serve"
LOG="$ARTIFACTS_DIR/serve/$RUN_TAG.log"

docker rm -f "$NAME" >/dev/null 2>&1 || true

# Args after the action are forwarded to the underlying engine (vLLM).
# Keep this list in sync with what the selected backend actually accepts -
# if NIM lands on SGLang, translate these (--mem-fraction-static etc.).
ENGINE_ARGS=(
  --max-model-len "$MAX_MODEL_LEN"
  --gpu-memory-utilization "$GPU_MEM_UTIL"
  --max-num-seqs "$MAX_NUM_SEQS"
)
# shellcheck disable=SC2206
[ -n "${EXTRA_ARGS:-}" ] && ENGINE_ARGS+=(${EXTRA_ARGS})

echo "== starting $NAME =="
echo "   model=$MODEL tp=$TP_SIZE len=$MAX_MODEL_LEN seqs=$MAX_NUM_SEQS"

docker run -d --name "$NAME" --gpus all \
  --shm-size=16GB --network=host --ipc=host \
  -u "$(id -u)" \
  -v "$CACHE_DIR:/opt/nim/.cache" \
  -v "$HF_HOME:$HF_HOME" \
  -e HF_HOME="$HF_HOME" \
  -e HF_TOKEN="$HF_TOKEN" \
  -e NIM_MODEL_NAME="hf://$MODEL" \
  -e NIM_TENSOR_PARALLEL_SIZE="$TP_SIZE" \
  -e NIM_SERVED_MODEL_NAME="apertus" \
  -e NIM_HTTP_API_PORT="$NIM_PORT" \
  ${NIM_MODEL_PROFILE:+-e NIM_MODEL_PROFILE="$NIM_MODEL_PROFILE"} \
  "$NIM_IMAGE" nim-serve "${ENGINE_ARGS[@]}"

echo "== waiting for /v1/health/ready (first run downloads + builds, be patient) =="
for i in $(seq 1 180); do
  if curl -fs "http://localhost:$NIM_PORT/v1/health/ready" >/dev/null 2>&1; then
    echo "   ready after ${i}0s"
    docker logs "$NAME" > "$LOG" 2>&1
    echo "$RUN_TAG" > "$ARTIFACTS_DIR/serve/CURRENT"
    exit 0
  fi
  sleep 10
  if [ "$((i % 6))" -eq 0 ]; then echo "   ...${i}0s"; fi
done

echo "TIMED OUT. Last 60 log lines:"
docker logs --tail 60 "$NAME"
docker logs "$NAME" > "$LOG" 2>&1
echo
echo "Common causes:"
echo "  * 'Model architecture ApertusForCausalLM not supported' -> the NIM image's"
echo "    engine predates Apertus support. Use nim/13_fallback_vllm.sh and report"
echo "    the version gap as a finding."
echo "  * OOM -> lower --gpu-memory-utilization or --max-model-len, or raise TP_SIZE."
echo "  * stuck on download -> check disk and the HF mirror."
exit 1
