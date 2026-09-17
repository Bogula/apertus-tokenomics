# Optimized Apertus — NIM + Dynamo on NVIDIA LaunchPad

A runbook and working scaffold for the *"how efficiently can you run an AI model?"*
challenge: serve **Apertus** with **NVIDIA NIM**, optimize it, optionally scale it
with **Dynamo**, and turn the numbers into a **tokenomics study** against cloud
alternatives.

---

## 0. The thing nobody tells you until hour six

Read this before you plan anything else.

**Apertus is not a Llama.** It was trained with the **xIELU** activation and the
AdEMAMix optimizer, and `ApertusForCausalLM` **does not appear in the
TensorRT-LLM supported-models list**. NIM's headline value — a pre-built,
hand-tuned TensorRT-LLM engine — therefore probably **does not exist for this
model**. NIM will fall back to its vLLM or SGLang backend.

Three ways teams react to this:

| Reaction | Outcome |
|---|---|
| Don't notice, benchmark anyway, claim "NIM speedup" | Judges will ask which backend ran. No answer. |
| Panic, abandon NIM | You've thrown away the challenge's core tool. |
| **Measure it, name it, quantify it** | **This is the interesting result.** |

The strongest submission says: *"NIM gave us X% over vanilla vLLM on this model,
and here is the gap to what a TRT-LLM-supported model of the same size achieves —
that difference is the cost of the architectural novelty, in dollars per million
tokens."* You can even measure it directly: run the identical sweep against
Llama-3.1-8B (which does have a TRT-LLM profile) as a reference point.

Run `nim/10_list_profiles.sh` in your first hour. Whatever it prints is Finding #1.

---

## 1. LaunchPad: what you're getting, and what to nail down first

NVIDIA LaunchPad gives you a **time-boxed, curated GPU environment** — a
preconfigured node (or DGX-class slice) with drivers, container runtime and NGC
access already set up, reached through a browser terminal / Jupyter / SSH. For a
hackathon, access usually comes as an **event-specific lab code** rather than the
public free-trial flow, and the environment is reclaimed when the session expires.

Because the exact silicon, GPU count and session length vary per lab, **do not
plan around an assumption**. The first thing you run is:

```bash
cp env/.env.example .env && $EDITOR .env    # NGC key, HF token, image tags
bash env/00_env_check.sh                    # 3 minutes, decides your whole plan
```

It reports GPU model and count, total GPU memory, **NVLink vs PCIe topology**,
free disk, and egress throughput. Those five facts determine:

- **Total GPU memory** → is Apertus-70B in bf16 even on the table? (~140 GB weights
  before KV cache. Under ~180 GB usable, you need FP8 or a short context.)
- **Interconnect** → `nvidia-smi topo -m` showing `NV#` means tensor parallelism
  scales; `PIX`/`SYS` means TP>2 will disappoint and you should prefer independent
  replicas behind a router.
- **GPU count** → Dynamo disaggregation needs ≥2 GPUs to be meaningful and ≥3 to
  be interesting. With 1 GPU, skip Dynamo entirely and go deeper on NIM configs.
- **Disk** → 70B weights + engine caches will fill a small root volume. Find the
  scratch mount before you start a 140 GB download.
- **Egress** → if you pull at 50 MB/s, the 70B download is ~50 minutes. Start it
  in a background terminal *now*, while you're still writing your plan.

Also record the **GPU model's hourly list price**. Your entire tokenomics study
rests on it, and looking it up at 2am while writing slides is how teams end up
with an unsourced number in their conclusion.

> **LaunchPad session hygiene.** The environment is ephemeral. Every script here
> writes to `artifacts/`. Rsync or `git push` that directory somewhere off-box at
> the end of each phase. Losing a four-hour sweep to an expired session is the
> single most common way these challenges go wrong.

---

## 2. Phase plan

You chose *NIM first, Dynamo as a stretch*, with **8B and 70B as a scaling study**.
Time-box each phase and write up before moving on.

| Phase | Hours | Output | Gate to proceed |
|---|---|---|---|
| 0 — Recon | 0.5 | `artifacts/env/`, profile list | Know your GPUs and your backend |
| 1 — Serve 8B | 1.5 | Working NIM endpoint | Smoke test passes |
| 2 — Sweep 8B | 2 | `artifacts/results.csv` | Throughput/latency curves per workload |
| 3 — Tokenomics v1 | 1 | `artifacts/tokenomics.md` | A defensible $/1M tokens |
| 4 — Optimize | 2–3 | Config deltas | Quantified % improvement |
| 5 — 70B scaling | 2 | Same tables, 70B | 8B-vs-70B cost curve |
| 6 — Dynamo | 3+ | Agg + disagg comparison | Only if GPUs and time allow |
| 7 — Write-up | 2 | `docs/FINDINGS.md`, slides | — |

**Phase 3 before Phase 4 is deliberate.** Produce a complete, end-to-end,
unoptimized cost number early. Then every optimization has a baseline to beat,
and if you run out of time you still have a finished study rather than a pile of
benchmark logs.

---

## 3. Phase 1 — Apertus under NIM

```bash
bash env/01_login.sh                  # docker login nvcr.io, pull image, pre-fetch 8B
bash nim/10_list_profiles.sh          # <- Finding #1 lives here
bash nim/11_serve.sh                  # 8B, TP=1
bash nim/12_smoke.sh                  # prove it answers, in German, and can multiply
```

`nim/11_serve.sh` drives the universal NIM image with:

```
NIM_MODEL_NAME="hf://swiss-ai/Apertus-8B-Instruct-2509"
NIM_TENSOR_PARALLEL_SIZE=<TP>
```

and forwards engine flags (`--max-model-len`, `--gpu-memory-utilization`,
`--max-num-seqs`) straight through. Every knob is an env var so the sweep can
restart the server in a new configuration without editing files.

**If NIM refuses the architecture** (its bundled engine predates Apertus
support), you are not blocked: `nim/13_fallback_vllm.sh` serves the same model on
the same port with upstream vLLM (needs ≥ 0.10.2 for `ApertusForCausalLM`) or
SGLang. Everything downstream keeps working. And you now have the honest
NIM-vs-vanilla baseline the report wants anyway — note the version gap as a
finding rather than hiding it.

**Quality gate.** `nim/12_smoke.sh` checks `17*23` and a German response. Re-run
it after every quantization change. A config that is 3× faster and produces
garbage is not a result, and the judges *will* ask whether you checked.

---

## 4. Phase 2 — benchmarking that means something

```bash
bash bench/20_install.sh
SYSTEM=nim-8b-tp1 bash bench/21_sweep.sh all
python3 bench/22_collect.py --root artifacts/bench -o artifacts/results.csv
```

Five workload shapes are defined in `bench/scenarios.json`, because **the
input:output ratio decides everything downstream**:

| Workload | ISL / OSL | Bottleneck | Why it's here |
|---|---|---|---|
| `chat` | 512 / 256 | decode | The TTFT-sensitive default |
| `rag` | 4096 / 256 | prefill | Where disaggregation pays |
| `summarize` | 8000 / 200 | prefill | Most extreme prefill case |
| `agent` | 1024 / 1024 | decode | Long structured generation |
| `batch` | 1024 / 128 | throughput | No SLO — pure cost floor |

Each runs a concurrency ladder (1 → 256) and **stops early once the p95 SLO is
violated**. That knee is the point of the exercise: peak throughput at
concurrency 256 with a nine-second TTFT is not a product anyone can sell, and
costing tokens at that point is self-deception.

AIPerf is used deliberately — it speaks the OpenAI chat API, so the *same client
with the same flags* benchmarks NIM, vanilla vLLM, Dynamo, and a cloud endpoint.
That is what makes your comparison apples-to-apples instead of an argument.

Metrics that matter, in order: **TTFT p95**, **ITL/TPOT p95**, **output tokens/s
per GPU**, **requests/s**, and only then total throughput.

---

## 5. Phase 3 — tokenomics

```bash
python3 tokenomics/40_tokenomics.py \
    --results artifacts/results.csv \
    --gpu H100-80GB-SXM --gpus-per-replica 1 \
    --out artifacts/tokenomics.md
```

The framing that wins this challenge:

> Self-hosting is a **fixed** cost — you rent the GPU whether it's busy or not.
> A token API is a **variable** cost. The question is not "which is cheaper" but
> **"above what monthly volume does fixed beat variable, and how far left does
> optimization move that crossover?"**

So the script reports, per configuration and workload:

- **$/1M output tokens** and **$/1M blended** (input and output weighted by the
  workload's real ISL/OSL ratio — a RAG workload is 94% input tokens, and pricing
  it on output alone is wrong by an order of magnitude)
- the same at a **realistic duty cycle**, not 100% utilization
- **break-even monthly volume** against each cloud comparator
- a **sensitivity band** across 20 / 45 / 80 / 100% utilization

`tokenomics/prices.json` ships with **placeholders, all flagged `verified: false`**.
Filling them in with sourced numbers is part of the work, and the script warns
on every unverified price it uses. Include at least:

1. a frontier closed API,
2. an open-weights model at a serverless token vendor,
3. an Apertus endpoint hosted by someone else, if one exists — the most honest
   comparator for this challenge,
4. an **amortized owned-hardware** basis (capex/3yr + power × PUE + hosting
   overhead). For a Swiss enterprise with a data-residency requirement this is
   often the real alternative, and it usually beats rental at high volume.

**Don't let it be only about money.** Apertus is Apache-2.0 with open weights,
open data and published recipes, trained on Swiss infrastructure. Data residency,
auditability, no rate limits and no vendor deprecation belong in the same table
as dollars — they're a large part of why anyone self-hosts a 8B model when an API
is a tenth of the price.

---

## 6. Phase 4 — optimization levers, roughly by payoff

Change **one** thing at a time and re-run the sweep with a new `SYSTEM=` tag, so
each delta is attributable.

1. **Backend choice** — vLLM vs SGLang for Apertus. Often 10–30%, and free.
2. **Quantization** — FP8 weights+KV on Hopper is the single biggest lever:
   roughly halves memory, raises the batch you can hold, and typically improves
   throughput per GPU substantially. **Re-run the quality gate.** Report accuracy
   alongside speed or the result is worthless.
3. **`--max-model-len`** — KV cache is preallocated. Serving 8k instead of 64k
   context can double your concurrent sequences. Match it to the workload, don't
   default to the model's maximum.
4. **`--max-num-seqs` / batching** — find the saturation point per workload.
5. **TP vs replicas** — on PCIe-only nodes, *N* independent 1-GPU replicas usually
   beat one TP=N instance. On NVLink, the reverse. This is why the topology check
   in Phase 0 matters.
6. **`--gpu-memory-utilization`** — 0.90 → 0.95 buys KV cache; too high and you
   OOM mid-sweep.
7. **Prefix caching** — huge on RAG with a shared system prompt, near-zero on
   `batch`. Workload-dependent, so measure per scenario.
8. **Speculative decoding** — high effort, needs a draft model; only if time is
   left over.

For the 70B leg: TP is not optional, FP8 probably isn't either. Report **$/1M
tokens for 8B vs 70B on the same hardware** — the ratio is usually far worse than
the 8.75× parameter ratio, and explaining *why* (memory bandwidth, worse batching
headroom, TP communication overhead) is exactly the kind of analysis this
challenge is asking for.

---

## 7. Phase 6 — Dynamo (stretch)

```bash
bash dynamo/30_setup.sh compose                       # etcd + NATS
REPLICAS=2 ROUTER=kv bash dynamo/31_agg.sh            # baseline: same GPUs, router only
PREFILL=1 DECODE=1 ROUTER=kv bash dynamo/32_disagg.sh # split the phases
```

Dynamo separates **prefill** (compute-bound, bursty) from **decode**
(memory-bandwidth-bound, steady) onto distinct GPU pools and streams the KV cache
between them, with a **KV-cache-aware router** that sends a request to the worker
most likely to already hold its prefix.

Three rules for getting a real result rather than a confusing one:

- **Hold GPU count constant.** A disaggregated 1+1 must be compared against an
  aggregated deployment using 2 GPUs, not 1. Otherwise you've measured "more
  hardware is faster".
- **Run `31_agg.sh` first.** It isolates the router's contribution from
  disaggregation's. Without it you cannot tell whether a gain came from
  splitting phases or just from a different vLLM build.
- **Benchmark the prefill-heavy workloads.** Disaggregation helps `rag` and
  `summarize`. On `chat` you will likely measure a small regression from the KV
  transfer — report that too; a measured "it didn't help here, and here's why"
  is a genuine finding.

Then sweep the **prefill:decode ratio** (1:1, 1:2, 2:1). The optimum is a function
of ISL/OSL, and plotting that curve is a strong result in its own right.

Set `PYTHONHASHSEED=0` on every worker — KV-aware routing hashes blocks across
processes and needs deterministic hashing. The scripts do this for you.

---

## 8. Deliverable

`docs/FINDINGS.md` is a skeleton with the sections judges look for. Fill it as you
go, not at the end.

The five claims worth making, in order:

1. **Which backend actually served Apertus, and what that cost** (the xIELU /
   TRT-LLM story). Nobody else will have this.
2. **The optimization delta, expressed in $/1M tokens**, not tokens/sec. Speed is
   the input; money is the study.
3. **The break-even volume** against each cloud comparator, with the utilization
   assumption stated out loud.
4. **The 8B-vs-70B cost curve** and why it's non-linear.
5. **The one assumption that would flip your conclusion.** Saying it before the
   judges find it is the difference between a benchmark dump and an analysis.

---

## 9. Risk register

| Risk | Early signal | Mitigation |
|---|---|---|
| NIM has no profile for Apertus | `10_list_profiles.sh` shows no TRT-LLM entry | Expected. Use vLLM/SGLang profile; make it Finding #1. |
| NIM image's engine too old | "architecture not supported" at startup | `nim/13_fallback_vllm.sh`; report the version gap. |
| 70B won't fit | `00_env_check.sh` total memory < 180 GB | FP8 + short `--max-model-len`, or make 8B the study and 70B a projection. |
| Weight download eats the session | Egress probe is slow | Start the 70B pull in hour 0, in the background. |
| Session expires | — | Push `artifacts/` off-box after every phase. |
| Only 1 GPU | `00_env_check.sh` | Drop Dynamo, go deeper on quantization + config sweeps. |
| Unsourced prices in the deck | `prices.json` still `verified:false` | The script warns on every run. Fix it in Phase 3, not Phase 7. |

---

## 10. Layout

```
optimized-apertus/
├── README.md                    this runbook
├── env/
│   ├── .env.example             credentials, image tags, paths
│   ├── 00_env_check.sh          GPU/topology/disk/egress recon
│   └── 01_login.sh              NGC login, image pull, weight pre-fetch
├── nim/
│   ├── 10_list_profiles.sh      which backend will serve Apertus (Finding #1)
│   ├── 11_serve.sh              parameterized NIM launch
│   ├── 12_smoke.sh              correctness + TTFT sanity
│   └── 13_fallback_vllm.sh      vanilla vLLM/SGLang escape hatch + baseline
├── bench/
│   ├── scenarios.json           5 workload shapes + concurrency ladder + SLOs
│   ├── 20_install.sh            AIPerf
│   ├── 21_sweep.sh              ladder with SLO-based early stop
│   └── 22_collect.py            exports -> results.csv
├── dynamo/
│   ├── 30_setup.sh              etcd + NATS control plane
│   ├── 31_agg.sh                aggregated baseline (+ KV router)
│   └── 32_disagg.sh             disaggregated prefill/decode
├── tokenomics/
│   ├── prices.json              PLACEHOLDERS — verify before quoting
│   └── 40_tokenomics.py         $/1M tokens, break-even, sensitivity
├── tools/
│   └── selftest.sh              run the whole analysis pipeline with no GPU
└── docs/
    └── FINDINGS.md              write-up skeleton
```

**Do this before you travel:** `bash tools/selftest.sh` generates synthetic
benchmark exports, runs the collector and the tokenomics calculator, and prints
a full report — on a laptop, without a GPU. If that passes, the only thing that
can break on LaunchPad is the serving itself.

All scripts read `.env` from the repo root. Make them executable once:
`chmod +x env/*.sh nim/*.sh bench/*.sh dynamo/*.sh`

---

## Sources

- [Swiss-ai-Weeks/optimized-apertus](https://github.com/Swiss-ai-Weeks/optimized-apertus) (challenge repo — empty as of writing)
- [swiss-ai/Apertus-70B-Instruct-2509](https://huggingface.co/swiss-ai/Apertus-70B-Instruct-2509) — xIELU, AdEMAMix, 65k context, Apache-2.0
- [swiss-ai/Apertus-8B-Instruct-2509](https://huggingface.co/swiss-ai/Apertus-8B-Instruct-2509)
- [Accelerate a World of LLMs on Hugging Face with NVIDIA NIM](https://huggingface.co/blog/nvidia/multi-llm-nim) — `NIM_MODEL_NAME="hf://..."`, `list-model-profiles`
- [NIM for LLMs CLI reference](https://docs.nvidia.com/nim/large-language-models/2.0.2/reference/cli-reference.html) — `nim-serve`, engine arg pass-through
- [TensorRT-LLM supported models](https://nvidia.github.io/TensorRT-LLM/models/supported-models.html) — Apertus absent
- [ai-dynamo/dynamo](https://github.com/ai-dynamo/dynamo) — quickstart, backends
- [Dynamo vLLM backend](https://docs.nvidia.com/dynamo/latest/backends/vllm/README.html) — `--is-prefill-worker`, `--connector`, `PYTHONHASHSEED=0`
- [Dynamo disaggregated serving](https://docs.dynamo.nvidia.com/dynamo/design-docs/disaggregated-serving)
- [ai-dynamo/aiperf](https://github.com/ai-dynamo/aiperf) — benchmark client
- [LLM Inference Benchmarking: Fundamental Concepts](https://developer.nvidia.com/blog/llm-benchmarking-fundamental-concepts/) — TTFT/ITL/TPOT definitions
- [NVIDIA LaunchPad](https://launchpad.nvidia.com/)
