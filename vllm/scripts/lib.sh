#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_ROOT="$ROOT_DIR"
export PROJECT_ROOT

declare -ag AVAILABLE_LORA_NAMES=()
declare -ag ACTIVE_LORA_NAMES=()
declare -Ag AVAILABLE_LORA_PATHS=()
declare -Ag AVAILABLE_LORA_SCALES=()

fail() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

warn() {
  printf 'warn: %s\n' "$*" >&2
}

available_models_csv() {
  local path names=()
  shopt -s nullglob
  for path in "$ROOT_DIR"/config/models/*.env; do
    names+=("$(basename "${path%.env}")")
  done
  shopt -u nullglob
  printf '%s' "${names[*]}"
}

require_model() {
  local model="${1:?missing model name}"
  [[ -f "$ROOT_DIR/config/models/${model}.env" ]] || fail "unknown model '${model}'. expected one of: $(available_models_csv)"
}

load_global_env() {
  if [[ -f "$ROOT_DIR/.env" ]]; then
    set -a
    # shellcheck disable=SC1091
    source "$ROOT_DIR/.env"
    set +a
  fi
}

resolve_threads_default() {
  local cpu_count
  cpu_count="$(nproc)"
  if (( cpu_count > 2 )); then
    printf '%s' "$((cpu_count - 2))"
  else
    printf '%s' "$cpu_count"
  fi
}

ensure_project_dirs() {
  mkdir -p \
    "$ROOT_DIR/logs" \
    "$ROOT_DIR/models" \
    "$ROOT_DIR/runtime" \
    "$ROOT_DIR/runtime/logs" \
    "$ROOT_DIR/runtime/config" \
    "$ROOT_DIR/runtime/config/loras"
}

contains_csv_item() {
  local csv="${1:-}" needle="${2:-}" item
  IFS=, read -r -a items <<< "$csv"
  for item in "${items[@]}"; do
    [[ "$item" == "$needle" ]] && return 0
  done
  return 1
}

model_service_name() {
  printf 'vllm-model@%s.service' "$1"
}

available_models_list() {
  local path
  shopt -s nullglob
  for path in "$ROOT_DIR"/config/models/*.env; do
    basename "${path%.env}"
  done
  shopt -u nullglob
}

load_model_env() {
  local model="${1:?missing model name}"

  require_model "$model"
  ensure_project_dirs
  load_global_env

  MODEL_ENV_FILE="$ROOT_DIR/config/models/${model}.env"
  set -a
  # shellcheck disable=SC1090
  source "$MODEL_ENV_FILE"
  if [[ -f "$ROOT_DIR/runtime/config/${model}.env" ]]; then
    # shellcheck disable=SC1090
    source "$ROOT_DIR/runtime/config/${model}.env"
  fi
  set +a

  MODEL_KEY="${MODEL_KEY:-$model}"
  MODEL_DISPLAY_NAME="${MODEL_DISPLAY_NAME:-$model}"
  MODEL_SOURCE_REPO="${MODEL_SOURCE_REPO:-${MODEL_REPO:-}}"
  MODEL_REPO="${MODEL_REPO:-}"
  [[ -n "$MODEL_REPO" ]] || fail "MODEL_REPO is not set in ${MODEL_ENV_FILE}"
  MODEL_ENTRYPOINT="${MODEL_ENTRYPOINT:-config.json}"
  MODEL_INCLUDE_PATTERN="${MODEL_INCLUDE_PATTERN:-}"
  MODEL_REVISION="${MODEL_REVISION:-main}"
  MODEL_DIR="${MODEL_DIR:-$ROOT_DIR/models/$MODEL_KEY}"
  MODEL_PATH="${MODEL_PATH:-$MODEL_DIR}"
  MODEL_ALLOWED_DEVICES="${MODEL_ALLOWED_DEVICES:-cpu,gpu}"
  MODEL_DEVICE="${MODEL_DEVICE:-gpu}"
  MODEL_HOST="${MODEL_HOST:-127.0.0.1}"
  MODEL_PORT="${MODEL_PORT:-8000}"
  SERVER_TASK="${SERVER_TASK:-generate}"
  CONTEXT_SIZE="${CONTEXT_SIZE:-4096}"
  THREADS="${THREADS:-$(resolve_threads_default)}"
  TENSOR_PARALLEL_SIZE="${TENSOR_PARALLEL_SIZE:-1}"
  GPU_MEMORY_UTILIZATION="${GPU_MEMORY_UTILIZATION:-0.80}"
  SWAP_SPACE="${SWAP_SPACE:-4}"
  MAX_NUM_SEQS="${MAX_NUM_SEQS:-16}"
  MAX_NUM_BATCHED_TOKENS="${MAX_NUM_BATCHED_TOKENS:-8192}"
  DTYPE="${DTYPE:-auto}"
  QUANTIZATION="${QUANTIZATION:-}"
  TRUST_REMOTE_CODE="${TRUST_REMOTE_CODE:-false}"
  ENABLE_PREFIX_CACHING="${ENABLE_PREFIX_CACHING:-false}"
  CPU_KV_CACHE_GB="${CPU_KV_CACHE_GB:-8}"
  CPU_EXTRA_ARGS="${CPU_EXTRA_ARGS:-}"
  GPU_EXTRA_ARGS="${GPU_EXTRA_ARGS:-}"
  SERVER_EXTRA_ARGS="${SERVER_EXTRA_ARGS:-}"
  SERVER_API_KEY="${SERVER_API_KEY:-}"
  CHAT_TEMPLATE="${CHAT_TEMPLATE:-}"
  LORA_ENABLED="${LORA_ENABLED:-false}"
  LORA_MANIFEST="${LORA_MANIFEST:-}"
  LORA_MAX_COUNT="${LORA_MAX_COUNT:-4}"
  LORA_MAX_CPU_COUNT="${LORA_MAX_CPU_COUNT:-8}"
  LORA_MAX_RANK="${LORA_MAX_RANK:-64}"

  mkdir -p "$MODEL_DIR"
}

apply_device_profile() {
  contains_csv_item "$MODEL_ALLOWED_DEVICES" "$MODEL_DEVICE" || fail "model '${MODEL_KEY}' does not allow device '${MODEL_DEVICE}' (allowed: ${MODEL_ALLOWED_DEVICES})"

  case "$MODEL_DEVICE" in
    cpu)
      RUNTIME_DEVICE="cpu"
      RUNTIME_EXTRA_ARGS="$CPU_EXTRA_ARGS"
      ;;
    gpu)
      RUNTIME_DEVICE="cuda"
      RUNTIME_EXTRA_ARGS="$GPU_EXTRA_ARGS"
      ;;
    *)
      fail "unsupported device '${MODEL_DEVICE}'"
      ;;
  esac
}

append_split_args() {
  local value="${1:-}"
  local -a parts=()
  [[ -n "$value" ]] || return 0
  read -r -a parts <<< "$value"
  SERVER_ARGS+=("${parts[@]}")
}

append_bool_flag() {
  local value="${1:-}" flag="${2:?missing flag}"
  case "${value,,}" in
    true|1|yes|on)
      SERVER_ARGS+=("$flag")
      ;;
    false|0|no|off|"")
      ;;
    *)
      fail "invalid boolean value '${value}' for ${flag}"
      ;;
  esac
}

resolve_vllm_bin() {
  local candidate
  local -a candidates=()

  if [[ "${RUNTIME_DEVICE:-${MODEL_DEVICE:-}}" == "cpu" ]]; then
    candidates+=(
      "${VLLM_CPU_BIN:-}"
      "$ROOT_DIR/.venv-cpu/bin/vllm"
    )
  fi

  candidates+=(
    "${VLLM_BIN:-}"
    "$ROOT_DIR/.venv/bin/vllm"
    "$(command -v vllm 2>/dev/null || true)"
  )

  for candidate in "${candidates[@]}"; do
    if [[ -n "$candidate" && -x "$candidate" ]]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done

  if [[ "${RUNTIME_DEVICE:-${MODEL_DEVICE:-}}" == "cpu" ]]; then
    fail "cpu vllm was not found. run 'make install-prereqs' to provision .venv-cpu or set VLLM_CPU_BIN in .env"
  fi

  fail "vllm was not found. run 'make install-prereqs' or set VLLM_BIN in .env"
}

resolve_python_bin() {
  local candidate
  for candidate in \
    "${HF_PYTHON_BIN:-}" \
    "$ROOT_DIR/.venv/bin/python" \
    "$ROOT_DIR/.venv-cpu/bin/python" \
    "$(command -v python3 2>/dev/null || true)"; do
    if [[ -n "$candidate" && -x "$candidate" ]]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done

  fail "python3 was not found"
}

upsert_key() {
  local file="${1:?missing file}" key="${2:?missing key}" value="${3:-}"
  local escaped tmp

  printf -v escaped '%q' "$value"
  tmp="$(mktemp)"

  if [[ -f "$file" ]]; then
    awk -v key="$key" -v line="$key=$escaped" '
      BEGIN { done = 0 }
      index($0, key "=") == 1 { print line; done = 1; next }
      { print }
      END { if (!done) print line }
    ' "$file" > "$tmp"
  else
    printf '%s\n' "$key=$escaped" > "$tmp"
  fi

  mv "$tmp" "$file"
}

load_lora_manifest() {
  local name key enabled_var path_var scale_var enabled path scale
  local runtime_lora_file="$ROOT_DIR/runtime/config/loras/${MODEL_KEY}.env"

  AVAILABLE_LORA_NAMES=()
  ACTIVE_LORA_NAMES=()
  AVAILABLE_LORA_PATHS=()
  AVAILABLE_LORA_SCALES=()

  [[ "$LORA_ENABLED" == "true" ]] || return 0
  [[ -n "$LORA_MANIFEST" && -f "$LORA_MANIFEST" ]] || return 0

  set -a
  # shellcheck disable=SC1090
  source "$LORA_MANIFEST"
  if [[ -f "$runtime_lora_file" ]]; then
    # shellcheck disable=SC1090
    source "$runtime_lora_file"
  fi
  set +a

  for name in ${LORA_NAMES:-}; do
    key="$(printf '%s' "$name" | tr '[:lower:]-' '[:upper:]_')"
    enabled_var="LORA_${key}_ENABLED"
    path_var="LORA_${key}_PATH"
    scale_var="LORA_${key}_SCALE"

    enabled="$(eval "printf '%s' \"\${$enabled_var:-false}\"")"
    path="$(eval "printf '%s' \"\${$path_var:-}\"")"
    scale="$(eval "printf '%s' \"\${$scale_var:-1.0}\"")"

    if [[ "$enabled" == "true" && -n "$path" && -d "$path" ]]; then
      AVAILABLE_LORA_NAMES+=("$name")
      AVAILABLE_LORA_PATHS["$name"]="$path"
      AVAILABLE_LORA_SCALES["$name"]="$scale"
    fi
  done

  if [[ -n "${ACTIVE_LORAS:-}" ]]; then
    IFS=, read -r -a requested_active <<< "$ACTIVE_LORAS"
    for name in "${requested_active[@]}"; do
      [[ -n "$name" ]] || continue
      if [[ -n "${AVAILABLE_LORA_PATHS[$name]:-}" ]]; then
        ACTIVE_LORA_NAMES+=("$name")
      else
        warn "active LoRA '${name}' is not currently available locally for ${MODEL_KEY}"
      fi
    done
  fi
}

build_server_args() {
  load_lora_manifest

  SERVER_ARGS=(
    --host "$MODEL_HOST"
    --port "$MODEL_PORT"
    --served-model-name "$MODEL_DISPLAY_NAME"
    --max-model-len "$CONTEXT_SIZE"
    --tensor-parallel-size "$TENSOR_PARALLEL_SIZE"
    --max-num-seqs "$MAX_NUM_SEQS"
    --max-num-batched-tokens "$MAX_NUM_BATCHED_TOKENS"
    --dtype "$DTYPE"
    --generation-config vllm
  )

  case "$SERVER_TASK" in
    generate)
      SERVER_ARGS+=(--runner generate)
      ;;
    embed|score)
      SERVER_ARGS+=(--runner pooling)
      ;;
    *)
      fail "unsupported SERVER_TASK '${SERVER_TASK}'"
      ;;
  esac

  [[ -n "$QUANTIZATION" ]] && SERVER_ARGS+=(--quantization "$QUANTIZATION")
  [[ -n "$SERVER_API_KEY" ]] && SERVER_ARGS+=(--api-key "$SERVER_API_KEY")
  [[ -n "$CHAT_TEMPLATE" ]] && SERVER_ARGS+=(--chat-template "$CHAT_TEMPLATE")
  append_bool_flag "$TRUST_REMOTE_CODE" --trust-remote-code

  if [[ "$RUNTIME_DEVICE" == "cuda" ]]; then
    SERVER_ARGS+=(--gpu-memory-utilization "$GPU_MEMORY_UTILIZATION")
  fi

  if [[ "$SERVER_TASK" == "generate" ]]; then
    append_bool_flag "$ENABLE_PREFIX_CACHING" --enable-prefix-caching
  fi

  append_split_args "$SERVER_EXTRA_ARGS"
  append_split_args "$RUNTIME_EXTRA_ARGS"

  if [[ "$LORA_ENABLED" == "true" ]]; then
    SERVER_ARGS+=(--enable-lora)
    SERVER_ARGS+=(--max-loras "$LORA_MAX_COUNT")
    SERVER_ARGS+=(--max-cpu-loras "$LORA_MAX_CPU_COUNT")
    SERVER_ARGS+=(--max-lora-rank "$LORA_MAX_RANK")
    if (( ${#ACTIVE_LORA_NAMES[@]} > 0 )); then
      SERVER_ARGS+=(--lora-modules)
      local name
      for name in "${ACTIVE_LORA_NAMES[@]}"; do
        SERVER_ARGS+=("${name}=${AVAILABLE_LORA_PATHS[$name]}")
      done
    fi
  fi
}

model_url() {
  printf 'http://%s:%s' "$MODEL_HOST" "$MODEL_PORT"
}
