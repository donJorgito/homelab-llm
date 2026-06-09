#!/usr/bin/env bash
# 00-prerequisites.sh — non-destructive readiness check for the Ollama host.
#
# Verifies OS, GPU, sudo workflow, free disk, required commands, and that the
# Ollama port is free. Exits 1 if any critical check fails. Safe to run as
# many times as you like.
set -euo pipefail
IFS=$'\n\t'

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=lib/common.sh
source "${REPO_ROOT}/scripts/lib/common.sh"

# Source .env if present; tolerate absence.
if [[ -f "${REPO_ROOT}/.env" ]]; then
    # shellcheck disable=SC1091
    source "${REPO_ROOT}/.env"
fi

# Defaults.
OLLAMA_PORT="${OLLAMA_PORT:-11434}"
LV_MOUNT_POINT="${LV_MOUNT_POINT:-/var/lib/ollama}"
MIN_FREE_GB="${MIN_FREE_GB:-20}"

usage() {
    cat <<EOF
Usage: $(basename "$0") [--help]

Non-destructive check that hidra (or any Linux+NVIDIA host) is ready to
install Ollama, create the LVM volume and pull the configured models.

Reports a checklist with PASS / FAIL per item; exits 1 on any FAIL.

Environment:
  OLLAMA_PORT      (default 11434) — port that Ollama will bind to
  LV_MOUNT_POINT   (default /var/lib/ollama) — used to compute free disk
  MIN_FREE_GB      (default 20) — minimum free GB required at LV_MOUNT_POINT parent

Examples:
  $(basename "$0")
  MIN_FREE_GB=30 $(basename "$0")
EOF
}

# Argument parsing.
for arg in "$@"; do
    case "${arg}" in
        -h|--help) usage; exit 0 ;;
        *)
            log_error "Unknown argument: ${arg}"
            usage
            exit 2
            ;;
    esac
done

# Track failures.
FAIL_COUNT=0
pass() { printf '  %s[PASS]%s %s\n' "${__C_GREEN}" "${__C_RESET}" "$*"; }
fail() { printf '  %s[FAIL]%s %s\n' "${__C_RED}"   "${__C_RESET}" "$*"; FAIL_COUNT=$((FAIL_COUNT + 1)); }
warn() { printf '  %s[WARN]%s %s\n' "${__C_YELLOW}" "${__C_RESET}" "$*"; }

log_step "Step 1: Operating system"
if [[ "$(uname -s)" == "Linux" ]]; then
    pass "uname -s = Linux"
else
    fail "Expected Linux host; got $(uname -s)"
fi

# Distro check (best-effort: /etc/os-release is the canonical source).
if [[ -r /etc/os-release ]]; then
    # shellcheck disable=SC1091
    . /etc/os-release
    log_info "Distro: ${PRETTY_NAME:-${NAME:-unknown}}"
    case "${ID:-unknown}" in
        ubuntu|debian|pop)
            pass "Distro family supported (${ID})"
            ;;
        *)
            warn "Distro ${ID} not validated (Ubuntu 22.04+ is the reference); proceeding"
            ;;
    esac
else
    warn "/etc/os-release not readable; cannot identify distro"
fi

log_step "Step 2: NVIDIA GPU"
if command -v nvidia-smi >/dev/null 2>&1; then
    if nvidia-smi >/dev/null 2>&1; then
        local_vram="$(nvidia-smi --query-gpu=memory.total --format=csv,noheader,nounits 2>/dev/null | head -n1 || echo "?")"
        local_name="$(nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null | head -n1 || echo "?")"
        pass "nvidia-smi OK — ${local_name}, VRAM total: ${local_vram} MiB"
    else
        fail "nvidia-smi present but failed to query GPU"
    fi
else
    fail "nvidia-smi not found — install NVIDIA driver + utilities"
fi

log_step "Step 3: Sudo workflow"
if sudo -n true 2>/dev/null; then
    pass "sudo -n succeeds (passwordless sudo cached or configured)"
else
    fail "sudo -n failed — run 'sudo -v' in another shell or fix sudoers timestamp"
fi

log_step "Step 4: Free disk space"
# Pick the closest existing ancestor of LV_MOUNT_POINT to query df.
parent_path="${LV_MOUNT_POINT}"
while [[ ! -e "${parent_path}" && "${parent_path}" != "/" ]]; do
    parent_path="$(dirname "${parent_path}")"
done
if [[ -e "${parent_path}" ]]; then
    free_kb="$(df -Pk "${parent_path}" | awk 'NR==2 {print $4}')"
    free_gb=$(( free_kb / 1024 / 1024 ))
    if [[ "${free_gb}" -ge "${MIN_FREE_GB}" ]]; then
        pass "Free space at ${parent_path}: ${free_gb} GB (>= ${MIN_FREE_GB})"
    else
        fail "Free space at ${parent_path}: ${free_gb} GB (< ${MIN_FREE_GB} required)"
    fi
else
    warn "Could not resolve parent of ${LV_MOUNT_POINT}; skipping free-space check"
fi

log_step "Step 5: Required commands"
REQUIRED_CMDS=(curl jq lvcreate mkfs.ext4 mount systemctl ss)
for c in "${REQUIRED_CMDS[@]}"; do
    if command -v "${c}" >/dev/null 2>&1; then
        pass "${c} available"
    else
        fail "${c} not found"
    fi
done

log_step "Step 6: Ollama port availability"
if command -v ss >/dev/null 2>&1; then
    # Match :PORT$ to avoid matching e.g. port 1143 when looking for 11434.
    if ss -tlnH 2>/dev/null | awk '{print $4}' | grep -Eq ":${OLLAMA_PORT}\$"; then
        listener="$(ss -tlnp 2>/dev/null | awk -v p=":${OLLAMA_PORT}" '$4 ~ p {print; exit}')"
        # Tolerate Ollama itself already listening (idempotent re-check).
        if printf '%s' "${listener}" | grep -q 'ollama'; then
            warn "Port ${OLLAMA_PORT} already in use by ollama (likely fine):"
            printf '         %s\n' "${listener}"
        else
            fail "Port ${OLLAMA_PORT} already in use by another process:"
            printf '         %s\n' "${listener}"
        fi
    else
        pass "Port ${OLLAMA_PORT} is free"
    fi
else
    warn "ss not available; cannot verify port ${OLLAMA_PORT}"
fi

log_step "Summary"
if [[ "${FAIL_COUNT}" -eq 0 ]]; then
    log_info "All prerequisite checks passed."
    exit 0
fi

log_error "${FAIL_COUNT} prerequisite check(s) failed; resolve them before continuing."
exit 1
