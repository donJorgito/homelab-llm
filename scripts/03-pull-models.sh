#!/usr/bin/env bash
# 03-pull-models.sh — pull the comma-separated list of models in OLLAMA_MODELS.
#
# Idempotent: models already present according to `ollama list` are skipped.
# Disk usage at LV_MOUNT_POINT is reported on entry and exit so you can see
# how many GB each pull consumed.
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
LV_MOUNT_POINT="${LV_MOUNT_POINT:-/var/lib/ollama}"
# OLLAMA_MODELS in .env is the comma-separated list of model tags to pull.
# (NOT the OLLAMA_MODELS systemd env var, which is a path — that one lives
# in OLLAMA_MODELS_DIR per 02-install-ollama.sh.)
OLLAMA_MODELS="${OLLAMA_MODELS:-qwen2.5-coder:7b,qwen2.5-coder:3b}"
DRY_RUN="${DRY_RUN:-no}"

usage() {
    cat <<EOF
Usage: $(basename "$0") [--dry-run] [--help]

Pull each model tag listed in OLLAMA_MODELS (comma-separated) using
'ollama pull'. Tags already present in 'ollama list' are skipped.

Options:
  --dry-run   Print every 'ollama pull' command without executing it.
  -h, --help  Show this help.

Env vars used:
  OLLAMA_BASE_URL  (default http://\${OLLAMA_HOST:-127.0.0.1}:\${OLLAMA_PORT})
  OLLAMA_MODELS    (default qwen2.5-coder:7b,qwen2.5-coder:3b)
  LV_MOUNT_POINT   (default /var/lib/ollama)
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

require_cmd ollama curl awk

log_step "Step 1: Verify Ollama is running"
HTTP_CODE="$(curl -fsS -o /dev/null -w '%{http_code}' "${OLLAMA_BASE_URL}/api/tags" || echo "000")"
if [[ "${HTTP_CODE}" != "200" ]]; then
    log_error "Ollama API at ${OLLAMA_BASE_URL}/api/tags returned HTTP ${HTTP_CODE}."
    log_error "Run 02-install-ollama.sh first or fix the service."
    exit 1
fi
log_info "Ollama API responsive at ${OLLAMA_BASE_URL}."

log_step "Step 2: Pull each model in OLLAMA_MODELS"
log_info "Disk usage before pulls:"
df -h "${LV_MOUNT_POINT}" || true

# Cache `ollama list` once so we do N grep instead of N forks.
EXISTING_MODELS="$(ollama list 2>/dev/null | awk 'NR>1 {print $1}')"

# Split comma-separated tags. Trim whitespace per element.
IFS=',' read -r -a MODELS <<< "${OLLAMA_MODELS}"
for raw in "${MODELS[@]}"; do
    model="$(printf '%s' "${raw}" | awk '{$1=$1; print}')"
    [[ -z "${model}" ]] && continue
    log_info "Model: ${model}"
    if printf '%s\n' "${EXISTING_MODELS}" | grep -Fxq "${model}"; then
        log_info "  already present; skip pull."
        continue
    fi
    dry_run_exec ollama pull "${model}"
done

log_step "Step 3: Final state"
if ! is_dry_run; then
    ollama list || true
fi
log_info "Disk usage after pulls:"
df -h "${LV_MOUNT_POINT}" || true

log_info "03-pull-models.sh complete."
