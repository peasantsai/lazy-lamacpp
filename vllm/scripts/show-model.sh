#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

MODEL_NAME="${1:?usage: show-model.sh <model>}"

load_model_env "$MODEL_NAME"
apply_device_profile
build_server_args

printf '%s\n' \
  "MODEL=${MODEL_KEY}" \
  "DISPLAY=${MODEL_DISPLAY_NAME}" \
  "SOURCE_REPO=${MODEL_SOURCE_REPO}" \
  "HF_REPO=${MODEL_REPO}" \
  "ENTRYPOINT=${MODEL_ENTRYPOINT}" \
  "HF_PATTERN=${MODEL_INCLUDE_PATTERN}" \
  "LOCAL_PATH=${MODEL_PATH}" \
  "DEVICE=${MODEL_DEVICE}" \
  "RUNTIME_DEVICE=${RUNTIME_DEVICE}" \
  "HOST=${MODEL_HOST}" \
  "PORT=${MODEL_PORT}" \
  "TASK=${SERVER_TASK}" \
  "CONTEXT=${CONTEXT_SIZE}" \
  "THREADS=${THREADS}" \
  "DTYPE=${DTYPE}" \
  "QUANTIZATION=${QUANTIZATION}" \
  "GPU_MEMORY_UTILIZATION=${GPU_MEMORY_UTILIZATION}" \
  "SWAP_SPACE=${SWAP_SPACE}" \
  "TENSOR_PARALLEL_SIZE=${TENSOR_PARALLEL_SIZE}" \
  "MAX_NUM_SEQS=${MAX_NUM_SEQS}" \
  "MAX_NUM_BATCHED_TOKENS=${MAX_NUM_BATCHED_TOKENS}"

if (( ${#AVAILABLE_LORA_NAMES[@]} > 0 )); then
  printf 'AVAILABLE_LORAS=%s\n' "${AVAILABLE_LORA_NAMES[*]}"
fi

if (( ${#ACTIVE_LORA_NAMES[@]} > 0 )); then
  printf 'ACTIVE_LORAS=%s\n' "${ACTIVE_LORA_NAMES[*]}"
fi
