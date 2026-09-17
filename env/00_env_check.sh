#!/usr/bin/env bash
# 00_env_check.sh - run this FIRST, within 15 minutes of getting your LaunchPad box.
# Everything you plan for the next 24h depends on what this prints.
set -uo pipefail

ok()   { printf '  \033[32m[ok]\033[0m   %s\n' "$*"; }
warn() { printf '  \033[33m[warn]\033[0m %s\n' "$*"; }
bad()  { printf '  \033[31m[FAIL]\033[0m %s\n' "$*"; }
hdr()  { printf '\n\033[1m== %s ==\033[0m\n' "$*"; }

OUT="${ARTIFACTS_DIR:-./artifacts}/env"
mkdir -p "$OUT"

hdr "GPUs"
if command -v nvidia-smi >/dev/null 2>&1; then
  nvidia-smi --query-gpu=index,name,memory.total,driver_version,compute_cap \
             --format=csv | tee "$OUT/gpus.csv"
  NGPU=$(nvidia-smi --list-gpus | wc -l)
  MEM=$(nvidia-smi --query-gpu=memory.total --format=csv,noheader,nounits | head -1)
  ok "$NGPU GPU(s), ${MEM} MiB each"
  TOTAL=$(( NGPU * MEM / 1024 ))
  echo "  total GPU memory: ~${TOTAL} GB"
  if   [ "$TOTAL" -ge 320 ]; then ok  "70B in bf16 is comfortable (TP=${NGPU})"
  elif [ "$TOTAL" -ge 160 ]; then warn "70B bf16 is tight - plan FP8/INT4 or short max-model-len"
  elif [ "$TOTAL" -ge 40  ]; then warn "8B only in bf16; 70B needs quantization and will be slow"
  else bad "under 40 GB - 8B may need FP8 too"; fi
else
  bad "no nvidia-smi - wrong node, or driver not loaded"
fi

hdr "GPU interconnect (decides whether TP>1 is worth it)"
nvidia-smi topo -m 2>/dev/null | tee "$OUT/topo.txt" || warn "topo unavailable"
echo "  NV# = NVLink (good for TP). PIX/PHB/SYS = PCIe (TP scales poorly, prefer replicas)."

hdr "Container runtime"
if command -v docker >/dev/null 2>&1; then
  ok "docker $(docker --version | awk '{print $3}' | tr -d ,)"
  if docker run --rm --gpus all ubuntu:22.04 nvidia-smi -L >/dev/null 2>&1; then
    ok "docker can see GPUs (nvidia-container-toolkit working)"
  else
    bad "docker cannot see GPUs - try 'sudo nvidia-ctk runtime configure --runtime=docker && sudo systemctl restart docker'"
  fi
else
  warn "no docker - check for enroot/podman/pyxis on this image"
fi

hdr "Disk"
df -h "${HOME}" "${CACHE_DIR:-$HOME}" 2>/dev/null | tee "$OUT/disk.txt"
AVAIL=$(df -BG --output=avail "${HOME}" | tail -1 | tr -dc '0-9')
if [ "${AVAIL:-0}" -lt 60 ]; then
  bad "only ${AVAIL}G free - 70B weights alone are ~140 GB. Find a scratch mount NOW."
elif [ "${AVAIL:-0}" -lt 200 ]; then
  warn "${AVAIL}G free - enough for 8B + engines, not for 70B bf16"
else
  ok "${AVAIL}G free"
fi

hdr "Network egress (you will pull ~20-160 GB)"
START=$(date +%s)
curl -sL -o /dev/null -w '  huggingface.co: %{speed_download} B/s, http %{http_code}\n' \
  --max-time 15 "https://huggingface.co/swiss-ai/Apertus-v1.5-8B/resolve/main/config.json" \
  || warn "cannot reach huggingface.co - check proxy"
curl -sL -o /dev/null -w '  nvcr.io:        http %{http_code}\n' --max-time 15 "https://nvcr.io/v2/" \
  || warn "cannot reach nvcr.io"
echo "  probe took $(( $(date +%s) - START ))s"

hdr "Credentials"
[ -n "${NGC_API_KEY:-}" ] && [ "${NGC_API_KEY}" != "nvapi-CHANGE_ME" ] \
  && ok "NGC_API_KEY set" || bad "NGC_API_KEY missing - see env/.env.example"
[ -n "${HF_TOKEN:-}" ] && [ "${HF_TOKEN}" != "hf_CHANGE_ME" ] \
  && ok "HF_TOKEN set" || warn "HF_TOKEN missing (ok, but you may get rate-limited)"

hdr "CPU / RAM (matters for weight loading and CPU-offload KV)"
{ nproc; free -g | head -2; } | tee "$OUT/cpu.txt"

hdr "Summary written to $OUT"
echo "Record NGPU, GPU model, interconnect and hourly list price - the tokenomics"
echo "study needs all four. Put them in docs/FINDINGS.md before you touch NIM."
