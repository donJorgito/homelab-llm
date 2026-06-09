#!/usr/bin/env bash
# Test for homelab-llm.RQ004 - No Plaintext Secrets in Repository.
#
# Validates:
#   - gitleaks detect --no-git --source <repo> --redact returns 0 findings.
#   - .env appears in .gitignore.
#   - .env was never committed (git log returns empty for .env).
#   - .env.example exists.
#
# Non-destructive: read-only. Idempotent.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/assert.sh
source "${SCRIPT_DIR}/lib/assert.sh"

load_env

REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "${REPO_ROOT}"

# Locate or install gitleaks.
if ! command -v gitleaks >/dev/null 2>&1; then
  if command -v brew >/dev/null 2>&1; then
    info "gitleaks not found; attempting 'brew install gitleaks'"
    brew install gitleaks || fail "brew install gitleaks failed; install manually and re-run"
  else
    fail "gitleaks is not installed and brew is unavailable. Install gitleaks: https://github.com/gitleaks/gitleaks#installing"
  fi
fi

info "gitleaks version: $(gitleaks version 2>/dev/null || echo unknown)"

info "Running gitleaks against working tree (no-git)"
if ! gitleaks detect --no-git --source "${REPO_ROOT}" --redact --no-banner; then
  fail "gitleaks reported findings (see output above)"
fi
pass "gitleaks: no findings on working tree"

# .gitignore must list .env.
if [ ! -f "${REPO_ROOT}/.gitignore" ]; then
  fail ".gitignore not found at repo root"
fi
if ! grep -Eq '(^|/)\.env([[:space:]]|$)' "${REPO_ROOT}/.gitignore"; then
  fail ".env is not listed in .gitignore"
fi
pass ".env is gitignored"

# .env.example must exist.
if [ ! -f "${REPO_ROOT}/.env.example" ]; then
  fail ".env.example not found at repo root"
fi
pass ".env.example exists"

# .env must never have been committed. Skip check if git history is empty.
if git -C "${REPO_ROOT}" rev-parse --git-dir >/dev/null 2>&1; then
  if git -C "${REPO_ROOT}" rev-parse HEAD >/dev/null 2>&1; then
    LEAK_LOG="$(git -C "${REPO_ROOT}" log --all -p -- .env 2>/dev/null || true)"
    if [ -n "${LEAK_LOG}" ]; then
      fail ".env appears in git history (git log --all -p -- .env returned content)"
    fi
    pass ".env is absent from git history"
  else
    info "Repository has no commits yet; skipping git history check"
  fi
else
  info "Not inside a git repository; skipping git history check"
fi

info "RQ004 OK"
exit 0
