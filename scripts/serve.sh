#!/usr/bin/env bash
# Serve base model + LoRA adapter via vLLM OpenAI API. GPU_UTIL caps VRAM share.
MODEL=${MODEL:-Qwen/Qwen2.5-1.5B-Instruct}
ADAPTER=${ADAPTER:-outputs/trad/final}
export VLLM_USE_FLASHINFER_SAMPLER=0  # flashinfer JIT needs nvcc, absent on this box
exec vllm serve "$MODEL" --gpu-memory-utilization "${GPU_UTIL:-0.4}" --max-model-len 2048 \
  --enable-lora --lora-modules "tuned=$ADAPTER" --max-lora-rank 16 --port "${PORT:-8000}"
