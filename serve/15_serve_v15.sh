#!/usr/bin/env bash
# 15_serve_v15.sh - THE canonical way to serve Apertus 1.5.
#
# Uses the Swiss AI vLLM fork, because upstream vLLM does not know the
# `apertus1p5` architecture yet. Flags follow the model card exactly; every knob
# is an env var so the sweep can restart in a new configuration.
#
# Usage:
#   serve/15_serve_v15.sh                                    # 8B, TP=1, 8k ctx
#   MODEL=$APERTUS15_70B TP_SIZE=4 GPU_MEM_UTIL=0.8 serve/15_serve_v15.sh
#   MAX_MODEL_LEN=262144 RUN_TAG=v15-8b-fullctx serve/15_serve_v15.sh
#   ENABLE_THINKING=1 RUN_TAG=v15-8b-thinking serve/15_serve_v15.sh
set -euo pipefail
cd "$(dirname "$0")/.."
# shellcheck source=/dev/null
source .env

MODEL="${MODEL:-$APERTUS15_8B}"
TP_SIZE="${TP_SIZE:-1}"
MAX_MODEL_LEN="${MAX_MODEL_LEN:-8192}"
GPU_MEM_UTIL="${GPU_MEM_UTIL:-0.6}"
PORT="${NIM_PORT:-8000}"
ENABLE_THINKING="${ENABLE_THINKING:-0}"
RUN_TAG="${RUN_TAG:-$(basename "$MODEL")-tp${TP_SIZE}-len${MAX_MODEL_LEN}$([ "$ENABLE_THINKING" = 1 ] && echo -think)}"
NAME="apertus15-${RUN_TAG}"
LOGD="$ARTIFACTS_DIR/serve"; mkdir -p "$LOGD"

ARGS=(
  serve "$MODEL"
  --served-model-name apertus
  # REQUIRED: the 1.5 chat template expects string content, not content-parts.
  --chat-template-content-format string
  --tensor-parallel-size "$TP_SIZE"
  --gpu-memory-utilization "$GPU_MEM_UTIL"
  --max-model-len "$MAX_MODEL_LEN"
  --enable-auto-tool-choice
  --tool-call-parser apertus          # model-specific parser, fork-only
  --host 0.0.0.0 --port "$PORT"
)

# Documented known issue: CUDA graph capture can fail with TP>1 because of the
# fused all-reduce RMS optimization. Pre-emptively disable it rather than
# debugging a cryptic capture error at 2am.
if [ "$TP_SIZE" -gt 1 ]; then
  ARGS+=(--compilation-config.pass_config.fuse_allreduce_rms false)
fi

# Thinking mode is OFF by default in 1.5. Turning it on multiplies the tokens
# you pay for - measure it, don't leave it on by accident. See bench/24_thinking_tax.py.
if [ "$ENABLE_THINKING" = 1 ]; then
  ARGS+=(--reasoning-parser apertus
         --default-chat-template-kwargs.enable_thinking true)
fi

# shellcheck disable=SC2206
[ -n "${EXTRA_ARGS:-}" ] && ARGS+=(${EXTRA_ARGS})

docker rm -f "$NAME" >/dev/null 2>&1 || true
echo "== $NAME =="
echo "   image=$APERTUS15_VLLM_IMAGE"
echo "   model=$MODEL tp=$TP_SIZE len=$MAX_MODEL_LEN util=$GPU_MEM_UTIL thinking=$ENABLE_THINKING"

docker run -d --name "$NAME" --gpus all \
  --shm-size=32GB --network=host --ipc=host \
  -v "$HF_HOME:/root/.cache/huggingface" \
  -e HF_TOKEN="$HF_TOKEN" \
  -e HF_HUB_ENABLE_HF_TRANSFER=1 \
  "$APERTUS15_VLLM_IMAGE" \
  vllm "${ARGS[@]}"

echo "== waiting for :$PORT (first run downloads weights) =="
for i in $(seq 1 180); do
  if curl -fs "http://localhost:$PORT/v1/models" >/dev/null 2>&1; then
    echo "   ready after ${i}0s"
    docker logs "$NAME" > "$LOGD/$RUN_TAG.log" 2>&1
    echo "$RUN_TAG" > "$LOGD/CURRENT"
    exit 0
  fi
  sleep 10
  [ "$((i % 6))" -eq 0 ] && echo "   ...${i}0s"
done

echo "TIMED OUT. Last 60 lines:"
docker logs --tail 60 "$NAME"
docker logs "$NAME" > "$LOGD/$RUN_TAG.log" 2>&1
cat <<'EOF'

Checklist:
  * 401 / gated repo  -> accept the AUP on huggingface.co for BOTH v1.5 repos
                         while logged in, then re-check HF_TOKEN.
  * OOM at startup    -> lower MAX_MODEL_LEN first (262144 KV is enormous),
                         then GPU_MEM_UTIL, then raise TP_SIZE.
  * CUDA graph error  -> already handled for TP>1; if it still fails, add
                         EXTRA_ARGS="--enforce-eager" to isolate.
  * unknown arch      -> you are not on the fork image. Check APERTUS15_VLLM_IMAGE.
EOF
exit 1
