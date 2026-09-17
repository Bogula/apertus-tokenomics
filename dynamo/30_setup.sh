#!/usr/bin/env bash
# 30_setup.sh - stand up the Dynamo control plane.
#
# Only start this phase once Phase 1-3 are DONE and written up. Dynamo is the
# stretch goal; a complete NIM tokenomics study beats a half-working disagg demo.
#
# Dynamo needs a discovery backend. Two options:
#   * etcd + NATS via docker compose  (the documented path, needed for KV routing)
#   * --discovery-backend file        (single-node shortcut, fewer moving parts)
set -euo pipefail
cd "$(dirname "$0")/.."
# shellcheck source=/dev/null
source .env

MODE="${1:-compose}"   # compose | file

if [ ! -d dynamo/.src ]; then
  git clone --depth 1 https://github.com/ai-dynamo/dynamo.git dynamo/.src
fi

case "$MODE" in
compose)
  ( cd dynamo/.src && docker compose -f deploy/docker-compose.yml up -d )
  echo "etcd + NATS up. Verify:"
  curl -fs http://localhost:2379/health && echo " etcd ok"
  ;;
file)
  echo "using --discovery-backend file; nothing to start"
  ;;
esac

echo
echo "Install the Python runtime (pick the backend that actually serves Apertus):"
echo "  uv pip install --prerelease=allow 'ai-dynamo[vllm]'"
echo "  # or run inside: docker run --gpus all --network host --rm -it $DYNAMO_IMAGE"
