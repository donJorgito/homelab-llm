#!/usr/bin/env bash
# 05-install-aider-linux.sh — install aider on Linux via pipx.
#
# Idempotent and effectively non-destructive. Prefers pipx; bootstraps pipx
# from apt or pip --user if missing.
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

Install aider on Linux using pipx. Bootstraps pipx via apt or
'python3 -m pip install --user pipx' if it is not already available.
Idempotent: skipped if 'aider' is already on PATH.

Options:
  --dry-run   Print every install command without executing it.
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

log_step "Step 1: Verify Linux"
if [[ "$(uname -s)" != "Linux" ]]; then
    log_error "This script targets Linux; got $(uname -s)."
    log_error "On macOS use 04-install-aider-mac.sh instead."
    exit 1
fi
log_info "Running on Linux."

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

log_step "Step 3: Ensure pipx is available"
if command -v pipx >/dev/null 2>&1; then
    log_info "pipx already available at $(command -v pipx)."
else
    if command -v apt-get >/dev/null 2>&1; then
        log_info "Installing pipx via apt-get."
        dry_run_exec sudo apt-get update
        dry_run_exec sudo apt-get install -y pipx
        if ! is_dry_run; then
            dry_run_exec pipx ensurepath || true
        fi
    elif command -v python3 >/dev/null 2>&1; then
        log_info "Installing pipx via 'python3 -m pip install --user pipx'."
        dry_run_exec python3 -m pip install --user pipx
        if ! is_dry_run; then
            dry_run_exec python3 -m pipx ensurepath || true
        fi
    else
        log_error "Neither apt-get nor python3 found; cannot bootstrap pipx."
        exit 1
    fi
fi

log_step "Step 4: pipx install aider-chat"
dry_run_exec pipx install aider-chat

log_step "Step 5: Validate"
if is_dry_run; then
    log_info "[DRY] skipping aider --version validation."
else
    # pipx may have only added the bin dir to PATH for new shells; try the
    # standard pipx bin location as a fallback.
    if ! command -v aider >/dev/null 2>&1; then
        if [[ -x "${HOME}/.local/bin/aider" ]]; then
            log_warn "aider not on PATH yet; found at ~/.local/bin/aider."
            log_warn "Open a new shell or run 'pipx ensurepath' and restart."
        else
            log_error "Install ran but 'aider' is not on PATH and not at ~/.local/bin."
            exit 1
        fi
    else
        log_info "aider --version: $(aider --version 2>/dev/null || echo 'unknown')"
    fi
fi

log_step "Step 6: Usage example"
cat <<EOF
  OLLAMA_API_BASE=${OLLAMA_BASE_URL} \\
    aider --model ${AIDER_MODEL} \\
          --edit-format ${AIDER_EDIT_FORMAT} \\
          --no-show-release-notes
EOF

log_info "05-install-aider-linux.sh complete."
