# Optimized Apertus 1.5 — NIM + Dynamo on NVIDIA LaunchPad

A runbook and working scaffold for the *"how efficiently can you run an AI
model?"* challenge: serve **Apertus 1.5** with **NVIDIA NIM**, optimize it,
optionally scale it with **Dynamo**, and turn the numbers into a **tokenomics
study** against cloud alternatives.

**Read [`docs/APERTUS-1.5.md`](docs/APERTUS-1.5.md) first.** Apertus 1.5 is not a
drop-in for 1.0, and almost every default you'd reach for is wrong for it.

---

## 0. The thing that decides your whole submission

**Apertus 1.5 does not run on stock anything.** Its architecture id is
`apertus1p5`, which is not yet in upstream vLLM or Transformers — Swiss AI ship
forks, and the supported path is a specific Docker image:
`ghcr.io/swiss-ai/vllm_apertus_1.5_release:latest-amd64`. On top of that,
`ApertusForCausalLM` has never been in the TensorRT-LLM supported-model list,
because of the xIELU activation.

So NIM — whose entire value proposition is a pre-built, hand-tuned TensorRT-LLM
engine — very likely **cannot load Apertus 1.5 at all**. Not a tuning problem.
A model-registry problem.

Three ways teams will react:

| Reaction | Outcome |
|---|---|
| Benchmark whatever loads, claim "NIM speedup" | Judges ask which backend and which model version ran. No answer. |
| Panic and abandon NIM | You've discarded the challenge's named tool. |
| **Measure the gap, name it, price it** | **This is the strongest result available.** |

The submission that wins says:

> *"The vendor-optimized serving stack lags the open-model frontier. Here is that
> gap measured three ways — in supported architectures, in weeks of engineering,
> and in dollars per million tokens."*

`nim/14_nim_v15_attempt.sh` captures that evidence with logs and timestamps, and
tells you which two reference models to run so the claim has a number attached.

---

## 1. Three legs, three questions

This is the study structure the model's particularities force on you, and it's
better than the obvious one:

| Leg | Stack | Question it answers |
|---|---|---|
| **A** | NIM + Apertus **1.0** (`-2509`) | Does the vendor stack help on this model family at all? |
| **B** | swiss-ai vLLM fork + Apertus **1.5** | The real deployment. All optimization happens here. |
| **C** | Swisscom hosted Apertus **1.5 70B** | Build vs buy, with *zero* model confounds. |

A vs B is *"what does being on the frontier cost you"*.
B vs C is *"build versus buy"* — and because leg C serves **the same weights**,
nobody can wave the comparison away as apples-to-oranges. That endpoint is the
single most valuable thing in the Swisscom Hacker Guide.

---

## 2. LaunchPad: what to nail down in the first 15 minutes

LaunchPad gives you a **time-boxed, curated GPU environment** — drivers,
container runtime and NGC access preconfigured, reached through a browser
terminal / Jupyter / SSH. For a hackathon, access usually arrives as an
**event-specific lab code**, and the environment is reclaimed when the session
expires. Silicon, GPU count and session length vary per lab, so don't plan around
an assumption:

```bash
cp env/.env.example .env && $EDITOR .env    # HF token, Swisscom key, NGC key
bash env/00_env_check.sh                    # 3 minutes, decides your whole plan
bash env/01_login.sh                        # gate check, image pulls, weights
```

`00_env_check.sh` reports GPU model and count, total GPU memory, **NVLink vs
PCIe topology**, free disk and egress throughput. Those five facts determine:

- **Total GPU memory** → is 70B in bf16 on the table? (~140 GB of weights, plus a
  KV allocation that is brutal at 262k context.)
- **Interconnect** → `NV#` in `nvidia-smi topo -m` means TP scales; `PIX`/`SYS`
  means TP>2 disappoints and you should prefer independent replicas.
- **GPU count** → Dynamo disaggregation needs ≥2 GPUs to mean anything, ≥3 to be
  interesting. On 1 GPU, skip Dynamo and go deeper on context and quantization.
- **Disk** → 70B is ~140 GB. Find the scratch mount before starting that pull.
- **Egress** → at 50 MB/s the 70B download is ~50 minutes. Background it in hour 0.

Record the **GPU model's hourly list price** too. The whole tokenomics study
rests on it, and looking it up at 2am while writing slides is how teams end up
with an unsourced number in their conclusion.

> **Session hygiene.** The environment is ephemeral and every script writes to
> `artifacts/`. Push that directory off-box after each phase. Losing a four-hour
> sweep to an expired session is the most common way these challenges go wrong.

---

## 3. Before the hackathon (do these now, they're blocking)

1. **Accept the Apertus 1.5 Acceptable Use Policy on Hugging Face**, logged in,
   for *both* `Apertus-v1.5-8B` and `Apertus-v1.5-70B`. Gated repos 401 in a way
   that looks exactly like a bad token. `env/01_login.sh` fails loudly if you
   skipped this.
2. **Get a Swisscom API key** from The Keymaker → select Swisscom → the email you
   registered with on Luma. The bearer **expires after 60 minutes**, so you'll
   refresh it during the event; what you're setting up now is the account.
3. **Run `bash tools/selftest.sh`** on your laptop. It exercises the collector
   and the tokenomics calculator on synthetic data, no GPU needed. If that
   passes, the only thing that can break on LaunchPad is the serving itself.

---

## 4. Phase plan

| Phase | Hours | Output | Gate to proceed |
|---|---|---|---|
| 0 — Recon | 0.5 | `artifacts/env/` | Know your GPUs, disk and topology |
| 1 — NIM evidence (leg A) | 1 | `artifacts/nim-v15-attempt/` | Documented: what NIM can and cannot load |
| 2 — Serve 1.5 (leg B) | 1.5 | Working endpoint | `serve/16_smoke_v15.sh` passes all six checks |
| 3 — Sweep | 2 | `artifacts/results.csv` | Curves per workload |
| 4 — Tokenomics v1 | 1 | `artifacts/tokenomics.md` | A defensible $/1M tokens |
| 5 — Optimize | 2–3 | Config deltas | Quantified % improvement |
| 6 — Hosted compare (leg C) | 1 | Swisscom rows | Build-vs-buy crossover |
| 7 — 70B + thinking tax | 2–3 | Scaling + multiplier | Two more headline numbers |
| 8 — Dynamo | 3+ | Agg vs disagg | Only if GPUs and time allow |
| 9 — Write-up | 2 | `docs/FINDINGS.md` | — |

**Phase 4 before Phase 5 is deliberate.** Produce a complete, end-to-end,
unoptimized cost number early. Then every optimization has a baseline to beat,
and if time runs out you still have a finished study rather than a pile of logs.

---

## 5. Serving Apertus 1.5

```bash
bash nim/14_nim_v15_attempt.sh    # leg A evidence — do this even though it fails
bash serve/15_serve_v15.sh        # leg B: the fork image, 8B, TP=1
bash serve/16_smoke_v15.sh        # text, multilingual, tools, thinking, image
```

`serve/15_serve_v15.sh` wraps the model card's own command. The flags that are
not optional:

- `--chat-template-content-format string` — the 1.5 template expects string
  content, not OpenAI content-parts. Omit it and multi-part messages break oddly.
- `--tool-call-parser apertus` with `--enable-auto-tool-choice` — model-specific,
  fork-only.
- `--gpu-memory-utilization 0.6` on the **8B** — lower than the usual 0.9,
  because multimodal encoders plus a 262k KV allocation need headroom.
- `--compilation-config.pass_config.fuse_allreduce_rms false` when TP>1 — a
  documented CUDA-graph capture failure. The script adds it automatically.

`16_smoke_v15.sh` checks the four things that distinguish 1.5 from 1.0 and are
easy to silently lose: tool calling, thinking markers, image input and
multilingual output. Re-run it after **every** quantization change. A config
that's 3× faster and produces garbage isn't a result, and the judges will ask.

---

## 6. Benchmarking

```bash
bash bench/20_install.sh
SYSTEM=v15-8b-len8k bash bench/21_sweep.sh all
python3 bench/22_collect.py --root artifacts/bench -o artifacts/results.csv
```

Seven workload shapes in `bench/scenarios.json`, because the input:output ratio
decides everything downstream:

| Workload | ISL / OSL | Why it's here |
|---|---|---|
| `chat` | 512 / 256 | TTFT-sensitive default, decode-bound |
| `rag` | 4096 / 256 | Prefill-heavy — where disaggregation pays |
| `summarize` | 8000 / 200 | Most prefill-dominant |
| `agent` | 1024 / 1024 | Tool-calling loop; 1.5 improved tool use |
| `batch` | 1024 / 128 | No SLO, pure cost floor |
| `longctx` | 100000 / 512 | **Prices the advertised 262k context** |
| `think` | 512 / ≤2048 | **Thinking mode — output length is a budget, not a target** |

Each runs a concurrency ladder and **stops at the SLO knee**. Peak throughput at
concurrency 256 with a nine-second TTFT isn't a product, and costing tokens there
is self-deception — `40_tokenomics.py` refuses to price a config that missed its
p95 budget.

AIPerf is used deliberately: it speaks the OpenAI chat API, so *the same client
with the same flags* benchmarks the fork, NIM, Dynamo and the Swisscom endpoint.
That's what makes the comparison a measurement instead of an argument.

**The `longctx` and `think` shapes are your differentiators.** Everyone will have
a chat throughput number. Almost nobody will have priced the 262k context or the
thinking tax.

---

## 7. The two numbers nobody else will have

### The thinking tax

```bash
python3 bench/24_thinking_tax.py --tag plain           # server without thinking
ENABLE_THINKING=1 bash serve/15_serve_v15.sh
python3 bench/24_thinking_tax.py --tag thinking
python3 bench/24_thinking_tax.py --compare artifacts/thinking/plain.json \
                                           artifacts/thinking/thinking.json
```

Thinking mode reasons between `<|inner_prefix|>` and `<|inner_suffix|>` before
answering. You pay for every reasoning token; the user sees none of them. So one
deployment has two costs:

- **$/1M billed tokens** — what the GPU produced
- **$/1M visible tokens** — what the user received

The comparison prints the multiplier and the accuracy delta on the same eight
checkable prompts. Feed it forward:

```bash
python3 tokenomics/40_tokenomics.py --thinking-multiplier 4.1 ...
```

Then answer the question that actually matters: *for which workloads is that
accuracy worth that multiplier?*

### Cost per minute of audio

Apertus 1.5 takes audio at **40 tokens per second** — one minute of speech is
2,400 input tokens. `--audio-minutes` turns your throughput numbers into cost per
minute of audio, directly comparable to a dedicated speech API. That's a cost
axis a text-only study structurally cannot reach.

---

## 8. Tokenomics

```bash
python3 tokenomics/40_tokenomics.py \
    --results artifacts/results.csv \
    --gpu H100-80GB-SXM --gpus-per-replica 1 \
    --thinking-multiplier 4.1 --audio-minutes \
    --out artifacts/tokenomics.md
```

The framing that wins this challenge:

> Self-hosting is a **fixed** cost — you rent the GPU whether it's busy or not.
> A token API is a **variable** cost. The question isn't "which is cheaper" but
> **"above what monthly volume does fixed beat variable, and how far left does
> optimization move that crossover?"**

The script reports, per configuration and workload: $/1M output and $/1M blended
(weighted by the workload's real ISL/OSL — a RAG workload is 94% input tokens,
and pricing it on output alone is wrong by an order of magnitude), the same at a
realistic duty cycle, break-even monthly volume against each comparator, and a
sensitivity band across 20/45/80/100% utilization.

`tokenomics/prices.json` ships **placeholders, all flagged `verified: false`**,
and the script warns on every unverified price it uses. Fill in:

1. the GPU hourly rate for your LaunchPad silicon,
2. a frontier closed API,
3. an open-weights serverless vendor,
4. **Swisscom's commercial rate for hosted Apertus** — or, if there isn't one,
   say plainly that leg C is a free tier and use measured throughput at their
   5 req/s cap as the basis,
5. an **amortized owned-hardware** basis (capex/3yr + power × PUE + hosting).
   For a Swiss enterprise with a data-residency requirement this is often the
   real alternative, and it usually beats rental at high volume.

**And don't let it be only about money.** Apertus is Apache-2.0 with open
weights, open data and published recipes, trained on Swiss infrastructure,
respecting retroactive opt-out. Data residency, auditability, EU AI Act
documentation, no rate limits, no deprecation risk — those belong in the same
table as dollars. They're most of why anyone self-hosts an 8B model when an API
is a tenth of the price.

---

## 9. Optimization levers, roughly by payoff

Change **one** thing at a time, re-run with a new `SYSTEM=` tag, so each delta is
attributable.

1. **`--max-model-len`** — the biggest lever in this model, by far. KV cache is
   preallocated; serving 8k instead of 262k can multiply your concurrent
   sequences. Sweep **8k / 32k / 131k / 262k** and plot $/1M against it. The
   finding writes itself: *serving the advertised context costs N× per token.*
2. **`--gpu-memory-utilization`** — the card's 0.6 for 8B is conservative;
   0.75–0.85 buys KV cache. It OOMs fast, so step carefully.
3. **Quantization (FP8 on Hopper)** — roughly halves memory and lifts the batch
   you can hold. **Critical caveat:** the vision and audio tokenizers are
   precision-sensitive and stay float32 by design. Quantize the language model,
   leave the encoders alone, and re-run the multimodal smoke test — this is
   where a naive FP8 pass silently wrecks quality.
4. **Thinking on/off** — a cost multiplier, not a speed knob. See §7.
5. **TP vs replicas** — on PCIe-only nodes, N independent 1-GPU replicas usually
   beat one TP=N instance. On NVLink, the reverse. Hence the Phase 0 topology check.
6. **`--max-num-seqs` / batching** — find the saturation point per workload.
7. **Prefix caching** — large on RAG with a shared system prompt, near-zero on
   `batch`. Measure per scenario.

For the 70B leg, TP is mandatory (the card uses TP=4) and the CUDA-graph
workaround will hit you. Report **$/1M tokens for 8B vs 70B on the same
hardware** — the ratio is usually far worse than the ~8× parameter ratio, and
explaining why (memory bandwidth, worse batching headroom, TP communication) is
exactly the analysis this challenge wants.

---

## 10. Dynamo (stretch)

```bash
bash dynamo/33_build_apertus_image.sh                 # REQUIRED for 1.5
bash dynamo/30_setup.sh compose                       # etcd + NATS
REPLICAS=2 ROUTER=kv bash dynamo/31_agg.sh            # baseline: same GPUs, router only
PREFILL=1 DECODE=1 ROUTER=kv bash dynamo/32_disagg.sh
```

Dynamo's vLLM backend runs its own vLLM, which doesn't know `apertus1p5` either —
so the stock Dynamo image can't serve 1.5 any more than NIM can.
`33_build_apertus_image.sh` installs the Dynamo runtime **into** the Swiss AI fork
image and verifies the fork survived the pip install. Budget an hour.

Three rules for a real result rather than a confusing one:

- **Hold GPU count constant.** Disaggregated 1+1 compares against *aggregated on
  2 GPUs*, not 1. Otherwise you've measured "more hardware is faster".
- **Run `31_agg.sh` first**, so you can separate the router's contribution from
  disaggregation's.
- **Benchmark `rag` and `summarize`.** Disaggregation helps prefill-heavy shapes.
  On `chat` you'll likely see a small regression from KV transfer — report that
  too; a measured "it didn't help here, and here's why" is a genuine finding.

Then sweep the prefill:decode ratio (1:1, 1:2, 2:1); the optimum is a function of
ISL/OSL, and that curve is a strong result on its own. `PYTHONHASHSEED=0` is set
for you — KV-aware routing hashes blocks across processes.

---

## 11. Deliverable

`docs/FINDINGS.md` is the skeleton. Fill it as you go, not at the end.

The six claims worth making, in order:

1. **What NIM could and could not load, with logs** — the frontier-lag story.
2. **The optimization delta in $/1M tokens**, not tokens/sec. Speed is the
   input; money is the study.
3. **The price of the 262k context** — cost per token at 8k vs 262k.
4. **The thinking tax** — billed vs visible tokens, against accuracy gained.
5. **Self-hosted vs Swisscom-hosted, same weights** — the break-even volume,
   with the utilization assumption stated out loud.
6. **The one assumption that would flip your conclusion.** Saying it before the
   judges find it is the difference between a benchmark dump and an analysis.

---

## 12. Risk register

| Risk | Early signal | Mitigation |
|---|---|---|
| NIM can't load 1.5 | `14_nim_v15_attempt.sh` | **Expected.** It's leg A evidence; leg B carries the study. |
| Gated repo 401 | `01_login.sh` gate check | Accept the AUP on HF, logged in, before the event. |
| OOM at 262k context | Startup failure | Lower `MAX_MODEL_LEN` first, then `GPU_MEM_UTIL`, then raise TP. |
| CUDA graph fails at TP>1 | Capture error | Handled automatically; `--enforce-eager` to isolate. |
| Swisscom budget burned | `swisscom_budget.json` ledger | The guard refuses runs above 90% of quota. |
| Bearer expired mid-sweep | 401s partway through | 60-minute lifetime; refresh and split sweeps into sub-hour chunks. |
| FP8 breaks multimodal | Smoke test 6 fails | Don't quantize the vision/audio encoders. |
| 70B won't fit | `00_env_check.sh` | FP8 + short context, or make 8B the study and 70B a projection. |
| Session expires | — | Push `artifacts/` off-box after every phase. |
| Unsourced prices in the deck | `prices.json` still `verified:false` | The script warns every run. Fix it in Phase 4, not Phase 9. |

---

## 13. Layout

```
optimized-apertus/
├── README.md                     this runbook
├── docs/
│   ├── APERTUS-1.5.md            READ FIRST — every v1.5 gotcha, sourced
│   └── FINDINGS.md               write-up skeleton
├── env/
│   ├── .env.example              credentials, image tags, model ids
│   ├── 00_env_check.sh           GPU/topology/disk/egress recon
│   └── 01_login.sh               AUP gate check, image pulls, weight pre-fetch
├── serve/                        ← leg B: the real Apertus 1.5 deployment
│   ├── 15_serve_v15.sh           swiss-ai vLLM fork, card-exact flags
│   └── 16_smoke_v15.sh           text/multilingual/tools/thinking/image checks
├── nim/                          ← leg A: what the vendor stack can do
│   ├── 10_list_profiles.sh       which backend NIM picks (Apertus 1.0)
│   ├── 11_serve.sh               parameterized NIM launch (1.0)
│   ├── 12_smoke.sh               correctness + TTFT sanity
│   ├── 13_fallback_vllm.sh       vanilla vLLM/SGLang baseline
│   └── 14_nim_v15_attempt.sh     documented 1.5 attempt → evidence
├── bench/
│   ├── scenarios.json            7 workload shapes incl. longctx + think
│   ├── 20_install.sh             AIPerf
│   ├── 21_sweep.sh               ladder with SLO early stop
│   ├── 22_collect.py             exports → results.csv
│   ├── 23_swisscom.sh            ← leg C, with quota + rate-limit guards
│   └── 24_thinking_tax.py        billed vs visible tokens, and accuracy
├── dynamo/
│   ├── 30_setup.sh               etcd + NATS
│   ├── 31_agg.sh                 aggregated baseline (+ KV router)
│   ├── 32_disagg.sh              disaggregated prefill/decode
│   └── 33_build_apertus_image.sh Dynamo on top of the fork — required for 1.5
├── tokenomics/
│   ├── prices.json               PLACEHOLDERS — verify before quoting
│   └── 40_tokenomics.py          $/1M, break-even, sensitivity, thinking, audio
└── tools/
    └── selftest.sh               whole analysis pipeline, no GPU
```

All scripts read `.env` from the repo root.
`chmod +x env/*.sh serve/*.sh nim/*.sh bench/*.sh dynamo/*.sh tools/*.sh`

---

## Sources

- [swiss-ai/Apertus-v1.5-8B](https://huggingface.co/swiss-ai/Apertus-v1.5-8B) — serving commands, thinking mode, multimodal notes, known issues, gating
- [swiss-ai/Apertus-v1.5-70B](https://huggingface.co/swiss-ai/Apertus-v1.5-70B) — TP=4 reference command
- [Swisscom Hacker Guide](https://zh.ai-weeks.ch/tools/swisscom-hacker-guide) — hosted endpoint, rate limits, token budgets, key process
- [Swiss-ai-Weeks/optimized-apertus](https://github.com/Swiss-ai-Weeks/optimized-apertus) — challenge repo (empty as of writing)
- [TensorRT-LLM supported models](https://nvidia.github.io/TensorRT-LLM/models/supported-models.html) — Apertus absent
- [Multi-LLM NIM](https://huggingface.co/blog/nvidia/multi-llm-nim) · [NIM CLI reference](https://docs.nvidia.com/nim/large-language-models/2.0.2/reference/cli-reference.html)
- [ai-dynamo/dynamo](https://github.com/ai-dynamo/dynamo) · [Dynamo vLLM backend](https://docs.nvidia.com/dynamo/latest/backends/vllm/README.html) · [ai-dynamo/aiperf](https://github.com/ai-dynamo/aiperf)
- [LLM Inference Benchmarking: Fundamental Concepts](https://developer.nvidia.com/blog/llm-benchmarking-fundamental-concepts/) · [NVIDIA LaunchPad](https://launchpad.nvidia.com/)
