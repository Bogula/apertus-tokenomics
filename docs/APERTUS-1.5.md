# Apertus 1.5 — everything that will bite you

Verified against the model cards and the Swisscom Hacker Guide, September 2026.
Read this before you write a line of config. Almost every default assumption from
Apertus 1.0 (`-2509`) is wrong for 1.5.

---

## 1. The headline problem: 1.5 does not run on stock anything

The architecture identifier is **`apertus1p5`**, and it is **not yet in upstream
vLLM or Transformers** — upstreaming is in progress. Swiss AI ships forks:

| Stack | What you must use |
|---|---|
| vLLM | `ghcr.io/swiss-ai/vllm_apertus_1.5_release:latest-amd64` (or `-arm64`) |
| Transformers | `pip install "transformers[torch,vision,audio] @ git+https://github.com/swiss-ai/transformers.git@3797303"` |
| SGLang | listed as an ecosystem target, but vLLM is the supported path |

**Consequence for this challenge:** NIM ships its own engine builds. If that
engine predates `apertus1p5`, **NIM cannot load Apertus 1.5 at all** — not a
tuning problem, a model-registry problem. This is on top of the older issue that
`ApertusForCausalLM` is absent from TensorRT-LLM's supported-model list, so there
is no TRT-LLM engine for the xIELU activation either.

Do not treat this as a failure to hide. It is the most quotable finding in the
whole challenge:

> *"The vendor-optimized serving stack lags the open-model frontier. We measured
> the gap in weeks of engineering and in dollars per million tokens."*

`nim/14_nim_v15_attempt.sh` captures the evidence properly so you can say that
with receipts rather than anecdote.

---

## 2. Gated repo — do this **now**, not on hackathon morning

Both v1.5 repos require you to **accept the Acceptable Use Policy while logged in
to Hugging Face** before the weights download. An un-accepted repo fails with a
401 that looks like a broken token.

1. Log in to Hugging Face.
2. Open `swiss-ai/Apertus-v1.5-8B` and `swiss-ai/Apertus-v1.5-70B`, click **Agree**.
3. Create a token with read access and put it in `.env` as `HF_TOKEN`.
4. Verify: `hf download swiss-ai/Apertus-v1.5-8B --include config.json`

---

## 3. Serving commands (verbatim from the model card)

**8B:**

```bash
vllm serve swiss-ai/Apertus-v1.5-8B \
  --chat-template-content-format string \
  --gpu-memory-utilization 0.6 \
  --max-model-len 262144 \
  --enable-auto-tool-choice \
  --tool-call-parser apertus
```

**70B:**

```bash
vllm serve swiss-ai/Apertus-v1.5-70B \
  --chat-template-content-format string \
  --tensor-parallel-size 4 \
  --gpu-memory-utilization 0.8 \
  --max-model-len 262144 \
  --enable-auto-tool-choice \
  --tool-call-parser apertus
```

Flag by flag, and why each one matters to you:

- `--chat-template-content-format string` — **required**. The chat template
  expects string content, not the OpenAI content-parts array. Omit it and
  multi-part messages break in confusing ways.
- `--gpu-memory-utilization 0.6` on the **8B** — note it's *lower* than the
  usual 0.9. The multimodal encoders plus a 262k-token KV allocation need
  headroom. Raising this is one of your optimization levers, but it OOMs fast.
- `--max-model-len 262144` — see §5. This is the single biggest performance knob
  in the whole study.
- `--enable-auto-tool-choice --tool-call-parser apertus` — the tool parser is
  model-specific and only exists in the fork.
- `--compilation-config.pass_config.fuse_allreduce_rms false` — **add this if
  CUDA graph capture fails with `--tensor-parallel-size > 1`.** Documented known
  issue. It will hit you on the 70B leg.

---

## 4. Thinking mode — and the "thinking tax"

Thinking is **off by default**. Enabled, the model reasons between
`<|inner_prefix|>` and `<|inner_suffix|>` before the visible answer.

- Transformers: `apply_chat_template(..., enable_thinking=True)`
- vLLM: `--reasoning-parser apertus` plus
  `--default-chat-template-kwargs.enable_thinking true`
- The card warns: **budget generously for `max_new_tokens`** — reasoning can be
  several times longer than the answer, and a truncated generation may stop
  before the answer even starts.
- The markers are deliberately **not** stripped by `skip_special_tokens=True`, so
  you can parse the deliberation span out and count it.

**This is a tokenomics goldmine, and nobody else will measure it.** You pay for
every reasoning token, and the user sees none of them. So there are two different
costs per million tokens:

- **$/1M billed tokens** — what the GPU actually produced
- **$/1M visible tokens** — what the user received

The ratio between them is the *thinking tax*. `bench/24_thinking_tax.py`
measures it on a fixed prompt set. Then the real question becomes: for which
workloads does the accuracy gain justify a 3–5× cost multiplier? That is exactly
the performance/cost trade-off the challenge is asking about, and it's a far
more interesting answer than another tokens-per-second chart.

---

## 5. 262,144-token context changes the arithmetic

Four times the 1.0 context. KV cache is preallocated per sequence slot, so at
full context length you hold very few concurrent sequences — which is precisely
why the card's own 8B example sits at `--gpu-memory-utilization 0.6`.

Sweep `--max-model-len` at **8k / 32k / 131k / 262k** and plot concurrent
sequences and $/1M tokens against it. Expect the cost curve to be dramatic. The
finding writes itself: *"serving the advertised context costs N× more per token
than serving the context your workload actually uses."*

---

## 6. Multimodal — images and audio in, text out

New in 1.5, and it opens a cost axis no text-only study will have:

- **Audio contributes 40 tokens per second.** So one minute of speech = 2,400
  input tokens. You can quote **cost per minute of audio transcribed** and
  compare it against dedicated speech APIs.
- Images are one content block each; placeholder/media count mismatches raise an
  error rather than being silently reassigned.
- **No native video.** Extract frames and pass them as images.
- **The vision and audio tokenizers stay in float32** on half-precision loads, by
  design, and the card says not to re-cast with `.half()`/`.to(dtype)`. If you
  quantize, quantize the language model and **leave the encoders alone** — this
  is where a naive FP8 pass will silently wreck multimodal quality.
- Vocabulary: the LM head covers 131,072 text tokens; logits are padded to
  266,752 so image and audio tokens can never be generated.

---

## 7. The Swisscom endpoint — your ideal comparator

The Swisscom Hacker Guide gives hackathon participants a **hosted Apertus 1.5
70B** endpoint. This is the strongest possible cloud comparator: *the same model,
same weights*, self-hosted versus hosted. No architecture caveats, no "well, it's
a different model" objection from the judges.

```
base_url: https://api.swisscom.com/products/swiss-ai-weeks/apertus-1.5-70b/v1
model:    swiss-ai/Apertus-v1.5-70B
auth:     Bearer $SWISSCOM_API_KEY
```

Get a key via **The Keymaker** → select Swisscom → the email you registered on
Luma → key arrives by mail.

**Operational limits you must design your benchmark around:**

| Limit | Value | What it forces |
|---|---|---|
| Rate | **5 requests/s** | Cap client concurrency. A 256-concurrency sweep will just measure their rate limiter. |
| Input budget | **10,000,000 tokens** | Finite. A careless sweep burns it in one run. |
| Output budget | **2,500,000 tokens** | The tighter of the two — budget it deliberately. |
| Bearer lifetime | **60 minutes** | A two-hour sweep dies mid-run. Refresh, or split into sub-hour chunks. |

`bench/23_swisscom.sh` enforces a token budget before each rung, caps concurrency
at the documented rate, and fails loudly on a 401 rather than silently recording
zeros.

**Budget arithmetic before you start:** at `rag` shape (4096 in / 256 out), one
request costs ~4,352 tokens. The 2.5M *output* budget allows roughly 9,700
requests total. That is enough for a careful comparison ladder and nothing more,
so spend it on the two or three operating points that matter.

---

## 8. Model facts for the report

| | Apertus-v1.5-8B | Apertus-v1.5-70B |
|---|---|---|
| Actual params | ~9B | ~70B |
| Continued-pretrain tokens added | 4T multimodal | 2T multimodal |
| Total pretraining tokens | 19T | 17T |
| Context | 262,144 | 262,144 |
| Precision | bfloat16 | bfloat16 |
| Multimodal | image + audio in | image + audio in |
| Architecture | decoder-only, xIELU, AdEMAMix | same |
| License | Apache 2.0 + Acceptable Use Policy | same |

Post-training: SFT plus QRPO, DPO and RLVR. Technical report not yet published as
of writing — so benchmark numbers you produce are genuinely new information.

---

## 9. Suggested study structure given all of the above

Three legs, each answering a different question:

1. **NIM + Apertus 1.0 (`-2509`)** — does the vendor stack help at all on this
   model family? Gives you the NIM measurement the challenge asks for.
2. **swiss-ai vLLM fork + Apertus 1.5** — the real deployment. All optimization
   work happens here: context length, quantization, batching, thinking on/off.
3. **Swisscom hosted 1.5-70B** — the same model as a service. The tokenomics
   comparison, with no confounds.

Leg 1 versus leg 2 is the *"what does being on the frontier cost you"* story.
Leg 2 versus leg 3 is the *"build versus buy"* story. Together they're a complete
answer to the challenge, and the seam between them — that the optimized stack
can't yet run the model you actually want — is the insight most teams will miss.

---

## Sources

- [swiss-ai/Apertus-v1.5-8B](https://huggingface.co/swiss-ai/Apertus-v1.5-8B) — serving commands, thinking mode, multimodal notes, known issues
- [swiss-ai/Apertus-v1.5-70B](https://huggingface.co/swiss-ai/Apertus-v1.5-70B)
- [Swisscom Hacker Guide](https://zh.ai-weeks.ch/tools/swisscom-hacker-guide) — endpoint, limits, key process
- [TensorRT-LLM supported models](https://nvidia.github.io/TensorRT-LLM/models/supported-models.html) — Apertus absent
