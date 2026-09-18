# Apertus tokenomics

- Cost basis: **1 x H100-NVL-94GB** = $3.12/h on-demand, $1.63/h amortized-owned

- Utilization assumption: **45%** (730 h/month billed)

- Operating point: highest-throughput configuration that still met its p95 latency SLO.

- Unverified prices are flagged; see `tokenomics/prices.json`.


## Self-hosted cost per million tokens

| system | workload | conc | out tok/s | TTFT p95 (ms) | $/1M out (100% util) | $/1M out (@util) | $/1M blended (@util) |
|---|---|---:|---:|---:|---:|---:|---:|
| h100nvl-co3 | agent | 128 | 2,672 | 607 | $0.32 | $0.72 | $0.36 |
| h100nvl-co3 | batch | 128 | 1,804 | 581 | $0.48 | $1.07 | $0.12 |
| h100nvl-co3 | chat | 64 | 2,639 | 368 | $0.33 | $0.73 | $0.24 |
| h100nvl-co3 | rag | 16 | 930 | 1862 | $0.93 | $2.07 | $0.12 |
| h100nvl-co3 | summarize | 16 | 528 | 3432 | $1.64 | $3.65 | $0.09 |
| h100nvl-co3 | think | 64 | 1,801 | 369 | $0.48 | $1.07 | $0.43 |

## Versus cloud token APIs

Break-even = monthly volume above which the self-hosted deployment is cheaper. Below it, pay per token.


### chat (ISL 512 / OSL 256)

| comparator | $/1M blended | cloud ÷ self-host (<1 = cloud cheaper) | break-even (M tok/month) |
|---|---:|---:|---:|
| **self-host: h100nvl-co3** | **$0.24** | - | - |
| frontier-api-tier1 ⚠ | $7.00 | 28.8x | 325.4 |
| open-weights-vendor-70b ⚠ | $0.67 | 2.7x | 3,416.4 |
| open-weights-vendor-8b ⚠ | $0.13 | 0.5x | 17,082.0 |
| swisscom-apertus-v1.5-70b | _no price on file_ | - | - |

### rag (ISL 4096 / OSL 256)

| comparator | $/1M blended | cloud ÷ self-host (<1 = cloud cheaper) | break-even (M tok/month) |
|---|---:|---:|---:|
| **self-host: h100nvl-co3** | **$0.12** | - | - |
| frontier-api-tier1 ⚠ | $3.71 | 30.7x | 614.6 |
| open-weights-vendor-70b ⚠ | $0.61 | 5.1x | 3,723.0 |
| open-weights-vendor-8b ⚠ | $0.11 | 0.9x | 21,510.7 |
| swisscom-apertus-v1.5-70b | _no price on file_ | - | - |

### summarize (ISL 7500 / OSL 200)

| comparator | $/1M blended | cloud ÷ self-host (<1 = cloud cheaper) | break-even (M tok/month) |
|---|---:|---:|---:|
| **self-host: h100nvl-co3** | **$0.09** | - | - |
| frontier-api-tier1 ⚠ | $3.31 | 35.3x | 687.7 |
| open-weights-vendor-70b ⚠ | $0.61 | 6.4x | 3,763.4 |
| open-weights-vendor-8b ⚠ | $0.10 | 1.1x | 22,199.4 |
| swisscom-apertus-v1.5-70b | _no price on file_ | - | - |

### agent (ISL 1024 / OSL 1024)

| comparator | $/1M blended | cloud ÷ self-host (<1 = cloud cheaper) | break-even (M tok/month) |
|---|---:|---:|---:|
| **self-host: h100nvl-co3** | **$0.36** | - | - |
| frontier-api-tier1 ⚠ | $9.00 | 25.0x | 253.1 |
| open-weights-vendor-70b ⚠ | $0.70 | 1.9x | 3,253.7 |
| open-weights-vendor-8b ⚠ | $0.15 | 0.4x | 15,184.0 |
| swisscom-apertus-v1.5-70b | _no price on file_ | - | - |

### batch (ISL 1024 / OSL 128)

| comparator | $/1M blended | cloud ÷ self-host (<1 = cloud cheaper) | break-even (M tok/month) |
|---|---:|---:|---:|
| **self-host: h100nvl-co3** | **$0.12** | - | - |
| frontier-api-tier1 ⚠ | $4.33 | 36.7x | 525.6 |
| open-weights-vendor-70b ⚠ | $0.62 | 5.3x | 3,660.4 |
| open-weights-vendor-8b ⚠ | $0.11 | 0.9x | 20,498.4 |
| swisscom-apertus-v1.5-70b | _no price on file_ | - | - |

### think (ISL 512 / OSL 2048)

| comparator | $/1M blended | cloud ÷ self-host (<1 = cloud cheaper) | break-even (M tok/month) |
|---|---:|---:|---:|
| **self-host: h100nvl-co3** | **$0.43** | - | - |
| frontier-api-tier1 ⚠ | $12.60 | 29.6x | 180.8 |
| open-weights-vendor-70b ⚠ | $0.76 | 1.8x | 2,996.8 |
| open-weights-vendor-8b ⚠ | $0.18 | 0.4x | 12,653.3 |
| swisscom-apertus-v1.5-70b | _no price on file_ | - | - |

## Sensitivity to utilization

The single assumption that moves the answer most.

| system | workload | $/1M out @ 20% | $/1M out @ 45% | $/1M out @ 80% | $/1M out @ 100% |
|---|---|---:|---:|---:|---:|
| h100nvl-co3 | agent | $1.62 | $0.72 | $0.41 | $0.32 |
| h100nvl-co3 | batch | $2.40 | $1.07 | $0.60 | $0.48 |
| h100nvl-co3 | chat | $1.64 | $0.73 | $0.41 | $0.33 |
| h100nvl-co3 | rag | $4.66 | $2.07 | $1.16 | $0.93 |
| h100nvl-co3 | summarize | $8.20 | $3.65 | $2.05 | $1.64 |
| h100nvl-co3 | think | $2.41 | $1.07 | $0.60 | $0.48 |

## What to say about this

1. State the operating point, not the peak. Every cost number above is anchored to a configuration that met an explicit latency SLO.

2. Report the optimization delta as a percentage move in $/1M tokens, not just tokens/sec. That is the language of the study.

3. Name the assumption that would flip your conclusion (usually utilization, then GPU hourly rate).

4. Cost is not the only axis: data residency, model openness (Apertus is Apache-2.0 with open data) and rate-limit headroom belong in the same table as dollars.

