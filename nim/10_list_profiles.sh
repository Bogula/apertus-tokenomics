#!/usr/bin/env bash
# 10_list_profiles.sh - THE most important 5 minutes of this challenge.
#
# NIM inspects the checkpoint, matches architecture + quantization + your GPUs,
# and emits a list of "model profiles". Each profile is a (backend, precision,
# TP, GPU) tuple. Apertus uses the xIELU activation and is NOT in the
# TensorRT-LLM supported-model list, so expect vLLM or SGLang profiles, not a
# TRT-LLM one. Capture that output - it is a finding, not a failure.
set -euo pipefail
cd "$(dirname "$0")/.."
# shellcheck source=/dev/null
source .env

MODEL="${1:-$APERTUS_8B}"
OUT="$ARTIFACTS_DIR/profiles"
mkdir -p "$OUT"
SAFE=$(echo "$MODEL" | tr '/' '_')

docker run --rm --gpus all --shm-size=16GB --network=host \
  -u "$(id -u)" \
  -v "$CACHE_DIR:/opt/nim/.cache" \
  -e HF_TOKEN="$HF_TOKEN" \
  "$NIM_IMAGE" list-model-profiles --model "hf://$MODEL" \
  2>&1 | tee "$OUT/$SAFE.txt"

cat <<EOF

--------------------------------------------------------------------------
Read $OUT/$SAFE.txt and answer these three questions in docs/FINDINGS.md:

  1. Which backend did NIM select?  (trtllm | vllm | sglang)
  2. Is there a TRT-LLM profile at all? If not, say WHY in the report:
     Apertus's xIELU activation has no TensorRT-LLM kernel, so the
     "NIM = TensorRT-LLM speedup" assumption does not hold for this model.
     Quantifying that gap IS the interesting result.
  3. Which profile hash will you pin with NIM_MODEL_PROFILE for reproducible runs?
--------------------------------------------------------------------------
EOF
