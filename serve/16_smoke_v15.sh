#!/usr/bin/env bash
# 16_smoke_v15.sh - prove the 1.5 endpoint really is 1.5 before benchmarking it.
# Checks text, multilingual, tool calling, thinking markers and image input -
# the four things that distinguish 1.5 from 1.0 and are easy to silently lose.
set -euo pipefail
cd "$(dirname "$0")/.."
# shellcheck source=/dev/null
source .env
BASE="http://localhost:${NIM_PORT:-8000}/v1"
J() { python3 -m json.tool 2>/dev/null || cat; }

echo "== 1. models =="
curl -s "$BASE/models" | J

echo
echo "== 2. arithmetic (quality gate - rerun after every quantization change) =="
curl -s "$BASE/chat/completions" -H 'Content-Type: application/json' -d '{
 "model":"apertus","max_tokens":10,"temperature":0,
 "messages":[{"role":"user","content":"What is 17*23? Reply with only the number."}]}' \
 | python3 -c 'import sys,json;print("  ->",json.load(sys.stdin)["choices"][0]["message"]["content"].strip(),"(expect 391)")'

echo
echo "== 3. multilingual (Apertus natively covers 1811 languages - use it) =="
curl -s "$BASE/chat/completions" -H 'Content-Type: application/json' -d '{
 "model":"apertus","max_tokens":80,"temperature":0.2,
 "messages":[{"role":"user","content":"Antworte auf Schweizerdeutsch: Was macht Apertus besonders?"}]}' \
 | python3 -c 'import sys,json;print("  ->",json.load(sys.stdin)["choices"][0]["message"]["content"].strip()[:300])'

echo
echo "== 4. tool calling (needs --enable-auto-tool-choice --tool-call-parser apertus) =="
curl -s "$BASE/chat/completions" -H 'Content-Type: application/json' -d '{
 "model":"apertus","max_tokens":200,"temperature":0,
 "messages":[{"role":"user","content":"What is the weather in Zurich right now?"}],
 "tools":[{"type":"function","function":{"name":"get_weather",
   "description":"Get current weather for a city",
   "parameters":{"type":"object","properties":{"city":{"type":"string"}},"required":["city"]}}}],
 "tool_choice":"auto"}' \
 | python3 -c '
import sys,json
m=json.load(sys.stdin)["choices"][0]["message"]
tc=m.get("tool_calls")
print("  -> tool_calls:", json.dumps(tc)[:250] if tc else "NONE - parser flag missing or model declined")'

echo
echo "== 5. thinking mode (only if served with ENABLE_THINKING=1) =="
curl -s "$BASE/chat/completions" -H 'Content-Type: application/json' -d '{
 "model":"apertus","max_tokens":2048,"temperature":0.3,
 "messages":[{"role":"user","content":"A bat and a ball cost 1.10 CHF together. The bat costs 1 CHF more than the ball. What does the ball cost?"}]}' \
 | python3 -c '
import sys,json
d=json.load(sys.stdin)
m=d["choices"][0]["message"]
txt=(m.get("content") or "")
rc=m.get("reasoning_content")
u=d.get("usage",{})
print("  -> reasoning_content present:", bool(rc))
print("  -> inner markers in text:", "<|inner_prefix|>" in txt)
print("  -> completion_tokens:", u.get("completion_tokens"), "| answer chars:", len(txt))
print("  -> answer:", txt.strip()[-160:])
print("  NOTE: expect 0.05 CHF. If completion_tokens is large but the answer is")
print("        empty, you truncated mid-reasoning - raise max_tokens.")'

echo
echo "== 6. image input (1.5 is multimodal; 1.0 is not) =="
curl -s "$BASE/chat/completions" -H 'Content-Type: application/json' -d '{
 "model":"apertus","max_tokens":80,"temperature":0,
 "messages":[{"role":"user","content":[
   {"type":"text","text":"Describe this image in one sentence."},
   {"type":"image_url","image_url":{"url":"https://cdn.britannica.com/61/93061-050-99147DCE/Statue-of-Liberty-Island-New-York-Bay.jpg"}}]}]}' \
 | python3 -c '
import sys,json
d=json.load(sys.stdin)
if "error" in d: print("  -> ERROR:", str(d["error"])[:200])
else: print("  ->", d["choices"][0]["message"]["content"].strip()[:250])'

echo
echo "Done. If 4/5/6 fail, you are serving without the right flags - or you are"
echo "accidentally serving Apertus 1.0. Check serve/15_serve_v15.sh."
