#!/usr/bin/env bash
# 20_install.sh - benchmark client. AIPerf is the current NVIDIA LLM load
# generator (successor to genai-perf); it speaks the OpenAI chat API, so it
# works identically against NIM, vanilla vLLM, Dynamo, and a cloud endpoint.
# That last point is what makes the tokenomics comparison apples-to-apples.
set -euo pipefail
python3 -m pip install -q --upgrade pip
python3 -m pip install -q aiperf
aiperf --version || true
echo "ok - 'aiperf profile --help' for the full flag list"
