# vLLM model stack

Systemd-first orchestration for a small local model stack built on `vLLM`.

This repository mirrors the operator contract of `../llama-cpp-models`: `make`
is the primary control surface, user-level `systemd` is the primary runtime,
tracked defaults live in `config/`, mutable local overrides live in `runtime/`,
and each model can be downloaded, configured, started, stopped, sampled, and
replaced independently.

## What this repo does

- Installs CUDA `vLLM` into `.venv` and CPU `vLLM` into `.venv-cpu`.
- Installs templated user-level `systemd` units for long-running model services.
- Downloads model snapshots from Hugging Face using the token stored in `.env`.
- Keeps tracked defaults in `config/` and writes mutable overrides to `runtime/config/`.
- Exposes a `make` interface for lifecycle control, model replacement, LoRA activation, and sample requests.
- Logs every top-level `make` action to `logs/<target>-<timestamp>.log` while still streaming output to the terminal.

## Model catalog

| Model | Role | Default endpoint | Default port | Default device | Allowed devices | Default context | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `embeddings` | `google/embeddinggemma-300m` | `/v1/embeddings` | `8101` | `gpu` | `cpu,gpu` | `2048` | Pooling model served with `--runner pooling`. |
| `dense` | `Qwen/Qwen2.5-3B-Instruct-AWQ` | `/v1/chat/completions` | `8102` | `gpu` | `gpu` | `8192` | Main reasoning and extraction model. Supports optional LoRA adapters. |
| `sparse` | `HuggingFaceTB/SmolLM2-1.7B-Instruct` | `/v1/chat/completions` | `8103` | `gpu` | `cpu,gpu` | `3584` | Fast low-latency extraction and lightweight generation. Context is reduced on this 6 GiB GPU for stable startup. |
| `reranker` | `BAAI/bge-reranker-v2-m3` | `/v1/rerank` | `8104` | `gpu` | `cpu,gpu` | `8192` | Pooling model served with `--runner pooling`. |
| `coding` | `Qwen/Qwen2.5-Coder-1.5B-Instruct-AWQ` | `/v1/chat/completions` | `8105` | `gpu` | `gpu` | `8192` | Coding-focused generation model. |

The repo keeps the same five-role layout as the `llama.cpp` stack. The default
checkpoint choices are adapted to `vLLM` rather than GGUF, so two practical
differences matter:

- `dense` and `coding` default to smaller AWQ checkpoints and are GPU-only out of the box on this host.
- CPU mode for compatible checkpoints is backed by the separate `.venv-cpu` install, while the tracked defaults stay tuned for the CUDA path on this host.
- `sparse` keeps the same role and model family as the source repo, but its tracked context limit is reduced to `3584` to fit stable vLLM startup on a 6 GiB laptop GPU.

## Architecture

The control flow stays intentionally close to the source repo:

1. `make` targets call shell helpers in `scripts/`.
2. Model defaults come from `config/models/*.env`.
3. Mutable overrides are written to `runtime/config/*.env`.
4. `systemd` starts `scripts/run-vllm-server.sh <model>`.
5. `run-vllm-server.sh` resolves the effective config and launches `vllm serve`.

The repository is intentionally systemd-first. Docker is not the primary runtime
path here.

## Repository layout

```text
.
|-- Makefile
|-- .env.example
|-- config/
|   |-- models/              # tracked model defaults
|   `-- loras/               # tracked LoRA manifests
|-- data/                    # sample request payloads by model
|-- docs/
|   `-- system-capabilities.md
|-- logs/                    # make command transcripts
|-- runtime/
|   `-- config/              # mutable local overrides written by make
|-- scripts/                 # operational helpers
`-- systemd/user/            # user-level units
```

## Quick start

### 1. Seed `.env`

```bash
cp .env.example .env
make env-token HF_TOKEN=hf_your_token
```

The checked-in `.env.example` contains:

```bash
HF_TOKEN=
HF_HOME=${HOME}/.cache/huggingface
HF_HUB_ENABLE_HF_TRANSFER=1
VLLM_PYTHON_VERSION=3.12
VLLM_CPU_PYTHON_VERSION=3.12
VLLM_CPU_VERSION=0.19.0
VLLM_CPU_PACKAGE_URL=
```

This working tree already includes the copied `.env` from
`../llama-cpp-models/.env`, as requested.

### 2. Install prerequisites

```bash
make install-prereqs
```

This target:

- installs OS packages such as `build-essential`, `python3-venv`, `curl`, `git`, and `jq`
- installs `uv` when it is missing
- provisions `.venv` for the CUDA build and `.venv-cpu` for the CPU build
- installs the configured CUDA `vllm`, the official x86 CPU `vllm` wheel, `huggingface_hub[cli]`, and `nvitop`
- refreshes the user `systemd` units

### 3. Download model files

```bash
make download-all
```

Or download one model at a time:

```bash
make download MODEL=embeddings
make download MODEL=dense
make download MODEL=sparse
make download MODEL=reranker
make download MODEL=coding
```

### 4. Install or refresh the user units

```bash
make systemd-install
```

This links:

- `systemd/user/vllm-model@.service`
- `systemd/user/vllm-stack.target`

into `~/.config/systemd/user/` and writes the project root to
`~/.config/vllm-models/project.env`.

### 5. Start models

Examples:

```bash
make start MODEL=embeddings
make start MODEL=dense
make start MODEL=sparse
make start MODEL=reranker
make start MODEL=coding
```

If you need to flip a compatible model to CPU mode:

```bash
make start MODEL=embeddings DEVICE=cpu
make start MODEL=reranker DEVICE=cpu
make start MODEL=sparse DEVICE=cpu
```

CPU requests use `.venv-cpu`, while GPU requests use `.venv`.

## Primary commands

### Inspection

```bash
make help
make show MODEL=dense
make status MODEL=dense
make status-all
make logs MODEL=dense LINES=200
make logs-all LINES=200
```

### Lifecycle

```bash
make start MODEL=dense
make stop MODEL=dense
make restart MODEL=dense
make start-all
make stop-all
make restart-all
```

### Configuration and replacement

```bash
make configure MODEL=dense GPU_MEMORY_UTILIZATION=0.80 CTX_SIZE=8192
make replace MODEL=sparse HF_REPO=HuggingFaceTB/SmolLM2-360M-Instruct
make env-token HF_TOKEN=hf_your_new_token
```

### Sampling and validation

```bash
make sample MODEL=dense SAMPLE=extract
make sample MODEL=embeddings SAMPLE=basic
make sample-all
make test-sequence
```

### Dense LoRA workflow

```bash
make lora-config MODEL=dense LORA=cypher HF_REPO=org/cypher-lora ENABLED=true
make lora-download MODEL=dense LORA=cypher
make restart MODEL=dense
make lora-activate MODEL=dense LORAS=cypher,policy
make lora-deactivate MODEL=dense
```

## Configuration model

Tracked defaults live in `config/models/*.env`. Local mutable overrides are
written to `runtime/config/<model>.env`. LoRA overrides are written to
`runtime/config/loras/<model>.env`.

Effective precedence is:

1. Global environment from `.env`
2. Tracked model defaults in `config/models/<model>.env`
3. Local runtime overrides in `runtime/config/<model>.env`
4. For dense LoRAs only: tracked manifest in `config/loras/dense.env`
5. For dense LoRAs only: local overrides in `runtime/config/loras/dense.env`

This means `make configure` and `make start MODEL=... DEVICE=...` are not just
one-shot flags. They persist overrides to the local runtime config.

## Supported `make configure` keys

The Makefile supports these per-model override inputs:

| Input | Stored key | Meaning |
| --- | --- | --- |
| `DEVICE` | `MODEL_DEVICE` | `cpu` or `gpu` |
| `PORT` | `MODEL_PORT` | HTTP port for the service |
| `HOST` | `MODEL_HOST` | bind address |
| `CTX_SIZE` or `N_CTX` | `CONTEXT_SIZE` | `vLLM` max model length |
| `THREADS` | `THREADS` | CPU thread count for compatible CPU runs |
| `DISPLAY_NAME` | `MODEL_DISPLAY_NAME` | served model name |
| `SOURCE_REPO` | `MODEL_SOURCE_REPO` | upstream reference repo |
| `HF_REPO` | `MODEL_REPO` | Hugging Face repo used for download |
| `HF_FILE` | `MODEL_ENTRYPOINT` | optional file or directory entry to verify after download |
| `HF_PATTERN` | `MODEL_INCLUDE_PATTERN` | optional comma-separated download patterns |
| `HF_REVISION` | `MODEL_REVISION` | branch, tag, or revision |
| `DTYPE` | `DTYPE` | requested `vLLM` dtype |
| `QUANTIZATION` | `QUANTIZATION` | requested `vLLM` quantization mode |
| `GPU_MEMORY_UTILIZATION` | `GPU_MEMORY_UTILIZATION` | `vLLM` GPU cache budget |
| `SWAP_SPACE` | `SWAP_SPACE` | Retained for config compatibility with the source repo; current `vllm serve` on this host does not consume it directly |
| `TENSOR_PARALLEL_SIZE` | `TENSOR_PARALLEL_SIZE` | tensor parallel degree |
| `MAX_NUM_SEQS` | `MAX_NUM_SEQS` | concurrent sequence slots |
| `MAX_NUM_BATCHED_TOKENS` | `MAX_NUM_BATCHED_TOKENS` | scheduler batch budget |
| `ENABLE_PREFIX_CACHING` | `ENABLE_PREFIX_CACHING` | `true` or `false` |
| `TRUST_REMOTE_CODE` | `TRUST_REMOTE_CODE` | `true` or `false` |
| `CPU_KV_CACHE_GB` | `CPU_KV_CACHE_GB` | CPU kv-cache budget for compatible CPU runs |
| `EXTRA_ARGS` | `SERVER_EXTRA_ARGS` | extra `vllm serve` arguments |

Use `make show MODEL=<name>` to inspect the resolved runtime values.

## Device selection

Device switching is per model and persistent once written.

- `make start MODEL=<name> DEVICE=cpu` updates the runtime override and starts the service in CPU mode.
- `make start MODEL=<name> DEVICE=gpu` updates the runtime override and starts the service in GPU mode.
- `make restart MODEL=<name> DEVICE=...` behaves the same way.

Current defaults are GPU-first because this repo is tuned around a CUDA-capable
`vLLM` install on this host:

- `embeddings` defaults to GPU, but can be switched to CPU.
- `dense` defaults to GPU and ships with a GPU-only AWQ checkpoint.
- `sparse` defaults to GPU, but can be switched to CPU.
- `reranker` defaults to GPU, but can be switched to CPU.
- `coding` defaults to GPU and ships with a GPU-only AWQ checkpoint.

`make start-all` exists, but it starts all declared services at once. On a
single 6 GiB laptop GPU, the sequential flows are usually the practical choice:

- `make sample-all`
- `make test-sequence`

## Model replacement

Use `make replace` when you want to swap a configured model to another Hugging
Face repo and download it immediately.

Example:

```bash
make replace \
  MODEL=dense \
  HF_REPO=Qwen/Qwen2.5-14B-Instruct-AWQ \
  HF_PATTERN='*.json,*.safetensors,*.model,*.py,*.txt'
```

Notes:

- `HF_REPO` is the actual model snapshot used for download.
- `HF_PATTERN` is optional. Leave it empty to download the full repo.
- `HF_FILE` is no longer a GGUF filename. Here it is only an optional existence check for a known file inside the snapshot, such as `config.json` or `adapter_config.json`.

## Dense LoRA management

The `dense` model can load PEFT-style LoRA adapters through `vLLM`.

Tracked manifest:

- `config/loras/dense.env`

Available logical LoRA slots:

- `extract`
- `explain`
- `cypher`
- `resolve`
- `policy`

Typical flow:

```bash
make lora-config MODEL=dense LORA=extract HF_REPO=org/extract-lora ENABLED=true
make lora-download MODEL=dense LORA=extract
make restart MODEL=dense
make lora-activate MODEL=dense LORAS=extract
```

What the commands do:

- `lora-config` writes repo, revision, expected file, pattern, scale, and enabled state to the local LoRA override file.
- `lora-download` downloads the adapter snapshot into `models/dense/loras/<name>/`.
- `restart` reloads the service so previously selected adapters are exposed on startup.
- `lora-activate` persists the active adapter list and, when the service is already running, uses `vLLM`'s runtime LoRA API to load or unload adapters immediately.
- `lora-deactivate` clears the persisted active list and unloads adapters from the running service when possible.

This is the closest `vLLM` analogue to the dynamic LoRA workflow in the
`llama.cpp` stack. The important behavioral difference is that adapters are
requested by model name in `vLLM`, not by a global server-side scale list.

## Sample requests and metrics

Sample request payloads live under:

```text
data/<model>/<sample>/request.json
```

Current samples:

- `data/embeddings/basic/request.json`
- `data/embeddings/long-context/request.json`
- `data/dense/extract/request.json`
- `data/sparse/entities/request.json`
- `data/reranker/basic/request.json`
- `data/coding/refactor/request.json`

For a heavier embeddings run, use:

```bash
make sample MODEL=embeddings SAMPLE=long-context
```

If you actually want to exercise a much larger embedding window on this host,
raise the embeddings context first, because the tracked default is still `2048`:

```bash
make configure MODEL=embeddings CTX_SIZE=128000
make restart MODEL=embeddings
make sample MODEL=embeddings SAMPLE=long-context
```

`make sample MODEL=<name> [SAMPLE=<name>]`:

- requires the target service to already be active
- waits for the model health endpoint before sending the request
- prints a formatted response preview
- reports endpoint-appropriate metrics

Metrics reported by service type:

- generation models: HTTP status, total latency, time to first byte, prompt tokens, completion tokens, total tokens, output speed
- embeddings: HTTP status, total latency, time to first byte, input items, embeddings returned, vector dimensions, prompt tokens
- reranker: HTTP status, total latency, time to first byte, documents submitted, results returned, prompt tokens, best score

`make sample-all`:

- stops any currently running model services
- starts each selected model one by one
- runs the default sample for each
- leaves the last model running

`make test-sequence`:

- starts each selected model one by one
- verifies the unit reaches `active/running`
- stops each model before moving to the next
- leaves the last model running

## Logging and observability

There are two log layers.

### Make command logs

Every top-level `make` target runs through `scripts/run-with-log.sh` and writes:

```text
logs/<target>-<timestamp>.log
```

Those logs include:

- action name
- timestamp
- working directory
- exact command line
- streamed stdout and stderr

The same output is shown in the terminal while the file is being written.

### Service runtime logs

The `systemd` units send `vLLM` stdout and stderr to the journal.

Use:

```bash
make logs MODEL=dense
make logs-all
journalctl --user -u vllm-model@dense.service -f
```

`make start` and `make restart` also print a post-start `systemctl status`
snapshot so the command log captures the effective command line and recent
journal lines.

## Systemd design

Main unit:

- `systemd/user/vllm-model@.service`

Stack target:

- `systemd/user/vllm-stack.target`

The model service uses:

- `Restart=on-failure`
- `RestartSec=5`
- `TimeoutStartSec=1800`
- `KillSignal=SIGINT`

Each model is started with:

```bash
scripts/run-vllm-server.sh <model>
```

which resolves the final config and launches `vllm serve` with the correct:

- host
- port
- served model name
- local snapshot path
- max model length
- device
- tensor parallel size
- dtype and quantization settings
- scheduler budgets
- optional prefix caching
- optional pooling task flags such as `embed` or `score`
- optional LoRA module arguments

## Hugging Face authentication

Hugging Face downloads use the token in `.env`.

Set or rotate it with:

```bash
make env-token HF_TOKEN=hf_your_new_token
```

Optional related environment values:

- `HF_HOME`
- `HF_HUB_ENABLE_HF_TRANSFER`
- `HF_PYTHON_BIN`
- `VLLM_BIN`
- `VLLM_PYTHON_VERSION`
- `VLLM_PACKAGE`

`HF_REPO`, `HF_FILE`, `HF_PATTERN`, and `HF_REVISION` are per-model settings,
not global environment variables.

## Host notes

The host capability summary is captured in `docs/system-capabilities.md`.

This repository was tuned on a machine with:

- AMD Ryzen 7 6800H
- 30 GiB system RAM
- NVIDIA RTX 3060 Laptop GPU with 6 GiB VRAM

That is enough for the default split here, but not enough headroom to assume
all GPU-oriented services should run concurrently.

## Compatibility notes

- `vLLM` serves Hugging Face model snapshots, not GGUF-only checkpoints.
- Pooling workloads are handled through the `embed` and `score` tasks.
- Runtime LoRA loading requires `VLLM_ALLOW_RUNTIME_LORA_UPDATING=True`, which this repo exports only for LoRA-enabled model runs.
- The repo is intentionally optimized for `make + systemd` as the primary operator flow.

## Troubleshooting

### `make start` succeeds but the model is still loading

Use:

```bash
make logs MODEL=<name>
```

or

```bash
journalctl --user -u vllm-model@<name>.service -f
```

The `sample` command already waits for `GET /health` before sending the request.

### A model snapshot was downloaded but start fails

Run:

```bash
make show MODEL=<name>
```

and confirm:

- `HF_REPO`
- `HF_PATTERN`
- `LOCAL_PATH`
- `ENTRYPOINT`

match the files present under `models/<name>/`.

### GPU mode is unstable or OOMs

Lower the cache pressure and concurrency:

```bash
make configure MODEL=dense GPU_MEMORY_UTILIZATION=0.72 MAX_NUM_SEQS=4 MAX_NUM_BATCHED_TOKENS=4096
make restart MODEL=dense
```

### The units do not refresh after changes

Run:

```bash
make systemd-install
systemctl --user daemon-reload
```

## Contribution note

This repository is structured like an operator toolkit. If you extend it,
prefer:

- tracked defaults in `config/`
- mutable machine-specific state in `runtime/`
- thin `make` targets over direct one-off shell use
- separate commits by concern
