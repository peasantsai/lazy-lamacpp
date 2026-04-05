# System capabilities

Snapshot date: 2026-04-03

- CPU: AMD Ryzen 7 6800H with Radeon Graphics, 8 cores / 16 threads
- RAM: 30 GiB total, 23 GiB available at capture time
- GPU: NVIDIA GeForce RTX 3060 Laptop GPU, 6144 MiB VRAM
- NVIDIA driver: 580.126.09
- Toolchain detected: Python 3.14.3, `uv` 0.11.2, GNU Make 4.4.1

Practical `vLLM` notes on this host:

- Treat `start-all` as a convenience target, not a realistic steady-state plan for all GPU-backed services at once.
- The default profiles are tuned for one model at a time or small combinations, with `sample-all` and `test-sequence` being the safer validation flows.
- CPU mode is available through the separate `.venv-cpu` backend; embeddings and reranker CPU flows were validated on this host.
- The tracked defaults still favor CUDA-friendly checkpoints for `vLLM`.
