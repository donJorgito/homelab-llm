#!/usr/bin/env bash
# Test for homelab-llm.RQ002 - CLI Agent Edits Files End-to-End.
#
# Validates that aider, pointed at the self-hosted Ollama endpoint, can:
#   - Create hello.py with a greet(name) function.
#   - Create test_hello.py with a pytest assertion.
#   - Produce code that passes python3 -m py_compile and python3 -m pytest.
#
# Idempotent: each run uses a fresh mktemp dir and cleans up on exit.
# Non-destructive against the host: only touches a tempdir under $TMPDIR.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/assert.sh
source "${SCRIPT_DIR}/lib/assert.sh"

load_env

OLLAMA_HOST="${OLLAMA_HOST:-192.0.2.143}"
OLLAMA_PORT="${OLLAMA_PORT:-11434}"
OLLAMA_BASE_URL="${OLLAMA_BASE_URL:-http://${OLLAMA_HOST}:${OLLAMA_PORT}}"
AIDER_MODEL="${AIDER_MODEL:-ollama_chat/qwen2.5-coder:7b}"
AIDER_EDIT_FORMAT="${AIDER_EDIT_FORMAT:-whole}"
AIDER_TIMEOUT_SECONDS="${AIDER_TIMEOUT_SECONDS:-180}"

command -v aider >/dev/null 2>&1 || fail "aider is required but not installed (brew install aider on Mac)"
command -v python3 >/dev/null 2>&1 || fail "python3 is required but not installed"
python3 -c 'import pytest' 2>/dev/null || fail "pytest is required (pip install pytest)"

WORKDIR="$(mktemp -d -t rq002-aider.XXXXXX)"
info "Working dir: ${WORKDIR}"
# shellcheck disable=SC2329  # invoked indirectly via `trap cleanup EXIT`
cleanup() { rm -rf "${WORKDIR}"; }
trap cleanup EXIT

PROMPT="Create hello.py containing a function greet(name) that returns 'Hello, ' + name. Also create test_hello.py with a pytest test that asserts greet('World') == 'Hello, World'. Use only Python standard library."

info "Invoking aider against ${OLLAMA_BASE_URL} with model ${AIDER_MODEL}"
info "Aider timeout budget: ${AIDER_TIMEOUT_SECONDS}s"

# Run aider non-interactively. --yes-always auto-confirms file creation prompts.
# OLLAMA_API_BASE is the documented env var aider reads to reach a remote Ollama.
(
  cd "${WORKDIR}"
  OLLAMA_API_BASE="${OLLAMA_BASE_URL}" \
    aider \
    --model "${AIDER_MODEL}" \
    --edit-format "${AIDER_EDIT_FORMAT}" \
    --no-show-release-notes \
    --no-auto-commits \
    --no-git \
    --yes-always \
    --message "${PROMPT}" \
    >"${WORKDIR}/.aider.stdout" 2>"${WORKDIR}/.aider.stderr" &
  AIDER_PID=$!

  # Enforce timeout budget without relying on coreutils `timeout` (not on macOS by default).
  SECONDS_WAITED=0
  while kill -0 "${AIDER_PID}" 2>/dev/null; do
    if [ "${SECONDS_WAITED}" -ge "${AIDER_TIMEOUT_SECONDS}" ]; then
      kill -TERM "${AIDER_PID}" 2>/dev/null || true
      sleep 2
      kill -KILL "${AIDER_PID}" 2>/dev/null || true
      echo "TIMEOUT" >"${WORKDIR}/.aider.timeout"
      break
    fi
    sleep 2
    SECONDS_WAITED=$((SECONDS_WAITED + 2))
  done
  wait "${AIDER_PID}" 2>/dev/null || true
)

if [ -f "${WORKDIR}/.aider.timeout" ]; then
  fail "aider exceeded ${AIDER_TIMEOUT_SECONDS}s timeout budget"
fi

if [ ! -f "${WORKDIR}/hello.py" ]; then
  warn "aider stderr tail:"
  tail -n 40 "${WORKDIR}/.aider.stderr" >&2 || true
  fail "aider did not create hello.py"
fi
pass "hello.py was created"

if [ ! -f "${WORKDIR}/test_hello.py" ]; then
  fail "aider did not create test_hello.py"
fi
pass "test_hello.py was created"

if ! python3 -m py_compile "${WORKDIR}/hello.py"; then
  fail "hello.py does not compile (py_compile failed)"
fi
pass "hello.py compiles"

if ! (cd "${WORKDIR}" && python3 -m pytest -q test_hello.py); then
  fail "pytest failed against the generated test_hello.py"
fi
pass "pytest passes on generated test_hello.py"

info "RQ002 OK"
exit 0
