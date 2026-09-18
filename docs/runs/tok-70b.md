# Apertus tokenomics

- Cost basis: **2 x H100-NVL-94GB** = $6.24/h on-demand, $3.26/h amortized-owned

- Utilization assumption: **45%** (730 h/month billed)

- Operating point: highest-throughput configuration that still met its p95 latency SLO.

- Unverified prices are flagged; see `tokenomics/prices.json`.


## Self-hosted cost per million tokens

| system | workload | conc | out tok/s | TTFT p95 (ms) | $/1M out (100% util) | $/1M out (@util) | $/1M blended (@util) |
|---|---|---:|---:|---:|---:|---:|---:|
| v15-70b-tp2-len8k | chat | 4 | 145 | 448 | $11.95 | $26.55 | $8.85 |

## Versus cloud token APIs

Break-even = monthly volume above which the self-hosted deployment is cheaper. Below it, pay per token.


### chat (ISL 512 / OSL 256)

| comparator | $/1M blended | cloud ÷ self-host (<1 = cloud cheaper) | break-even (M tok/month) |
|---|---:|---:|---:|
| **self-host: v15-70b-tp2-len8k** | **$8.85** | - | - |
| frontier-api-tier1 ⚠ | $7.00 | 0.8x | 650.7 |
| open-weights-vendor-70b ⚠ | $0.67 | 0.1x | 6,832.8 |
| open-weights-vendor-8b ⚠ | $0.13 | 0.0x | 34,164.0 |
| swisscom-apertus-v1.5-70b | _no price on file_ | - | - |

## Sensitivity to utilization

The single assumption that moves the answer most.

| system | workload | $/1M out @ 20% | $/1M out @ 45% | $/1M out @ 80% | $/1M out @ 100% |
|---|---|---:|---:|---:|---:|
| v15-70b-tp2-len8k | chat | $59.73 | $26.55 | $14.93 | $11.95 |

## What to say about this

1. State the operating point, not the peak. Every cost number above is anchored to a configuration that met an explicit latency SLO.

2. Report the optimization delta as a percentage move in $/1M tokens, not just tokens/sec. That is the language of the study.

3. Name the assumption that would flip your conclusion (usually utilization, then GPU hourly rate).

4. Cost is not the only axis: data residency, model openness (Apertus is Apache-2.0 with open data) and rate-limit headroom belong in the same table as dollars.

