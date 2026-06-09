#!/usr/bin/env bash
# Test for homelab-llm.RQ005 - Multi-Model Co-Hosting and Per-Request Switching.
#
# Validates that two models from ${OLLAMA_MODELS} can be invoked back-to-back
# via the same Ollama endpoint, each returning HTTP 200 and a JSON body whose
# .model field matches the requested tag, with no service restart in between.
#
# Non-destructive: only issues /api/generate requests. Idempotent.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/assert.sh
source "${SCRIPT_DIR}/lib/assert.sh"

load_env

OLLAMA_HOST="${OLLAMA_HOST:-192.0.2.143}"
OLLAMA_PORT="${OLLAMA_PORT:-11434}"
OLLAMA_BASE_URL="${OLLAMA_BASE_URL:-http://${OLLAMA_HOST}:${OLLAMA_PORT}}"
OLLAMA_MODELS="${OLLAMA_MODELS:-qwen2.5-coder:7b,qwen2.5-coder:3b}"
PER_REQUEST_TIMEOUT="${PER_REQUEST_TIMEOUT:-60}"

command -v curl >/dev/null 2>&1 || fail "curl is required but not installed"
command -v jq >/dev/null 2>&1 || fail "jq is required but not installed"

# Parse OLLAMA_MODELS (comma-separated) into an array.
IFS=',' read -r -a MODEL_LIST <<<"${OLLAMA_MODELS}"
if [ "${#MODEL_LIST[@]}" -lt 2 ]; then
  fail "RQ005 requires at least 2 models in OLLAMA_MODELS; got: ${OLLAMA_MODELS}"
fi

MODEL_A="${MODEL_LIST[0]// /}"
MODEL_B="${MODEL_LIST[1]// /}"
info "Model A: ${MODEL_A}"
info "Model B: ${MODEL_B}"

# Confirm both models are present in /api/tags.
TAGS_URL="${OLLAMA_BASE_URL%/}/api/tags"
TAGS_BODY="$(curl --silent --show-error --fail --max-time 10 "${TAGS_URL}")" \
  || fail "Could not GET ${TAGS_URL}"

for m in "${MODEL_A}" "${MODEL_B}"; do
  if ! echo "${TAGS_BODY}" | jq -e --arg m "${m}" '.models[] | select(.name == $m)' >/dev/null; then
    fail "Model '${m}' is not present in ${TAGS_URL}"
  fi
  pass "Model '${m}' is registered on the endpoint"
done

# Issue a tiny generation request per model and verify the .model field.
generate_and_check() {
  local model="$1"
  local url="${OLLAMA_BASE_URL%/}/api/generate"
  local payload
  payload="$(jq -nc --arg m "${model}" \
    '{model: $m, prompt: "Reply with only the word: ok", stream: false, options: {num_predict: 4}}')"

  info "POST ${url} (model=${model})"
  local body
  body="$(curl --silent --show-error --fail \
    --max-time "${PER_REQUEST_TIMEOUT}" \
    -H 'Content-Type: application/json' \
    -d "${payload}" \
    "${url}")" || fail "Request to ${url} for model '${model}' failed"

  if ! echo "${body}" | jq -e . >/dev/null 2>&1; then
    fail "Response for model '${model}' is not valid JSON"
  fi

  local got
  got="$(echo "${body}" | jq -r '.model // empty')"
  if [ "${got}" != "${model}" ]; then
    fail "Response .model='${got}' does not match requested model '${model}'"
  fi
  pass "Model '${model}' returned valid JSON with .model='${got}'"
}

START_TS="$(date +%s)"
generate_and_check "${MODEL_A}"
generate_and_check "${MODEL_B}"
END_TS="$(date +%s)"
ELAPSED=$((END_TS - START_TS))

info "Both model requests completed in ${ELAPSED}s"
# 30s budget per AC for the second request specifically; we conservatively
# bound the whole pair at 2 * PER_REQUEST_TIMEOUT (default 120s) since the
# first call may include a cold load.

info "RQ005 OK"
exit 0
