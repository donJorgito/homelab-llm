#!/usr/bin/env bash
# 02-install-ollama.sh — install Ollama and apply the systemd override.
#
# Idempotent. The systemd override is rewritten only when the desired contents
# differ from the on-disk file (a .bak backup is kept of the previous version).
#
# Steps:
#   1. Detect whether ollama is already installed and active.
#   2. If not installed: run upstream installer (curl | sh) — WARN to user.
#   3. Create /etc/systemd/system/ollama.service.d/.
#   4. Render override.conf from .env values; backup + replace if changed.
#   5. chown LV_MOUNT_POINT to ollama:ollama (mode 0750).
#   6. systemctl daemon-reload + restart ollama.
#   7. Wait briefly + verify /api/tags returns HTTP 200.
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
# OLLAMA_HOST in .env is the *server hostname*; the runtime listen var includes
# the bind address. Compose it explicitly so we never bake the host IP into a
# systemd unit.
OLLAMA_LISTEN="${OLLAMA_LISTEN:-0.0.0.0:${OLLAMA_PORT}}"
OLLAMA_BASE_URL="${OLLAMA_BASE_URL:-http://${OLLAMA_HOST:-127.0.0.1}:${OLLAMA_PORT}}"
OLLAMA_MODELS_DIR="${OLLAMA_MODELS_DIR:-${LV_MOUNT_POINT:-/var/lib/ollama}/models}"
OLLAMA_CONTEXT_LENGTH="${OLLAMA_CONTEXT_LENGTH:-16384}"
OLLAMA_KEEP_ALIVE="${OLLAMA_KEEP_ALIVE:-30m}"
LV_MOUNT_POINT="${LV_MOUNT_POINT:-/var/lib/ollama}"
DRY_RUN="${DRY_RUN:-no}"

usage() {
    cat <<EOF
Usage: $(basename "$0") [--dry-run] [--help]

Install Ollama via the upstream installer and apply the systemd override that
points OLLAMA_MODELS at the dedicated LV plus runtime tuning. Idempotent.

Options:
  --dry-run   Print every install/restart command without executing it.
  -h, --help  Show this help.

Env vars used:
  OLLAMA_PORT             (default 11434)
  OLLAMA_LISTEN           (default 0.0.0.0:\${OLLAMA_PORT})
  OLLAMA_BASE_URL         (default http://\${OLLAMA_HOST:-127.0.0.1}:\${OLLAMA_PORT})
  OLLAMA_MODELS_DIR       (default \${LV_MOUNT_POINT}/models)
  OLLAMA_CONTEXT_LENGTH   (default 16384)
  OLLAMA_KEEP_ALIVE       (default 30m)
  LV_MOUNT_POINT          (default /var/lib/ollama)
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

require_cmd sudo curl systemctl install diff mktemp
if is_dry_run; then
    log_warn "DRY_RUN=yes — no destructive command will execute."
fi

log_step "Step 1: Detect existing Ollama"
ALREADY_INSTALLED="no"
ALREADY_ACTIVE="no"
if command -v ollama >/dev/null 2>&1; then
    ALREADY_INSTALLED="yes"
    log_info "ollama binary present at $(command -v ollama)"
fi
if systemctl is-active --quiet ollama 2>/dev/null; then
    ALREADY_ACTIVE="yes"
    log_info "ollama.service is active."
fi

log_step "Step 2: Install Ollama (if missing)"
if [[ "${ALREADY_INSTALLED}" == "yes" ]]; then
    log_info "Ollama already installed; skipping upstream installer."
else
    log_warn "About to download and execute https://ollama.com/install.sh."
    log_warn "This is the upstream-recommended path; review the script if your"
    log_warn "policy requires it. Skip with Ctrl-C and install manually instead."
    dry_run_exec sh -c "curl -fsSL https://ollama.com/install.sh | sh"
fi

log_step "Step 3: Ensure systemd override directory"
OVERRIDE_DIR="/etc/systemd/system/ollama.service.d"
OVERRIDE_FILE="${OVERRIDE_DIR}/override.conf"
dry_run_exec sudo mkdir -p "${OVERRIDE_DIR}"

log_step "Step 4: Render systemd override"
DESIRED_OVERRIDE="$(cat <<EOF
# Managed by homelab-llm scripts/02-install-ollama.sh — do not edit by hand.
# Edits will be overwritten on next run; change the values via .env instead.
[Service]
Environment="OLLAMA_HOST=${OLLAMA_LISTEN}"
Environment="OLLAMA_MODELS=${OLLAMA_MODELS_DIR}"
Environment="OLLAMA_CONTEXT_LENGTH=${OLLAMA_CONTEXT_LENGTH}"
Environment="OLLAMA_KEEP_ALIVE=${OLLAMA_KEEP_ALIVE}"
EOF
)"

OVERRIDE_CHANGED="no"
if sudo test -f "${OVERRIDE_FILE}"; then
    CURRENT_OVERRIDE="$(sudo cat "${OVERRIDE_FILE}")"
    if [[ "${CURRENT_OVERRIDE}" == "${DESIRED_OVERRIDE}" ]]; then
        log_info "${OVERRIDE_FILE} already up to date; skipping."
    else
        OVERRIDE_CHANGED="yes"
        log_info "${OVERRIDE_FILE} differs from desired; will replace (with .bak)."
    fi
else
    OVERRIDE_CHANGED="yes"
    log_info "${OVERRIDE_FILE} does not exist; will create."
fi

if [[ "${OVERRIDE_CHANGED}" == "yes" ]]; then
    if is_dry_run; then
        printf '%s[DRY]%s would write %s with content:\n' "${__C_YELLOW}" "${__C_RESET}" "${OVERRIDE_FILE}"
        printf '%s\n' "${DESIRED_OVERRIDE}" | sed 's/^/         /'
    else
        if sudo test -f "${OVERRIDE_FILE}"; then
            BACKUP="${OVERRIDE_FILE}.bak.$(date -u +%Y%m%dT%H%M%SZ)"
            sudo cp -a "${OVERRIDE_FILE}" "${BACKUP}"
            log_info "Backed up previous override to ${BACKUP}"
        fi
        TMP="$(mktemp)"
        printf '%s\n' "${DESIRED_OVERRIDE}" >"${TMP}"
        sudo install -m 0644 -o root -g root "${TMP}" "${OVERRIDE_FILE}"
        rm -f "${TMP}"
    fi
fi

log_step "Step 5: chown mount point to ollama:ollama"
if id ollama >/dev/null 2>&1 || is_dry_run; then
    dry_run_exec sudo chown -R ollama:ollama "${LV_MOUNT_POINT}"
    dry_run_exec sudo chmod 0750 "${LV_MOUNT_POINT}"
else
    log_warn "User 'ollama' does not exist yet; skipping chown."
    log_warn "Re-run this script after the upstream installer completes."
fi

log_step "Step 6: Reload systemd + restart ollama"
dry_run_exec sudo systemctl daemon-reload
if [[ "${OVERRIDE_CHANGED}" == "yes" || "${ALREADY_ACTIVE}" != "yes" ]]; then
    dry_run_exec sudo systemctl restart ollama
else
    log_info "Override unchanged and service already active; skipping restart."
fi
dry_run_exec sudo systemctl enable ollama

log_step "Step 7: Verify Ollama API responds"
if is_dry_run; then
    log_info "[DRY] would curl ${OLLAMA_BASE_URL}/api/tags"
else
    log_info "Sleeping 5 s for service warm-up..."
    sleep 5
    HTTP_CODE="$(curl -fsS -o /dev/null -w '%{http_code}' "${OLLAMA_BASE_URL}/api/tags" || echo "000")"
    if [[ "${HTTP_CODE}" == "200" ]]; then
        log_info "Ollama API OK at ${OLLAMA_BASE_URL}/api/tags (HTTP 200)."
    else
        log_error "Ollama API not responding correctly: HTTP ${HTTP_CODE}"
        log_error "Check 'sudo journalctl -u ollama -n 200' for details."
        exit 1
    fi
fi

log_info "02-install-ollama.sh complete."
