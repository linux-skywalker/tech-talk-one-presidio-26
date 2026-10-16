"""LoRA fine-tune of Qwen2.5-1.5B-Instruct with TRL. Resumes from the latest checkpoint if one exists."""
import argparse, glob, os, time
import torch
from datasets import load_dataset
from peft import LoraConfig
from trl import SFTConfig, SFTTrainer

p = argparse.ArgumentParser()
p.add_argument("--model", default=os.environ.get("MODEL", "Qwen/Qwen2.5-1.5B-Instruct"))
p.add_argument("--out", default=os.environ.get("OUT_DIR", "outputs/trad"))
p.add_argument("--examples", type=int, default=800)
p.add_argument("--epochs", type=float, default=float(os.environ.get("EPOCHS", 3)))
p.add_argument("--save_steps", type=int, default=25)
p.add_argument("--max_len", type=int, default=512)
a = p.parse_args()

ds = load_dataset("tatsu-lab/alpaca", split="train").shuffle(seed=0).select(range(a.examples))

def fmt(ex):
    user = ex["instruction"] + (("\n\n" + ex["input"]) if ex["input"] else "")
    return {"messages": [{"role": "user", "content": user}, {"role": "assistant", "content": ex["output"]}]}

ds = ds.map(fmt, remove_columns=ds.column_names)

cfg = SFTConfig(
    output_dir=a.out, num_train_epochs=a.epochs, per_device_train_batch_size=4,
    gradient_accumulation_steps=2, learning_rate=2e-4, bf16=True, logging_steps=5,
    save_steps=a.save_steps, save_total_limit=2, max_length=a.max_len,
    gradient_checkpointing=True, report_to="none",
)
lora = LoraConfig(r=16, lora_alpha=32, lora_dropout=0.05, task_type="CAUSAL_LM",
                  target_modules=["q_proj", "k_proj", "v_proj", "o_proj", "gate_proj", "up_proj", "down_proj"])
trainer = SFTTrainer(model=a.model, args=cfg, train_dataset=ds, peft_config=lora)

ckpts = glob.glob(os.path.join(a.out, "checkpoint-*"))
resume = max(ckpts, key=lambda c: int(c.rsplit("-", 1)[1])) if ckpts else None
print(f"[train] resume_from_checkpoint={resume}", flush=True)
t0 = time.time()
trainer.train(resume_from_checkpoint=resume)
trainer.save_model(os.path.join(a.out, "final"))
print(f"[train] done in {time.time()-t0:.0f}s, adapter at {a.out}/final", flush=True)
