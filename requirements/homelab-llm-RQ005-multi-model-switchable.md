### homelab-llm.RQ005 - Multi-Model Co-Hosting and Per-Request Switching

**Description:**

The system MUST support multiple LLM models cohosted on the same Ollama instance and switchable on a per-request basis without restarting the service. This enables Pareto trade-offs (e.g., a small fast model for autocomplete-style tasks and a larger model for refactors) and the `aider --architect` planner+editor pattern, both of which require two distinct models reachable through the same endpoint.

**Parent Requirement:** N/A (personal homelab repository).

**Acceptance Criteria:**

- At least two models from `${OLLAMA_MODELS}` are present in the response of `GET ${OLLAMA_BASE_URL}/api/tags` (default reference set: `qwen2.5-coder:7b` and `qwen2.5-coder:3b`).
- Issuing two consecutive `POST ${OLLAMA_BASE_URL}/api/generate` requests, one per model, returns HTTP `200` and a JSON body with the `model` field equal to the requested model in each case.
- The second request succeeds within 30 seconds of the first, accounting for warm-cache reload between models on a 4 GB-VRAM GPU.
- Switching does not require restarting the `ollama` systemd unit between requests.
- The test does not pull, delete, or otherwise modify the model store.
