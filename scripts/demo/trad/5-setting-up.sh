#!/usr/bin/env bash
# Metric 5 of 6, traditional way: set up from scratch. Live: fresh Python environment, pinned install, GPU check, first vLLM start. Uses the warm package cache (no sudo).
# usage: bash scripts/demo/trad/5-setting-up.sh        (about 3 to 5 minutes)
source "$(dirname "$0")/../common.sh"
need_idle_host
step 5 "Setting up (traditional)"
V=.demo-venv; rm -rf $V
problem "Every machine is built by hand: environment, pinned packages, GPU check, first start. Driver, CUDA runtime and Python come first and are the host's job."
say "Prerequisites already on the host: driver $(nvidia-smi --query-gpu=driver_version --format=csv,noheader), uv $(uv --version | cut -d' ' -f2). Package downloads come from the local cache."
tl_start; T0=$(date +%s)
show uv venv $V --python 3.10
T1=$(date +%s); tl "environment created in $((T1-T0)) s"
say "Installing vllm==0.31.0, trl==1.14.2, peft==0.21.2, datasets, accelerate..."
uv pip install --python $V/bin/python "vllm==0.31.0" "trl==1.14.2" "peft==0.21.2" datasets accelerate 2>&1 | tail -3
T2=$(date +%s); NPK=$($V/bin/python -m pip list 2>/dev/null | tail -n +3 | wc -l); [ "$NPK" = 0 ] && NPK=$(uv pip list --python $V/bin/python 2>/dev/null | tail -n +3 | wc -l)
tl "packages installed in $((T2-T1)) s: $NPK packages, environment $(du -sh $V | cut -f1)"
echo "${B}Does the GPU work from this environment?${R}"
$V/bin/python -c 'import torch,vllm;print("  torch",torch.__version__,"CUDA",torch.version.cuda,"| cuda available:",torch.cuda.is_available(),"|",torch.cuda.get_device_name(0));print("  vllm",vllm.__version__)' 2>&1 | tail -3
T3=$(date +%s); tl "GPU check done"
say "First start of vLLM (tiny model from the local cache)..."
(PATH=$PWD/$V/bin:$PATH MODEL=HuggingFaceTB/SmolLM2-135M-Instruct ADAPTER=/none GPU_UTIL=0.1 PORT=8101 scripts/serve.sh > logs/demo_trad_setup_serve.log 2>&1 &)
for t in $(seq 1 90); do curl -s -m 2 localhost:8101/v1/models | grep -q SmolLM2 && break; [ "$(nprocs 'vllm serve')" != 0 ] || break; sleep 2; done
T4=$(date +%s); curl -s -m 2 localhost:8101/v1/models | grep -q SmolLM2 && UP=answering || UP="NOT answering"
tl "vLLM $UP after $((T4-T3)) s"
killprocs 'vllm serve'; wait_gpu_free; TOT=$((T4-T0)); echo "$TOT" > logs/demo_trad_setup_seconds.txt; rm -rf $V
echo "${B}Scoreboard: setting up, traditional (this machine, warm package cache)${R}"
echo "  environment + install:  $((T2-T0)) s ($NPK packages)"
echo "  first vLLM start:       $((T4-T3)) s"
echo "  total to a serving model: ${TOT} s; plus the host's driver/Python, and none of it is written down as one reusable unit"
echo "  measured earlier, cold: install 106 s, model download and fine-tune 639 s, first vLLM 48 s (about 13.3 min to first serving)"
result "Setting up" "environment, $NPK packages and first vLLM start in ${TOT} s on a warm cache; repeated by hand on every machine"
