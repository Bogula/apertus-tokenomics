#!/usr/bin/env bash
# 01_login.sh - authenticate to NGC and pre-pull images/weights.
# Run this while you are still writing your plan; it is the long pole.
set -euo pipefail
cd "$(dirname "$0")/.."
# shellcheck source=/dev/null
source .env

echo "== docker login nvcr.io =="
echo "$NGC_API_KEY" | docker login nvcr.io --username '$oauthtoken' --password-stdin

echo "== pulling NIM image: $NIM_IMAGE =="
docker pull "$NIM_IMAGE"

mkdir -p "$CACHE_DIR" "$HF_HOME" "$ARTIFACTS_DIR"
chmod -R a+w "$CACHE_DIR" || true

echo "== pre-downloading Apertus-8B weights (~16 GB) =="
pip install -q --upgrade "huggingface_hub[cli]"
hf download "$APERTUS_8B" --local-dir "$HF_HOME/$(basename "$APERTUS_8B")" \
  ${HF_TOKEN:+--token "$HF_TOKEN"}

cat <<'EOF'

Done. Optional, start it now in a second terminal if you are going for 70B:

  hf download swiss-ai/Apertus-70B-Instruct-2509 \
      --local-dir "$HF_HOME/Apertus-70B-Instruct-2509"

~140 GB. Check disk first.
EOF
