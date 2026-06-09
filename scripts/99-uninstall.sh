#!/usr/bin/env bash
# 99-uninstall.sh — completely remove the Ollama install + LV.
#
# VERY DESTRUCTIVE. Without --force, prints a plan and exits 0. Even with
# --force the literal-yes prompt from confirm_destructive() is still required
# unless --yes is also passed (or FORCE=yes already implies it via env).
#
# Order of operations is the inverse of 02->01:
#   stop service -> disable service -> remove override -> apt remove --purge
#   ollama -> umount LV -> remove fstab entry -> lvremove -> rmdir mount point
set -euo pipefail
IFS=$'\n\t'

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=lib/common.sh
source "${REPO_ROOT}/scripts/lib/common.sh"
# shellcheck source=lib/confirm.sh
source "${REPO_ROOT}/scripts/lib/confirm.sh"

if [[ -f "${REPO_ROOT}/.env" ]]; then
    # shellcheck disable=SC1091
    source "${REPO_ROOT}/.env"
fi

# Defaults.
LV_VG_NAME="${LV_VG_NAME:-vg0}"
LV_NAME="${LV_NAME:-lv-ollama}"
LV_MOUNT_POINT="${LV_MOUNT_POINT:-/var/lib/ollama}"
DRY_RUN="${DRY_RUN:-no}"
SKIP_CONFIRM="${SKIP_CONFIRM:-no}"
FORCE_FLAG="${FORCE_FLAG:-no}"

usage() {
    cat <<EOF
Usage: $(basename "$0") [--force] [--dry-run] [--yes] [--help]

REMOVE the Ollama install and the dedicated LV. WITHOUT --force the script
just prints what it WOULD do and exits 0 — safe to invoke for inspection.

Options:
  --force     Actually perform the removal. Without this, no destructive op runs.
  --dry-run   With --force, log every command but do not execute it.
  --yes       Skip the literal-'yes' confirmation prompt (CI/automation).
  -h, --help  Show this help.

Env vars used:
  LV_VG_NAME       (default vg0)
  LV_NAME          (default lv-ollama)
  LV_MOUNT_POINT   (default /var/lib/ollama)
EOF
}

for arg in "$@"; do
    case "${arg}" in
        --force)   FORCE_FLAG="yes" ;;
        --dry-run) DRY_RUN="yes" ;;
        --yes)     SKIP_CONFIRM="yes" ;;
        -h|--help) usage; exit 0 ;;
        *)
            log_error "Unknown argument: ${arg}"
            usage
            exit 2
            ;;
    esac
done
export DRY_RUN
# Map --yes to FORCE for confirm_destructive. (Naming clash: this script's
# --force toggles the *destruction itself*; confirm_destructive's FORCE
# toggles the *prompt*. Keep them separate via FORCE_FLAG / FORCE.)
if [[ "${SKIP_CONFIRM}" == "yes" ]]; then
    export FORCE="yes"
fi

LV_DEV="/dev/${LV_VG_NAME}/${LV_NAME}"

log_step "Step 1: Plan — what would be destroyed"
cat <<EOF
The following will be removed:

  Ollama service        : systemctl stop ollama && systemctl disable ollama
  systemd override      : /etc/systemd/system/ollama.service.d/override.conf
  Ollama package        : sudo apt-get remove --purge -y ollama
                          (falls back to /usr/local/bin/ollama removal if not apt)
  LV mount              : umount ${LV_MOUNT_POINT}
  fstab entry           : line referring to ${LV_DEV} or its UUID
  LV                    : lvremove ${LV_VG_NAME}/${LV_NAME}
  Mount point dir       : rmdir ${LV_MOUNT_POINT}
  Models on disk        : everything under ${LV_MOUNT_POINT} (~13 GB typical)

EOF

if [[ "${FORCE_FLAG}" != "yes" ]]; then
    log_warn "Run again with --force to actually destroy the items above."
    exit 0
fi

# Plan-mode runs anywhere; destructive mode needs the Linux toolchain.
require_cmd sudo systemctl umount

log_step "Step 2: Confirmation"
if ! confirm_destructive "Will permanently remove Ollama, LV ${LV_VG_NAME}/${LV_NAME}, and all downloaded models at ${LV_MOUNT_POINT}"; then
    log_error "Confirmation declined; aborting."
    exit 1
fi

log_step "Step 3: Stop + disable ollama service"
if systemctl list-unit-files 2>/dev/null | grep -q '^ollama\.service'; then
    dry_run_exec sudo systemctl stop ollama || true
    dry_run_exec sudo systemctl disable ollama || true
else
    log_info "ollama.service unit not registered; skipping stop/disable."
fi

log_step "Step 4: Remove systemd override"
OVERRIDE_DIR="/etc/systemd/system/ollama.service.d"
OVERRIDE_FILE="${OVERRIDE_DIR}/override.conf"
if sudo test -e "${OVERRIDE_FILE}"; then
    dry_run_exec sudo rm -f "${OVERRIDE_FILE}"
fi
if sudo test -d "${OVERRIDE_DIR}"; then
    # rmdir only if empty (after override.conf removal); ignore non-empty error.
    dry_run_exec sudo rmdir --ignore-fail-on-non-empty "${OVERRIDE_DIR}"
fi
dry_run_exec sudo systemctl daemon-reload

log_step "Step 5: Remove ollama package or binary"
if command -v apt-get >/dev/null 2>&1 && dpkg -s ollama >/dev/null 2>&1; then
    dry_run_exec sudo apt-get remove --purge -y ollama
elif [[ -x /usr/local/bin/ollama ]]; then
    log_info "ollama not installed via apt; removing /usr/local/bin/ollama directly."
    dry_run_exec sudo rm -f /usr/local/bin/ollama
else
    log_info "No ollama binary to remove."
fi
# Remove ollama user/group if upstream installer created them and they are unused.
if id ollama >/dev/null 2>&1; then
    log_info "Leaving 'ollama' user/group in place (manual cleanup if you want them gone)."
fi

log_step "Step 6: Unmount LV"
if mountpoint -q "${LV_MOUNT_POINT}" 2>/dev/null; then
    dry_run_exec sudo umount "${LV_MOUNT_POINT}"
else
    log_info "${LV_MOUNT_POINT} is not currently mounted."
fi

log_step "Step 7: Remove fstab entry"
FSTAB="/etc/fstab"
if [[ -e "${LV_DEV}" ]]; then
    LV_UUID="$(sudo blkid -s UUID -o value "${LV_DEV}" 2>/dev/null || true)"
else
    LV_UUID=""
fi
# Match by device path or UUID. Use sed -i with a backup so we always have a rollback.
if sudo grep -Eq "(^[[:space:]]*UUID=${LV_UUID:-__none__}\\b|^[[:space:]]*${LV_DEV}\\b)" "${FSTAB}" 2>/dev/null; then
    if is_dry_run; then
        printf '%s[DRY]%s sed -i.bak removing fstab line for %s (UUID=%s)\n' \
            "${__C_YELLOW}" "${__C_RESET}" "${LV_DEV}" "${LV_UUID:-?}"
    else
        # Remove device-path lines first, then UUID lines (if UUID known).
        sudo sed -i.bak -E "\\#^[[:space:]]*${LV_DEV}\\b#d" "${FSTAB}"
        if [[ -n "${LV_UUID}" ]]; then
            sudo sed -i -E "\\#^[[:space:]]*UUID=${LV_UUID}\\b#d" "${FSTAB}"
        fi
        log_info "Removed fstab entry; backup at ${FSTAB}.bak"
    fi
else
    log_info "No matching fstab entry; skipping."
fi

log_step "Step 8: lvremove"
if sudo lvs "${LV_VG_NAME}/${LV_NAME}" >/dev/null 2>&1; then
    dry_run_exec sudo lvremove -f "${LV_VG_NAME}/${LV_NAME}"
else
    log_info "LV ${LV_VG_NAME}/${LV_NAME} does not exist; skipping lvremove."
fi

log_step "Step 9: Remove mount point directory"
if [[ -d "${LV_MOUNT_POINT}" ]]; then
    if mountpoint -q "${LV_MOUNT_POINT}" 2>/dev/null; then
        log_warn "${LV_MOUNT_POINT} still appears mounted; not removing."
    else
        dry_run_exec sudo rm -rf "${LV_MOUNT_POINT}"
    fi
fi

log_step "Step 10: Final state"
if ! is_dry_run; then
    log_info "ollama on PATH: $(command -v ollama 2>/dev/null || echo '<absent>')"
    log_info "LV present: $(sudo lvs "${LV_VG_NAME}/${LV_NAME}" >/dev/null 2>&1 && echo yes || echo no)"
    log_info "Mount point exists: $([[ -d "${LV_MOUNT_POINT}" ]] && echo yes || echo no)"
fi
log_info "99-uninstall.sh complete."
