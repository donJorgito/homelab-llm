# Benchmarks

Real benchmarks measured on hidra (i7-4770S, GTX 970 4 GB) — Ollama 0.30.6 / driver 580.159.03 / cuda_v12.
Methodology: `scripts/bench/bench-perf.sh` and `scripts/bench/bench-toolcall.sh`.

## Methodology

Two benchmark scripts drive every measurement in this document:

- `scripts/bench/bench-perf.sh <model>` — issues a warmup call (model load + 1 token) followed by three deterministic prompts of varying length (Python groupby, Go middleware, JS refactor). It reports per-prompt generated tokens, generation time, generation tok/s, prompt-eval tok/s, time-to-first-token (TTFT) and total wall time. VRAM usage and GPU utilization are sampled with `nvidia-smi` during the run.
- `scripts/bench/bench-toolcall.sh <model> [<model> ...]` — sends a single tool-use prompt with one declared function to each model via `/api/chat` and inspects whether the response contains a structured `tool_calls[]` array (OpenAI-spec compliant) or a JSON blob serialized inside `content`.

All numbers below are from runs on hidra on 2026-06-08, in a single Ollama session with `OLLAMA_KEEP_ALIVE=30m` so warmup amortizes across prompts. Network jitter between Mac client and hidra over WiFi USB ranged 21–106 ms during the session and is **not** included in the model TTFT figures (those measure server-side time only).

## Hardware under test

| Component | Value |
|---|---|
| Host | hidra |
| OS | Ubuntu 24.04.4 LTS, kernel 6.8.0-110 |
| CPU | Intel i7-4770S (Haswell, 4c/8t) |
| RAM | 16 GB + 8 GB swap |
| GPU | NVIDIA GTX 970 (Maxwell, compute capability 5.2, 4 GB VRAM, ~3.8 GB usable) |
| NVIDIA driver | 580.159.03 |
| CUDA runtime | Ollama 0.30.6 falls back to `cuda_v12` (binary `cuda_v13` requires cc ≥ 7.5) |
| Ollama storage | LV `vg0/lv-ollama` 128 GB mounted at `/var/lib/ollama` |
| Network | WiFi USB `wlx5091e38a3a1f` (eno1 cabled is DOWN) |

## Performance benchmarks

### Qwen2.5-Coder 3B (full GPU)

Warmup (load + 1 token): **25.5 s**. Once loaded, the model fits entirely in VRAM (2397 MiB used, 100% GPU offload).

| Prompt | Tokens generated | Time | tok/s | Prompt eval tok/s | TTFT | Total |
|---|---:|---:|---:|---:|---:|---:|
| 1 — Python groupby | 56 | 1.70 s | 33.0 | 189.9 | 0.31 s | 2.39 s |
| 2 — Go middleware | 200 | 6.17 s | 32.4 | 200.0 | 0.25 s | 6.82 s |
| 3 — JS refactor | 102 | 3.13 s | 32.6 | 265.3 | 0.30 s | 3.78 s |

GPU utilization during generation: **79%**.

### Qwen2.5-Coder 7B (offload 51% CPU / 49% GPU)

Warmup (model partially cached): **6.7 s**. The 7B model does not fit in VRAM and runs split: 51% on CPU, 49% on GPU. VRAM use 3260 MiB.

| Prompt | Tokens generated | Time | tok/s | Prompt eval tok/s | TTFT | Total |
|---|---:|---:|---:|---:|---:|---:|
| 1 — Python groupby | 60 | 8.18 s | 7.3 | 61.0 | 0.95 s | 9.13 s |
| 2 — Go middleware | 200 | 27.56 s | 7.3 | 38.7 | 1.29 s | 28.85 s |
| 3 — JS refactor | 117 | 16.75 s | 7.0 | 80.3 | 1.00 s | 17.75 s |

GPU utilization during generation: **20%** (CPU is the bottleneck due to the offload split).

### Comparison summary

| Model | Avg gen tok/s | TTFT | VRAM use | Split | UX assessment |
|---|---:|---:|---:|---|---|
| Qwen2.5-Coder 3B | 32.7 | ~0.3 s | 2397 MiB | 100% GPU | Excellent for chat / snippets |
| Qwen2.5-Coder 7B | 7.2 | ~1.0 s | 3260 MiB | 51% CPU / 49% GPU | Acceptable for aider edits, slow but usable |

## Tool-use compatibility benchmark

Six models were probed for structured tool-use support. The benchmark looks for a populated `tool_calls[]` array in the response (OpenAI-spec compliant) versus a JSON blob serialized inside the `content` string.

| Model | Avg tok/s | `tool_calls[]` structured | Verdict | Compatible clients |
|---|---:|---|---|---|
| `qwen2.5-coder:3b` | 31.9 | No (53 tokens, JSON in `content`) | △ Content-style (aider only) | aider |
| `qwen2.5-coder:7b` | 6.0 | No (72 tokens, JSON in `content`) | △ Content-style (aider only) | aider |
| `granite-code:3b` | n/a (0 tokens) | No — `does not support tools` | ✗ Tool-use unsupported | none |
| `granite-code:8b` | n/a (0 tokens) | No — `does not support tools` | ✗ Tool-use unsupported | none |
| `granite3.3:2b` | 24.7 | Yes (56 tokens) | ✓ Native (OpenAI-spec compliant) | OpenCode, Cline, Continue, aider |
| `granite3.3:8b` | 4.6 | Yes (43 tokens) | ✓ Native (OpenAI-spec compliant) | OpenCode, Cline, Continue, aider |

**Verdict legend:**

- `✓ Native (OpenAI-spec compliant)` — server returns a populated `tool_calls[]` array; works with any client that follows the OpenAI tool-calling contract.
- `△ Content-style (aider only)` — server returns the tool call serialized as JSON inside the `content` field. aider parses code/markdown blocks directly from `content` so it doesn't care, but OpenCode / Cline / Continue all expect the structured array and will silently end the step without applying edits.
- `✗ Tool-use unsupported` — Ollama reports the model's `capabilities` does not include `"tools"`; the request errors out with `does not support tools`.

The Qwen2.5-Coder family is the strongest *coder* at this size class, but at the time of measurement the Ollama shim serializes its tool calls into `content` rather than promoting them to the structured `tool_calls[]` field. For aider this is a non-issue — aider drives the model with `--edit-format whole`/`diff` and parses code blocks straight from `content`. For OpenCode / Cline / Continue it is a hard blocker. See `docs/decisions/ADR-0003-aider-as-default-client.md` for the full rationale.

## Findings and recommendations

- **Real coding-agent UX with a large system prompt (OpenCode tier).** You need both *native* tool-use and enough cognitive headroom to keep the system prompt coherent. On a GTX 970, none of the tested models meet both bars: the only models with native `tool_calls[]` (Granite 3.3 2B / 8B) saturate badly under OpenCode-class system prompts and aren't strong coders. The coder-strong models (Qwen2.5-Coder) speak content-style tool calls and are rejected by OpenCode.
- **aider with a minimalist system prompt.** Qwen2.5-Coder 7B is the sweet spot — usable agentic quality at ~7.2 tok/s with the 51/49 offload split. Each turn costs roughly 90–180 s, which is slow but workable for non-interactive edits.
- **Pure chat / snippet generation.** Qwen2.5-Coder 3B at ~33 tok/s is excellent and feels nearly local-LLM-native on this hardware.

## Reproducibility

Both scripts read configuration (model host, output paths) from `.env`. To reproduce the numbers above on hidra:

```bash
source .env && scripts/bench/bench-perf.sh qwen2.5-coder:7b
scripts/bench/bench-toolcall.sh qwen2.5-coder:3b qwen2.5-coder:7b granite3.3:2b granite3.3:8b
```

`bench-perf.sh` writes per-prompt JSON results next to the script; `bench-toolcall.sh` prints a verdict table to stdout and exits non-zero if any model errors out.

## Notes

- GTX 970 has compute capability 5.2, below the cc ≥ 7.5 threshold of the prebuilt `cuda_v13` binary in Ollama 0.30.6 (`archs="[750 800 ...]"`). Ollama silently falls back to the legacy `cuda_v12` runtime, which works but loses the tensor-core-aware paths. Effective throughput is roughly 50% of what an RTX 30xx would deliver on the same model.
- Effective VRAM is ~3.8 GB after Xorg/GNOME residency (~100 MiB). Qwen2.5-Coder 7B Q4_K_M needs ~6.0 GB total, hence the mandatory ~50% CPU offload.
- Network jitter on the Mac→hidra path during the session was 21–106 ms over WiFi USB. This is *not* included in the model TTFT figures above (those are server-side only) but it does affect end-to-end client UX.
