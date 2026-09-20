# Apertus tokenomics

- Cost basis: **1 x H100-NVL-94GB** = $3.12/h on-demand, $1.63/h amortized-owned

- Utilization assumption: **45%** (730 h/month billed)

- Operating point: highest-throughput configuration that still met its p95 latency SLO.

- Unverified prices are flagged; see `tokenomics/prices.json`.


## Self-hosted cost per million tokens

| system | workload | conc | out tok/s | TTFT p95 (ms) | $/1M out (100% util) | $/1M out (@util) | $/1M blended (@util) |
|---|---|---:|---:|---:|---:|---:|---:|
| h100nvl-70b-fp8-tp1 | agent | 1 | 35 | 323 | $24.74 | $54.98 | $27.48 |
| h100nvl-70b-fp8-tp1 | batch | 64 | 207 | 8609 | $4.18 | $9.28 | $1.03 |
| h100nvl-70b-fp8-tp1 | chat | 1 | 34 | 245 | $25.25 | $56.11 | $18.70 |
| h100nvl-70b-fp8-tp1 | rag | 1 | 27 | 1133 | $31.81 | $70.68 | $4.16 |
| h100nvl-70b-fp8-tp1 | summarize | 1 | 20 | 2215 | $43.41 | $96.47 | $2.51 |
| h100nvl-70b-fp8-tp1 | think | 1 | 35 | 239 | $24.58 | $54.63 | $34.98 |

## Versus cloud token APIs

Break-even = monthly volume above which the self-hosted deployment is cheaper. Below it, pay per token.


### chat (ISL 512 / OSL 256)

| comparator | $/1M blended | cloud ÷ self-host (<1 = cloud cheaper) | break-even (M tok/month) |
|---|---:|---:|---:|
| **self-host: h100nvl-70b-fp8-tp1** | **$18.70** | - | - |
| frontier-api-tier1 ⚠ | $7.00 | 0.4x | 325.4 |
| open-weights-vendor-70b ⚠ | $0.67 | 0.0x | 3,416.4 |
| open-weights-vendor-8b ⚠ | $0.13 | 0.0x | 17,082.0 |
| swisscom-apertus-v1.5-70b | _no price on file_ | - | - |

### rag (ISL 4096 / OSL 256)

| comparator | $/1M blended | cloud ÷ self-host (<1 = cloud cheaper) | break-even (M tok/month) |
|---|---:|---:|---:|
| **self-host: h100nvl-70b-fp8-tp1** | **$4.16** | - | - |
| frontier-api-tier1 ⚠ | $3.71 | 0.9x | 614.6 |
| open-weights-vendor-70b ⚠ | $0.61 | 0.1x | 3,723.0 |
| open-weights-vendor-8b ⚠ | $0.11 | 0.0x | 21,510.7 |
| swisscom-apertus-v1.5-70b | _no price on file_ | - | - |

### summarize (ISL 7500 / OSL 200)

| comparator | $/1M blended | cloud ÷ self-host (<1 = cloud cheaper) | break-even (M tok/month) |
|---|---:|---:|---:|
| **self-host: h100nvl-70b-fp8-tp1** | **$2.51** | - | - |
| frontier-api-tier1 ⚠ | $3.31 | 1.3x | 687.7 |
| open-weights-vendor-70b ⚠ | $0.61 | 0.2x | 3,763.4 |
| open-weights-vendor-8b ⚠ | $0.10 | 0.0x | 22,199.4 |
| swisscom-apertus-v1.5-70b | _no price on file_ | - | - |

### agent (ISL 1024 / OSL 1024)

| comparator | $/1M blended | cloud ÷ self-host (<1 = cloud cheaper) | break-even (M tok/month) |
|---|---:|---:|---:|
| **self-host: h100nvl-70b-fp8-tp1** | **$27.48** | - | - |
| frontier-api-tier1 ⚠ | $9.00 | 0.3x | 253.1 |
| open-weights-vendor-70b ⚠ | $0.70 | 0.0x | 3,253.7 |
| open-weights-vendor-8b ⚠ | $0.15 | 0.0x | 15,184.0 |
| swisscom-apertus-v1.5-70b | _no price on file_ | - | - |

### batch (ISL 1024 / OSL 128)

| comparator | $/1M blended | cloud ÷ self-host (<1 = cloud cheaper) | break-even (M tok/month) |
|---|---:|---:|---:|
| **self-host: h100nvl-70b-fp8-tp1** | **$1.03** | - | - |
| frontier-api-tier1 ⚠ | $4.33 | 4.2x | 525.6 |
| open-weights-vendor-70b ⚠ | $0.62 | 0.6x | 3,660.4 |
| open-weights-vendor-8b ⚠ | $0.11 | 0.1x | 20,498.4 |
| swisscom-apertus-v1.5-70b | _no price on file_ | - | - |

### think (ISL 512 / OSL 2048)

| comparator | $/1M blended | cloud ÷ self-host (<1 = cloud cheaper) | break-even (M tok/month) |
|---|---:|---:|---:|
| **self-host: h100nvl-70b-fp8-tp1** | **$34.98** | - | - |
| frontier-api-tier1 ⚠ | $12.60 | 0.4x | 180.8 |
| open-weights-vendor-70b ⚠ | $0.76 | 0.0x | 2,996.8 |
| open-weights-vendor-8b ⚠ | $0.18 | 0.0x | 12,653.3 |
| swisscom-apertus-v1.5-70b | _no price on file_ | - | - |

## Sensitivity to utilization

The single assumption that moves the answer most.

| system | workload | $/1M out @ 20% | $/1M out @ 45% | $/1M out @ 80% | $/1M out @ 100% |
|---|---|---:|---:|---:|---:|
| h100nvl-70b-fp8-tp1 | agent | $123.71 | $54.98 | $30.93 | $24.74 |
| h100nvl-70b-fp8-tp1 | batch | $20.89 | $9.28 | $5.22 | $4.18 |
| h100nvl-70b-fp8-tp1 | chat | $126.25 | $56.11 | $31.56 | $25.25 |
| h100nvl-70b-fp8-tp1 | rag | $159.03 | $70.68 | $39.76 | $31.81 |
| h100nvl-70b-fp8-tp1 | summarize | $217.06 | $96.47 | $54.27 | $43.41 |
| h100nvl-70b-fp8-tp1 | think | $122.91 | $54.63 | $30.73 | $24.58 |

## What to say about this

1. State the operating point, not the peak. Every cost number above is anchored to a configuration that met an explicit latency SLO.

2. Report the optimization delta as a percentage move in $/1M tokens, not just tokens/sec. That is the language of the study.

3. Name the assumption that would flip your conclusion (usually utilization, then GPU hourly rate).

4. Cost is not the only axis: data residency, model openness (Apertus is Apache-2.0 with open data) and rate-limit headroom belong in the same table as dollars.

