#!/usr/bin/env python3
"""Build the Ninkasi SFT dataset.

Merges the hand-crafted persona seed (data/persona_seed.jsonl) with any real, consented
exchanges the app exported (scripts/ninkasi/export-dataset.mjs → ../scripts/ninkasi/out/*.jsonl),
normalizes every row to a single canonical system prompt (config/persona.txt, kept in sync with
src/lib/bartender.ts), upsamples the hard guardrail examples, dedupes, and writes a train/val split.

Output: out/train.jsonl, out/val.jsonl  (chat format: {"messages":[{role,content}, ...]})

Usage:
    python data/build_dataset.py                 # uses config/ninkasi.yaml
    python data/build_dataset.py --config path   # custom config

No GPU, no network. Run this before train/finetune.py.
"""
from __future__ import annotations

import argparse
import glob
import hashlib
import json
import os
import random
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)


def load_yaml(path: str) -> dict:
    try:
        import yaml  # type: ignore
    except ImportError:
        sys.exit("PyYAML is required: pip install pyyaml  (or see requirements.txt)")
    with open(path, "r", encoding="utf-8") as f:
        return yaml.safe_load(f)


def read_persona() -> str:
    """Canonical system prompt. Prefer the live app source so persona never drifts; fall back
    to the committed copy so this repo also works standalone."""
    app_src = os.path.join(ROOT, "..", "src", "lib", "bartender.ts")
    if os.path.exists(app_src):
        with open(app_src, "r", encoding="utf-8") as f:
            src = f.read()
        # Extract the template literal assigned to SYSTEM_PROMPT.
        marker = "export const SYSTEM_PROMPT = `"
        i = src.find(marker)
        if i != -1:
            start = i + len(marker)
            end = src.find("`", start)
            if end != -1:
                persona = src[start:end].strip()
                if persona:
                    return persona
    with open(os.path.join(ROOT, "config", "persona.txt"), "r", encoding="utf-8") as f:
        return f.read().strip()


def iter_jsonl(path: str):
    with open(path, "r", encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            try:
                yield json.loads(line)
            except json.JSONDecodeError:
                print(f"  ! skipped a malformed line in {os.path.basename(path)}", file=sys.stderr)


def normalize(row: dict, persona: str) -> dict | None:
    """Return a clean {"messages":[system, user, assistant, ...]} row or None if unusable.
    Any incoming system message is REPLACED with the canonical persona (single source of truth)."""
    msgs = row.get("messages")
    if not isinstance(msgs, list):
        return None
    convo = [m for m in msgs if isinstance(m, dict) and m.get("role") in ("user", "assistant")]
    convo = [{"role": m["role"], "content": (m.get("content") or "").strip()} for m in convo]
    convo = [m for m in convo if m["content"]]
    if not convo or convo[0]["role"] != "user" or convo[-1]["role"] != "assistant":
        return None
    return {"messages": [{"role": "system", "content": persona}, *convo]}


def first_user(row: dict) -> str:
    for m in row["messages"]:
        if m["role"] == "user":
            return m["content"].lower()
    return ""


def row_key(row: dict) -> str:
    payload = json.dumps(
        [(m["role"], m["content"]) for m in row["messages"] if m["role"] != "system"],
        ensure_ascii=False,
    )
    return hashlib.sha256(payload.encode("utf-8")).hexdigest()


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--config", default=os.path.join(ROOT, "config", "ninkasi.yaml"))
    args = ap.parse_args()

    cfg = load_yaml(args.config)
    dcfg = cfg["data"]
    persona = read_persona()
    random.seed(cfg.get("train", {}).get("seed", 42))

    sources: list[str] = [os.path.join(ROOT, dcfg["persona_seed"])]
    export_glob = dcfg.get("app_export_glob")
    if export_glob:
        sources += sorted(glob.glob(os.path.join(ROOT, export_glob)))

    rows: list[dict] = []
    seen: set[str] = set()
    n_seed = n_export = 0
    for src in sources:
        if not os.path.exists(src):
            continue
        is_seed = "persona_seed" in src
        for raw in iter_jsonl(src):
            row = normalize(raw, persona)
            if row is None:
                continue
            k = row_key(row)
            if k in seen:
                continue
            seen.add(k)
            rows.append(row)
            if is_seed:
                n_seed += 1
            else:
                n_export += 1

    if not rows:
        sys.exit("No usable rows found. Is data/persona_seed.jsonl present?")

    # Upsample the guardrail/persona-critical rows so a few epochs don't wash them out.
    keywords = [k.lower() for k in dcfg.get("upsample_keywords", [])]
    factor = int(dcfg.get("upsample_factor", 1))
    upsampled = 0
    if keywords and factor > 1:
        extra: list[dict] = []
        for row in rows:
            u = first_user(row)
            if any(k in u for k in keywords):
                extra.extend([row] * (factor - 1))
                upsampled += 1
        rows.extend(extra)

    random.shuffle(rows)
    val_frac = float(dcfg.get("val_fraction", 0.08))
    n_val = max(1, int(len(rows) * val_frac))
    val, train = rows[:n_val], rows[n_val:]

    out_dir = os.path.join(ROOT, "out")
    os.makedirs(out_dir, exist_ok=True)
    for name, split in (("train.jsonl", train), ("val.jsonl", val)):
        with open(os.path.join(out_dir, name), "w", encoding="utf-8") as f:
            for r in split:
                f.write(json.dumps(r, ensure_ascii=False) + "\n")

    print("Ninkasi dataset built:")
    print(f"  seed rows        : {n_seed}")
    print(f"  app export rows  : {n_export}")
    print(f"  guardrail upsample: {upsampled} rows x{factor}")
    print(f"  total after upsample: {len(rows)}  ->  train {len(train)} / val {len(val)}")
    print(f"  written to {out_dir}/train.jsonl, val.jsonl")
    if n_export == 0:
        print("  (no real exchanges yet — training on the seed alone. That's fine to bootstrap; "
              "collect consented exchanges via the app, then re-run to fold them in.)")


if __name__ == "__main__":
    main()
