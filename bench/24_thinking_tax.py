#!/usr/bin/env python3
"""Measure the thinking tax: tokens you pay for versus tokens the user sees.

Apertus 1.5 can reason between <|inner_prefix|> and <|inner_suffix|> before its
visible answer. Those reasoning tokens are generated, billed and never shown. So
one deployment has two very different costs per million tokens:

    $/1M billed tokens   - what the GPU produced
    $/1M visible tokens  - what the user received

The ratio is the multiplier you feed to tokenomics/40_tokenomics.py, and the
accuracy delta on the same prompts is what justifies it. Reporting the pair
"thinking costs 4.1x per useful token and buys +18 points on these reasoning
prompts" is a far stronger result than another tokens-per-second chart.

Usage
-----
  # against a server started WITHOUT thinking:
  python3 bench/24_thinking_tax.py --tag plain
  # restart with ENABLE_THINKING=1, then:
  python3 bench/24_thinking_tax.py --tag thinking
  python3 bench/24_thinking_tax.py --compare artifacts/thinking/plain.json \
                                             artifacts/thinking/thinking.json
"""
from __future__ import annotations

import argparse
import json
import re
import time
import urllib.error
import urllib.request
from pathlib import Path

# Prompts with checkable answers, so accuracy and cost move together.
PROMPTS = [
    ("bat_ball", "A bat and a ball cost 1.10 CHF together. The bat costs 1 CHF more "
                 "than the ball. What does the ball cost? End with 'ANSWER: <value>'.", "0.05"),
    ("trains", "Two trains 300 km apart approach each other at 70 km/h and 80 km/h. "
               "How many hours until they meet? End with 'ANSWER: <value>'.", "2"),
    ("socks", "A drawer has 10 red and 10 blue socks. How many socks must you draw "
              "in the dark to guarantee a matching pair? End with 'ANSWER: <value>'.", "3"),
    ("compound", "A sum grows 10% per year for 3 years from 1000 CHF. What is the "
                 "final amount, rounded to the nearest franc? End with 'ANSWER: <value>'.", "1331"),
    ("days", "If today is Wednesday, what day is it 100 days from now? "
             "End with 'ANSWER: <day>'.", "friday"),
    ("primes", "How many prime numbers are strictly between 20 and 40? "
               "End with 'ANSWER: <count>'.", "4"),
    ("ages", "Anna is twice as old as Ben. In 6 years she will be 1.5x his age. "
             "How old is Ben now? End with 'ANSWER: <value>'.", "6"),
    ("water", "A tank fills in 6 h with tap A and 12 h with tap B. Both open, how "
              "many hours to fill? End with 'ANSWER: <value>'.", "4"),
]

INNER = re.compile(r"<\|inner_prefix\|>(.*?)<\|inner_suffix\|>", re.S)


def ask(base: str, prompt: str, max_tokens: int, model: str) -> dict:
    body = json.dumps({
        "model": model, "max_tokens": max_tokens, "temperature": 0.0,
        "messages": [{"role": "user", "content": prompt}],
    }).encode()
    req = urllib.request.Request(base + "/chat/completions", data=body,
                                 headers={"Content-Type": "application/json"})
    t0 = time.time()
    with urllib.request.urlopen(req, timeout=600) as fh:
        d = json.load(fh)
    msg = d["choices"][0]["message"]
    usage = d.get("usage", {}) or {}
    text = msg.get("content") or ""
    # Servers expose reasoning either as a separate field (--reasoning-parser)
    # or inline between the markers. Handle both.
    reasoning = msg.get("reasoning_content") or ""
    inline = INNER.search(text)
    if inline and not reasoning:
        reasoning = inline.group(1)
        text = INNER.sub("", text)
    return {
        "elapsed_s": round(time.time() - t0, 2),
        "completion_tokens": usage.get("completion_tokens"),
        "prompt_tokens": usage.get("prompt_tokens"),
        "reasoning_chars": len(reasoning),
        "visible_chars": len(text.strip()),
        "visible": text.strip(),
        "finish_reason": d["choices"][0].get("finish_reason"),
    }


def grade(visible: str, expected: str) -> bool:
    m = re.search(r"ANSWER:\s*([^\n]*)", visible, re.I)
    got = (m.group(1) if m else visible[-40:]).strip().lower()
    got = got.replace("chf", "").replace(",", "").strip(" .`*")
    return expected.lower() in got


def run(a) -> int:
    out = Path(a.out_dir) / f"{a.tag}.json"
    out.parent.mkdir(parents=True, exist_ok=True)
    rows = []
    for name, prompt, expected in PROMPTS:
        try:
            r = ask(a.url, prompt, a.max_tokens, a.model)
        except urllib.error.URLError as e:
            print(f"  {name}: request failed ({e}) - is the server up?")
            return 1
        r["name"] = name
        r["correct"] = grade(r["visible"], expected)
        if r["finish_reason"] == "length":
            print(f"  ! {name}: hit the token cap - raise --max-tokens or you are "
                  f"measuring truncation, not reasoning")
        rows.append(r)
        print(f"  {name:10s} completion={r['completion_tokens']:>6} "
              f"reasoning_chars={r['reasoning_chars']:>6} "
              f"visible_chars={r['visible_chars']:>5} "
              f"{'OK' if r['correct'] else 'WRONG'}")

    tot_c = sum(r["completion_tokens"] or 0 for r in rows)
    vis_c = sum(r["visible_chars"] for r in rows)
    rea_c = sum(r["reasoning_chars"] for r in rows)
    acc = sum(r["correct"] for r in rows) / len(rows)
    # Character share is the honest proxy for the token split when the server
    # does not report reasoning tokens separately.
    vis_share = vis_c / max(vis_c + rea_c, 1)
    summary = {
        "tag": a.tag, "n": len(rows),
        "total_completion_tokens": tot_c,
        "visible_char_share": round(vis_share, 4),
        "est_visible_tokens": round(tot_c * vis_share),
        "accuracy": round(acc, 3),
        "mean_latency_s": round(sum(r["elapsed_s"] for r in rows) / len(rows), 2),
        "rows": rows,
    }
    out.write_text(json.dumps(summary, indent=1))
    print(f"\n  completion tokens: {tot_c:,} | est. visible: {summary['est_visible_tokens']:,}"
          f" | accuracy: {acc:.0%} | mean latency: {summary['mean_latency_s']}s")
    print(f"  wrote {out}")
    return 0


def compare(p1: Path, p2: Path) -> int:
    a, b = json.loads(p1.read_text()), json.loads(p2.read_text())
    ta, tb = a["total_completion_tokens"], b["total_completion_tokens"]
    va, vb = a["est_visible_tokens"], b["est_visible_tokens"]
    print(f"\n{'':22s} {a['tag']:>14s} {b['tag']:>14s}")
    print(f"{'completion tokens':22s} {ta:>14,} {tb:>14,}")
    print(f"{'est. visible tokens':22s} {va:>14,} {vb:>14,}")
    print(f"{'accuracy':22s} {a['accuracy']:>13.0%} {b['accuracy']:>13.0%}")
    print(f"{'mean latency (s)':22s} {a['mean_latency_s']:>14} {b['mean_latency_s']:>14}")
    if ta and va:
        billed_x = tb / ta
        useful_x = (tb / max(vb, 1)) / (ta / max(va, 1))
        print(f"\n  thinking tax: {billed_x:.2f}x billed tokens, "
              f"{useful_x:.2f}x per VISIBLE token")
        print(f"  accuracy delta: {(b['accuracy'] - a['accuracy']) * 100:+.0f} points")
        print(f"\n  feed to the cost model:  "
              f"python3 tokenomics/40_tokenomics.py --thinking-multiplier {billed_x:.2f}")
        print("  then answer the only question that matters: is that accuracy")
        print("  worth that multiplier, for WHICH workloads?")
    return 0


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--url", default="http://localhost:8000/v1")
    ap.add_argument("--model", default="apertus")
    ap.add_argument("--tag", default="plain")
    ap.add_argument("--max-tokens", type=int, default=4096,
                    help="budget generously - the model card warns reasoning can be "
                         "several times the answer length")
    ap.add_argument("--out-dir", default="artifacts/thinking")
    ap.add_argument("--compare", nargs=2, type=Path)
    a = ap.parse_args()
    return compare(*a.compare) if a.compare else run(a)


if __name__ == "__main__":
    raise SystemExit(main())
