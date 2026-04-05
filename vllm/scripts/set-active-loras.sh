#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

MODEL_NAME="${1:?usage: set-active-loras.sh <model> [lora,lora,...]}"
ACTIVE_NAMES="${2:-}"

load_model_env "$MODEL_NAME"
load_lora_manifest
(( ${#AVAILABLE_LORA_NAMES[@]} > 0 )) || fail "no enabled LoRAs with local files are available for '${MODEL_NAME}'"

declare -A requested=()
declare -a requested_names=()
for name in ${ACTIVE_NAMES//,/ }; do
  [[ -n "$name" ]] || continue
  [[ -n "${AVAILABLE_LORA_PATHS[$name]:-}" ]] || fail "LoRA '${name}' is not enabled and downloaded for '${MODEL_NAME}'"
  requested["$name"]=1
  requested_names+=("$name")
done

runtime_lora_file="$ROOT_DIR/runtime/config/loras/${MODEL_KEY}.env"
upsert_key "$runtime_lora_file" "ACTIVE_LORAS" "$ACTIVE_NAMES"

unit="$(model_service_name "$MODEL_KEY")"
if systemctl --user is-active "$unit" >/dev/null 2>&1 && curl -fsS "$(model_url)/health" >/dev/null 2>&1; then
  PYTHON_BIN="$(resolve_python_bin)"

  for name in "${ACTIVE_LORA_NAMES[@]}"; do
    if [[ -z "${requested[$name]:-}" ]]; then
      payload="$("$PYTHON_BIN" -c 'import json,sys; print(json.dumps({"lora_name": sys.argv[1]}))' "$name")"
      curl -fsS \
        -H 'Content-Type: application/json' \
        -X POST \
        -d "$payload" \
        "$(model_url)/v1/unload_lora_adapter" >/dev/null
    fi
  done

  for name in "${requested_names[@]}"; do
    payload="$("$PYTHON_BIN" -c 'import json,sys; print(json.dumps({"lora_name": sys.argv[1], "lora_path": sys.argv[2], "load_inplace": True}))' "$name" "${AVAILABLE_LORA_PATHS[$name]}")"
    curl -fsS \
      -H 'Content-Type: application/json' \
      -X POST \
      -d "$payload" \
      "$(model_url)/v1/load_lora_adapter" >/dev/null
  done
else
  printf 'service-inactive=%s\n' "$MODEL_KEY"
fi

printf 'ACTIVE_LORAS=%s\n' "$ACTIVE_NAMES"
