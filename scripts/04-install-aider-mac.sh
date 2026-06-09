#!/usr/bin/env bash
# 04-install-aider-mac.sh — install aider on macOS via Homebrew.
#
# Idempotent and effectively non-destructive (brew install is reversible).
set -euo pipefail
IFS=$'\n\t'

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=lib/common.sh
source "${REPO_ROOT}/scripts/lib/common.sh"

if [[ -f "${REPO_ROOT}/.env" ]]; then
    # shellcheck disable=SC1091
    source "${REPO_ROOT}/.env"
fi

# Defaults.
OLLAMA_PORT="${OLLAMA_PORT:-11434}"
OLLAMA_BASE_URL="${OLLAMA_BASE_URL:-http://${OLLAMA_HOST:-127.0.0.1}:${OLLAMA_PORT}}"
DEFAULT_MODEL="${DEFAULT_MODEL:-qwen2.5-coder:7b}"
AIDER_MODEL="${AIDER_MODEL:-ollama_chat/${DEFAULT_MODEL}}"
AIDER_EDIT_FORMAT="${AIDER_EDIT_FORMAT:-whole}"
DRY_RUN="${DRY_RUN:-no}"

usage() {
    cat <<EOF
Usage: $(basename "$0") [--dry-run] [--help]

Install aider on macOS using 'brew install aider'. Idempotent: skipped if
'aider' is already on PATH.

Options:
  --dry-run   Print 'brew install' without executing it.
  -h, --help  Show this help.

Env vars used (only for the printed example command):
  OLLAMA_BASE_URL    (default http://\${OLLAMA_HOST:-127.0.0.1}:\${OLLAMA_PORT})
  AIDER_MODEL        (default ollama_chat/\${DEFAULT_MODEL})
  AIDER_EDIT_FORMAT  (default whole)
EOF
}

for arg in "$@"; do
    case "${arg}" in
        --dry-run) DRY_RUN="yes" ;;
        -h|--help) usage; exit 0 ;;
        *)
            log_error "Unknown argument: ${arg}"
            usage
            exit 2
            ;;
    esac
done
export DRY_RUN

log_step "Step 1: Verify macOS"
if [[ "$(uname -s)" != "Darwin" ]]; then
    log_error "This script targets macOS; got $(uname -s)."
    log_error "On Linux use 05-install-aider-linux.sh instead."
    exit 1
fi
log_info "Running on Darwin."

log_step "Step 2: Skip if aider already installed"
if command -v aider >/dev/null 2>&1; then
    log_info "aider already installed at $(command -v aider)"
    log_info "version: $(aider --version 2>/dev/null || echo 'unknown')"
    log_info "Nothing to do."
    log_step "Usage example"
    cat <<EOF
  OLLAMA_API_BASE=${OLLAMA_BASE_URL} \\
    aider --model ${AIDER_MODEL} \\
          --edit-format ${AIDER_EDIT_FORMAT} \\
          --no-show-release-notes
EOF
    exit 0
fi

log_step "Step 3: Verify Homebrew is present"
if ! command -v brew >/dev/null 2>&1; then
    log_error "Homebrew not found. Install from https://brew.sh and retry."
    exit 1
fi
log_info "brew available at $(command -v brew)."

log_step "Step 4: brew install aider"
dry_run_exec brew install aider

log_step "Step 5: Validate"
if is_dry_run; then
    log_info "[DRY] skipping aider --version validation."
else
    if ! command -v aider >/dev/null 2>&1; then
        log_error "Install ran but 'aider' is still not on PATH."
        exit 1
    fi
    log_info "aider --version: $(aider --version 2>/dev/null || echo 'unknown')"
fi

log_step "Step 6: Usage example"
cat <<EOF
  OLLAMA_API_BASE=${OLLAMA_BASE_URL} \\
    aider --model ${AIDER_MODEL} \\
          --edit-format ${AIDER_EDIT_FORMAT} \\
          --no-show-release-notes
EOF

log_info "04-install-aider-mac.sh complete."
