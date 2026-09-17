#!/usr/bin/env bash
# 33_build_apertus_image.sh - make Dynamo able to serve Apertus 1.5.
#
# Dynamo's vLLM backend runs ITS OWN vLLM. That vLLM does not know `apertus1p5`,
# so the stock Dynamo runtime image cannot load Apertus 1.5 any more than NIM
# can. The fix is to install the Dynamo Python runtime INTO the Swiss AI vLLM
# fork image, so Dynamo's worker imports the patched vLLM.
#
# This is a real engineering task, and documenting it is part of the challenge's
# "what does it take to operate AI efficiently in the real world" question.
# Budget an hour, and only after the NIM and vLLM legs are written up.
set -euo pipefail
cd "$(dirname "$0")/.."
# shellcheck source=/dev/null
source .env

TAG="${TAG:-dynamo-apertus15:local}"
BUILD_DIR="$(mktemp -d)"
trap 'rm -rf "$BUILD_DIR"' EXIT

cat > "$BUILD_DIR/Dockerfile" <<EOF
# Start from the Swiss AI fork so the patched vLLM (apertus1p5) is what gets imported.
FROM $APERTUS15_VLLM_IMAGE

# Dynamo's Python runtime. --no-deps on vllm keeps pip from "helpfully" replacing
# the forked vLLM with an upstream wheel, which would undo the whole point.
RUN pip install --no-cache-dir --prerelease=allow \\
        "ai-dynamo[vllm]" --extra-index-url https://pypi.nvidia.com \\
    || pip install --no-cache-dir "ai-dynamo[vllm]" --extra-index-url https://pypi.nvidia.com

# Verify the fork survived the install.
RUN python3 -c "import vllm, importlib; \\
    from vllm.model_executor.models.registry import ModelRegistry as R; \\
    archs=[a for a in R.get_supported_archs() if 'pertus' in a]; \\
    print('vllm', vllm.__version__, 'apertus archs:', archs); \\
    assert archs, 'FORK LOST: upstream vLLM replaced the patched build'"
RUN python3 -c "import dynamo; print('dynamo ok')"
EOF

echo "== building $TAG on top of $APERTUS15_VLLM_IMAGE =="
docker build -t "$TAG" "$BUILD_DIR"

cat <<EOF

Built: $TAG

Run the Dynamo scripts inside it, e.g.:

  docker run --gpus all --network host --ipc=host --rm -it \\
    -v "\$HF_HOME:/root/.cache/huggingface" -e HF_TOKEN="\$HF_TOKEN" \\
    -v "\$PWD:/work" -w /work $TAG bash

  # then, inside:
  REPLICAS=2 ROUTER=kv bash dynamo/31_agg.sh
  PREFILL=1 DECODE=1 ROUTER=kv bash dynamo/32_disagg.sh

Pass the 1.5 serving flags through EXTRA_ARGS so the workers match the standalone
server you benchmarked - otherwise the comparison is meaningless:

  EXTRA_ARGS="--chat-template-content-format string --enable-auto-tool-choice --tool-call-parser apertus"

If the build's verification step fails, the fork was overwritten. Pin the fork's
vLLM wheel or install ai-dynamo with --no-deps and add its own requirements by
hand. If it cannot be made to work in the time you have, that is a legitimate
finding too - record which layer blocked you and move on. A clean NIM+vLLM study
beats a broken Dynamo demo.
EOF
