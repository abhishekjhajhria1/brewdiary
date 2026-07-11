# Fine-tune "our own Ninkasi" — a LoRA over a small open model, trained on the
# exported corpus (scripts/ninkasi/export-dataset.mjs → out/ninkasi-train.jsonl).
#
# Model choice (the "model specifically for our problem"):
#   meta-llama/Llama-3.1-8B-Instruct — small enough to host for cents/hr on one
#   24GB GPU (vLLM), big enough to hold the persona + drink knowledge. The corpus
#   is distilled from a 70B teacher (Groq), so the 8B learns to answer like it.
#
# Runs anywhere with one CUDA GPU (Colab T4/A10 works via Unsloth's 4-bit path):
#   pip install unsloth
#   python scripts/ninkasi/train_lora.py
#
# Output: ./ninkasi-lora (adapter) + ./ninkasi-8b-merged (full model, vLLM-ready).
# Host it:  vllm serve ./ninkasi-8b-merged --served-model-name ninkasi-8b
# Then in .env.local:  AI_BASE_URL=http://<host>:8000/v1   AI_MODEL=ninkasi-8b

from unsloth import FastLanguageModel
from unsloth.chat_templates import get_chat_template
from datasets import load_dataset
from trl import SFTConfig, SFTTrainer

BASE = "unsloth/Meta-Llama-3.1-8B-Instruct-bnb-4bit"
TRAIN = "scripts/ninkasi/out/ninkasi-train.jsonl"
VAL = "scripts/ninkasi/out/ninkasi-val.jsonl"

model, tokenizer = FastLanguageModel.from_pretrained(
    model_name=BASE,
    max_seq_length=2048,
    load_in_4bit=True,
)
model = FastLanguageModel.get_peft_model(
    model,
    r=16,
    lora_alpha=32,
    lora_dropout=0.0,
    target_modules=["q_proj", "k_proj", "v_proj", "o_proj", "gate_proj", "up_proj", "down_proj"],
)
tokenizer = get_chat_template(tokenizer, chat_template="llama-3.1")

def to_text(example):
    return {"text": tokenizer.apply_chat_template(example["messages"], tokenize=False)}

data = load_dataset("json", data_files={"train": TRAIN, "val": VAL})
data = data.map(to_text, remove_columns=data["train"].column_names)

trainer = SFTTrainer(
    model=model,
    tokenizer=tokenizer,
    train_dataset=data["train"],
    eval_dataset=data["val"],
    args=SFTConfig(
        dataset_text_field="text",
        per_device_train_batch_size=2,
        gradient_accumulation_steps=8,
        num_train_epochs=2,
        learning_rate=2e-4,
        lr_scheduler_type="cosine",
        warmup_ratio=0.05,
        logging_steps=10,
        eval_strategy="epoch",
        output_dir="ninkasi-lora",
        seed=7,
    ),
)
trainer.train()

model.save_pretrained("ninkasi-lora")                       # adapter only (small)
model.save_pretrained_merged("ninkasi-8b-merged", tokenizer)  # vLLM-servable
print("done. serve with: vllm serve ./ninkasi-8b-merged --served-model-name ninkasi-8b")
