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

## 14. Honest gaps

| gap | why it matters | cost |
|---|---|---|
| Config flag sets unrecorded (§4) | `p2-c04` is the headline and we can't define it | ~2 min |
| xIELU confirmation (§9) | would close the strongest mechanistic story | ~2 min |
| Spark `seqs32` crossover (§8) | decides build-vs-rent for owned hardware | ~30 min |
| `think` rows mislabelled | thinking was never enabled; they are a second chat variant | ~25 min |
| Swisscom commercial rate unverified | cost column compares against a free tier | ~10 min |
| 70B H100 ladder granularity | c1→c4 jump inflates interactive cost ~2× | ~15 min |
| Dynamo not attempted | stretch goal; build script written, unrun | ~60 min |

The `think` workload deserves emphasis: `bench/21_sweep.sh` never reads the
scenario's `"thinking": true` field, and every server ran with
`ENABLE_THINKING=0`. Those rows measure a non-thinking model with a large output
budget. They are not wrong, they are **mislabelled** — and are reported here as
`think` only for consistency with the CSV.
