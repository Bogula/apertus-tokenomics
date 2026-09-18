# Findings — Optimized Apertus 1.5

> Fill this in as you go. A half-written findings doc at hour 20 beats a blank
> one plus perfect logs.

## Environment (Phase 0)

| Item | Value |
|---|---|
| LaunchPad lab / instance | |
| GPU model | |
| GPU count | |
| GPU memory (each / total) | |
| Interconnect (`nvidia-smi topo -m`) | NVLink / PCIe |
| Driver / CUDA | |
| Free disk | |
| Egress throughput | |
| GPU hourly list price (with source URL) | |

## Finding #1 — the frontier lag (Phase 1, leg A)

Evidence in `artifacts/nim-v15-attempt/`.

| model | NIM profile offered | backend | loads? |
|---|---|---|---|
| Llama-3.1-8B-Instruct (reference) | | trtllm? | |
| Apertus-8B-Instruct-2509 (v1.0) | | | |
| **Apertus-v1.5-8B** | | | |

- NIM image tag and build date used:
- Exact error for v1.5:
- Upstream vLLM version bundled in NIM vs version needed for `apertus1p5`:
- **Gap, stated as a number** (weeks between model release and vendor support,
  or "unsupported as of \<date\>"):
- **Implication for anyone running open models in production:**

## Serving configuration (Phase 2, leg B)

- Image: `ghcr.io/swiss-ai/vllm_apertus_1.5_release:` \_\_\_\_
- Flags used:
- Smoke test results: text ☐ multilingual ☐ tool calling ☐ thinking ☐ image ☐

## Baseline (Phase 3)

| system | workload | conc at SLO knee | out tok/s | TTFT p95 | ITL p95 |
|---|---|---:|---:|---:|---:|
| v15-8b-len8k | chat | | | | |
| v15-8b-len8k | rag | | | | |
| v15-8b-len8k | summarize | | | | |
| v15-8b-len8k | agent | | | | |
| v15-8b-len8k | batch | | | | |

## Finding #2 — the price of 262k context (Phase 5)

| `--max-model-len` | max concurrent seqs | out tok/s @ knee | $/1M out |
|---:|---:|---:|---:|
| 8,192 | | | |
| 32,768 | | | |
| 131,072 | | | |
| 262,144 | | | |

Cost multiple from 8k → 262k: \_\_\_×

Takeaway sentence for the slide:

## Finding #3 — the thinking tax (Phase 7)

From `bench/24_thinking_tax.py --compare`:

| | thinking off | thinking on |
|---|---:|---:|
| completion tokens (8 prompts) | | |
| est. visible tokens | | |
| accuracy | | |
| mean latency (s) | | |

- Billed-token multiplier: \_\_\_×
- Multiplier **per visible token**: \_\_\_×
- Accuracy delta: \_\_\_ points
- **Worth it for which workloads, and not for which:**

## Optimization deltas (Phase 5)

One row per single change, always relative to the baseline above.

| change | workload | out tok/s | Δ vs baseline | $/1M out | Δ cost | quality gate |
|---|---|---:|---:|---:|---:|---|
| max-model-len 262k → 8k | | | | | | pass/fail |
| gpu-mem-util 0.6 → 0.8 | | | | | | |
| FP8 (LM only, encoders fp32) | | | | | | multimodal ☐ |
| TP=2 vs 2 replicas | | | | | | |
| prefix caching on | | | | | | |
| max-num-seqs sweep | | | | | | |

**Best config found:**

## Finding #4 — build vs buy, same weights (Phase 6, leg C)

Swisscom hosted Apertus-v1.5-70B vs self-hosted. Caveats to state: network RTT
from LaunchPad, their batching is shared across teams, free tier.

| | self-hosted 70B | Swisscom hosted |
|---|---:|---:|
| out tok/s @ SLO | | |
| TTFT p95 | | |
| $/1M blended | | (free tier / commercial rate: ___) |

- Break-even monthly volume: \_\_\_ M tokens
- Utilization assumption behind that: \_\_\_%
- Quota consumed: \_\_\_ input / \_\_\_ output (of 10M / 2.5M)

## Scaling: 8B vs 70B (Phase 7)

| model | GPUs | precision | out tok/s | $/1M out | $/1M blended |
|---|---:|---|---:|---:|---:|
| Apertus-v1.5-8B | | | | | |
| Apertus-v1.5-70B | | | | | |

Cost ratio 70B/8B: \_\_\_ (parameter ratio ≈ 8×)

Why the ratio differs from 8×:

## Multimodal cost axis (optional but differentiating)

- Audio: 40 tokens/s → 2,400 tokens per minute of speech
- Measured $/minute of audio: \_\_\_
- Versus a dedicated speech API at \_\_\_/min:

## Dynamo (Phase 8, if reached)

Total GPUs held constant at \_\_\_ across all rows.

| topology | workload | out tok/s | TTFT p95 | $/1M blended |
|---|---|---:|---:|---:|
| aggregated (baseline) | rag | | | |
| aggregated + KV router | rag | | | |
| disaggregated 1P+1D | rag | | | |
| disaggregated 1P+2D | rag | | | |

- Did `33_build_apertus_image.sh` succeed? If not, which layer blocked it:
- Optimal prefill:decode ratio vs ISL/OSL:
- Where disaggregation did **not** help, and why:

## Beyond cost

| factor | self-hosted Apertus | hosted Apertus | closed frontier API |
|---|---|---|---|
| Data residency | | | |
| Weights + data openness | Apache 2.0, open data | same model | closed |
| EU AI Act documentation | published | | |
| Rate limits | your hardware | 5 req/s | vendor tiers |
| Deprecation risk | none | | vendor-controlled |

## The assumption that would flip our conclusion

## Reproduction

```bash
git clone <this repo> && cd optimized-apertus
cp env/.env.example .env && $EDITOR .env
bash env/00_env_check.sh && bash env/01_login.sh
bash nim/14_nim_v15_attempt.sh                  # leg A evidence
bash serve/15_serve_v15.sh && bash serve/16_smoke_v15.sh
bash bench/20_install.sh && SYSTEM=v15-8b-len8k bash bench/21_sweep.sh all
bash bench/23_swisscom.sh rag                   # leg C
python3 bench/22_collect.py --root artifacts/bench -o artifacts/results.csv
python3 tokenomics/40_tokenomics.py --results artifacts/results.csv \
        --gpu <GPU> --thinking-multiplier <X> --audio-minutes
```

## Run log — 2026-09-17T16:20:36+00:00
```
model: swiss-ai/Apertus-v1.5-8B
served_as: apertus
max_model_len: 8192
["vllm","serve","swiss-ai/Apertus-v1.5-8B","--served-model-name","apertus","--chat-template-content-format","string","--tensor-parallel-size","1","--gpu-memory-utilization","0.85","--max-model-len","8192","--enable-auto-tool-choice","--tool-call-parser","apertus","--host","0.0.0.0","--port","8000"]
index, name, memory.total [MiB]
0, NVIDIA H100 NVL, 95830 MiB
1, NVIDIA H100 NVL, 95830 MiB
```

## Running Apertus 1.5 8B on Spark DGX
The Spark reports 85× KV capacity but misses a 50 ms ITL interactive budget at concurrency 
1. It is not a serving box at any concurrency — it's a batch box. 
Price it on batch and summarize, where latency has no SLO, 
and its cost per token competes with the datacenter GPU. 
Price it on chat and it never qualifies at any price.
