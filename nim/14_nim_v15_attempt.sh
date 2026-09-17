#!/usr/bin/env bash
# 14_nim_v15_attempt.sh - deliberately attempt Apertus 1.5 under NIM, and
# capture the result as EVIDENCE rather than as a dead end.
#
# Expected outcome: NIM cannot load it. The architecture id is `apertus1p5`,
# which is not in upstream vLLM/transformers yet (Swiss AI ship forks), and
# `ApertusForCausalLM` is not in the TensorRT-LLM supported-models list either.
#
# Do not skip this because you already know it will fail. A challenge about
# operating AI efficiently is exactly the place to document, with timestamps and
# logs, that the vendor-optimized stack lags the open-model frontier. That claim
# needs receipts.
set -euo pipefail
cd "$(dirname "$0")/.."
# shellcheck source=/dev/null
source .env

MODEL="${MODEL:-$APERTUS15_8B}"
OUT="$ARTIFACTS_DIR/nim-v15-attempt"; mkdir -p "$OUT"
SAFE=$(echo "$MODEL" | tr '/' '_')
{
  echo "date: $(date -Is)"
  echo "model: $MODEL"
  echo "nim image: $NIM_IMAGE"
  docker image inspect "$NIM_IMAGE" --format '{{index .Config.Labels "com.nvidia.build.version"}} {{.Created}}' 2>/dev/null || true
} > "$OUT/context.txt"

echo "== step 1: does NIM offer any profile for Apertus 1.5? =="
docker run --rm --gpus all --shm-size=16GB --network=host -u "$(id -u)" \
  -v "$CACHE_DIR:/opt/nim/.cache" -e HF_TOKEN="$HF_TOKEN" \
  "$NIM_IMAGE" list-model-profiles --model "hf://$MODEL" \
  2>&1 | tee "$OUT/$SAFE.profiles.txt" || true

echo
echo "== step 2: attempt an actual load (5 min cap) =="
NAME="nim-v15-attempt"
docker rm -f "$NAME" >/dev/null 2>&1 || true
docker run -d --name "$NAME" --gpus all --shm-size=16GB --network=host --ipc=host \
  -u "$(id -u)" \
  -v "$CACHE_DIR:/opt/nim/.cache" -v "$HF_HOME:$HF_HOME" -e HF_HOME="$HF_HOME" \
  -e HF_TOKEN="$HF_TOKEN" \
  -e NIM_MODEL_NAME="hf://$MODEL" \
  -e NIM_TENSOR_PARALLEL_SIZE="${TP_SIZE:-1}" \
  "$NIM_IMAGE" nim-serve --max-model-len 8192 >/dev/null

RESULT=timeout
for i in $(seq 1 30); do
  if curl -fs "http://localhost:${NIM_PORT:-8000}/v1/models" >/dev/null 2>&1; then
    RESULT=loaded; break
  fi
  if ! docker ps --format '{{.Names}}' | grep -qx "$NAME"; then
    RESULT=crashed; break
  fi
  sleep 10
done
docker logs "$NAME" > "$OUT/$SAFE.serve.log" 2>&1 || true
docker rm -f "$NAME" >/dev/null 2>&1 || true

echo "result: $RESULT" | tee -a "$OUT/context.txt"
echo
echo "== step 3: the comparison that makes this a finding, not a complaint =="
cat <<EOF
Now run the SAME two steps against a model NIM fully supports, so you can put a
number on the gap rather than asserting one:

  MODEL=meta-llama/Llama-3.1-8B-Instruct bash nim/10_list_profiles.sh
  MODEL=$APERTUS10_8B                    bash nim/10_list_profiles.sh

That gives three data points for the report:
  * Llama 3.1 8B  -> optimized TRT-LLM profile exists
  * Apertus 1.0   -> no TRT-LLM profile (xIELU), vLLM/SGLang fallback
  * Apertus 1.5   -> $RESULT

Evidence saved under $OUT/
Then serve 1.5 properly with: bash serve/15_serve_v15.sh
EOF
