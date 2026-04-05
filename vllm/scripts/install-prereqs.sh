#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

load_global_env
ensure_project_dirs

ensure_host_tools() {
  local missing=()
  local cmd

  for cmd in curl git jq python3; do
    command -v "$cmd" >/dev/null 2>&1 || missing+=("$cmd")
  done

  if (( ${#missing[@]} == 0 )); then
    return 0
  fi

  APT_GET=()
  if [[ $EUID -eq 0 ]]; then
    APT_GET=(apt-get)
  elif command -v sudo >/dev/null 2>&1 && sudo -n true >/dev/null 2>&1; then
    APT_GET=(sudo apt-get)
  else
    fail "missing required commands: ${missing[*]}; rerun as root or with passwordless sudo"
  fi

  "${APT_GET[@]}" update
  "${APT_GET[@]}" install -y --no-install-recommends \
    build-essential \
    ca-certificates \
    curl \
    git \
    jq \
    python3 \
    python3-venv
}

ensure_host_tools

if ! command -v uv >/dev/null 2>&1; then
  curl -LsSf https://astral.sh/uv/install.sh | sh
  # shellcheck disable=SC1091
  source "${HOME}/.cargo/env"
fi

VENV_PYTHON_VERSION="${VLLM_PYTHON_VERSION:-3.12}"
uv python install "$VENV_PYTHON_VERSION"
uv venv --clear --seed --python "$VENV_PYTHON_VERSION" "$ROOT_DIR/.venv"
uv pip install --python "$ROOT_DIR/.venv/bin/python" --upgrade pip setuptools wheel
uv pip install --python "$ROOT_DIR/.venv/bin/python" \
  "${VLLM_PACKAGE:-vllm}" \
  'huggingface_hub[cli]>=0.31,<1.0' \
  hf_transfer \
  nvitop

CPU_VENV_PYTHON_VERSION="${VLLM_CPU_PYTHON_VERSION:-$VENV_PYTHON_VERSION}"
CPU_VLLM_VERSION="${VLLM_CPU_VERSION:-0.19.0}"
CPU_VLLM_PACKAGE_URL="${VLLM_CPU_PACKAGE_URL:-https://github.com/vllm-project/vllm/releases/download/v${CPU_VLLM_VERSION}/vllm-${CPU_VLLM_VERSION}+cpu-cp38-abi3-manylinux_2_35_x86_64.whl}"

uv python install "$CPU_VENV_PYTHON_VERSION"
uv venv --clear --seed --python "$CPU_VENV_PYTHON_VERSION" "$ROOT_DIR/.venv-cpu"
uv pip install --python "$ROOT_DIR/.venv-cpu/bin/python" --upgrade pip setuptools wheel
uv pip install --python "$ROOT_DIR/.venv-cpu/bin/python" \
  "$CPU_VLLM_PACKAGE_URL" \
  --torch-backend cpu \
  'huggingface_hub[cli]>=0.31,<1.0' \
  hf_transfer \
  nvitop

"$ROOT_DIR/scripts/systemd-install.sh"
