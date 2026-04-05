#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

MODEL_NAME="${1:?usage: run-vllm-server.sh <model>}"

load_model_env "$MODEL_NAME"
apply_device_profile
build_server_args

VLLM_BIN="$(resolve_vllm_bin)"
[[ -d "$MODEL_PATH" ]] || fail "model path '${MODEL_PATH}' does not exist. run 'make download MODEL=${MODEL_KEY}' first"
if [[ -n "$MODEL_ENTRYPOINT" && "$MODEL_ENTRYPOINT" != "." ]]; then
  [[ -e "$MODEL_DIR/$MODEL_ENTRYPOINT" ]] || fail "entrypoint '${MODEL_DIR}/${MODEL_ENTRYPOINT}' does not exist. run 'make show MODEL=${MODEL_KEY}' and verify the download"
fi

mkdir -p "$ROOT_DIR/runtime/logs"

export HF_HOME="${HF_HOME:-$HOME/.cache/huggingface}"
export HF_HUB_ENABLE_HF_TRANSFER="${HF_HUB_ENABLE_HF_TRANSFER:-1}"
export PYTHONUNBUFFERED=1
export TOKENIZERS_PARALLELISM=false

if [[ "$MODEL_DEVICE" == "cpu" ]]; then
  cpu_iomp_lib="$(find "$ROOT_DIR/.venv-cpu/lib" -maxdepth 2 -type f -name libiomp5.so 2>/dev/null | head -n 1 || true)"
  cpu_tcmalloc_lib="$(find "$ROOT_DIR/.venv-cpu" -type f -path '*/site-packages/vllm/libs/libtcmalloc_minimal.so.4' 2>/dev/null | head -n 1 || true)"
  cpu_preload=()

  export CUDA_VISIBLE_DEVICES=""
  export OMP_NUM_THREADS="$THREADS"
  export VLLM_CPU_KVCACHE_SPACE="$CPU_KV_CACHE_GB"
  export VLLM_CPU_NUM_OF_RESERVED_CPU="${VLLM_CPU_NUM_OF_RESERVED_CPU:-1}"
  export VLLM_TARGET_DEVICE=cpu

  [[ -n "$cpu_tcmalloc_lib" && -f "$cpu_tcmalloc_lib" ]] && cpu_preload+=("$cpu_tcmalloc_lib")
  [[ -n "$cpu_iomp_lib" && -f "$cpu_iomp_lib" ]] && cpu_preload+=("$cpu_iomp_lib")
  if (( ${#cpu_preload[@]} > 0 )); then
    export LD_PRELOAD="$(IFS=:; printf '%s' "${cpu_preload[*]}")${LD_PRELOAD:+:$LD_PRELOAD}"
  fi
else
  export CUDA_MODULE_LOADING="${CUDA_MODULE_LOADING:-LAZY}"
fi

if [[ "$LORA_ENABLED" == "true" ]]; then
  export VLLM_ALLOW_RUNTIME_LORA_UPDATING=True
fi

printf '[%s] starting %s on %s using %s\n' \
  "$(date -Iseconds)" \
  "$MODEL_KEY" \
  "$MODEL_DEVICE" \
  "$MODEL_PATH" >&2

exec "$VLLM_BIN" serve "$MODEL_PATH" "${SERVER_ARGS[@]}"
