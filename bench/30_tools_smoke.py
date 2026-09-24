#!/usr/bin/env python3
"""30_tools_smoke.py - prüft, ob Werkzeugaufrufe nach einer Quantisierung noch
funktionieren.

    python3 bench/30_tools_smoke.py                       # gegen localhost:8000
    python3 bench/30_tools_smoke.py --tag 8bit -o artifacts/tools

Hintergrund: eine Konfiguration, die 3x schneller ist und dabei still das
Werkzeug-Verhalten verliert, ist kein Ergebnis. Der Durchsatz-Sweep merkt davon
nichts - AIPerf schickt gar keine Tools, die 'agent'-Shape misst nur die Form
(1024 rein, 1024 raus), nicht die Fähigkeit.

Vier Prüfungen:
  1. Aufruf      - wird das Werkzeug überhaupt gewählt, mit korrektem Namen?
  2. Argumente   - ist arguments gültiges JSON mit dem Pflichtfeld?
  3. Round-Trip  - kommt nach Rückgabe des Ergebnisses eine Antwort, die es nutzt?
  4. Enthaltung  - bleibt das Modell bei einer Frage ohne Werkzeugbezug ruhig?

Prüfung 4 ist die wichtigste: ein Modell, das nach der Quantisierung bei jeder
Frage ein Werkzeug aufruft, besteht 1-3 und ist trotzdem kaputt.
"""
from __future__ import annotations

import argparse
import json
import sys
import urllib.error
import urllib.request
from pathlib import Path

TOOLS = [{
    "type": "function",
    "function": {
        "name": "get_weather",
        "description": "Liefert das aktuelle Wetter einer Stadt.",
        "parameters": {
            "type": "object",
            "properties": {
                "city": {"type": "string", "description": "Name der Stadt"},
                "unit": {"type": "string", "enum": ["c", "f"],
                         "description": "Temperatureinheit"},
            },
            "required": ["city"],
        },
    },
}]


def chat(url: str, model: str, messages: list[dict], tools=None,
         max_tokens: int = 400) -> dict:
    body = {"model": model, "max_tokens": max_tokens, "temperature": 0.0,
            "messages": messages}
    if tools:
        body["tools"] = tools
    req = urllib.request.Request(
        url, data=json.dumps(body).encode(),
        headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=600) as fh:
        return json.load(fh)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--url", default="http://localhost:8000/v1/chat/completions")
    ap.add_argument("--model", default="apertus")
    ap.add_argument("--tag", default="run")
    ap.add_argument("-o", "--out-dir", default="artifacts/tools")
    a = ap.parse_args()

    results, ok_all = [], True

    def check(name: str, ok: bool, detail: str) -> None:
        nonlocal ok_all
        ok_all &= ok
        results.append({"check": name, "ok": bool(ok), "detail": detail})
        print(f"  [{'OK ' if ok else 'FAIL'}] {name:12} {detail}")

    try:
        # 1 + 2 --------------------------------------------------------------
        msgs = [{"role": "user", "content": "Wie warm ist es gerade in Zürich?"}]
        r = chat(a.url, a.model, msgs, TOOLS)
        msg = r["choices"][0]["message"]
        calls = msg.get("tool_calls") or []
        check("Aufruf", bool(calls) and calls[0]["function"]["name"] == "get_weather",
              f"tool_calls={[c['function']['name'] for c in calls]} "
              f"finish={r['choices'][0].get('finish_reason')}")

        args_ok, args = False, None
        if calls:
            try:
                args = json.loads(calls[0]["function"]["arguments"])
                args_ok = isinstance(args, dict) and "city" in args
            except json.JSONDecodeError:
                pass
        check("Argumente", args_ok, f"arguments={args!r}")

        # 3 ------------------------------------------------------------------
        if calls:
            msgs2 = msgs + [
                {"role": "assistant", "content": None, "tool_calls": calls},
                {"role": "tool", "tool_call_id": calls[0]["id"],
                 "content": '{"temperature_c": 19, "conditions": "bewölkt"}'},
            ]
            r2 = chat(a.url, a.model, msgs2, TOOLS)
            final = (r2["choices"][0]["message"].get("content") or "")
            check("Round-Trip", "19" in final,
                  f"{final.strip()[:90]!r}")
        else:
            check("Round-Trip", False, "übersprungen - kein Aufruf in Schritt 1")

        # 4 ------------------------------------------------------------------
        r3 = chat(a.url, a.model,
                  [{"role": "user", "content": "Nenne mir die Hauptstadt von Belgien."}],
                  TOOLS)
        m3 = r3["choices"][0]["message"]
        spurious = bool(m3.get("tool_calls"))
        text3 = (m3.get("content") or "").strip()
        check("Enthaltung", not spurious and "brüssel" in text3.lower(),
              f"kein Aufruf={not spurious} | {text3[:70]!r}")

    except urllib.error.HTTPError as e:
        print(f"\nHTTP {e.code}: {e.read().decode()[:300]}")
        return 1
    except urllib.error.URLError as e:
        print(f"\nRequest fehlgeschlagen ({e}) - läuft der Server?")
        return 1

    out = Path(a.out_dir) / f"{a.tag}.json"
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps({"tag": a.tag, "passed": ok_all,
                               "checks": results}, indent=1, ensure_ascii=False))
    print(f"\n  {'alle Prüfungen bestanden' if ok_all else 'FEHLGESCHLAGEN'}"
          f"  ->  {out}")
    return 0 if ok_all else 1


if __name__ == "__main__":
    raise SystemExit(main())
