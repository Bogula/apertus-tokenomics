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


Scaling efficiency is monotonic in the input:output ratio
workload	ISL/OSL	ratio	tok/s c1 → c8	scaling	ITL c1 → c8	per-user tok/s @ c8
agent	1024/1024	1.0	14.6 → 94.8	6.48×	68.7 → 70.3	14.3
chat	512/256	2.0	14.5 → 92.4	6.36×	66.6 → 64.8	15.4
batch	1024/128	8.0	14.7 → 87.9	5.99×	65.9 → 70.3	14.3
rag	4096/256	16	13.2 → 61.3	4.63×	68.8 → 91.7	11.1
summarize	7500/200	37.5	12.7 → 47.4	3.74×	70.5 → 129.2	8.0

Perfectly ordered, five for five. The more input tokens per output token, the worse the Spark batches — because prefill and decode compete for the same scarce resource, and chunked prefill steals decode steps. ITL confirms the mechanism: flat for decode-dominated shapes, +83% for the most prefill-dominated one.

I had this backwards. I predicted prefill-heavy work would suit the Spark because its FP4 compute is strong. The data says the opposite, decisively, and the monotonicity makes it more than an anecdote. Worth saying so in the write-up — a prediction, a measurement that refuted it, and a mechanism is a better story than a confirmation.

The machine's signature: per-user speed is pinned near 15 tok/s regardless of load. Not a wall you hit — a constant you live with. Worth noting that's roughly comfortable reading pace, so for one user it's usable; it just never gets faster, for anyone.

Cost, and the experiment you still need

At $0.22/h, best rung per workload:

workload	tok/s @ c8	$/1M out
agent	94.8	$0.65
chat	92.4	$0.66
batch	87.9	$0.70
rag	61.3	$1.00
summarize	47.4	$1.29

Your H100 chat baseline was $0.38. So the Spark loses on cost per token today — but it was still scaling at 80% efficiency at c8, capped by --max-num-seqs 8, not by hardware.

It needs 159 tok/s to match the H100. At 80% scaling efficiency, c16 lands around 165–175. The crossover is one rung away.

Your spark-v15-8b-seqs32 run only has chat c1 (14.4 tok/s, ITL 68.8 — identical single-stream, as expected). Finish it:




# Findings — Optimized Apertus 1.5

**HPE & NVIDIA Agentic AI Hackathon — Swiss AI Weeks, Zurich**
Challenge: *optimized-apertus* — run Apertus on NIM/Dynamo, optimize, and perform
a tokenomics study against cloud alternatives.

---

## 0. Executive summary

Five claims, each backed by a measurement below.

1. **NVIDIA's managed stack cannot run Apertus at all.** NIM rejects it, and
   NVIDIA's April 2026 vLLM container registers *no* Apertus architecture —
   not 1.5, not even the 1.0 release from September 2025. The model publisher
   says so too. The only path is the Swiss AI fork, which is a `.dev` build. → §1

2. **Serving configuration moves cost by 1.6× on identical hardware and weights.**
   Best config `p2-c04` (FP8 weights + FP8 KV): **$0.320/1M output**.
   Worst tested `co4` (NVFP4): **$0.516/1M**. → §4

3. **Quantization pays only where silicon supports it.** FP8 on Hopper: +3% and
   38% cheaper than NVFP4. NVFP4 on Hopper: emulated, −36%. NVFP4 on Blackwell
   GB10: software Marlin kernel, while FP8 in the *same model* runs on native
   CUTLASS. → §5

4. **The "70B costs 8× an 8B" rule is true only offline.** Fully batched, the
   ratio is 8.70× against a parameter ratio of 8.75×. Under an interactive SLO
   it blows out to 21×. The difference is batching you aren't allowed to do. → §6

5. **Self-hosting a 70B for interactive use is dominated.** Against the same
   weights hosted by Swisscom, it costs ~$25/1M (~$56 at realistic utilization)
   *and* delivers 35.3 tok/s per user against their 63.3. More expensive and
   slower, simultaneously. The 8B at $0.320/1M is the opposite: cheaper than
   anything purchasable. → §7

---

## 1. Finding #1 — the frontier lag

> **Refined by §14.** TensorRT-LLM stays closed — confirmed on x86 with JIT
> compilation offered. But NIM's Model-Free vLLM backend *does* serve
> Apertus 1.5, once the text tower is extracted. The measured claim is a
> distance, not a binary.

**Apertus 1.5 does not run on NVIDIA's managed inference stack.**

| Stack | Version | Result |
|---|---|---|
| NVIDIA NIM (LLM) | `nvcr.io/nim/nvidia/llm-nim` | ❌ architecture unknown |
| NIM (model-free vLLM) | `vllm-model-free-nim:2.1.1` | ❌ architecture unknown |
| NVIDIA vLLM container | `nvcr.io/nvidia/vllm:26.04-py3` | ❌ **no Apertus architecture registered at all** |
| TensorRT-LLM | current supported models | ❌ `ApertusForCausalLM` absent |
| **Swiss AI fork** | `ghcr.io/swiss-ai/vllm_apertus_1.5_release` | ✅ **works** (`v0.23.1rc1.dev1029+ga601a9d99`) |

### Exhibit A — NIM's own profile selector

`nim/10_list_profiles.sh swiss-ai/Apertus-v1.5-8B`, 2026-09-21. NIM downloaded
the full checkpoint, parsed the config, identified the architecture by name, and
evaluated every backend it ships — TensorRT-LLM, vLLM and SGLang (all three are
visible loading in the log):

```
INFO  profile_utils.py:766] Model architecture: ['Apertus1p5ForConditionalGeneration']
      is not supported in any available inference backends. Please check with NIM support.
ERROR info.py:62] No valid backend detected for model.
      Strategies applied: [FormatStrategy, ArchitectureStrategy]
```

This is not version skew that a flag could bridge. The vendor's own tooling
inspects the weights and concludes the model is unservable, then directs the
operator to open a support ticket.

The checkpoint NIM rejected contains, among other files:

```
model-apertus-model-0000{1..4}-of-00004.safetensors   # the LM
model-vision_tokenizer-model.safetensors              # image encoder
model-wavtokenizer-model.safetensors                  # audio encoder
Apertus_1_5_EU_Public_Summary.pdf
Apertus_1_5_EU_Code_of_Practice.pdf
```

A multimodal, EU-AI-Act-documented, Apache-2.0 model — with compliance paperwork
shipped alongside the weights — that the leading vendor's inference platform
cannot load at all.

### Exhibit B — the serving attempt

```
model type `apertus1p5` but Transformers does not recognize this architecture
```

### Exhibit C — the container registry

Reproducible in 30 seconds:

```bash
docker run --rm nvcr.io/nvidia/vllm:26.04-py3 python3 -c "
from vllm.model_executor.models.registry import ModelRegistry as R
print([a for a in R.get_supported_archs() if 'pertus' in a])"     # -> []
```

**Confirmed by the model publisher.** onprem.ai's card for the NVFP4 checkpoint
states plainly that the swiss-ai image is required *"until Apertus 1.5 support is
available in a native vLLM release."*

**Timeline.** Apertus 1.0 shipped September 2025. Apertus 1.5 shipped July 2026.
NVIDIA's April 2026 container supports neither.

### There is no `trust_remote_code` shortcut

Most new architectures bridge the support gap by shipping their modeling code in
the Hugging Face repo, so any stock `transformers` can load them with
`trust_remote_code=True`. Apertus 1.5 does not:

```python
c = AutoConfig.from_pretrained('swiss-ai/Apertus-v1.5-8B', trust_remote_code=True)
# config class: Apertus1p5Config
# model_type  : apertus1p5
# auto_map    : None          <- no in-repo modeling code
```

That config class resolves **only inside the swiss-ai container**, from their
patched `transformers`. `auto_map: None` means nothing is shipped in the repo for
a stock install to pick up.

So the dependency is not one fork but **two** — a patched `transformers` for the
model class and a patched `vLLM` for serving — and neither is a released package.
Any downstream tool that starts by calling `AutoModelForCausalLM.from_pretrained`
fails before it begins: NIM, TensorRT-LLM (including its experimental AutoDeploy
path, which converts *from* a loaded HF model), and Dynamo's bundled vLLM alike.
That is why `dynamo/33_build_apertus_image.sh` installs the vendor runtime *into*
the fork image rather than the reverse, and it is the structural reason the
frontier lag cannot be worked around with a flag.

**Implication.** Running a sovereign open-weights model in production means
running a vendor *fork* of the serving stack, not the vendor's supported product:
no NIM support contract, no TensorRT-LLM kernels, no pre-built engine profiles,
and you track the fork yourself. That cost is invisible in any per-token price
comparison, and it recurs with every model release.

It is not only "does it run" — it is also "does it run fast". See §9.

---

## 2. Environment

### H100 LaunchPad

| Item | Value |
|---|---|
| GPU | 2 × **H100 NVL**, 94 GB each (**sm_90 Hopper**) |
| Interconnect | NV12 NVLink |
| Host | 128 cores, 1 TB RAM, 1.35 TB disk |
| Price basis | **$3.12 / GPU-h** (gpus.io median; range 2.91–3.19) |

H100 is Hopper: **native FP8 tensor cores, no FP4 units whatsoever.** This single
fact explains §5.

### DGX Spark (on-prem comparator)

| Item | Value |
|---|---|
| GPU | **GB10** (sm_121, consumer Blackwell), arm64 |
| Memory | 128 GB unified LPDDR5X, **273 GB/s** |
| Power / price | 240 W / $4,699 |
| Cost basis | **$0.22/h** = $0.179 capex (3 yr) + $0.043 power @ $0.18/kWh |

273 GB/s against the H100's ~3.9 TB/s — a **14× bandwidth deficit**, with *more*
memory capacity (128 vs 94 GB). Capacity and throughput are independent axes and
the Spark demonstrates it clearly.

### Swisscom hosted endpoint

`swiss-ai/Apertus-v1.5-70B` — **identical weights to our self-hosted 70B.**
5 req/s, 10M input / 2.5M output budget, 60-minute bearer, free hackathon tier.

---

## 3. Serving configuration

```bash
docker run -d --gpus all -e CUDA_VISIBLE_DEVICES=0 \
  --shm-size=32GB --network=host --ipc=host \
  ghcr.io/swiss-ai/vllm_apertus_1.5_release:latest-amd64 \
  vllm serve swiss-ai/Apertus-v1.5-8B \
    --served-model-name apertus \
    --chat-template-content-format string \
    --tensor-parallel-size 1 --gpu-memory-utilization 0.85 \
    --max-model-len 8192 \
    --enable-auto-tool-choice --tool-call-parser apertus
```

Non-obvious requirements, each learned the hard way:

| Flag | Why |
|---|---|
| `--chat-template-content-format string` | 1.5's template is multimodal; plain text fails without it |
| `--tool-call-parser apertus` | model-specific, fork-only |
| `--network=host` | bridge networking + `--host 0.0.0.0` → Gloo *"Unable to find interface"* at TP>1 |
| `--gpus all` + `CUDA_VISIBLE_DEVICES` | `--gpus device=0,1` is comma-split by Docker |
| `fuse_allreduce_rms false` | CUDA graph capture fails at TP>1 otherwise |
| `:latest-arm64` on Spark | the amd64 tag gives `exec format error` |

**Smoke test — all six passed:** models ✅ · arithmetic (17×23=391) ✅ ·
Swiss German ✅ · tool calling ✅ · thinking markers ✅ · image input ✅

The multimodal and tool paths work, so the cost figures below describe a model
that can actually do the job.

---

## 4. H100 configuration sweep — 8B

`chat` (512/256), SLO knee, 1 × H100 NVL, $3.12/GPU-h, 100% utilization.

| config | conc | out tok/s | $/1M out | vs best |
|---|---:|---:|---:|---:|
| **`p2-c04` — FP8 weights + FP8 KV** ⭐ | c32 | **2,707.0** | **$0.320** | — |
| `co3` | c64 | 2,638.9 | $0.328 | +2.6% |
| `conf02` | c64 | 2,248.4 | $0.385 | +20% |
| `v15-8b-tp1-len8k` (baseline) | c128 | 2,260.3 | $0.383 | +20% |
| `co4` — NVFP4 | c16 | 1,679.2 | $0.516 | +61% |

**`p2-c04` is the best config on all six workloads**, and the tokenomics script
selects it for every one:

| workload | `co3` | `p2-c04` | Δ |
|---|---:|---:|---:|
| summarize | 556.1 @ c64 | **607.9 @ c32** | **+9.3%** |
| rag | 1,067.9 @ c64 | **1,139.7 @ c32** | **+6.7%** |
| agent | 2,671.5 @ c128 | **2,781.4 @ c128** | +4.1% |
| think | 1,800.8 @ c64 | **1,871.2 @ c32** | +3.9% |
| chat | 2,638.9 @ c64 | **2,707.0 @ c32** | +2.6% |
| batch | 1,804.4 @ c128 | 1,805.9 @ c64 | +0.1% |

Against the original baseline: **+20% chat, +23% agent.**

**The concurrency column matters more than the throughput column.** `p2-c04`
reaches those numbers at *half* the concurrency — c32 where `co3` needed c64.
The FP8 KV cache halves bytes per cached token, so twice as many sequences fit
before KV pressure forces queueing. That is a latency win as much as a
throughput win: shorter queues at any real-world load.

> **Open item.** The exact flag deltas between `co1`/`conf02`/`co3`/`co4` were set
> at the console and never recorded. The numbers are sound; the *attribution* is
> not. Recover with `docker inspect <container> --format '{{json .Config.Cmd}}'`.

---

## 5. Finding #2 — quantization pays only where silicon supports it

### NVFP4 on H100 (`co4`): a prefill regression

NVFP4 cost **+57%** vs `co3`. The SLO broke on **TTFT (546 ms)**, not ITL
(4.9 ms — *better* than baseline's 6.1 ms).

**Mechanism.** 4-bit weights shrink bytes read per token. Decode is
bandwidth-bound → decode improves. Prefill is compute-bound → dequantize adds
arithmetic with no bandwidth saving to trade against → prefill collapses. And
on sm_90 there are **no FP4 tensor cores at all**, so this is emulation.

The penalty scales monotonically with prefill share:

| workload | ISL:OSL | NVFP4 / bf16 |
|---|---:|---:|
| agent | 1:1 | 0.96 |
| chat | 2:1 | 0.91 |
| batch | 8:1 | 0.76 |
| rag | 16:1 | 0.69 |
| summarize | 37:1 | 0.62 |

**Five for five.**

### FP8 on H100 (`p2-c04`): the mirror image

Same idea, opposite outcome — because H100 has native FP8 tensor cores:

| | `co4` (NVFP4) | `p2-c04` (FP8) |
|---|---:|---:|
| chat vs `co3` | **−36%** | **+2.6%** |
| chat $/1M | $0.516 | **$0.320** |
| SLO knee | c16 | c32 |

And the workload ordering inverts: FP8's biggest gains are on the two most
prefill-heavy workloads (summarize +9.3%, rag +6.7%), because prefill is
compute-bound and H100's FP8 tensor cores do roughly double the bf16 FLOPs.
(Not a clean law — `batch` at +0.1% sits out of order, and its `co3` comparison
point was c128 vs c64.)

### NVFP4 on DGX Spark (sm_121): emulation again, different reason

vLLM's kernel selection, from one model load:

```
Selected CutlassFP8ScaledMMLinearKernel for CompressedTensorsW8A8Fp8
Using MarlinNvFp4LinearKernel for NVFP4 GEMM
```

**A natural experiment inside a single forward pass.** onprem.ai's checkpoint is
mixed-precision — MLP in NVFP4, attention in FP8, embeddings and the 266k output
head in BF16 (they found 4-bit attention produced NaN logits, xIELU's squaring
amplifying the noise). On GB10 the FP8 tier gets a **native CUTLASS kernel**
while the NVFP4 tier gets a **software emulation**.

Known and open: vLLM [#50925](https://github.com/vllm-project/vllm/issues/50925),
[#43906](https://github.com/vllm-project/vllm/issues/43906),
[#54666](https://github.com/vllm-project/vllm/issues/54666) (a request to try
B12X *before* the Marlin fallback).
[PR #52708](https://github.com/vllm-project/vllm/pull/52708) adds SM121 build
targets but **explicitly excludes FP4 kernels** and is unmerged. NVIDIA's own
engineers state native FP4 kernels exist in FlashInfer but do not yet outpace
the Marlin fallback.

> **The slide line.** GB10 is marketed on NVFP4. vLLM still selects a software
> kernel for NVFP4 on sm_121 while running FP8 on native CUTLASS in the same
> model. Buying the newest number format bought an emulator.

---

## 6. Finding #3 — model scaling is a latency question, not a parameter question

`batch` is the only workload with no latency SLO, so it is the only one where
both models batch to their natural limit. That makes it the only clean read on
size scaling.

| | 8B (`co3`) | 70B FP8 TP=1 | ratio |
|---|---:|---:|---:|
| **batch** (no SLO) | 1,804.4 tok/s | 207.5 tok/s | **8.70×** |
| chat (500 ms TTFT SLO) | 2,638.9 tok/s | 123.0 tok/s | **21.5×** |

Parameter ratio: **8.75×**.

Fully batched, the cost ratio lands within 1% of the parameter ratio. Under an
interactive SLO it is 2.5× worse — because the SLO stops the 70B at c4 while the
8B runs to c64.

> The "a 70B costs 8× an 8B" rule of thumb is true for offline work and badly
> wrong for interactive work. The extra 2.5× is not parameters — it is the
> batching the latency budget forbids.

### 70B: one GPU beats two

| | 70B bf16 TP=2 | 70B FP8 TP=1 |
|---|---:|---:|
| chat, best measured | 145.1 tok/s @ c4 | 123.0 tok/s @ c4 |
| GPUs / basis | 2 / $6.24 h | **1 / $3.12 h** |
| **$/1M output** | $11.95 | **$7.05** |

−15% throughput, **−41% cost**. FP8 weights (71.02 GiB) plus an FP8 KV cache
(12.78 GiB → 83,728 tokens, 10.2× concurrency at 8k) fit a 70B on a single
94 GB card.

*Caveats:* TP=2 passed its SLO at c4 and stopped only because we stopped it;
TP=1 FP8 failed at c4 (561 ms TTFT) and stopped itself. The comparison also
moves two variables at once — precision and tensor parallelism.

---

## 7. Finding #4 — build vs buy, identical weights

The one comparison in this study with **zero model confounds**: Swisscom serves
`swiss-ai/Apertus-v1.5-70B`, the same checkpoint we self-host.

Measured at **concurrency 1 only, deliberately.** Throughput at higher
concurrency on a shared, rate-limited, autoscaled endpoint measures their
provisioning, not the model. We measured what a user experiences and priced what
a customer pays.

### Per-user decode: theirs is flat, ours degrades

| ISL | Swisscom tok/s/user | self-hosted 70B FP8 TP=1 |
|---:|---:|---:|
| 512 (chat) | 63.3 | 35.3 |
| 1,024 (agent) | 62.8 | 35.4 |
| 4,096 (rag) | 62.6 | 30.9 |
| 7,500 (summarize) | 62.0 | **25.5** |

Theirs varies **2%** across a 15× range of prompt length. Ours drops **28%**.
Longer prompts mean a larger KV cache read on every decode step; on a single
H100 already holding 71 GB of weights that read is a meaningful share of
bandwidth. Sharded across many GPUs it barely registers.

### TTFT crosses over at ≈2,000 input tokens

Decomposing TTFT into fixed overhead plus prefill:

| | fixed overhead | prefill rate |
|---|---:|---:|
| self-hosted | ~73 ms | ~3,520 tok/s |
| Swisscom | ~415 ms (network + queue) | ~8,700 tok/s |

Measured, bracketing the crossover:

| workload | ISL | self-hosted TTFT | Swisscom TTFT |
|---|---:|---:|---:|
| chat | 512 | **218 ms** | 475 ms |
| agent | 1,024 | **320 ms** | 501 ms |
| rag | 4,096 | 1,127 ms | **970 ms** |
| summarize | 7,500 | 2,203 ms | **1,278 ms** |

> Under ~2k-token prompts, self-hosting wins on responsiveness — there is no
> internet in the path. Over ~2k, the hosted endpoint wins, because its prefill
> hardware outruns our network penalty.

### The verdict: self-hosting a 70B is dominated

| | self-hosted 70B | Swisscom |
|---|---:|---:|
| $/1M output @100% util | ~$25 | free tier (frontier APIs ≈ $15) |
| $/1M output @45% util | **~$56** | unchanged — no utilization exposure |
| per-user speed | 35.3 tok/s | **63.3 tok/s** |
| per-user speed, TP=2 | 38.7 tok/s | — |

Normally you would expect a trade: pay more, get better latency. Here
self-hosting is worse on **both** axes at once. TP=2 reaches only 38.7 tok/s per
user, so a second GPU does not close the gap; matching them would take roughly
TP=4 (~$12.48/h), widening the cost gap further.

**Latency is bought with GPUs and does not amortize across users the way
throughput does.**

So the case for self-hosting a 70B rests entirely on data residency, weight
ownership and deprecation risk — not on price or performance. The 8B is the
opposite: at **$0.320/1M** it is cheaper than anything purchasable.

*Caveats, stated rather than buried:* their batching is shared across every
hackathon team, so these are demo-day numbers, not commercial-tier numbers; the
free tier has no published per-token price, so the cost column compares against
a free service and a frontier-API reference rather than their commercial rate.

---

## 8. The DGX Spark — capacity without bandwidth

Apertus-v1.5-8B, bf16, `--max-num-seqs 8`, 8k context.

| | DGX Spark GB10 | H100 NVL (`p2-c04`) |
|---|---:|---:|
| cost basis | $0.22/h | $3.12/h |
| chat, best | 92.4 tok/s @ c8 | 2,707.0 @ c32 |
| $/1M out | **$0.661** | **$0.320** |
| per-user speed | ~15 tok/s, ITL ~67 ms | — |
| KV capacity | **85.04 GiB** / 696,656 tokens | 47.38× @ util 0.70 |
| max concurrency | **85.04×** | 47.38× |

**(a) More KV capacity than an H100, a fraction of the bandwidth.** It can *hold*
more concurrent sessions than an H100 while being unable to *serve* them quickly.

**(b) ITL ~67 ms at concurrency 1** misses a 50 ms interactive budget with a
single user and never recovers. Disqualifying for chat; irrelevant for batch,
overnight, or residency-mandated work.

**(c) Batching is nearly free, and the ISL:OSL ratio predicts how free:**

| workload | ISL:OSL | c1→c8 speedup |
|---|---:|---:|
| agent | 1:1 | 6.48× |
| chat | 2:1 | 6.36× |
| batch | 8:1 | 5.99× |
| rag | 16:1 | 4.63× |
| summarize | 37:1 | 3.74× |

Monotonic, five for five — the same ordering variable as §5, via a different
mechanism. Decode reads the full weight matrix once per step regardless of batch
size, so on a bandwidth-starved device the marginal user is almost free.

At c8 it was still scaling at ~80% efficiency — **not yet at the bandwidth wall.**

**Unfinished: the crossover test.** Parity needs **186 tok/s** (vs `p2-c04`) or
**159** (vs baseline). It is at 92.4, capped at `--max-num-seqs 8`. Naive
extrapolation puts parity between c16 and c32 — exactly where the cap sits.
Until that runs, the honest claim is *"2× the cost per token and 14× slower per
user, but not pushed to its limit."*

> Caveat for the slide: $0.22/h assumes 100% utilization of a bought box. At 45%
> it is ~$1.47/1M and loses decisively. Rented hardware has no such exposure —
> you stop paying when you stop using it.

---

## 9. The xIELU tax — an open thread worth pulling

Both platforms log:

> `CUDA-fused xIELU not available (No module named 'xielu') – falling back to a Python version.`
> `For CUDA xIELU (experimental), pip install git+https://github.com/nickjbrowning/XIELU`

Two independent estimates point at the same ~2× gap:

1. **Single-stream.** `co3` did 215 tok/s at c1 against baseline's 159 (+35%) —
   a gain at c1 with unchanged batching is the signature of a *kernel* change,
   not a scheduling change.
2. **Model scaling.** The 8B→70B `batch` ratio is 8.70× where first principles
   predict ~4.4× (70B at 1 byte/param vs 8B at 2). The 70B has **80 layers to
   the 8B's ~32** — 2.5× more Python activation launches per token.

The Python fallback costs a kernel launch and a memory round-trip per layer per
token. Confirmation is one command: `docker logs <co3> | grep -i xielu`. If the
warning is absent on `co3` and present on the baseline, this closes — and ties
back to §1:

> The frontier-lag tax is not only "does the vendor stack load it." It is also
> that a new activation function costs roughly a third of your single-stream
> latency until somebody writes the CUDA kernel — and on a 70B, nobody has.

---

## 10. Beyond cost

| factor | self-hosted | Swisscom-hosted | closed frontier API |
|---|---|---|---|
| Data residency | yours | Swiss | vendor-controlled |
| Weights + training data | Apache 2.0, open data | same model | closed |
| EU AI Act documentation | **shipped in the weights repo** (Public Summary + Code of Practice PDFs) | same model | partial |
| Rate limits | your hardware | 5 req/s (hackathon tier) | vendor tiers |
| Deprecation risk | none — weights are yours | operator-controlled | vendor-controlled |
| Serving stack support | **fork, unsupported** (§1) | operator's problem | n/a |
| Kernel maturity | **activation on Python fallback** (§9) | same | mature |

The last two rows are what this study adds that a price comparison cannot:
**sovereignty is not free, and its price appears as engineering time and a
throughput discount, not as a line item.**

---

## 11. The assumption that would flip our conclusion

**Utilization.** Every self-hosted figure divides a fixed hourly cost by
throughput at the SLO knee — i.e. assumes the GPU is saturated whenever you pay
for it. Real traffic is diurnal.

| | @100% | @45% | @20% |
|---|---:|---:|---:|
| 8B `p2-c04` | $0.320 | $0.71 | $1.60 |
| 70B FP8 TP=1 | ~$25 | ~$56 | ~$126 |
| DGX Spark 8B | $0.661 | $1.47 | $3.31 |

A per-token API has **zero** utilization exposure — that is the entire product.
So break-even is not "how many tokens per month" but "how many tokens per month,
*arriving how evenly*." 10M tokens in a nightly batch should be self-hosted. The
same 10M as interactive chat, nine to five, should not.

**Second-order:** if the Spark crossover test (§8) shows parity at c32, the capex
argument changes character — an idle bought box costs the same as a busy one, so
*low* utilization favours owned hardware over rented, while still favouring
per-token APIs over both.

---

## 12. Decision matrix

| workload | recommendation | $/1M out @45% |
|---|---|---:|
| 8B, interactive | **self-host** (`p2-c04`) | $0.71 |
| 8B, offline | **self-host** | $1.07 |
| 70B, offline / batch | **self-host** | $9.28 |
| 70B, interactive | **buy tokens** | $56 self-hosted vs ≈$15 API |
| 70B, prompts > 2k, latency-sensitive | **buy tokens** (§7) | — |
| any, data residency mandated | **self-host and pay for it** | — |

---

## 13. Reproduction

```bash
git clone git@github.com:Bogula/apertus-tokenomics.git && cd apertus-tokenomics
cp env/.env.example .env && $EDITOR .env      # HF_TOKEN, SWISSCOM_API_KEY
bash env/00_env_check.sh && bash env/01_login.sh

bash nim/14_nim_v15_attempt.sh                # leg A: documented failure

MODEL=swiss-ai/Apertus-v1.5-8B TP_SIZE=1 GPU_MEM_UTIL=0.85 MAX_MODEL_LEN=8192 \
  RUN_TAG=v15-8b-tp1-len8k bash serve/15_serve_v15.sh
bash serve/16_smoke_v15.sh                    # must return 391

SYSTEM=v15-8b-tp1-len8k TOKENIZER=swiss-ai/Apertus-v1.5-8B \
  bash bench/21_sweep.sh all

REQ_COUNT=50 bash bench/26_remote_sweep.sh swisscom-apertus-70b chat   # leg C

python3 bench/22_collect.py --root artifacts/bench -o artifacts/results-all.csv
python3 tokenomics/40_tokenomics.py --results artifacts/results-all.csv \
        --gpu H100-NVL-94GB --gpus-per-replica 1
```

Results are kept per machine under `artifacts/bench/$SYSTEM/` so H100, Spark and
hosted runs never overwrite each other.

**Gotchas that cost us hours:** it is `NIM_PORT`, not `PORT` · `TOKENIZER` must
match the served model or every cost figure is silently wrong · `batch` has no
SLO so it never early-stops · `.env` must use `${VAR:-default}` or it clobbers
command-line overrides.

---

## 14. Finding #5 — NIM serves Apertus 1.5 after all, via the text tower

This refines §1. The frontier lag is real, but it is not a wall, and the sharper
claim is worth more than the binary one.

### What actually blocks

`apertus1p5` is unknown to upstream vLLM and transformers — that part of §1
stands. But the **language model inside the omni checkpoint is plain
`ApertusForCausalLM` / `model_type: apertus`**, which upstream vLLM implements,
xIELU included. Extracting it strips the fork requirement as a side effect.
Model-Free NIM then picks its backend by *image* rather than by flag
(`model-free-nim` = vLLM, `sglang-model-free-nim` = SGLang), so a NIM path
exists that never touches TensorRT-LLM.

TensorRT-LLM itself remains closed, and this is now confirmed on the reference
platform rather than inferred: on 2× H100 NVL (x86), `list-model-profiles`
reports **"Compilable to TRT-LLM using just-in-time compilation: `<None>`"**.
With JIT HF→TRT-LLM compilation on offer, it still declines. That is a model
registry fact, not an architecture or tuning fact.

| | |
|---|---|
| Image | `nvcr.io/nim/nvidia/model-free-nim:latest` — multi-arch, arm64 and amd64 |
| Stack | NIM 2.0.13, vLLM v0.28.0, profile `vllm-tp1-pp1` (`d655bc3a…`) |
| Model | Apertus 1.5 8B **text tower**, bf16, TP=1, `--max-model-len 8192` |
| Hosts | DGX Spark (GB10, arm64) and H100 NVL (x86) — same profile id on both |
| Smoke | Coherent German, `stop_reason 68` (native Apertus EOS), chat template applied |

Build and launch: `nim/17_text_tower_for_nim.py` + `nim/18_serve_text_tower.sh`.

### Where it lands

SLO-compliant best rung, one H100 NVL, from `bench/27_slo_table.py`:

| workload | NIM-MF (bf16) | `p2-c04` (FP8) | `v15-8b-tp1` (bf16 fork) | NIM $/1M | vs `p2-c04` |
|---|---|---|---|---:|---:|
| chat | 1,832 @c16, 355 ms | 2,707 @c32 | 2,260 @c128 | $0.47 | −32% |
| rag | 636 @c8, 1,244 ms | 1,002 @c16 | 432 @c4 | $1.36 | −37% |
| summarize | 386 @c8, 2,351 ms | 569 @c16 | *not measured* | $2.24 | −32% |
| agent | 1,771 @c16, 605 ms | 2,781 @c128 | 2,269 @c128 | $0.49 | −36% |
| think | 1,229 @c16, 316 ms | 1,871 @c32 | 1,346 @c64 | $0.71 | −34% |
| batch | 2,434 @c128 | 1,806 @c64 | 1,488 @c128 | $0.36 | **+35%** |

### What the numbers mean, and what they do not

**The −32% to −37% is almost certainly precision, not packaging.** The spread is
flat across five very different ISL/OSL ratios, which a scheduler or runtime
difference would not produce. NIM runs the text tower in **bf16**; `p2-c04` is
FP8 weights plus FP8 KV. Against the *bf16* fork the picture is not a deficit at
all: −16% on chat, −18% on agent, −28% on think, but **+47% on rag** and
**+35% on batch**.

So the honest reading is: **at equal precision, upstream vLLM under NIM is not
behind the fork — it is differently shaped.** Weaker where decode dominates,
clearly stronger where prefill does.

**This leg is text-only by construction.** No image input, no audio input, and
therefore no cost-per-minute-of-audio figure (§ multimodal). Leg B is not
replaced by it.

**The concurrency ceiling is the real structural difference.** The fork holds
`chat` TTFT flat from c64 (492 ms) to c128 (461 ms). NIM doubles it from c16
(355 ms) to c32 (686 ms), and on `batch` at c128 posts 4,496 ms against the
fork's 754 ms — 6× the TTFT for 64% more throughput. That is prefill batching
bought at the cost of queueing. `max_num_batched_tokens` and the chunked-prefill
policy are the suspects, and NIM sets both itself.

**NIM overrides engine arguments silently.** `--gpu-memory-utilization` passed on
the command line was replaced by NIM's own `0.85` in the actual launch line;
`--max-model-len` and `--max-num-seqs` came through. Read the `Launching vLLM:`
line in the container log rather than trusting what was passed. On dedicated HBM
this is harmless; on the Spark's unified 128 GB it is not.

**The `think` caveat from §15 applies here too**, and more strongly: Model-Free
NIM exposes no thinking switch at all, so that row is a second chat variant with
a large output budget.

### Operational notes that cost an hour each

- **Profile ids are stable across architectures; their compatibility is not.**
  `d655bc3a…` is the same id on GB10 and H100 NVL. What changes is which ids
  appear under "compatible and runnable", following GPU count and memory. Read
  the section headings, not just the list.
- **`--network=host` makes port collisions real.** NIM runs its own vLLM on 8001
  behind the API on 8000. A leftover container answers `/v1/health/ready` within
  seconds — from the *wrong server* — while the new one dies with `Address
  already in use`. A smoke test replying `The model 'apertus' does not exist` is
  this, not a naming bug.
- **The NIM cache must be group-writable**: container runs as UID 1000, GID 0.
  `chgrp -R 0 "$CACHE_DIR" && chmod -R g+rwX "$CACHE_DIR"`.
- **`model-free-nim` needed no `docker login`** on either host — no nvcr.io
  credential was present in `~/.docker/config.json` and both pulls succeeded.

### The missing cell

**FP8 on the text tower under NIM.** Until that runs, "NIM vs fork" measures
precision for two thirds of its margin and packaging for the rest. It is the
single highest-value remaining experiment in this study, and it is cheap: the
checkpoint already exists in extracted form.

## 15. Honest gaps

| gap | why it matters | cost |
|---|---|---|
| Config flag sets unrecorded (§4) | `p2-c04` is the headline and we can't define it | ~2 min |
| xIELU confirmation (§9) | would close the strongest mechanistic story | ~2 min |
| Spark `seqs32` crossover (§8) | decides build-vs-rent for owned hardware | ~30 min |
| `think` rows mislabelled | thinking was never enabled; they are a second chat variant | ~25 min |
| Swisscom commercial rate unverified | cost column compares against a free tier | ~10 min |
| 70B H100 ladder granularity | c1→c4 jump inflates interactive cost ~2× | ~15 min |
| Dynamo not attempted | stretch goal; build script written, unrun | ~60 min |
| No FP8 run of the text tower under NIM (§14) | two thirds of the NIM deficit is unattributed | ~45 min |
| `v15-8b-tp1` has no `summarize` row | the bf16 reference is missing the shape where FP8 helps most | ~15 min |
| `v15-8b-tp1-len8k` tag carries no machine | cannot prove it ran on the same H100 NVL as the rest | ~2 min |
| Fork and NIM swept different concurrency ladders | fork untested at c8/c32, NIM at c64/c128 for SLO'd shapes | ~40 min |

The `think` workload deserves emphasis: `bench/21_sweep.sh` never reads the
scenario's `"thinking": true` field, and every server ran with
`ENABLE_THINKING=0`. Those rows measure a non-thinking model with a large output
budget. They are not wrong, they are **mislabelled** — and are reported here as
`think` only for consistency with the CSV.


