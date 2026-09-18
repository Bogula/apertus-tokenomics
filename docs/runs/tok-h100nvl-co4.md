# Apertus tokenomics

- Cost basis: **1 x H100-NVL-94GB** = $3.12/h on-demand, $1.63/h amortized-owned

- Utilization assumption: **45%** (730 h/month billed)

- Operating point: highest-throughput configuration that still met its p95 latency SLO.

- Unverified prices are flagged; see `tokenomics/prices.json`.


## Self-hosted cost per million tokens

| system | workload | conc | out tok/s | TTFT p95 (ms) | $/1M out (100% util) | $/1M out (@util) | $/1M blended (@util) |
|---|---|---:|---:|---:|---:|---:|---:|
| h100nvl-co4 | agent | 4 | 837 | 282 | $1.04 | $2.30 | $1.14 |
| h100nvl-co4 | batch | 64 | 1,293 | 1196 | $0.67 | $1.49 | $0.16 |
| h100nvl-co4 | chat | 4 | 807 | 179 | $1.07 | $2.39 | $0.79 |
| h100nvl-co4 | rag | 4 | 458 | 994 | $1.89 | $4.20 | $0.25 |
| h100nvl-co4 | summarize | 4 | 268 | 1846 | $3.23 | $7.18 | $0.18 |
| h100nvl-co4 | think | 4 | 755 | 183 | $1.15 | $2.55 | $0.85 |

## Versus cloud token APIs

Break-even = monthly volume above which the self-hosted deployment is cheaper. Below it, pay per token.


### chat (ISL 512 / OSL 256)

| comparator | $/1M blended | cloud ÷ self-host (<1 = cloud cheaper) | break-even (M tok/month) |
|---|---:|---:|---:|
| **self-host: h100nvl-co4** | **$0.79** | - | - |
| frontier-api-tier1 ⚠ | $7.00 | 8.8x | 325.4 |
| open-weights-vendor-70b ⚠ | $0.67 | 0.8x | 3,416.4 |
| open-weights-vendor-8b ⚠ | $0.13 | 0.2x | 17,082.0 |
| swisscom-apertus-v1.5-70b | _no price on file_ | - | - |

### rag (ISL 4096 / OSL 256)

| comparator | $/1M blended | cloud ÷ self-host (<1 = cloud cheaper) | break-even (M tok/month) |
|---|---:|---:|---:|
| **self-host: h100nvl-co4** | **$0.25** | - | - |
| frontier-api-tier1 ⚠ | $3.71 | 15.1x | 614.6 |
| open-weights-vendor-70b ⚠ | $0.61 | 2.5x | 3,723.0 |
| open-weights-vendor-8b ⚠ | $0.11 | 0.4x | 21,510.7 |
| swisscom-apertus-v1.5-70b | _no price on file_ | - | - |

### summarize (ISL 7500 / OSL 200)

| comparator | $/1M blended | cloud ÷ self-host (<1 = cloud cheaper) | break-even (M tok/month) |
|---|---:|---:|---:|
| **self-host: h100nvl-co4** | **$0.18** | - | - |
| frontier-api-tier1 ⚠ | $3.31 | 18.2x | 687.7 |
| open-weights-vendor-70b ⚠ | $0.61 | 3.3x | 3,763.4 |
| open-weights-vendor-8b ⚠ | $0.10 | 0.6x | 22,199.4 |
| swisscom-apertus-v1.5-70b | _no price on file_ | - | - |

### agent (ISL 1024 / OSL 1024)

| comparator | $/1M blended | cloud ÷ self-host (<1 = cloud cheaper) | break-even (M tok/month) |
|---|---:|---:|---:|
| **self-host: h100nvl-co4** | **$1.14** | - | - |
| frontier-api-tier1 ⚠ | $9.00 | 7.9x | 253.1 |
| open-weights-vendor-70b ⚠ | $0.70 | 0.6x | 3,253.7 |
| open-weights-vendor-8b ⚠ | $0.15 | 0.1x | 15,184.0 |
| swisscom-apertus-v1.5-70b | _no price on file_ | - | - |

### batch (ISL 1024 / OSL 128)

| comparator | $/1M blended | cloud ÷ self-host (<1 = cloud cheaper) | break-even (M tok/month) |
|---|---:|---:|---:|
| **self-host: h100nvl-co4** | **$0.16** | - | - |
| frontier-api-tier1 ⚠ | $4.33 | 26.3x | 525.6 |
| open-weights-vendor-70b ⚠ | $0.62 | 3.8x | 3,660.4 |
| open-weights-vendor-8b ⚠ | $0.11 | 0.7x | 20,498.4 |
| swisscom-apertus-v1.5-70b | _no price on file_ | - | - |

### think (ISL 512 / OSL 2048)

| comparator | $/1M blended | cloud ÷ self-host (<1 = cloud cheaper) | break-even (M tok/month) |
|---|---:|---:|---:|
| **self-host: h100nvl-co4** | **$0.85** | - | - |
| frontier-api-tier1 ⚠ | $12.60 | 14.8x | 180.8 |
| open-weights-vendor-70b ⚠ | $0.76 | 0.9x | 2,996.8 |
| open-weights-vendor-8b ⚠ | $0.18 | 0.2x | 12,653.3 |
| swisscom-apertus-v1.5-70b | _no price on file_ | - | - |

## Sensitivity to utilization

The single assumption that moves the answer most.

| system | workload | $/1M out @ 20% | $/1M out @ 45% | $/1M out @ 80% | $/1M out @ 100% |
|---|---|---:|---:|---:|---:|
| h100nvl-co4 | agent | $5.18 | $2.30 | $1.29 | $1.04 |
| h100nvl-co4 | batch | $3.35 | $1.49 | $0.84 | $0.67 |
| h100nvl-co4 | chat | $5.37 | $2.39 | $1.34 | $1.07 |
| h100nvl-co4 | rag | $9.46 | $4.20 | $2.36 | $1.89 |
| h100nvl-co4 | summarize | $16.16 | $7.18 | $4.04 | $3.23 |
| h100nvl-co4 | think | $5.74 | $2.55 | $1.44 | $1.15 |

## What to say about this

1. State the operating point, not the peak. Every cost number above is anchored to a configuration that met an explicit latency SLO.

2. Report the optimization delta as a percentage move in $/1M tokens, not just tokens/sec. That is the language of the study.

3. Name the assumption that would flip your conclusion (usually utilization, then GPU hourly rate).

4. Cost is not the only axis: data residency, model openness (Apertus is Apache-2.0 with open data) and rate-limit headroom belong in the same table as dollars.

