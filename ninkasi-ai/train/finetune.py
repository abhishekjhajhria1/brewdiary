#!/usr/bin/env python3
"""Fine-tune Ninkasi with QLoRA.

Teaches the persona onto an open base model (default Qwen2.5-7B-Instruct) using the chat dataset
built by data/build_dataset.py. Runs on a single 16–24GB GPU (Colab T4/L4, a 3090/4090, an A10).
Loss is computed on Ninkasi's replies only (completion-only) so she learns to ANSWER in character,
not to echo the prompt.

    python train/finetune.py                 # reads config/ninkasi.yaml, out/train.jsonl, out/val.jsonl

Outputs:
    out/<output_name>-lora/      the LoRA adapter (small, ~tens of MB)
    out/<output_name>/           the merged fp16 model, ready for vLLM / Ollama / upload

If you have no GPU: skip this file. out/train.jsonl is already in the format Together AI, Fireworks,
and OpenAI fine-tuning accept — upload it there instead (see README.md → "No GPU? Two other paths").
"""
from __future__ import annotations

import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)


def load_cfg() -> dict:
    import yaml  # type: ignore
    with open(os.path.join(ROOT, "config", "ninkasi.yaml"), "r", encoding="utf-8") as f:
        return yaml.safe_load(f)


def main() -> None:
    try:
        import torch
        from datasets import load_dataset
        from transformers import (
            AutoModelForCausalLM,
            AutoTokenizer,
            BitsAndBytesConfig,
        )
        from peft import LoraConfig, get_peft_model, prepare_model_for_kbit_training
        from trl import SFTConfig, SFTTrainer, DataCollatorForCompletionOnlyLM
    except ImportError as e:
        sys.exit(
            f"Missing a training dependency ({e.name}). Install the GPU stack:\n"
            "  pip install -r requirements.txt\n"
            "(needs a CUDA GPU. No GPU? Use the hosted fine-tune path in README.md.)"
        )

    cfg = load_cfg()
    mcfg, lcfg, tcfg = cfg["model"], cfg["lora"], cfg["train"]

    train_path = os.path.join(ROOT, "out", "train.jsonl")
    val_path = os.path.join(ROOT, "out", "val.jsonl")
    if not os.path.exists(train_path):
        sys.exit("out/train.jsonl not found — run: python data/build_dataset.py")

    base = mcfg["base_model"]
    print(f"Loading base model: {base}  (4-bit={mcfg.get('load_in_4bit', True)})")

    tok = AutoTokenizer.from_pretrained(base)
    if tok.pad_token is None:
        tok.pad_token = tok.eos_token

    quant = None
    if mcfg.get("load_in_4bit", True):
        quant = BitsAndBytesConfig(
            load_in_4bit=True,
            bnb_4bit_quant_type="nf4",
            bnb_4bit_compute_dtype=torch.bfloat16,
            bnb_4bit_use_double_quant=True,
        )

    model = AutoModelForCausalLM.from_pretrained(
        base,
        quantization_config=quant,
        torch_dtype=torch.bfloat16,
        device_map="auto",
    )
    model = prepare_model_for_kbit_training(model)

    lora = LoraConfig(
        r=lcfg["r"],
        lora_alpha=lcfg["alpha"],
        lora_dropout=lcfg["dropout"],
        target_modules=lcfg["target_modules"],
        bias="none",
        task_type="CAUSAL_LM",
    )
    model = get_peft_model(model, lora)
    model.print_trainable_parameters()

    data = load_dataset(
        "json",
        data_files={"train": train_path, "validation": val_path},
    )

    def to_text(batch):
        # Render each chat with the base model's own chat template so special tokens match at serve time.
        return {
            "text": [
                tok.apply_chat_template(m, tokenize=False, add_generation_prompt=False)
                for m in batch["messages"]
            ]
        }

    data = data.map(to_text, batched=True, remove_columns=data["train"].column_names)

    # Completion-only: compute loss on the assistant turns only. The response template is the
    # assistant-turn opener for the chat template in use (Qwen/Llama/Mistral all expose one).
    response_template = _assistant_opener(tok)
    collator = DataCollatorForCompletionOnlyLM(response_template, tokenizer=tok)

    sft = SFTConfig(
        output_dir=os.path.join(ROOT, "out", "_checkpoints"),
        num_train_epochs=tcfg["epochs"],
        per_device_train_batch_size=tcfg["batch_size"],
        gradient_accumulation_steps=tcfg["grad_accum"],
        learning_rate=float(tcfg["learning_rate"]),
        warmup_ratio=tcfg["warmup_ratio"],
        weight_decay=tcfg["weight_decay"],
        lr_scheduler_type=tcfg["lr_scheduler"],
        max_seq_length=mcfg["max_seq_len"],
        logging_steps=5,
        eval_strategy="epoch",
        save_strategy="epoch",
        bf16=True,
        seed=tcfg["seed"],
        report_to="none",
        dataset_text_field="text",
    )

    trainer = SFTTrainer(
        model=model,
        args=sft,
        train_dataset=data["train"],
        eval_dataset=data["validation"],
        data_collator=collator,
    )
    trainer.train()

    out_name = mcfg["output_name"]
    lora_dir = os.path.join(ROOT, "out", f"{out_name}-lora")
    trainer.save_model(lora_dir)
    tok.save_pretrained(lora_dir)
    print(f"Saved LoRA adapter -> {lora_dir}")

    # Merge to a standalone fp16 model for the simplest possible serving.
    print("Merging LoRA into the base for serving...")
    from peft import AutoPeftModelForCausalLM

    merged = AutoPeftModelForCausalLM.from_pretrained(lora_dir, torch_dtype="auto", device_map="auto")
    merged = merged.merge_and_unload()
    merged_dir = os.path.join(ROOT, "out", out_name)
    merged.save_pretrained(merged_dir, safe_serialization=True)
    tok.save_pretrained(merged_dir)
    print(f"Saved merged model -> {merged_dir}")
    print("\nServe it:  see serve/README.md  (vLLM one-liner or an Ollama Modelfile).")


def _assistant_opener(tok) -> str:
    """Best-effort assistant-turn marker for completion-only masking, derived from the tokenizer's
    own chat template so it stays correct across Qwen / Llama / Mistral."""
    rendered = tok.apply_chat_template(
        [{"role": "user", "content": "x"}, {"role": "assistant", "content": "y"}],
        tokenize=False,
        add_generation_prompt=False,
    )
    idx = rendered.rfind("y")
    if idx == -1:
        # Fallbacks by family.
        for cand in ("<|im_start|>assistant\n", "<|start_header_id|>assistant<|end_header_id|>\n\n", "[/INST]"):
            if cand in rendered:
                return cand
        return "assistant"
    # Take the text immediately preceding the assistant content as the response template.
    head = rendered[:idx]
    for marker in ("<|im_start|>assistant\n", "<|start_header_id|>assistant<|end_header_id|>\n\n", "[/INST]", "assistant\n"):
        if head.endswith(marker) or marker in head[-40:]:
            return marker
    return head[-24:]


if __name__ == "__main__":
    main()
