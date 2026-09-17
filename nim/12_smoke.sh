#!/usr/bin/env bash
# 12_smoke.sh - prove the endpoint is real before burning GPU-hours benchmarking it.
set -euo pipefail
cd "$(dirname "$0")/.."
# shellcheck source=/dev/null
source .env
PORT="${NIM_PORT:-8000}"
BASE="http://localhost:$PORT"

echo "== models =="
curl -s "$BASE/v1/models" | python3 -m json.tool

echo
echo "== chat completion (German + French, Apertus is multilingual - check it) =="
curl -s "$BASE/v1/chat/completions" -H 'Content-Type: application/json' -d '{
  "model": "apertus",
  "messages": [{"role":"user","content":"Erkläre in zwei Sätzen, was Tokenomics bei LLM-Inferenz bedeutet. Antworte auf Deutsch."}],
  "max_tokens": 120, "temperature": 0.2
}' | python3 -m json.tool

echo
echo "== streaming TTFT sanity check =="
python3 - "$BASE" <<'PY'
import json,sys,time,urllib.request
base=sys.argv[1]
req=urllib.request.Request(base+"/v1/chat/completions",
  data=json.dumps({"model":"apertus","stream":True,"max_tokens":64,
    "messages":[{"role":"user","content":"Count from 1 to 40."}]}).encode(),
  headers={"Content-Type":"application/json"})
t0=time.time(); first=None; n=0
for line in urllib.request.urlopen(req):
    if line.startswith(b"data: ") and b"[DONE]" not in line:
        if first is None: first=time.time()-t0
        n+=1
dt=time.time()-t0
print(f"TTFT ~ {first*1000:.0f} ms | {n} chunks | {dt:.2f} s | ~{n/max(dt-first,1e-9):.1f} tok/s single-stream")
PY

echo
echo "== quality guard: does it still speak sense? =="
curl -s "$BASE/v1/chat/completions" -H 'Content-Type: application/json' -d '{
  "model":"apertus",
  "messages":[{"role":"user","content":"What is 17*23? Reply with only the number."}],
  "max_tokens":10,"temperature":0
}' | python3 -c 'import sys,json; print("answer:", json.load(sys.stdin)["choices"][0]["message"]["content"].strip(), "(expect 391)")'

echo
echo "Run this again after EVERY quantization change. A config that is 3x faster"
echo "and wrong is not a result - the judges will ask."
