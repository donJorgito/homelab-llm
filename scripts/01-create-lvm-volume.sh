#!/usr/bin/env bash
# 01-create-lvm-volume.sh — provision the LVM logical volume that backs Ollama.
#
# Idempotent. Destructive on first run only (lvcreate + mkfs.ext4); subsequent
# runs detect existing state and skip the destructive parts.
#
# Steps:
#   1. Validate required env vars.
#   2. Detect existing LV; skip create if present.
#   3. lvcreate + mkfs.ext4 (with confirmation) when LV is missing.
#   4. Ensure mount point directory exists.
#   5. Mount the LV with noatime,nodiratime (or verify existing mount).
#   6. Persist fstab entry by UUID with noatime,nodiratime.
#   7. NOTE: chown to ollama:ollama is deferred to 02-install-ollama.sh
#      because the 'ollama' user only exists after the Ollama install script
#      has run. Do not chown here.
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

# Defaults (preserve any value coming from .env / environment).
LV_VG_NAME="${LV_VG_NAME:-vg0}"
LV_NAME="${LV_NAME:-lv-ollama}"
LV_SIZE="${LV_SIZE:-128G}"
LV_MOUNT_POINT="${LV_MOUNT_POINT:-/var/lib/ollama}"
DRY_RUN="${DRY_RUN:-no}"
SKIP_CONFIRM="${SKIP_CONFIRM:-no}"

usage() {
    cat <<EOF
Usage: $(basename "$0") [--dry-run] [--yes] [--help]

Create the LVM logical volume that hosts Ollama models, format it ext4 and
mount it at \${LV_MOUNT_POINT} with noatime,nodiratime. Persist the mount in
/etc/fstab by UUID. Idempotent — re-running is safe.

Options:
  --dry-run   Print every destructive command without executing it.
  --yes       Skip the interactive confirmation prompt (use in automation).
  -h, --help  Show this help.

Env vars used (override via .env at repo root):
  LV_VG_NAME       (default vg0)
  LV_NAME          (default lv-ollama)
  LV_SIZE          (default 128G)
  LV_MOUNT_POINT   (default /var/lib/ollama)
EOF
}

# Argument parsing.
for arg in "$@"; do
    case "${arg}" in
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
export DRY_RUN SKIP_CONFIRM
# confirm_destructive consults FORCE; reuse SKIP_CONFIRM here so --yes also
# auto-accepts the literal-yes prompt. Documented behaviour.
export FORCE="${FORCE:-${SKIP_CONFIRM}}"

LV_DEV="/dev/${LV_VG_NAME}/${LV_NAME}"

log_step "Step 1: Validate environment"
require_var LV_VG_NAME LV_NAME LV_SIZE LV_MOUNT_POINT
require_cmd sudo lvs lvcreate mkfs.ext4 mount blkid awk grep
log_info "VG=${LV_VG_NAME} LV=${LV_NAME} SIZE=${LV_SIZE} MOUNT=${LV_MOUNT_POINT}"
if is_dry_run; then
    log_warn "DRY_RUN=yes — no destructive command will execute."
fi

log_step "Step 2: Detect existing LV"
LV_EXISTS="no"
if sudo lvs "${LV_VG_NAME}/${LV_NAME}" >/dev/null 2>&1; then
    LV_EXISTS="yes"
    log_info "LV ${LV_VG_NAME}/${LV_NAME} already exists; create step will be skipped."
else
    log_info "LV ${LV_VG_NAME}/${LV_NAME} not present yet."
fi

log_step "Step 3: Create LV + ext4 filesystem (if missing)"
if [[ "${LV_EXISTS}" == "yes" ]]; then
    log_info "Skipping lvcreate + mkfs.ext4 — LV already exists."
else
    if ! confirm_destructive "Will create LV '${LV_NAME}' size '${LV_SIZE}' in VG '${LV_VG_NAME}' and mkfs.ext4 on ${LV_DEV}"; then
        log_error "User declined creation; aborting before any destructive op."
        exit 1
    fi
    dry_run_exec sudo lvcreate -L "${LV_SIZE}" -n "${LV_NAME}" "${LV_VG_NAME}"
    dry_run_exec sudo mkfs.ext4 -L ollama "${LV_DEV}"
fi

log_step "Step 4: Ensure mount point exists"
if [[ -d "${LV_MOUNT_POINT}" ]]; then
    log_info "Mount point ${LV_MOUNT_POINT} already exists."
else
    dry_run_exec sudo mkdir -p "${LV_MOUNT_POINT}"
fi

log_step "Step 5: Mount the LV"
# Resolve current mount target of the LV device, if any.
CURRENT_MOUNT=""
if [[ -e "${LV_DEV}" ]] || is_dry_run; then
    # findmnt prints empty if not mounted; tolerate dry-run when device may not exist.
    CURRENT_MOUNT="$(findmnt -nro TARGET --source "${LV_DEV}" 2>/dev/null || true)"
fi

if [[ -n "${CURRENT_MOUNT}" ]]; then
    if [[ "${CURRENT_MOUNT}" == "${LV_MOUNT_POINT}" ]]; then
        log_info "${LV_DEV} already mounted at ${LV_MOUNT_POINT}; skipping mount."
    else
        log_error "${LV_DEV} is mounted at ${CURRENT_MOUNT}, not ${LV_MOUNT_POINT}."
        log_error "Refusing to remount; resolve manually."
        exit 1
    fi
else
    dry_run_exec sudo mount -o noatime,nodiratime "${LV_DEV}" "${LV_MOUNT_POINT}"
fi

log_step "Step 6: Persist mount in /etc/fstab (by UUID)"
FSTAB="/etc/fstab"
LV_UUID=""
if [[ -e "${LV_DEV}" ]]; then
    LV_UUID="$(sudo blkid -s UUID -o value "${LV_DEV}" 2>/dev/null || true)"
fi

if is_dry_run && [[ -z "${LV_UUID}" ]]; then
    LV_UUID="<UUID-resolved-after-mkfs>"
    log_warn "[DRY] UUID not resolvable yet; placeholder used in preview."
fi

if [[ -z "${LV_UUID}" ]]; then
    log_error "Could not read UUID from ${LV_DEV}; aborting fstab update."
    exit 1
fi

# Existing entry detection: match either the LV device or its UUID.
FSTAB_HAS_ENTRY="no"
if sudo grep -Eq "(^[[:space:]]*UUID=${LV_UUID}\\b|^[[:space:]]*${LV_DEV}\\b)" "${FSTAB}" 2>/dev/null; then
    FSTAB_HAS_ENTRY="yes"
fi

if [[ "${FSTAB_HAS_ENTRY}" == "yes" ]]; then
    log_info "fstab already has an entry for this LV; skipping append."
else
    FSTAB_LINE="UUID=${LV_UUID} ${LV_MOUNT_POINT} ext4 noatime,nodiratime 0 2"
    log_info "Adding fstab line: ${FSTAB_LINE}"
    if is_dry_run; then
        printf '%s[DRY]%s sudo tee -a %s <<< "%s"\n' "${__C_YELLOW}" "${__C_RESET}" "${FSTAB}" "${FSTAB_LINE}"
    else
        printf '%s\n' "${FSTAB_LINE}" | sudo tee -a "${FSTAB}" >/dev/null
    fi
fi

log_step "Step 7: chown is deferred"
log_info "chown ${LV_MOUNT_POINT} -> ollama:ollama happens in 02-install-ollama.sh"
log_info "(the 'ollama' user is created by the upstream install script)."

log_step "Final status"
if ! is_dry_run; then
    sudo lvs "${LV_VG_NAME}/${LV_NAME}" || true
    df -h "${LV_MOUNT_POINT}" || true
fi
log_info "01-create-lvm-volume.sh complete."
