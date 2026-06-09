# ADR-0004: Qwen2.5-Coder 7B as the default model + 3B fallback

- Status: Accepted
- Date: 2026-06-08
- Deciders: donJorgito (Owner)

## Context

`hidra` has an NVIDIA GTX 970 with 4 GB VRAM (~3.8 GB usable in practice). This caps model size aggressively. We benchmarked: Qwen2.5-Coder 3B/7B/32B, Granite Code 3B/8B, Granite 3.3 2B/8B. We need decent agentic-coding quality, usable speed, and a working tool-use path with aider (see ADR-0003).

## Decision

- **Default model:** `qwen2.5-coder:7b` (`Q4_K_M`), offloaded ~51% CPU / 49% GPU. Measured: **6.8 tok/s, ~1 s TTFT**.
- **Fast fallback:** `qwen2.5-coder:3b` (`Q4_K_M`), full GPU. Measured: **32 tok/s, ~0.3 s TTFT**. Used for quick iteration where 7B-level quality is not needed.
- **aider config:** `--edit-format whole` (validated end-to-end; `diff` may fail on complex refactors).
- **Ollama tuning** (via `systemd` override):
  - `OLLAMA_CONTEXT_LENGTH=16384` (up from default 4096) so tool-use prompts fit comfortably.
  - `OLLAMA_KEEP_ALIVE=30m` to keep the model resident in VRAM between turns.

## Consequences

### Positive

- Qwen2.5-Coder is state-of-the-art for small-coding models in 2026 (HumanEval ~88% on 7B).
- Capabilities advertised include `["completion", "tools", "insert"]`.
- 7B fits on a GTX 970 with CPU offload; the 3B fits entirely on GPU for snappy iteration.
- aider `whole` format works reliably across both sizes.

### Negative

- 6.8 tok/s on 7B is slow in absolute terms (cloud Sonnet 4.6 is 100+ tok/s). Multi-file refactors with complex intent need iteration with human feedback — the shakedown confirmed 4/5 tasks autonomous, 1 needed a hint.
- 7B `Q4_K_M` occupies ~6.0 GB total, ~1.5 GB of which lives in CPU RAM, adding offload latency.
- Qwen-Coder emits tool calls inside `content`, not in structured `tool_calls[]` — incompatible with OpenCode (see ADR-0003).

## Alternatives considered

- **Qwen2.5-Coder 32B** — Best quality, requires 18+ GB VRAM. Does not fit.
- **Qwen2.5-Coder 14B** — ~9 GB VRAM. Does not fit.
- **DeepSeek-Coder-V2-Lite (16B MoE / 2.4B active)** — ~10 GB total footprint. Does not fit.
- **Granite 3.3 8B** — Emits structured `tool_calls[]` (a plus) but measured at ~4.6 tok/s with offload (worse than 7B Qwen) and inferior coding quality.
- **Codestral 22B** — Would require Q2 quants plus heavy offload; throughput unviable.
- **Llama 3.2 3B** — Fits and is fast, but weaker than Qwen-Coder 3B on multi-file code-edit tasks.

## References

- [docs/benchmarks.md](../benchmarks.md)
- [docs/shakedown-results.md](../shakedown-results.md)
- [.env.example](../../.env.example)
- [ADR-0003](0003-aider-as-cli-agent-not-opencode.md)
