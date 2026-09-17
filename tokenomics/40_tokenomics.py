#!/usr/bin/env python3
"""Turn benchmark throughput into money.

Reads artifacts/results.csv (from bench/22_collect.py) plus tokenomics/prices.json
and produces, per configuration and workload:

  * cost per 1M output tokens, and blended cost per 1M total tokens
  * the same at your real duty cycle, not at a fictional 100% utilization
  * break-even monthly volume against each cloud API comparator
  * a sensitivity band across utilization assumptions

The honest framing, and the one that wins this kind of challenge:
self-hosting is a FIXED cost (you rent the GPU whether it is busy or not),
a token API is a VARIABLE cost. So the comparison is not "which is cheaper"
but "above what volume does fixed beat variable, and how does optimization
move that crossover point to the left".

Usage
-----
  python3 tokenomics/40_tokenomics.py \
      --results artifacts/results.csv \
      --gpu H100-80GB-SXM --gpus-per-replica 1 \
      --out artifacts/tokenomics.md
"""
from __future__ import annotations

import argparse
import csv
import json
import math
from pathlib import Path

HOURS_PER_MONTH_DEFAULT = 730.0


# ---------------------------------------------------------------- cost basis
def rental_hourly(prices: dict, gpu: str, n_gpus: int) -> tuple[float, str]:
    entry = prices["gpu_rental"].get(gpu)
    if entry is None:
        raise SystemExit(f"unknown gpu '{gpu}'. known: {list(prices['gpu_rental'])}")
    if not entry.get("verified"):
        print(f"  ! WARNING: price for {gpu} is unverified placeholder "
              f"({entry['gpu_hourly_usd']} USD/GPU-h). Fix prices.json.")
    return entry["gpu_hourly_usd"] * n_gpus, f"rental:{gpu}"


def owned_hourly(prices: dict, n_gpus: int) -> tuple[float, str] | tuple[None, None]:
    o = prices.get("owned_hardware", {})
    if not o.get("enabled"):
        return None, None
    years = o["amortization_years"]
    hours = years * 365 * 24
    capex_per_gpu_h = o["capex_usd_per_gpu"] / hours
    kw = o["power_watts_per_gpu"] / 1000.0 * o["pue"]
    power_per_gpu_h = kw * o["electricity_usd_per_kwh"]
    base = (capex_per_gpu_h + power_per_gpu_h) * (1 + o["hosting_overhead_pct"] / 100.0)
    ops_per_gpu_h = o.get("ops_fte_usd_per_year", 0) / max(o.get("gpus_in_cluster", 1), 1) / (365 * 24)
    return (base + ops_per_gpu_h) * n_gpus, "owned"


# ---------------------------------------------------------------- core math
def cost_per_mtok(hourly_usd: float, tok_per_s: float, utilization: float) -> float:
    """USD per 1e6 tokens. Utilization<1 means you pay for idle GPU time."""
    if tok_per_s <= 0 or utilization <= 0:
        return float("inf")
    tokens_per_hour_paid = tok_per_s * 3600 * utilization
    return hourly_usd / tokens_per_hour_paid * 1e6


def cloud_blended(api: dict, isl: int, osl: int, egress: float = 0.0) -> float | None:
    if api.get("input_usd_per_mtok") is None or api.get("output_usd_per_mtok") is None:
        return None
    total = isl + osl
    return (api["input_usd_per_mtok"] * isl + api["output_usd_per_mtok"] * osl) / total + egress


def breakeven_mtok_per_month(hourly_usd: float, hours: float, cloud_blended_usd: float) -> float:
    """Monthly total-token volume (millions) at which fixed == variable."""
    if not cloud_blended_usd or cloud_blended_usd <= 0:
        return float("inf")
    return (hourly_usd * hours) / cloud_blended_usd


# ---------------------------------------------------------------- reporting
def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--results", type=Path, default=Path("artifacts/results.csv"))
    ap.add_argument("--prices", type=Path, default=Path("tokenomics/prices.json"))
    ap.add_argument("--scenarios", type=Path, default=Path("bench/scenarios.json"))
    ap.add_argument("--gpu", default="H100-80GB-SXM")
    ap.add_argument("--gpus-per-replica", type=int, default=1,
                    help="GPUs the measured config occupies (TP size x replicas, "
                         "or prefill+decode GPUs for a Dynamo topology)")
    ap.add_argument("--utilization", type=float, default=None,
                    help="0-1; defaults to prices.json assumptions.utilization_pct")
    ap.add_argument("--thinking-multiplier", type=float, default=1.0,
                    help="billed tokens per visible token with thinking mode on "
                         "(from bench/24_thinking_tax.py --compare). Adds a "
                         "$/1M VISIBLE tokens column - the cost the user's value "
                         "is actually measured against.")
    ap.add_argument("--audio-minutes", action="store_true",
                    help="also report cost per minute of audio input (40 tok/s)")
    ap.add_argument("--ignore-slo", action="store_true",
                    help="cost the peak-throughput point even if it misses the "
                         "latency SLO (report both if you use this)")
    ap.add_argument("--out", type=Path, default=Path("artifacts/tokenomics.md"))
    a = ap.parse_args()

    prices = json.loads(a.prices.read_text())
    scen = json.loads(a.scenarios.read_text())
    shapes = {w["name"]: (w["isl"], w["osl"]) for w in scen["workloads"]}
    slos = {w["name"]: (w.get("slo") or {}) for w in scen["workloads"]}

    util = a.utilization if a.utilization is not None \
        else prices["assumptions"]["utilization_pct"] / 100.0
    hours = prices["assumptions"].get("hours_per_month", HOURS_PER_MONTH_DEFAULT)
    egress = prices["assumptions"].get("cloud_egress_usd_per_mtok", 0.0)

    with a.results.open() as fh:
        rows = list(csv.DictReader(fh))
    if not rows:
        raise SystemExit("no rows in results.csv")

    print(f"cost basis: {a.gpus_per_replica} x {a.gpu}, utilization {util:.0%}")
    rent_h, rent_lbl = rental_hourly(prices, a.gpu, a.gpus_per_replica)
    own_h, own_lbl = owned_hourly(prices, a.gpus_per_replica)
    print(f"  {rent_lbl}: ${rent_h:.2f}/h" +
          (f"   {own_lbl}: ${own_h:.2f}/h" if own_h else ""))

    # ---- pick the best operating point per (system, workload) --------------
    # "Best" = highest throughput AMONG points that still meet the workload SLO.
    # Costing tokens at a peak-throughput point that blows the latency budget is
    # the most common way these studies mislead.
    def meets_slo(r: dict) -> bool:
        if a.ignore_slo:
            return True
        s = slos.get(r["workload"]) or {}
        if not s:
            return True
        def f(*keys):
            for k in keys:
                v = r.get(k)
                if v not in (None, ""):
                    try:
                        return float(v)
                    except ValueError:
                        pass
            return None
        t = f("ttft_ms_p95", "ttft_ms_avg")
        i = f("itl_ms_p95", "itl_ms_avg", "tpot_ms_p95")
        if s.get("ttft_ms_p95") and t and t > s["ttft_ms_p95"]:
            return False
        if s.get("itl_ms_p95") and i and i > s["itl_ms_p95"]:
            return False
        return True

    best: dict = {}
    dropped = 0
    for r in rows:
        if not meets_slo(r):
            dropped += 1
            continue
        try:
            tp = float(r.get("out_tok_per_s_avg") or 0)
        except ValueError:
            tp = 0.0
        k = (r["system"], r["workload"])
        if tp > float(best.get(k, {}).get("out_tok_per_s_avg") or 0):
            best[k] = r
    if dropped:
        print(f"  {dropped}/{len(rows)} measurement(s) excluded for missing their "
              f"latency SLO (use --ignore-slo to include them)")
    if not best:
        raise SystemExit("no measurement met its SLO - loosen bench/scenarios.json "
                         "or rerun with --ignore-slo")

    md: list[str] = []
    md.append("# Apertus tokenomics\n")
    md.append(f"- Cost basis: **{a.gpus_per_replica} x {a.gpu}** "
              f"= ${rent_h:.2f}/h on-demand"
              + (f", ${own_h:.2f}/h amortized-owned" if own_h else "") + "\n")
    md.append(f"- Utilization assumption: **{util:.0%}** "
              f"({hours:.0f} h/month billed)\n")
    md.append("- Operating point: highest-throughput configuration that still met "
              "its p95 latency SLO"
              + (" — **SLO filtering disabled for this run**" if a.ignore_slo else "")
              + ".\n")
    md.append(f"- Unverified prices are flagged; see `tokenomics/prices.json`.\n")

    md.append("\n## Self-hosted cost per million tokens\n")
    think_col = a.thinking_multiplier and a.thinking_multiplier != 1.0
    if think_col:
        md.append(f"Thinking multiplier **{a.thinking_multiplier:.2f}x** applied: "
                  "reasoning tokens are billed but never shown to the user, so "
                  "*$/1M visible* is the cost the delivered value is measured against.\n")
    md.append("| system | workload | conc | out tok/s | TTFT p95 (ms) | "
              "$/1M out (100% util) | $/1M out (@util) | $/1M blended (@util) |"
              + (" $/1M visible (@util) |" if think_col else ""))
    md.append("|---|---|---:|---:|---:|---:|---:|---:|" + ("---:|" if think_col else ""))

    self_costs: dict = {}
    for (system, wl), r in sorted(best.items()):
        tp = float(r.get("out_tok_per_s_avg") or 0)
        conc = r["concurrency"]
        ttft = r.get("ttft_ms_p95") or r.get("ttft_ms_avg") or ""
        ttft_s = f"{float(ttft):.0f}" if ttft not in ("", None) else "-"
        isl, osl = shapes.get(wl, (1024, 256))
        # total token throughput = output stream + prefill tokens consumed
        rps = float(r.get("req_per_s_avg") or 0)
        total_tp = tp + rps * isl if rps else tp * (isl + osl) / max(osl, 1)

        c_ideal = cost_per_mtok(rent_h, tp, 1.0)
        c_real = cost_per_mtok(rent_h, tp, util)
        c_blend = cost_per_mtok(rent_h, total_tp, util)
        self_costs[(system, wl)] = {"out": c_real, "blended": c_blend,
                                    "tp": tp, "total_tp": total_tp}
        row_md = (f"| {system} | {wl} | {conc} | {tp:,.0f} | {ttft_s} | "
                  f"${c_ideal:,.2f} | ${c_real:,.2f} | ${c_blend:,.2f} |")
        if think_col:
            row_md += f" ${c_real * a.thinking_multiplier:,.2f} |"
        md.append(row_md)

    # ---- comparison vs cloud ----------------------------------------------
    md.append("\n## Versus cloud token APIs\n")
    md.append("Break-even = monthly volume above which the self-hosted deployment "
              "is cheaper. Below it, pay per token.\n")

    for wl, (isl, osl) in shapes.items():
        entries = [(s, w) for (s, w) in self_costs if w == wl]
        if not entries:
            continue
        md.append(f"\n### {wl} (ISL {isl} / OSL {osl})\n")
        md.append("| comparator | $/1M blended | cloud ÷ self-host (<1 = cloud cheaper) | "
                  "break-even (M tok/month) |")
        md.append("|---|---:|---:|---:|")
        best_self = min(self_costs[k]["blended"] for k in entries)
        best_sys = min(entries, key=lambda k: self_costs[k]["blended"])[0]
        md.append(f"| **self-host: {best_sys}** | **${best_self:,.2f}** | - | - |")
        for name, api in prices["cloud_apis"].items():
            if name.startswith("_"):
                continue
            cb = cloud_blended(api, isl, osl, egress)
            if cb is None:
                md.append(f"| {name} | _no price on file_ | - | - |")
                continue
            flag = "" if api.get("verified") else " ⚠"
            ratio = cb / best_self if best_self else float("inf")
            be = breakeven_mtok_per_month(rent_h, hours, cb)
            md.append(f"| {name}{flag} | ${cb:,.2f} | {ratio:,.1f}x | {be:,.1f} |")

    # ---- sensitivity -------------------------------------------------------
    md.append("\n## Sensitivity to utilization\n")
    md.append("The single assumption that moves the answer most.\n")
    md.append("| system | workload | " +
              " | ".join(f"$/1M out @ {u:.0%}" for u in (0.20, 0.45, 0.80, 1.00)) + " |")
    md.append("|---|---|" + "---:|" * 4)
    for (system, wl), d in sorted(self_costs.items()):
        cells = " | ".join(f"${cost_per_mtok(rent_h, d['tp'], u):,.2f}"
                           for u in (0.20, 0.45, 0.80, 1.00))
        md.append(f"| {system} | {wl} | {cells} |")

    if a.audio_minutes:
        mm = prices.get("multimodal", {})
        tps = mm.get("audio_tokens_per_second", 40)
        md.append("\n## Cost per minute of audio input\n")
        md.append(f"Apertus 1.5 takes audio at **{tps} tokens/second**, so one "
                  f"minute of speech = **{tps * 60:,} input tokens**.\n")
        md.append("| system | $/1M blended (@util) | $/minute of audio |")
        md.append("|---|---:|---:|")
        for (system, wl), d in sorted(self_costs.items()):
            if wl != "summarize":   # long-input shape is the closest text analogue
                continue
            md.append(f"| {system} | ${d['blended']:,.2f} | "
                      f"${d['blended'] * tps * 60 / 1e6:,.5f} |")
        ref = mm.get("speech_api_usd_per_audio_minute")
        md.append(f"\nComparator speech API: "
                  + (f"${ref}/min" if ref else "_not filled in - see prices.json_") + "\n")

    md.append("\n## What to say about this\n")
    md.append("1. State the operating point, not the peak. Every cost number above "
              "is anchored to a configuration that met an explicit latency SLO.\n")
    md.append("2. Report the optimization delta as a percentage move in $/1M tokens, "
              "not just tokens/sec. That is the language of the study.\n")
    md.append("3. Name the assumption that would flip your conclusion "
              "(usually utilization, then GPU hourly rate).\n")
    md.append("4. Cost is not the only axis: data residency, model openness "
              "(Apertus is Apache-2.0 with open data) and rate-limit headroom "
              "belong in the same table as dollars.\n")

    a.out.parent.mkdir(parents=True, exist_ok=True)
    a.out.write_text("\n".join(md) + "\n")
    print(f"\nwrote {a.out}")
    print("\n".join(md[:14]))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
