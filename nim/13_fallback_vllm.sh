#!/usr/bin/env bash
# 13_fallback_vllm.sh - the escape hatch.
#
# If the NIM image ships an engine older than Apertus support, you are NOT stuck:
# serve the model with upstream vLLM (or SGLang) on the same OpenAI-compatible
# API and the same port, so every downstream script keeps working unchanged.
#
# This is also a legitimate BASELINE for the report: "vanilla vLLM" vs
# "NIM-packaged, NIM-tuned" is exactly the optimization delta the challenge asks
# you to quantify.
set -euo pipefail
cd "$(dirname "$0")/.."
# shellcheck source=/dev/null
source .env

MODEL="${MODEL:-$APERTUS10_8B}"
TP_SIZE="${TP_SIZE:-1}"
MAX_MODEL_LEN="${MAX_MODEL_LEN:-8192}"
PORT="${NIM_PORT:-8000}"
ENGINE="${ENGINE:-vllm}"   # vllm | sglang
NAME="baseline-$ENGINE"

docker rm -f "$NAME" >/dev/null 2>&1 || true

case "$ENGINE" in
vllm)
  # Apertus needs vLLM >= 0.10.2 (ApertusForCausalLM + xIELU). Pin a known tag.
  IMG="${VLLM_IMAGE:-vllm/vllm-openai:latest}"
  docker run -d --name "$NAME" --gpus all --shm-size=16GB --network=host --ipc=host \
    -v "$HF_HOME:/root/.cache/huggingface" -e HF_TOKEN="$HF_TOKEN" \
    "$IMG" \
    --model "$MODEL" --served-model-name apertus \
    --tensor-parallel-size "$TP_SIZE" \
    --max-model-len "$MAX_MODEL_LEN" \
    --gpu-memory-utilization "${GPU_MEM_UTIL:-0.90}" \
    --max-num-seqs "${MAX_NUM_SEQS:-256}" \
    --port "$PORT"
  ;;
sglang)
  IMG="${SGLANG_IMAGE:-lmsysorg/sglang:latest}"
  docker run -d --name "$NAME" --gpus all --shm-size=16GB --network=host --ipc=host \
    -v "$HF_HOME:/root/.cache/huggingface" -e HF_TOKEN="$HF_TOKEN" \
    "$IMG" python3 -m sglang.launch_server \
    --model-path "$MODEL" --served-model-name apertus \
    --tp "$TP_SIZE" --context-length "$MAX_MODEL_LEN" \
    --host 0.0.0.0 --port "$PORT"
  ;;
*) echo "ENGINE must be vllm or sglang"; exit 1 ;;
esac

echo "waiting for $NAME on :$PORT ..."
for _ in $(seq 1 120); do
  curl -fs "http://localhost:$PORT/v1/models" >/dev/null 2>&1 && { echo ready; exit 0; }
  sleep 10
done
docker logs --tail 60 "$NAME"; exit 1
