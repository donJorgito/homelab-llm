#!/usr/bin/env bash
# Test for homelab-llm.RQ001 - Self-Hosted Inference Endpoint.
#
# Validates:
#   - GET ${OLLAMA_BASE_URL}/api/tags returns HTTP 200.
#   - Response body is valid JSON.
#   - .models array has at least one element.
#   - Round-trip latency on a warm endpoint is under 2 seconds.
#
# Non-destructive: read-only HTTP GET. Idempotent: safe to run repeatedly.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/assert.sh
source "${SCRIPT_DIR}/lib/assert.sh"

load_env

OLLAMA_HOST="${OLLAMA_HOST:-192.0.2.143}"
OLLAMA_PORT="${OLLAMA_PORT:-11434}"
OLLAMA_BASE_URL="${OLLAMA_BASE_URL:-http://${OLLAMA_HOST}:${OLLAMA_PORT}}"
MAX_LATENCY_SECONDS="${MAX_LATENCY_SECONDS:-2}"

command -v curl >/dev/null 2>&1 || fail "curl is required but not installed"
command -v jq >/dev/null 2>&1 || fail "jq is required but not installed"

URL="${OLLAMA_BASE_URL%/}/api/tags"
info "Probing inference endpoint at ${URL}"

TMP_BODY="$(mktemp)"
trap 'rm -f "${TMP_BODY}"' EXIT

# Warm-up request (discarded) so the latency assertion is against a warm endpoint.
curl --silent --show-error --fail --max-time 10 -o /dev/null "${URL}" \
  || fail "Warm-up GET ${URL} failed (endpoint unreachable or non-2xx)"

# Measured request.
HTTP_CODE_AND_TIME="$(
  curl --silent --show-error --max-time 10 \
    --output "${TMP_BODY}" \
    --write-out '%{http_code} %{time_total}' \
    "${URL}"
)"

HTTP_CODE="${HTTP_CODE_AND_TIME%% *}"
TIME_TOTAL="${HTTP_CODE_AND_TIME##* }"

if [ "${HTTP_CODE}" != "200" ]; then
  fail "Expected HTTP 200, got ${HTTP_CODE} from ${URL}"
fi
pass "HTTP status is 200"

if ! jq -e . >/dev/null 2>&1 <"${TMP_BODY}"; then
  fail "Response body is not valid JSON"
fi
pass "Response body is valid JSON"

MODEL_COUNT="$(jq '.models | length' <"${TMP_BODY}")"
if [ "${MODEL_COUNT}" -lt 1 ]; then
  fail ".models array is empty (expected >= 1, got ${MODEL_COUNT})"
fi
pass ".models array has ${MODEL_COUNT} element(s)"

# Compare time_total (float) against MAX_LATENCY_SECONDS using awk for portability.
if awk -v t="${TIME_TOTAL}" -v m="${MAX_LATENCY_SECONDS}" 'BEGIN { exit (t+0 <= m+0) ? 0 : 1 }'; then
  pass "Round-trip latency ${TIME_TOTAL}s <= ${MAX_LATENCY_SECONDS}s"
else
  fail "Round-trip latency ${TIME_TOTAL}s exceeded ${MAX_LATENCY_SECONDS}s budget"
fi

info "RQ001 OK"
exit 0
