#!/usr/bin/env bash
# usage: ask.sh <model: Qwen/Qwen2.5-1.5B-Instruct | tuned> "prompt"
curl -s localhost:${PORT:-8000}/v1/chat/completions -H 'Content-Type: application/json' \
  -d "$(jq -n --arg m "$1" --arg p "$2" '{model:$m,messages:[{role:"user",content:$p}],max_tokens:80,temperature:0}')" | jq -r '.choices[0].message.content // .'
