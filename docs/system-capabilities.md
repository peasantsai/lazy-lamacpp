# System capability report

Generated from local inspection on 2026-04-03.

## Host inventory

- OS: Ubuntu 26.04 development branch
- systemd: 259
- CPU: AMD Ryzen 7 6800H, 8 cores / 16 threads, AVX2 and FMA available
- Memory: 30 GiB total, about 23 GiB available at inspection time
- GPU: NVIDIA GeForce RTX 3060 Laptop GPU, 6 GiB VRAM
- Driver / CUDA: NVIDIA driver 580.126.09, CUDA runtime 13.0, `nvcc` 13.2.51
- Disk: 815 GiB free on `/`

## Practical llama.cpp implications

- CPU inference is viable for embeddings, reranking, and fallback inference on the 1.7B and 7B models.
- GPU offload is viable for 4-bit GGUF models. The 6 GiB RTX 3060 is a reasonable fit for `Qwen2.5-7B-Instruct` in Q4 with an 8k context target.
- `Jackrong/Qwen3.5-9B-Claude-4.6-Opus-Reasoning-Distilled-v2-GGUF` in `Q4_K_M` is listed at 5.63 GB, so this host should treat GPU mode as partial offload rather than full residency.
- A 30 GiB RAM budget is enough to keep CPU-backed models and some split GGUF shards resident without pressure.
- Disk capacity is not a constraint for the configured stack.

## Compatibility notes

- `google/embeddinggemma-300m` is configured through `ggml-org/embeddinggemma-300M-GGUF`.
- `Qwen/Qwen2.5-7B-Instruct-AWQ` is not directly consumable by llama.cpp, so the stack uses `Qwen/Qwen2.5-7B-Instruct-GGUF`.
- The official Qwen GGUF repo stores the Q4 checkpoint as split shards. The stack downloads both shards and uses shard `00001` as the entry file.
- The `embeddinggemma-300m` default context is set to 2048 because that is the current model-card limit, even though the original request mentioned 128k.
