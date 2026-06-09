# ADR-0001: Ollama as the inference engine

- Status: Accepted
- Date: 2026-06-08
- Deciders: donJorgito (Owner)

## Context

We need to serve LLMs on `hidra` (NVIDIA GPU host) and expose an HTTP endpoint compatible with existing CLI clients (aider, OpenCode, future ones). The runtime must be simple to install, manage models out of the box, and integrate with `systemd`. Building a custom runner around `llama.cpp` is out of scope for a personal homelab.

## Decision

Use **Ollama 0.30.6+** installed via the official `curl | sh` script, with a `systemd` drop-in override:

- `OLLAMA_HOST=0.0.0.0:${OLLAMA_PORT}` so the daemon listens on the LAN.
- `OLLAMA_MODELS=/var/lib/ollama/models` pointing to a dedicated LVM volume (see ADR-0002).
- Service runs as the `ollama` system user managed by `systemd`.

## Consequences

### Positive

- One-liner install; no compile step.
- Handles quantization variants automatically (`Q4_K_M`, `Q5_K_M`, etc.).
- Exposes both native `/api/chat` and OpenAI-compatible `/v1/chat/completions` endpoints.
- `systemd`-managed: autostart on boot, logs in `journald`, standard restart policies.
- Friendly CLI (`ollama list`, `ollama pull`, `ollama show`) for day-2 ops.

### Negative

- Dependency on an upstream project with external governance; the OpenAI-compatible shim is regularly updated but is not perfect (see ADR-0003).
- CUDA architecture threshold: the `cuda_v13` binary requires `cc >= 7.5`; on Maxwell (GTX 970, `cc 5.2`) it falls back to `cuda_v12`, which works but is legacy.
- No first-class multi-GPU sharding for a single model.
- Runtime install via `curl | sh` requires trusting the upstream installer. We pin model digests via tags but cannot easily pin the installer binary itself; this limitation is acknowledged.

## Alternatives considered

- **vLLM** — Higher throughput, but heavier setup and less ergonomic for hosting multiple coding models concurrently on a small GPU.
- **llama.cpp standalone** — Maximum control, but requires building the HTTP server and operational tooling by hand.
- **LM Studio** — GUI-first, does not fit a headless homelab server.

## References

- [docs/architecture.md](../architecture.md)
- [scripts/02-install-ollama.sh](../../scripts/02-install-ollama.sh)
- [docs/case-study-hidra.md](../case-study-hidra.md)
- [ADR-0002](0002-storage-on-dedicated-lvm-volume.md)
- [ADR-0004](0004-qwen25-coder-7b-as-default-model.md)
