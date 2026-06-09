# ADR-0003: Use aider as the CLI agentic client (not OpenCode)

- Status: Accepted
- Date: 2026-06-08
- Deciders: donJorgito (Owner)

## Context

We want a CLI agentic client to drive the local LLM hosted on `hidra`. Two candidates were tested:

- **OpenCode 1.16.2** — UX closest to Claude Code, MCP-aware, rich TUI.
- **aider 0.86.2** — minimalist CLI, parses markdown code blocks, native git integration.

OpenCode failed against **every small local model** tested (Qwen2.5-Coder 3B/7B, Granite Code 3B/8B, Granite 3.3 2B/8B). Direct probing of Ollama's `/v1/chat/completions` and `/api/chat` showed that the model emits the tool call **inside the `content` field as serialized JSON**, not in the structured `tool_calls[]` array — OpenCode rejects that response.

aider, by contrast, parses markdown code blocks directly from `content` and applies edits without requiring structured tool calls.

## Decision

Use **aider 0.86+** with `--edit-format whole` as the primary CLI client. OpenCode is **rejected for small local models** and only revisited if a substantially larger local model (>14B) or an external provider (e.g. Anthropic API) becomes available.

## Consequences

### Positive

- Works **today** with Qwen2.5-Coder via Ollama — no waiting on upstream tool-call shim improvements.
- Compact system prompt (~600 tokens) leaves headroom for context on small models.
- Native git integration with optional auto-commits.
- Multiple edit formats available (`whole`, `diff`, `udiff`); `whole` validated end-to-end (see ADR-0004).

### Negative

- UX is rougher than OpenCode (no rich TUI, no MCP).
- No native MCP support.
- `--edit-format diff` can fail on complex multi-file refactors with Qwen-Coder; `whole` is the safer default but consumes more output tokens per turn.
- Requires Python 3.10+ via `pipx`.

## Alternatives considered

- **OpenCode** — Better UX, but its ~7000-token system prompt (tools + skills + MCP) saturates 2-8B models, which then respond as plain markdown that OpenCode discards. Confirmed against Qwen2.5-Coder 3B/7B and Granite 3.3 2B/8B. Will be reconsidered when a larger local model or the Anthropic API is in play.
- **Cline / Continue.dev** — VS Code extensions, do not match the "old laptop, CLI from another house" target use case (see [docs/roadmap.md](../roadmap.md) v1.0).
- **Goose (Block)** — MCP-first; same system-prompt-bloat problem as OpenCode for small local models.
- **OpenClaw** — Deferred. It is a chat front-end for WhatsApp/Telegram, not a CLI agentic client.

## References

- [docs/case-study-hidra.md](../case-study-hidra.md) — "Client journey" section
- [docs/benchmarks.md](../benchmarks.md) — "Tool-use compatibility"
- [scripts/04-install-aider-mac.sh](../../scripts/04-install-aider-mac.sh)
- [ADR-0004](0004-qwen25-coder-7b-as-default-model.md)
