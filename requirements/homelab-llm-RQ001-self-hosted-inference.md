### homelab-llm.RQ001 - Self-Hosted Inference Endpoint

**Description:**

The system MUST expose a self-hosted LLM inference endpoint reachable on the LAN, returning model metadata via HTTP `GET` to `${OLLAMA_BASE_URL}/api/tags`. The endpoint is the canonical liveness probe for the inference layer and confirms that Ollama is bound to the LAN interface, the systemd unit is running, and at least one model has been pulled into the configured `OLLAMA_MODELS` directory.

**Parent Requirement:** N/A (personal homelab repository, no upstream solution-level requirement).

**Acceptance Criteria:**

- `GET ${OLLAMA_BASE_URL}/api/tags` returns HTTP status `200` from a client on the same LAN.
- Response body is valid JSON.
- Parsed JSON contains a `.models` array with at least one element.
- Round-trip latency is under 2 seconds against a warm endpoint (process already started, no cold disk reads).
- Test is non-destructive: it only issues a read request and does not pull, push, or delete models.
