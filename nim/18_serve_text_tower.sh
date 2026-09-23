#!/usr/bin/env bash
# 18_serve_text_tower.sh - Apertus 1.5 8B (Text-Tower) unter NIM auf einer H100.
#
#   bash nim/18_serve_text_tower.sh                 # baut bei Bedarf und startet
#   SKIP_BUILD=1 bash nim/18_serve_text_tower.sh    # Ordner existiert schon
#   bash nim/18_serve_text_tower.sh profiles        # nur Profile auflisten
#
# Der Unterschied zu 11_serve.sh, und warum es ein eigenes Skript ist:
#
#   * Es laeuft ueber MODEL-FREE NIM, nicht ueber das llm-nim-Image. Bei
#     Model-Free NIM waehlt das IMAGE das Backend - nicht eine Umgebungs-
#     variable: model-free-nim ist vLLM, sglang-model-free-nim ist SGLang.
#     Das ist der Hebel, den wir brauchen: TensorRT-LLM kennt weder Apertus
#     noch xIELU, vLLM upstream beides.
#   * Die Gewichte kommen aus einem lokalen Ordner ueber NIM_MODEL_PATH
#     (nicht NIM_MODEL_NAME), weil der Text-Tower erst erzeugt werden muss.
#   * NIM_MODEL_PROFILE steuert hier Parallelitaet und LoRA, nicht das
#     Backend. Welche Werte es gibt, sagt `profiles`.
set -euo pipefail
cd "$(dirname "$0")/.."
# shellcheck source=/dev/null
source .env

SRC_DIR="${SRC_DIR:-$HOME/models/Apertus-v1.5-8B}"
MODEL_DIR="${MODEL_DIR:-$HOME/models/apertus15-8b-text}"
MF_IMAGE="${MF_IMAGE:-nvcr.io/nim/nvidia/model-free-nim:latest}"
TP_SIZE="${TP_SIZE:-1}"
MAX_MODEL_LEN="${MAX_MODEL_LEN:-8192}"
MAX_NUM_SEQS="${MAX_NUM_SEQS:-256}"
NIM_PORT="${NIM_PORT:-8000}"

# Maschine gehoert in den Tag. results.csv schluesselt auf `system`; laufen
# Spark- und H100-Zeilen unter demselben Tag zusammen, sieht die CSV plausibel
# aus und der Vergleich ist still kaputt.
ARCH="$(uname -m)"
MACHINE="${MACHINE:-$([ "$ARCH" = "aarch64" ] && echo spark || echo h100)}"

# Unified Memory auf GB10: die GPU teilt sich die 128 GB mit dem Host. 0.90
# wuerde dem System den Speicher wegnehmen. Die Modellkarte nennt 0.6 fuer das
# 8B, und deine .env benutzt das fuer die Fork auch - also gleiche Basis.
if [ "$ARCH" = "aarch64" ]; then
  GPU_MEM_UTIL="${GPU_MEM_UTIL:-0.60}"
else
  GPU_MEM_UTIL="${GPU_MEM_UTIL:-0.90}"
fi

RUN_TAG="${RUN_TAG:-nim-mf-vllm-8b-text-${MACHINE}-tp${TP_SIZE}-len${MAX_MODEL_LEN}-seqs${MAX_NUM_SEQS}}"
NAME="nim-${RUN_TAG}"
OUT="$ARTIFACTS_DIR/nim-text-tower"; mkdir -p "$OUT" "$ARTIFACTS_DIR/serve"

# --- 0. Cache-Rechte -------------------------------------------------------
# NIM laeuft im Container als UID 1000, GID 0 und will in /opt/nim/.cache
# schreiben. Gehoert der Host-Ordner dir allein mit 0755, scheitert das mit
# "not accessible by the container user" - noch bevor irgendein Modell geladen
# wird. GID 0 statt chmod 777, damit der Ordner nicht weltweit schreibbar wird.
mkdir -p "$CACHE_DIR"
if ! docker run --rm -u "$(id -u):0" -v "$CACHE_DIR:/opt/nim/.cache" \
     "$MF_IMAGE" bash -c 'test -w /opt/nim/.cache && test -x /opt/nim/.cache' \
     >/dev/null 2>&1; then
  echo "== Cache-Ordner ist fuer den Container nicht schreibbar, korrigiere =="
  echo "   $CACHE_DIR  ->  Gruppe 0, g+rwX"
  sudo chgrp -R 0 "$CACHE_DIR"
  sudo chmod -R g+rwX "$CACHE_DIR"
fi

# --- 1. Text-Tower erzeugen -------------------------------------------------
if [ "${1:-}" != "profiles" ] && [ "${SKIP_BUILD:-0}" != "1" ]; then
  if [ ! -f "$MODEL_DIR/config.json" ]; then
    if [ ! -f "$SRC_DIR/config.json" ]; then
      echo "== lade Original-Checkpoint (gated, HF_TOKEN noetig) =="
      huggingface-cli download "$APERTUS15_8B" --local-dir "$SRC_DIR"
    fi
    echo "== erzeuge Text-Tower =="
    python3 nim/17_text_tower_for_nim.py --src "$SRC_DIR" --dst "$MODEL_DIR"
  else
    echo "== $MODEL_DIR existiert, ueberspringe Bau =="
  fi

  # Gegenprobe: genau diese drei Werte entscheiden, ob upstream vLLM das
  # Modell annimmt. Lieber hier scheitern als nach dem Image-Pull.
  python3 - "$MODEL_DIR" <<'PY'
import json, sys
c = json.load(open(f"{sys.argv[1]}/config.json"))
ok = (c.get("model_type") == "apertus"
      and c.get("architectures") == ["ApertusForCausalLM"]
      and c.get("vocab_size") == 131072
      and c.get("hidden_act") == "xielu"
      and "rope_scaling" in c)
print(f"  model_type={c.get('model_type')} arch={c.get('architectures')} "
      f"vocab={c.get('vocab_size')} act={c.get('hidden_act')} "
      f"rope_scaling={'ja' if 'rope_scaling' in c else 'NEIN'}")
sys.exit(0 if ok else "  config.json passt nicht zu upstream vLLM - abgebrochen")
PY
fi

# --- 1b. Passt das Image zur Architektur? -----------------------------------
# Auf dem Spark (aarch64) ist das die erste Huerde: viele NIM-Images gibt es
# nur fuer amd64. Das vorher zu wissen spart einen langen Pull ins Leere.
echo "== Architektur-Gegenprobe: Host ist $ARCH =="
if docker manifest inspect "$MF_IMAGE" >/dev/null 2>&1; then
  docker manifest inspect "$MF_IMAGE" \
    | grep -o '"architecture": *"[^"]*"' | sort -u | sed 's/^/   /' \
    | tee "$OUT/image-arch.txt"
  if [ "$ARCH" = "aarch64" ] && ! grep -q "arm64" "$OUT/image-arch.txt"; then
    echo
    echo "   Das Image hat kein arm64. Auf dem Spark laeuft es nicht."
    echo "   Das ist ein Studienbefund fuer Leg A - mit diesem Log belegen."
    echo "   Alternativen: NGC nach einem arm64-Tag durchsuchen, oder diesen"
    echo "   Lauf auf x86 verschieben und den Spark-Vergleich streichen."
    exit 1
  fi
else
  echo "   (manifest nicht abfragbar - evtl. docker login nvcr.io noetig)"
fi

# --- 2. Profile auflisten ---------------------------------------------------
echo "== verfuegbare Profile fuer diesen Ordner =="
docker run --rm --gpus all --shm-size=16GB -u "$(id -u):0" \
  -v "$CACHE_DIR:/opt/nim/.cache" \
  -v "$MODEL_DIR:/model:ro" \
  -e NIM_MODEL_PATH=/model \
  "$MF_IMAGE" list-model-profiles 2>&1 | tee "$OUT/profiles.txt" || true

if [ "${1:-}" = "profiles" ]; then
  echo
  echo "Profil waehlen und dann:  NIM_MODEL_PROFILE=<id> bash nim/18_serve_text_tower.sh"
  exit 0
fi

# --- 3. Starten -------------------------------------------------------------
docker rm -f "$NAME" >/dev/null 2>&1 || true
LOG="$ARTIFACTS_DIR/serve/$RUN_TAG.log"

# Engine-Argumente werden an vLLM durchgereicht. Nimmt das Image sie nicht an,
# die Entsprechungen als NIM_* Variablen setzen - die Liste steht in
# artifacts/nim-text-tower/profiles.txt bzw. in den NIM-Release-Notes.
ENGINE_ARGS=(
  --max-model-len "$MAX_MODEL_LEN"
  --gpu-memory-utilization "$GPU_MEM_UTIL"
  --max-num-seqs "$MAX_NUM_SEQS"
)
# shellcheck disable=SC2206
[ -n "${EXTRA_ARGS:-}" ] && ENGINE_ARGS+=(${EXTRA_ARGS})

echo "== starte $NAME =="
echo "   image=$MF_IMAGE  model=$MODEL_DIR  tp=$TP_SIZE len=$MAX_MODEL_LEN"

docker run -d --name "$NAME" --gpus all \
  --shm-size=16GB --network=host --ipc=host -u "$(id -u):0" \
  -v "$CACHE_DIR:/opt/nim/.cache" \
  -v "$MODEL_DIR:/model:ro" \
  -e NIM_MODEL_PATH=/model \
  -e NIM_SERVED_MODEL_NAME=apertus \
  -e NIM_TENSOR_PARALLEL_SIZE="$TP_SIZE" \
  -e NIM_HTTP_API_PORT="$NIM_PORT" \
  ${NIM_MODEL_PROFILE:+-e NIM_MODEL_PROFILE="$NIM_MODEL_PROFILE"} \
  "$MF_IMAGE" "${ENGINE_ARGS[@]}"

echo "== warte auf /v1/health/ready =="
for i in $(seq 1 180); do
  if curl -fs "http://localhost:$NIM_PORT/v1/health/ready" >/dev/null 2>&1; then
    echo "   bereit nach ${i}0s"
    docker logs "$NAME" > "$LOG" 2>&1
    echo "$RUN_TAG" > "$ARTIFACTS_DIR/serve/CURRENT"
    echo
    echo "Rauchtest:"
    curl -s "http://localhost:$NIM_PORT/v1/chat/completions" \
      -H 'Content-Type: application/json' \
      -d '{"model":"apertus","max_tokens":80,"temperature":0,
           "messages":[{"role":"user","content":"Erkläre in zwei Sätzen, was ein Synchrotron ist."}]}' \
      | tee "$OUT/smoke.json"
    echo
    echo "Dann sweepen:  SYSTEM=$RUN_TAG bash bench/21_sweep.sh all"
    exit 0
  fi
  sleep 10
  [ "$((i % 6))" -eq 0 ] && echo "   ...${i}0s"
done

echo "ZEITUEBERSCHREITUNG. Letzte 60 Zeilen:"
docker logs --tail 60 "$NAME"
docker logs "$NAME" > "$LOG" 2>&1
cat <<'MSG'

Haeufige Ursachen:
  * "ApertusForCausalLM not supported" -> das vLLM im Image ist aelter als
    der Apertus-Merge. Version im Log pruefen; das IST ein Studienbefund.
  * "unknown model_type apertus" -> transformers im Image ist aelter als
    4.56. Gleiche Kategorie.
  * OOM -> --gpu-memory-utilization senken oder --max-model-len kuerzen.
    Ein 8B in bf16 sind ~16 GB Gewichte. Auf einer H100 (80 GB dediziert)
    reichlich Luft; auf dem Spark teilt sich die GPU 128 GB mit dem Host,
    dort zuerst GPU_MEM_UTIL senken, nicht erhoehen.
  * Image akzeptiert die Engine-Argumente nicht -> ohne sie starten und die
    Werte als NIM_* Variablen setzen.
MSG
exit 1

