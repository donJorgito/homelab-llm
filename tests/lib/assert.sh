#!/usr/bin/env bash
# shellcheck shell=bash
# Shared assertion / output helpers for homelab-llm tests.
#
# Source this file from individual test scripts:
#     # shellcheck source=lib/assert.sh
#     source "$(dirname "$0")/lib/assert.sh"
#
# Provides:
#   info "msg"   — neutral status line on stderr
#   pass "msg"   — green PASS line on stderr
#   fail "msg"   — red   FAIL line on stderr, then exit 1
#   load_env     — sources .env from the repo root if present
#
# Colors are auto-disabled when stderr is not a TTY or when NO_COLOR is set.

if [ -t 2 ] && [ -z "${NO_COLOR:-}" ]; then
  __C_RESET='\033[0m'
  __C_RED='\033[0;31m'
  __C_GREEN='\033[0;32m'
  __C_YELLOW='\033[0;33m'
  __C_BLUE='\033[0;34m'
else
  __C_RESET=''
  __C_RED=''
  __C_GREEN=''
  __C_YELLOW=''
  __C_BLUE=''
fi

info() {
  printf '%b[INFO]%b %s\n' "${__C_BLUE}" "${__C_RESET}" "$*" >&2
}

warn() {
  printf '%b[WARN]%b %s\n' "${__C_YELLOW}" "${__C_RESET}" "$*" >&2
}

pass() {
  printf '%b[PASS]%b %s\n' "${__C_GREEN}" "${__C_RESET}" "$*" >&2
}

fail() {
  printf '%b[FAIL]%b %s\n' "${__C_RED}" "${__C_RESET}" "$*" >&2
  exit 1
}

# load_env [path-to-.env]
# Sources the given .env (default: <repo-root>/.env) if it exists. Silent if not.
load_env() {
  local env_file="${1:-}"
  if [ -z "${env_file}" ]; then
    # Resolve repo root as the parent of tests/
    local script_dir
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
    env_file="$(cd "${script_dir}/.." && pwd)/.env"
  fi
  if [ -f "${env_file}" ]; then
    info "Sourcing ${env_file}"
    set -a
    # shellcheck disable=SC1090
    source "${env_file}"
    set +a
  else
    info "No .env found at ${env_file}; using defaults from environment."
  fi
}
