# Findings — Optimized Apertus

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

## Finding #1 — which backend actually serves Apertus

Output of `nim/10_list_profiles.sh`:

```
(paste)
```

- Backend selected: `trtllm` / `vllm` / `sglang`
- TensorRT-LLM profile available? yes / no
- If no — why: Apertus uses the xIELU activation; `ApertusForCausalLM` is not in
  the TensorRT-LLM supported-models list.
- **Implication for the study:**

## Baseline (Phase 2)

| system | workload | conc at SLO knee | out tok/s | TTFT p95 | ITL p95 |
|---|---|---:|---:|---:|---:|
| nim-8b-tp1 | chat | | | | |
| nim-8b-tp1 | rag | | | | |
| nim-8b-tp1 | summarize | | | | |
| nim-8b-tp1 | agent | | | | |
| nim-8b-tp1 | batch | | | | |

SLOs used: TTFT p95 / ITL p95 per `bench/scenarios.json`.

## Optimization deltas (Phase 4)

One row per single change. Always relative to the baseline above.

| change | workload | out tok/s | Δ vs baseline | $/1M out | Δ cost | quality gate |
|---|---|---:|---:|---:|---:|---|
| FP8 weights + KV | | | | | | pass/fail |
| max-model-len 64k → 8k | | | | | | |
| TP=2 vs 2 replicas | | | | | | |
| prefix caching on | | | | | | |
| SGLang instead of vLLM | | | | | | |
| NIM vs vanilla vLLM | | | | | | |

**Best config found:**

## Scaling: 8B vs 70B (Phase 5)

| model | GPUs | precision | out tok/s | $/1M out | $/1M blended |
|---|---:|---|---:|---:|---:|
| Apertus-8B | | | | | |
| Apertus-70B | | | | | |

Cost ratio 70B/8B: ______ (parameter ratio is 8.75×)

Why the ratio differs from 8.75×:

## Tokenomics (Phase 3 + 7)

Assumptions stated out loud:

- GPU hourly rate: ______ (source: ______)
- Utilization: ______%
- Cost basis: rental / amortized-owned

| comparator | $/1M blended | vs self-host | break-even (M tok/month) |
|---|---:|---:|---:|
| self-host (best config) | | — | — |
| frontier API | | | |
| open-weights vendor | | | |
| hosted Apertus | | | |

Non-cost factors that change the decision:

- Data residency:
- Model openness / auditability (Apertus is Apache-2.0, open data + recipes):
- Rate limits and burst headroom:
- Deprecation risk:

## Dynamo (Phase 6, if reached)

Total GPUs held constant at ______ across all three rows.

| topology | workload | out tok/s | TTFT p95 | $/1M blended |
|---|---|---:|---:|---:|
| aggregated (baseline) | rag | | | |
| aggregated + KV router | rag | | | |
| disaggregated 1P+1D | rag | | | |
| disaggregated 1P+2D | rag | | | |

Optimal prefill:decode ratio vs ISL/OSL:

Where disaggregation did **not** help, and why:

## The assumption that would flip our conclusion

## Reproduction

```bash
git clone <this repo> && cd optimized-apertus
cp env/.env.example .env && $EDITOR .env
bash env/00_env_check.sh && bash env/01_login.sh
bash nim/10_list_profiles.sh && bash nim/11_serve.sh && bash nim/12_smoke.sh
bash bench/20_install.sh && SYSTEM=nim-8b-tp1 bash bench/21_sweep.sh all
python3 bench/22_collect.py --root artifacts/bench -o artifacts/results.csv
python3 tokenomics/40_tokenomics.py --results artifacts/results.csv --gpu <GPU>
```
