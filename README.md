# Optimized Apertus 1.5 — a tokenomics study

**HPE & NVIDIA Agentic AI Hackathon · Swiss AI Weeks, Zurich**
Challenge: *optimized-apertus* — run Apertus on NVIDIA NIM and Dynamo, optimize
for performance, and perform a tokenomics study against cloud alternatives.

We benchmarked **Apertus 1.5** across three machines and a hosted endpoint, using
one workload suite, one SLO gate and one cost model throughout — then priced
every result in dollars per million tokens.

**→ [`docs/FINDINGS.md`](docs/FINDINGS.md) is the write-up.** This file explains
what is here and how to reproduce it.
**→ [`docs/APERTUS-1.5.md`](docs/APERTUS-1.5.md)** collects every 1.5-specific
gotcha, sourced. Apertus 1.5 is not a drop-in for 1.0.

---

## What we found

**1. NVIDIA's managed stack cannot run Apertus 1.5 at all.** NIM's profile
selector downloads the checkpoint, identifies the architecture by name, evaluates
TensorRT-LLM, vLLM and SGLang, and reports *"not supported in any available
inference backend."* NVIDIA's April 2026 vLLM container registers no Apertus
architecture whatsoever. There is no `trust_remote_code` shortcut — the model
class exists only in Swiss AI's patched `transformers`, so you need **two** forks
before anything loads.

**2. Serving configuration moves cost by 1.6× on identical hardware and weights.**
Best config (FP8 weights + FP8 KV cache): **$0.320 / 1M output tokens**.
Worst tested (NVFP4): **$0.516**. Same GPU, same model, same SLO.

**3. Quantization pays only where the silicon supports it.** FP8 on Hopper: +3%
throughput and 38% cheaper than NVFP4. NVFP4 on Hopper: emulated, −36%. On a DGX
Spark, NVFP4 falls back to a software Marlin kernel *while FP8 in the same model
runs on native CUTLASS* — visible in two consecutive lines of one vLLM log.

**4. The "a 70B costs 8× an 8B" rule is true only offline.** Fully batched, the
ratio is **8.70×** against a parameter ratio of 8.75×. Under an interactive SLO
it blows out to **21×**. The difference is not parameters — it is the batching
the latency budget forbids.

**5. Dynamo converts throughput into latency, at a rate set by ISL:OSL.** Per-GPU
cost penalty, monotonic across five workloads: **+57% at 1:1, +54% at 2:1, +38%
at 8:1, +9% at 16:1, +7% at 37:1.** What the premium buys is time-to-first-token
and headroom — on `rag`, 8× the concurrency inside the SLO for 9%.

**6. Self-hosting a 70B for interactive use is dominated.** Against the *same
weights* hosted by Swisscom, self-hosting costs ~$25/1M (~$56 at realistic
utilization) **and** delivers 35.3 tok/s per user against their 63.3 — more
expensive and slower at once. The 8B is the opposite: at $0.320/1M it is cheaper
than anything purchasable.

### The through-line

One variable — the **input:output token ratio** — independently ordered three
findings produced by three unrelated mechanisms:

| finding | mechanism | points |
|---|---|---:|
| NVFP4 penalty on H100 | emulated kernels | 5/5 |
| DGX Spark batching efficiency | memory bandwidth | 5/5 |
| Dynamo cost penalty | scheduling + KV transfer | 5/5 |

If the study has one slide, it is that one.

---

## What we measured

| system | hardware | role |
|---|---|---|
| `apertus-p2-c04-fp8weights-fp8kv` | 1 × H100 NVL | **best config** — FP8 weights + FP8 KV |
| `h100nvl-co3` · `conf02` · `v15-8b-tp1-len8k` | 1 × H100 NVL | 8B configuration sweep |
| `h100nvl-co4` | 1 × H100 NVL | NVFP4 — emulated on sm_90 |
| `h100nvl-70b-fp8-tp1` | 1 × H100 NVL | 70B FP8 — fits on one 94 GB card |
| `v15-70b-tp2-len8k` | 2 × H100 NVL | 70B bf16, tensor-parallel |
| `h100nvl-dynamo-pref-run-2gpu` | 2 × H100 NVL | NVIDIA Dynamo |
| `spark-v15-8b-bf16-len8k` | DGX Spark GB10 | on-prem comparator, $0.22/h |
| `spark-v15-70b-nvfp4` | DGX Spark GB10 | third-party NVFP4 quant |
| `remote-swisscom-apertus-70b` | hosted | **identical weights** — build vs buy |

All serving uses the Swiss AI vLLM fork
(`ghcr.io/swiss-ai/vllm_apertus_1.5_release`), which is the only thing that loads
Apertus 1.5 — see finding 1.

---

## Reproduce

```bash
git clone <this repo> && cd optimized-apertus
cp env/.env.example .env && $EDITOR .env     # HF_TOKEN, NGC, SWISSCOM_API_KEY
bash env/00_env_check.sh                     # GPUs, topology, disk, egress
bash env/01_login.sh                         # AUP gate, image pulls, weights
```

**Leg A — the NIM evidence.** Expected to fail; that *is* the result:

```bash
bash nim/10_list_profiles.sh swiss-ai/Apertus-v1.5-8B
bash nim/14_nim_v15_attempt.sh
```

**Leg B — serve and benchmark:**

```bash
MODEL=swiss-ai/Apertus-v1.5-8B TP_SIZE=1 GPU_MEM_UTIL=0.85 MAX_MODEL_LEN=8192 \
  RUN_TAG=v15-8b-tp1-len8k bash serve/15_serve_v15.sh

bash serve/16_smoke_v15.sh          # six checks; arithmetic MUST return 391

bash bench/20_install.sh
export SYSTEM=v15-8b-tp1-len8k TOKENIZER=swiss-ai/Apertus-v1.5-8B NIM_PORT=8000
bash bench/21_sweep.sh all          # 1–3 h; the SLO early-stop trims it
```

**Leg C — hosted comparators:**

```bash
DRY_RUN=1 bash bench/26_remote_sweep.sh swisscom-apertus-70b chat   # budget first
REQ_COUNT=50 bash bench/26_remote_sweep.sh swisscom-apertus-70b chat

# an endpoint that only speaks /v1/responses, or exposes no tokenizer:
python3 bench/27_responses_probe.py --url https://api.example.com/v1/responses \
        --system remote-example --rounds 20
```

**Collect and price:**

```bash
python3 bench/22_collect.py --root artifacts/bench -o artifacts/results-all.csv

# one run per (machine, GPU count, model size) — mixing them misprices rows
python3 tokenomics/40_tokenomics.py --results artifacts/r-h100-8b-1gpu.csv \
        --gpu H100-NVL-94GB --gpus-per-replica 1
```

---

## Layout

```
env/     00_env_check.sh  01_login.sh          recon, credentials, image pulls
nim/     10_list_profiles.sh … 14_nim_v15_attempt.sh   leg A — the NIM evidence
serve/   15_serve_v15.sh  16_smoke_v15.sh      leg B — the fork, and the quality gate
bench/   20_install.sh          aiperf
         21_sweep.sh            SLO-gated concurrency ladder; one workload or `all`
         22_collect.py          tolerant JSON → one tidy CSV
         23_swisscom.sh         the original hosted probe
         24_thinking_tax.py     billed vs visible tokens (unrun — see Status)
         26_remote_sweep.sh     generic hosted endpoints, driven by endpoints.json
         27_responses_probe.py  /v1/responses; needs no tokenizer
         scenarios.json         workload shapes, SLOs, concurrency ladder
         endpoints.json         hosted endpoints — names of key env vars, never keys
dynamo/  30_setup.sh … 33_build_apertus_image.sh   Dynamo, incl. the fork-image build
tokenomics/ 40_tokenomics.py  prices.json       SLO-filtered cost model
docs/    FINDINGS.md            the write-up
         APERTUS-1.5.md         every 1.5 gotcha, sourced
         runs/                  committed results (artifacts/ is gitignored)
tools/   selftest.sh            validate the pipeline with no GPU
```

---

## Method

**Seven workload shapes** (`bench/scenarios.json`), each with its own p95 SLO:

| workload | ISL / OSL | ISL:OSL | SLO (TTFT / ITL) |
|---|---|---:|---|
| chat | 512 / 256 | 2:1 | 500 ms / 50 ms |
| rag | 4096 / 256 | 16:1 | 2000 ms / 50 ms |
| summarize | 7500 / 200 | 37:1 | 4000 ms / 80 ms |
| agent | 1024 / 1024 | 1:1 | 1000 ms / 40 ms |
| batch | 1024 / 128 | 8:1 | **none** — the cost floor |
| longctx | 100000 / 512 | 195:1 | 30 s / 120 ms |
| think | 512 / 2048 | 1:4 | 500 ms / 60 ms |

The sweep walks a concurrency ladder and **stops at the first SLO violation**.
The knee of the throughput-versus-latency curve under your SLO is the only
operating point whose cost-per-token means anything — peak throughput at c256
with a nine-second TTFT is not a product.

`batch` is the control. It carries no latency budget, so it measures the cheapest
tokens the hardware can physically produce, and the gap between it and everything
else is the price of interactivity, stated in dollars.

Results land in `artifacts/bench/$SYSTEM/$WORKLOAD/c$N/`, so runs from different
machines never overwrite each other and `22_collect.py --root artifacts/bench`
gathers all of them — including hosted endpoints — into one CSV.

---

## Gotchas that cost us hours

- It is **`NIM_PORT`**, not `PORT`. Setting `PORT` does nothing.
- **`TOKENIZER` must match the served model.** A mismatch silently corrupts every
  token count, and therefore every cost figure, with no warning anywhere.
- **`SERVED_MODEL`** must match `/v1/models` when a server was started outside
  `serve/15_serve_v15.sh`, or every request returns an error object and the
  scripts die on `KeyError: 'choices'`.
- `.env` must use `${VAR:-default}` or it clobbers command-line overrides.
- `--gpus device=0,1` is comma-split by Docker. Use `--gpus all` plus
  `CUDA_VISIBLE_DEVICES`.
- Bridge networking with `--host 0.0.0.0` makes Gloo fail at TP>1. Use
  `--network=host`.
- `:latest-arm64` on DGX Spark — the amd64 tag gives `exec format error`.
- `batch` has no SLO, so it never early-stops and walks the entire ladder.
- **Ladder granularity is not cosmetic.** A ladder that jumps 1 → 4 can place the
  SLO-valid operating point at c1 and double the reported cost.

---

## Status

Measured and written up: the NIM and TensorRT-LLM evidence, the 8B configuration
sweep, FP8 versus NVFP4 on two architectures, the 70B on one and two GPUs, the
DGX Spark, the Swisscom hosted comparator, and Dynamo across five workloads.

Gaps, declared rather than hidden (full list in §15 of `FINDINGS.md`):

- **Cloud API prices in `tokenomics/prices.json` are unverified**, so break-even
  volumes cannot be computed. This is the largest remaining hole.
- The Dynamo topology — aggregated versus disaggregated, and the prefill:decode
  split — was not recorded.
- The exact flag deltas between the 8B configs were set at the console and never
  captured, so the best config cannot be fully described.
- **`think` rows are mislabelled.** The sweep never reads the scenario's
  `thinking` flag and every server ran with thinking off, so they are a second
  chat variant. The thinking tax is unmeasured.
- The 70B FP8 TP=1 ladder skipped c2 and c3, leaving its true SLO knee unknown
  and its cost verdict against TP=2 unresolved.

**Security.** `.env` holds HF, NGC and Swisscom credentials and is gitignored.
Run `git status --short` and confirm it is absent before every commit.

---

## Sources

- [swiss-ai/Apertus-v1.5-8B](https://huggingface.co/swiss-ai/Apertus-v1.5-8B) ·
  [Apertus-v1.5-70B](https://huggingface.co/swiss-ai/Apertus-v1.5-70B)
- [Swiss AI vLLM fork build recipe](https://github.com/swiss-ai/model-launch/tree/main/images/vllm_apertus_1.5)
- [onprem.ai — Apertus v1.5 70B on a single RTX 6000](https://www.onprem.ai/en/knowhow/run-apertus-v15-70b-single-nvidia-rtx-6000/)
- [Swisscom hacker guide](https://zh.ai-weeks.ch/tools/swisscom-hacker-guide)
- vLLM sm_121 NVFP4 fallback:
  [#50925](https://github.com/vllm-project/vllm/issues/50925) ·
  [#43906](https://github.com/vllm-project/vllm/issues/43906) ·
  [#54666](https://github.com/vllm-project/vllm/issues/54666) ·
  [PR #52708](https://github.com/vllm-project/vllm/pull/52708)
- [NVIDIA AIPerf command-line options](https://docs.nvidia.com/aiperf/reference/command-line-options)
- [TensorRT-LLM AutoDeploy](https://nvidia.github.io/TensorRT-LLM/torch/auto_deploy/auto-deploy.html)
