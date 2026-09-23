#!/usr/bin/env python3
"""
17_text_tower_for_nim.py — turn an Apertus 1.5 omni checkpoint into a plain
text-tower checkpoint that upstream vLLM (and therefore NIM's vLLM backend)
loads without the Swiss AI fork.

    python3 nim/17_text_tower_for_nim.py --src ~/models/Apertus-v1.5-8B \\
                                         --dst ~/models/apertus15-8b-text
    python3 nim/17_text_tower_for_nim.py --src ... --dst ... --dry-run

Needs only torch + safetensors, so it runs on the Spark, an H100 box or any
machine with the weights — no MLX, no Apple hardware.

Why this works at all
---------------------
The omni checkpoint declares `model_type: apertus1p5`, which upstream vLLM and
transformers do not know — that is what forces the fork. The text tower inside
it is plain `ApertusForCausalLM`, which upstream vLLM *does* implement,
including the xIELU activation (vllm/model_executor/models/apertus.py registers
`ApertusForCausalLM` and raises if hidden_act is not "xielu"). Extracting the
text tower therefore sidesteps the fork as a side effect.

TensorRT-LLM has no Apertus and no xIELU, so NIM's TRT path stays closed
regardless. Pin the vLLM backend via NIM_MODEL_PROFILE.

What it changes
---------------
1. Drops vision/audio towers, keeps `model.language_model.*` and `lm_head`.
2. Strips the `model.language_model.` prefix — vLLM expects `model.*`.
3. Trims embed_tokens from 266752 to 131072 rows. IDs above that are the
   vision/audio codebook tokens; lm_head only ever spans 131072, so without
   the trim the two disagree and vLLM fails on the embedding shape.
4. Writes model_type "apertus", top-level rope_theta and a llama3 rope_scaling
   block (the source keeps them only under rope_parameters).
5. Tags the safetensors metadata as "pt", not "mlx".
"""

from __future__ import annotations

import argparse
import json
import shutil
import sys
from pathlib import Path

try:
    import torch  # noqa: F401  (safetensors.torch braucht es)
    from safetensors.torch import load_file, save_file
except ImportError:
    sys.exit("Fehlt:  pip install torch safetensors")

TEXT_VOCAB = 131072
PREFIXES = ("model.language_model.", "model.")

SIDECAR = ["tokenizer.json", "tokenizer_config.json", "special_tokens_map.json",
           "generation_config.json", "chat_template.jinja"]


def rename(key: str) -> str | None:
    """Text-Tower-Schlüssel auf `model.*` normieren; alles andere verwerfen."""
    if key == "lm_head.weight":
        return key
    if key.startswith("model.language_model."):
        return "model." + key[len("model.language_model."):]
    if key.startswith("model."):
        # Schon flach (z.B. eine frühere Extraktion) - aber die Tuerme der
        # anderen Modalitaeten muessen trotzdem raus.
        if any(t in key for t in (".vision_", ".audio_", "vision_tokenizer",
                                  "wavtokenizer", "audio_tokenizer")):
            return None
        return key
    return None


def find_text_cfg(c):
    """Den Teilbaum der config.json finden, der das Sprachmodell beschreibt.

    Der Omni-Checkpoint verschachtelt die Textkonfiguration, eine bereits
    extrahierte ist flach - und wie der Schluessel heisst, ist zwischen
    Modellfamilien uneinheitlich. Deshalb nach INHALT suchen: hidden_size und
    num_hidden_layers zusammen gibt es nur im Sprachmodell.
    """
    if not isinstance(c, dict):
        return None
    if "hidden_size" in c and "num_hidden_layers" in c:
        return c
    for k in ("text_config", "language_model", "llm_config", "text_model", "decoder"):
        r = find_text_cfg(c.get(k))
        if r:
            return r
    for v in c.values():
        r = find_text_cfg(v)
        if r:
            return r
    return None


def build_config(raw: dict) -> dict:
    txt = find_text_cfg(raw)
    if txt is None:
        sys.exit(f"Keine Textkonfiguration in config.json gefunden. "
                 f"Top-Level-Schluessel: {sorted(raw)}")
    # Formen ausserhalb des Sprachmodells (Tokenizer-IDs etc.) stehen oft nur
    # auf oberster Ebene - deshalb beide Ebenen abfragen.
    src = {**{k: v for k, v in raw.items() if not isinstance(v, dict)}, **txt}
    rp = src.get("rope_parameters") or {}
    theta = float(rp.get("rope_theta", src.get("rope_theta", 4_000_000.0)))
    scaling = {
        "rope_type": rp.get("rope_type", "llama3"),
        "factor": float(rp.get("factor", 32.0)),
        "low_freq_factor": float(rp.get("low_freq_factor", 1.0)),
        "high_freq_factor": float(rp.get("high_freq_factor", 4.0)),
        "original_max_position_embeddings": int(
            rp.get("original_max_position_embeddings", 8192)),
    }
    return {
        "architectures": ["ApertusForCausalLM"],
        "model_type": "apertus",
        "attention_bias": src.get("attention_bias", False),
        "attention_dropout": src.get("attention_dropout", 0.0),
        "bos_token_id": src.get("bos_token_id", 1),
        "eos_token_id": src.get("eos_token_id", [2, 68, 72]),
        "pad_token_id": src.get("pad_token_id", 3),
        "dtype": "bfloat16",
        "torch_dtype": "bfloat16",
        "hidden_act": "xielu",
        "hidden_dropout": src.get("hidden_dropout", 0.0),
        "hidden_size": src["hidden_size"],
        "initializer_range": src.get("initializer_range", 0.02),
        "intermediate_size": src["intermediate_size"],
        "max_position_embeddings": src.get("max_position_embeddings", 65536),
        "mlp_bias": src.get("mlp_bias", False),
        "num_attention_heads": src["num_attention_heads"],
        "num_hidden_layers": src["num_hidden_layers"],
        "num_key_value_heads": src["num_key_value_heads"],
        "post_norm": src.get("post_norm", False),
        "qk_norm": src.get("qk_norm", True),
        "rms_norm_eps": src.get("rms_norm_eps", 1e-5),
        "rope_theta": theta,
        "rope_traditional": False,
        "rope_scaling": scaling,
        "rope_parameters": {**scaling, "rope_theta": theta},
        "tie_word_embeddings": src.get("tie_word_embeddings", False),
        "use_cache": True,
        "vocab_size": TEXT_VOCAB,
    }


def human(n: int) -> str:
    return f"{n / 1e9:.2f} GB"


def main() -> int:
    ap = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--src", required=True, help="Quellordner mit dem Checkpoint")
    ap.add_argument("--dst", required=True, help="Zielordner (wird angelegt)")
    ap.add_argument("--dry-run", action="store_true")
    a = ap.parse_args()

    src, dst = Path(a.src).expanduser(), Path(a.dst).expanduser()
    if not src.is_dir():
        sys.exit(f"Quelle fehlt: {src}")

    # Zeigt --src auf einen HF-Cache-Ordner (models--org--name), liegen die
    # Gewichte in snapshots/<commit>/ und nicht hier. Selbst aufloesen, statt
    # den Nutzer den Commit-Hash heraussuchen zu lassen.
    if not (src / "config.json").exists() and (src / "refs" / "main").exists():
        commit = (src / "refs" / "main").read_text().strip()
        snap = src / "snapshots" / commit
        if (snap / "config.json").exists():
            print(f"HF-Cache erkannt -> {snap}")
            src = snap
    if not (src / "config.json").exists():
        sys.exit(f"Keine config.json in {src}")
    if dst.exists() and any(dst.iterdir()) and not a.dry_run:
        sys.exit(f"{dst} ist nicht leer.")

    cfg_src = json.loads((src / "config.json").read_text())
    index = json.loads((src / "model.safetensors.index.json").read_text())
    all_shards = sorted({v for v in index["weight_map"].values()})

    # Im Omni-Checkpoint gibt es Shards, die NUR Vision- oder Audio-Tensoren
    # enthalten (vision_tokenizer, wavtokenizer). Die vorab aussortieren:
    # sonst entstuende eine leere Ausgabedatei und die Shard-Nummerierung
    # "00003-of-00006" passte nicht mehr zur Zahl der geschriebenen Dateien.
    shards = [n for n in all_shards
              if any(rename(k) for k, v in index["weight_map"].items() if v == n)]
    skipped = [n for n in all_shards if n not in shards]
    print(f"Quelle: {src}  ({len(index['weight_map'])} Tensoren, "
          f"{len(all_shards)} Shards)")
    if skipped:
        print(f"  ohne Text-Tensoren, uebersprungen: {', '.join(skipped)}")

    if not a.dry_run:
        dst.mkdir(parents=True, exist_ok=True)

    weight_map: dict[str, str] = {}
    total = 0
    n_out = len(shards)

    for i, name in enumerate(shards, start=1):
        tensors = load_file(str(src / name))
        out = {}
        dropped = 0
        for k, v in tensors.items():
            nk = rename(k)
            if nk is None:
                dropped += 1
                continue
            if nk == "model.embed_tokens.weight" and v.shape[0] > TEXT_VOCAB:
                print(f"    embed_tokens {v.shape[0]} -> {TEXT_VOCAB}")
                v = v[:TEXT_VOCAB].contiguous()
            out[nk] = v

        out_name = f"model-{i:05d}-of-{n_out:05d}.safetensors"
        for k, v in out.items():
            weight_map[k] = out_name
            total += v.numel() * v.element_size()

        if a.dry_run:
            print(f"  [dry-run] {name}: {len(out)} behalten, {dropped} verworfen")
        else:
            save_file(out, str(dst / out_name), metadata={"format": "pt"})
            print(f"  {out_name}: {len(out)} Tensoren, {dropped} verworfen, "
                  f"{human((dst / out_name).stat().st_size)}")
        del tensors, out

    if a.dry_run:
        print(f"\nDry run: {len(weight_map)} Tensoren, {human(total)}.")
        return 0

    (dst / "model.safetensors.index.json").write_text(json.dumps(
        {"metadata": {"total_size": total}, "weight_map": weight_map}, indent=2))
    (dst / "config.json").write_text(json.dumps(build_config(cfg_src), indent=2))
    for f in SIDECAR:
        if (src / f).exists():
            shutil.copy2(src / f, dst / f)
        else:
            print(f"  Hinweis: {f} nicht in der Quelle")

    print(f"\nGeschrieben: {dst}  ({human(total)}, {len(weight_map)} Tensoren)")
    print("\nGegenprobe vor dem NIM-Start:")
    print(f"  python3 -c \"from transformers import AutoConfig; "
          f"c=AutoConfig.from_pretrained('{dst}'); "
          f"print(c.model_type, c.architectures, c.vocab_size)\"")
    print("  -> apertus ['ApertusForCausalLM'] 131072")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
