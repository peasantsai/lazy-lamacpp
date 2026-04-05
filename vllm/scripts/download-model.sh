#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

MODEL_NAME="${1:?usage: download-model.sh <model>}"

load_model_env "$MODEL_NAME"

PYTHON_BIN="$(resolve_python_bin)"
HF_TOKEN_VALUE="${HF_TOKEN:-}"
args=(
  --repo "$MODEL_REPO"
  --local-dir "$MODEL_DIR"
  --revision "$MODEL_REVISION"
  --token "$HF_TOKEN_VALUE"
)

if [[ -n "$MODEL_INCLUDE_PATTERN" ]]; then
  IFS=, read -r -a patterns <<< "$MODEL_INCLUDE_PATTERN"
  for pattern in "${patterns[@]}"; do
    [[ -n "$pattern" ]] || continue
    args+=(--pattern "$pattern")
  done
fi

"$PYTHON_BIN" "$ROOT_DIR/scripts/hf-download.py" "${args[@]}"

[[ -d "$MODEL_PATH" ]] || fail "download completed but '${MODEL_PATH}' was not found"
if [[ -n "$MODEL_ENTRYPOINT" && "$MODEL_ENTRYPOINT" != "." ]]; then
  [[ -e "$MODEL_DIR/$MODEL_ENTRYPOINT" ]] || fail "download completed but '${MODEL_DIR}/${MODEL_ENTRYPOINT}' was not found"
fi

printf '%s\n' "$MODEL_PATH"
