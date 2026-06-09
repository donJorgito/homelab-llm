#!/usr/bin/env bash
# Test for homelab-llm.RQ003 - Reproducible Setup Across Fresh Hosts.
#
# Smoke-level static validation only. This test does NOT execute the
# destructive bootstrap scripts; it asserts contracts that the scripts
# must expose so a real reproducibility run is safe and predictable:
#
#   - Each scripts/00..05-*.sh file exists and has 'set -euo pipefail'.
#   - Each script passes 'bash -n' (parser check, no execution).
#   - Each script mentions a '--dry-run' flag (string match).
#
# Non-destructive: only reads files. Idempotent.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/assert.sh
source "${SCRIPT_DIR}/lib/assert.sh"

load_env

REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
SCRIPTS_DIR="${REPO_ROOT}/scripts"

if [ ! -d "${SCRIPTS_DIR}" ]; then
  fail "scripts/ directory not found at ${SCRIPTS_DIR}"
fi

# Collect 0[0-5]-*.sh deterministically without relying on shell glob behavior.
mapfile -t SETUP_SCRIPTS < <(find "${SCRIPTS_DIR}" -maxdepth 1 -type f -name '0[0-5]-*.sh' | sort)

if [ "${#SETUP_SCRIPTS[@]}" -eq 0 ]; then
  fail "No setup scripts matching scripts/0[0-5]-*.sh were found"
fi

info "Found ${#SETUP_SCRIPTS[@]} setup script(s) to validate"

for script in "${SETUP_SCRIPTS[@]}"; do
  rel="${script#"${REPO_ROOT}"/}"

  if ! bash -n "${script}"; then
    fail "${rel}: bash -n syntax check failed"
  fi
  pass "${rel}: bash -n OK"

  if ! grep -Eq '^[[:space:]]*set[[:space:]]+-euo[[:space:]]+pipefail' "${script}"; then
    fail "${rel}: missing 'set -euo pipefail'"
  fi
  pass "${rel}: has 'set -euo pipefail'"

  if ! grep -q -- '--dry-run' "${script}"; then
    fail "${rel}: does not reference a --dry-run flag"
  fi
  pass "${rel}: supports --dry-run"
done

info "RQ003 OK"
exit 0
