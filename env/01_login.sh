#!/usr/bin/env bash
# 01_login.sh - authenticate, pull images, pre-fetch weights.
# The long pole. Start it while you are still writing your plan.
set -euo pipefail
cd "$(dirname "$0")/.."
# shellcheck source=/dev/null
source .env

echo "== 0. Apertus 1.5 gate check (fails loudly if the AUP is not accepted) =="
pip install -q --upgrade "huggingface_hub[cli,hf_transfer]"
for M in "$APERTUS15_8B" "$APERTUS15_70B"; do
  if hf download "$M" --include config.json --quiet ${HF_TOKEN:+--token "$HF_TOKEN"} >/dev/null 2>&1; then
    echo "  [ok]   $M accessible"
  else
    echo "  [FAIL] $M not accessible."
    echo "         Log in to huggingface.co, open https://huggingface.co/$M ,"
    echo "         click Agree on the Acceptable Use Policy, then re-check HF_TOKEN."
    exit 1
  fi
done

echo
echo "== 1. Swiss AI vLLM fork (required - upstream vLLM lacks apertus1p5) =="
docker pull "$APERTUS15_VLLM_IMAGE"

echo
echo "== 2. NGC login + NIM image (for the Apertus 1.0 reference leg) =="
echo "$NGC_API_KEY" | docker login nvcr.io --username '$oauthtoken' --password-stdin
docker pull "$NIM_IMAGE" || echo "  (NIM pull failed - the 1.5 legs do not need it)"

mkdir -p "$CACHE_DIR" "$HF_HOME" "$ARTIFACTS_DIR"
chmod -R a+w "$CACHE_DIR" || true

echo
echo "== 3. pre-download Apertus-v1.5-8B (~18 GB) =="
export HF_HUB_ENABLE_HF_TRANSFER=1
hf download "$APERTUS15_8B" ${HF_TOKEN:+--token "$HF_TOKEN"}

echo
echo "== 4. Swisscom hosted endpoint reachability =="
if [ "${SWISSCOM_API_KEY:-CHANGE_ME}" != "CHANGE_ME" ]; then
  code=$(curl -s -o /dev/null -w '%{http_code}' -X POST "$SWISSCOM_BASE_URL/chat/completions" \
    -H "Authorization: Bearer $SWISSCOM_API_KEY" -H 'Content-Type: application/json' \
    -d "{\"model\":\"$SWISSCOM_MODEL\",\"max_tokens\":5,\"messages\":[{\"role\":\"user\",\"content\":\"hi\"}]}")
  case "$code" in
    200) echo "  [ok]   endpoint answered 200" ;;
    401|403) echo "  [FAIL] $code - key invalid or EXPIRED (bearer lives 60 min). Refresh it." ;;
    *) echo "  [warn] http $code" ;;
  esac
else
  echo "  [skip] SWISSCOM_API_KEY not set - get one from The Keymaker"
fi

cat <<EOF

Done. If you are going for the 70B leg, start this now in another terminal
(~140 GB, and it is the thing most likely to eat your session):

  HF_HUB_ENABLE_HF_TRANSFER=1 hf download $APERTUS15_70B

Check disk first: env/00_env_check.sh reports free space.
EOF
