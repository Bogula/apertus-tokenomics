# Apertus tokenomics

- Cost basis: **1 x H100-NVL-94GB** = $3.12/h on-demand, $1.63/h amortized-owned

- Utilization assumption: **45%** (730 h/month billed)

- Operating point: highest-throughput configuration that still met its p95 latency SLO.

- Unverified prices are flagged; see `tokenomics/prices.json`.


## Self-hosted cost per million tokens

| system | workload | conc | out tok/s | TTFT p95 (ms) | $/1M out (100% util) | $/1M out (@util) | $/1M blended (@util) |
|---|---|---:|---:|---:|---:|---:|---:|
| apertus-p2-c04-fp8weights-fp8kv | agent | 128 | 2,781 | 591 | $0.31 | $0.69 | $0.34 |
| apertus-p2-c04-fp8weights-fp8kv | batch | 64 | 1,806 | 613 | $0.48 | $1.07 | $0.12 |
| apertus-p2-c04-fp8weights-fp8kv | chat | 32 | 2,707 | 368 | $0.32 | $0.71 | $0.24 |
| apertus-p2-c04-fp8weights-fp8kv | rag | 16 | 1,002 | 1836 | $0.87 | $1.92 | $0.11 |
| apertus-p2-c04-fp8weights-fp8kv | summarize | 16 | 569 | 3330 | $1.52 | $3.38 | $0.09 |
| apertus-p2-c04-fp8weights-fp8kv | think | 32 | 1,871 | 397 | $0.46 | $1.03 | $0.42 |
| h100nvl-70b-fp8-tp1 | agent | 1 | 35 | 323 | $24.74 | $54.98 | $27.48 |
| h100nvl-70b-fp8-tp1 | batch | 64 | 207 | 8609 | $4.18 | $9.28 | $1.03 |
| h100nvl-70b-fp8-tp1 | chat | 1 | 34 | 245 | $25.25 | $56.11 | $18.70 |
| h100nvl-70b-fp8-tp1 | rag | 1 | 27 | 1133 | $31.81 | $70.68 | $4.16 |
| h100nvl-70b-fp8-tp1 | summarize | 1 | 20 | 2215 | $43.41 | $96.47 | $2.51 |
| h100nvl-70b-fp8-tp1 | think | 1 | 35 | 239 | $24.58 | $54.63 | $34.98 |
| h100nvl-co3 | agent | 128 | 2,672 | 607 | $0.32 | $0.72 | $0.36 |
| h100nvl-co3 | batch | 128 | 1,804 | 581 | $0.48 | $1.07 | $0.12 |
| h100nvl-co3 | chat | 64 | 2,639 | 368 | $0.33 | $0.73 | $0.24 |
| h100nvl-co3 | rag | 16 | 930 | 1862 | $0.93 | $2.07 | $0.12 |
| h100nvl-co3 | summarize | 16 | 528 | 3432 | $1.64 | $3.65 | $0.09 |
| h100nvl-co3 | think | 64 | 1,801 | 369 | $0.48 | $1.07 | $0.43 |
| h100nvl-co4 | agent | 4 | 837 | 282 | $1.04 | $2.30 | $1.14 |
| h100nvl-co4 | batch | 64 | 1,293 | 1196 | $0.67 | $1.49 | $0.16 |
| h100nvl-co4 | chat | 4 | 807 | 179 | $1.07 | $2.39 | $0.79 |
| h100nvl-co4 | rag | 4 | 458 | 994 | $1.89 | $4.20 | $0.25 |
| h100nvl-co4 | summarize | 4 | 268 | 1846 | $3.23 | $7.18 | $0.18 |
| h100nvl-co4 | think | 4 | 755 | 183 | $1.15 | $2.55 | $0.85 |
| h100nvl-conf02 | agent | 64 | 2,275 | 806 | $0.38 | $0.85 | $0.42 |
| h100nvl-conf02 | batch | 128 | 1,465 | 792 | $0.59 | $1.31 | $0.15 |
| h100nvl-conf02 | chat | 64 | 2,248 | 476 | $0.39 | $0.86 | $0.28 |
| h100nvl-conf02 | rag | 4 | 430 | 642 | $2.02 | $4.48 | $0.26 |
| h100nvl-conf02 | summarize | 4 | 296 | 1208 | $2.92 | $6.50 | $0.17 |
| h100nvl-conf02 | think | 64 | 1,361 | 466 | $0.64 | $1.42 | $0.58 |
| v15-8b-tp1-len8k | agent | 128 | 2,269 | 823 | $0.38 | $0.85 | $0.42 |
| v15-8b-tp1-len8k | batch | 128 | 1,488 | 754 | $0.58 | $1.29 | $0.14 |
| v15-8b-tp1-len8k | chat | 128 | 2,260 | 461 | $0.38 | $0.85 | $0.28 |
| v15-8b-tp1-len8k | rag | 4 | 432 | 643 | $2.01 | $4.46 | $0.26 |
| v15-8b-tp1-len8k | think | 64 | 1,346 | 432 | $0.64 | $1.43 | $0.46 |

## Versus cloud token APIs

Break-even = monthly volume above which the self-hosted deployment is cheaper. Below it, pay per token.


### chat (ISL 512 / OSL 256)

| comparator | $/1M blended | cloud ÷ self-host (<1 = cloud cheaper) | break-even (M tok/month) |
|---|---:|---:|---:|
| **self-host: apertus-p2-c04-fp8weights-fp8kv** | **$0.24** | - | - |
| frontier-api-tier1 ⚠ | $7.00 | 29.7x | 325.4 |
| open-weights-vendor-70b ⚠ | $0.67 | 2.8x | 3,416.4 |
| open-weights-vendor-8b ⚠ | $0.13 | 0.6x | 17,082.0 |
| swisscom-apertus-v1.5-70b | _no price on file_ | - | - |

### rag (ISL 4096 / OSL 256)

| comparator | $/1M blended | cloud ÷ self-host (<1 = cloud cheaper) | break-even (M tok/month) |
|---|---:|---:|---:|
| **self-host: apertus-p2-c04-fp8weights-fp8kv** | **$0.11** | - | - |
| frontier-api-tier1 ⚠ | $3.71 | 32.9x | 614.6 |
| open-weights-vendor-70b ⚠ | $0.61 | 5.4x | 3,723.0 |
| open-weights-vendor-8b ⚠ | $0.11 | 0.9x | 21,510.7 |
| swisscom-apertus-v1.5-70b | _no price on file_ | - | - |

### summarize (ISL 7500 / OSL 200)

| comparator | $/1M blended | cloud ÷ self-host (<1 = cloud cheaper) | break-even (M tok/month) |
|---|---:|---:|---:|
| **self-host: apertus-p2-c04-fp8weights-fp8kv** | **$0.09** | - | - |
| frontier-api-tier1 ⚠ | $3.31 | 38.0x | 687.7 |
| open-weights-vendor-70b ⚠ | $0.61 | 7.0x | 3,763.4 |
| open-weights-vendor-8b ⚠ | $0.10 | 1.2x | 22,199.4 |
| swisscom-apertus-v1.5-70b | _no price on file_ | - | - |

### agent (ISL 1024 / OSL 1024)

| comparator | $/1M blended | cloud ÷ self-host (<1 = cloud cheaper) | break-even (M tok/month) |
|---|---:|---:|---:|
| **self-host: apertus-p2-c04-fp8weights-fp8kv** | **$0.34** | - | - |
| frontier-api-tier1 ⚠ | $9.00 | 26.1x | 253.1 |
| open-weights-vendor-70b ⚠ | $0.70 | 2.0x | 3,253.7 |
| open-weights-vendor-8b ⚠ | $0.15 | 0.4x | 15,184.0 |
| swisscom-apertus-v1.5-70b | _no price on file_ | - | - |

### batch (ISL 1024 / OSL 128)

| comparator | $/1M blended | cloud ÷ self-host (<1 = cloud cheaper) | break-even (M tok/month) |
|---|---:|---:|---:|
| **self-host: apertus-p2-c04-fp8weights-fp8kv** | **$0.12** | - | - |
| frontier-api-tier1 ⚠ | $4.33 | 36.7x | 525.6 |
| open-weights-vendor-70b ⚠ | $0.62 | 5.3x | 3,660.4 |
| open-weights-vendor-8b ⚠ | $0.11 | 0.9x | 20,498.4 |
| swisscom-apertus-v1.5-70b | _no price on file_ | - | - |

### think (ISL 512 / OSL 2048)

| comparator | $/1M blended | cloud ÷ self-host (<1 = cloud cheaper) | break-even (M tok/month) |
|---|---:|---:|---:|
| **self-host: apertus-p2-c04-fp8weights-fp8kv** | **$0.42** | - | - |
| frontier-api-tier1 ⚠ | $12.60 | 30.1x | 180.8 |
| open-weights-vendor-70b ⚠ | $0.76 | 1.8x | 2,996.8 |
| open-weights-vendor-8b ⚠ | $0.18 | 0.4x | 12,653.3 |
| swisscom-apertus-v1.5-70b | _no price on file_ | - | - |

## Sensitivity to utilization

The single assumption that moves the answer most.

| system | workload | $/1M out @ 20% | $/1M out @ 45% | $/1M out @ 80% | $/1M out @ 100% |
|---|---|---:|---:|---:|---:|
| apertus-p2-c04-fp8weights-fp8kv | agent | $1.56 | $0.69 | $0.39 | $0.31 |
| apertus-p2-c04-fp8weights-fp8kv | batch | $2.40 | $1.07 | $0.60 | $0.48 |
| apertus-p2-c04-fp8weights-fp8kv | chat | $1.60 | $0.71 | $0.40 | $0.32 |
| apertus-p2-c04-fp8weights-fp8kv | rag | $4.33 | $1.92 | $1.08 | $0.87 |
| apertus-p2-c04-fp8weights-fp8kv | summarize | $7.62 | $3.38 | $1.90 | $1.52 |
| apertus-p2-c04-fp8weights-fp8kv | think | $2.32 | $1.03 | $0.58 | $0.46 |
| h100nvl-70b-fp8-tp1 | agent | $123.71 | $54.98 | $30.93 | $24.74 |
| h100nvl-70b-fp8-tp1 | batch | $20.89 | $9.28 | $5.22 | $4.18 |
| h100nvl-70b-fp8-tp1 | chat | $126.25 | $56.11 | $31.56 | $25.25 |
| h100nvl-70b-fp8-tp1 | rag | $159.03 | $70.68 | $39.76 | $31.81 |
| h100nvl-70b-fp8-tp1 | summarize | $217.06 | $96.47 | $54.27 | $43.41 |
| h100nvl-70b-fp8-tp1 | think | $122.91 | $54.63 | $30.73 | $24.58 |
| h100nvl-co3 | agent | $1.62 | $0.72 | $0.41 | $0.32 |
| h100nvl-co3 | batch | $2.40 | $1.07 | $0.60 | $0.48 |
| h100nvl-co3 | chat | $1.64 | $0.73 | $0.41 | $0.33 |
| h100nvl-co3 | rag | $4.66 | $2.07 | $1.16 | $0.93 |
| h100nvl-co3 | summarize | $8.20 | $3.65 | $2.05 | $1.64 |
| h100nvl-co3 | think | $2.41 | $1.07 | $0.60 | $0.48 |
| h100nvl-co4 | agent | $5.18 | $2.30 | $1.29 | $1.04 |
| h100nvl-co4 | batch | $3.35 | $1.49 | $0.84 | $0.67 |
| h100nvl-co4 | chat | $5.37 | $2.39 | $1.34 | $1.07 |
| h100nvl-co4 | rag | $9.46 | $4.20 | $2.36 | $1.89 |
| h100nvl-co4 | summarize | $16.16 | $7.18 | $4.04 | $3.23 |
| h100nvl-co4 | think | $5.74 | $2.55 | $1.44 | $1.15 |
| h100nvl-conf02 | agent | $1.90 | $0.85 | $0.48 | $0.38 |
| h100nvl-conf02 | batch | $2.96 | $1.31 | $0.74 | $0.59 |
| h100nvl-conf02 | chat | $1.93 | $0.86 | $0.48 | $0.39 |
| h100nvl-conf02 | rag | $10.08 | $4.48 | $2.52 | $2.02 |
| h100nvl-conf02 | summarize | $14.62 | $6.50 | $3.65 | $2.92 |
| h100nvl-conf02 | think | $3.18 | $1.42 | $0.80 | $0.64 |
| v15-8b-tp1-len8k | agent | $1.91 | $0.85 | $0.48 | $0.38 |
| v15-8b-tp1-len8k | batch | $2.91 | $1.29 | $0.73 | $0.58 |
| v15-8b-tp1-len8k | chat | $1.92 | $0.85 | $0.48 | $0.38 |
| v15-8b-tp1-len8k | rag | $10.03 | $4.46 | $2.51 | $2.01 |
| v15-8b-tp1-len8k | think | $3.22 | $1.43 | $0.80 | $0.64 |

## What to say about this

1. State the operating point, not the peak. Every cost number above is anchored to a configuration that met an explicit latency SLO.

2. Report the optimization delta as a percentage move in $/1M tokens, not just tokens/sec. That is the language of the study.

3. Name the assumption that would flip your conclusion (usually utilization, then GPU hourly rate).

4. Cost is not the only axis: data residency, model openness (Apertus is Apache-2.0 with open data) and rate-limit headroom belong in the same table as dollars.

