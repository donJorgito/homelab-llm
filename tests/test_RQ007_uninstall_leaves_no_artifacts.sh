#!/usr/bin/env bash
# Test for homelab-llm.RQ007 - Clean Uninstall Leaves No Artifacts.
#
# *** HIGHLY DESTRUCTIVE ***
# This test runs scripts/99-uninstall.sh --force --yes which removes:
#   - the ollama systemd unit and binary,
#   - the LVM logical volume ${LV_VG_NAME}/${LV_NAME},
#   - the /etc/fstab entry,
#   - the contents of ${LV_MOUNT_POINT} (downloaded models).
#
# Guard: refuses to run unless ALLOW_DESTRUCTIVE=yes. Run only on a host
# explicitly designated as a sandbox (NOT on hidra in steady state).
#
# After invocation, validates:
#   - systemctl is-active ollama -> inactive (or unit absent).
#   - mount | grep " ${LV_MOUNT_POINT} " is empty.
#   - /etc/fstab has no entry referencing ${LV_MOUNT_POINT} or the LV.
#   - ${LV_MOUNT_POINT} is empty or absent.
#   - lvs ${LV_VG_NAME}/${LV_NAME} returns non-zero or empty.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/assert.sh
source "${SCRIPT_DIR}/lib/assert.sh"

load_env

if [ "${ALLOW_DESTRUCTIVE:-no}" != "yes" ]; then
  fail "Set ALLOW_DESTRUCTIVE=yes to run RQ007 (will delete LV, models, service)"
fi

LV_VG_NAME="${LV_VG_NAME:-vg0}"
LV_NAME="${LV_NAME:-lv-ollama}"
LV_MOUNT_POINT="${LV_MOUNT_POINT:-/var/lib/ollama}"

REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
UNINSTALL_SCRIPT="${REPO_ROOT}/scripts/99-uninstall.sh"

if [ ! -f "${UNINSTALL_SCRIPT}" ]; then
  fail "Uninstall script not found at ${UNINSTALL_SCRIPT}"
fi

# Linux-only.
if [ "$(uname -s)" != "Linux" ]; then
  fail "RQ007 test must run on Linux (uname=$(uname -s))"
fi

command -v sudo >/dev/null 2>&1 || fail "sudo is required"
command -v systemctl >/dev/null 2>&1 || fail "systemctl is required"

info "Running ${UNINSTALL_SCRIPT} --force --yes"
if ! sudo -n bash "${UNINSTALL_SCRIPT}" --force --yes; then
  fail "Uninstall script exited non-zero"
fi
pass "Uninstall script exited 0"

# 1. ollama service must be inactive (or absent).
ACTIVE_STATE="$(systemctl is-active ollama 2>/dev/null || true)"
case "${ACTIVE_STATE}" in
  inactive | unknown | failed | "")
    pass "systemctl is-active ollama -> '${ACTIVE_STATE:-empty}' (acceptable)"
    ;;
  *)
    fail "systemctl is-active ollama -> '${ACTIVE_STATE}' (expected inactive/unknown/absent)"
    ;;
esac

# 2. Mount point must not appear in current mounts.
if mount | grep -F " ${LV_MOUNT_POINT} " >/dev/null 2>&1; then
  fail "${LV_MOUNT_POINT} is still mounted"
fi
pass "${LV_MOUNT_POINT} is not mounted"

# 3. /etc/fstab must not reference the mount point or the LV.
if grep -E "[[:space:]]${LV_MOUNT_POINT}[[:space:]]|/${LV_VG_NAME}/${LV_NAME}|${LV_VG_NAME}-${LV_NAME}" /etc/fstab >/dev/null 2>&1; then
  fail "/etc/fstab still references ${LV_MOUNT_POINT} or ${LV_VG_NAME}/${LV_NAME}"
fi
pass "/etc/fstab has no reference to ${LV_MOUNT_POINT} or the LV"

# 4. Mount point either does not exist or is empty.
if [ -e "${LV_MOUNT_POINT}" ]; then
  if [ -d "${LV_MOUNT_POINT}" ]; then
    if [ -n "$(ls -A "${LV_MOUNT_POINT}" 2>/dev/null)" ]; then
      fail "${LV_MOUNT_POINT} still exists and is not empty"
    fi
    pass "${LV_MOUNT_POINT} exists and is empty"
  else
    fail "${LV_MOUNT_POINT} exists but is not a directory"
  fi
else
  pass "${LV_MOUNT_POINT} does not exist"
fi

# 5. LV must be gone.
if sudo -n lvs --noheadings "${LV_VG_NAME}/${LV_NAME}" >/dev/null 2>&1; then
  REMAINING="$(sudo -n lvs --noheadings "${LV_VG_NAME}/${LV_NAME}" 2>/dev/null | tr -d ' \n')"
  if [ -n "${REMAINING}" ]; then
    fail "LV ${LV_VG_NAME}/${LV_NAME} still exists after uninstall"
  fi
fi
pass "LV ${LV_VG_NAME}/${LV_NAME} no longer exists"

info "RQ007 OK"
exit 0
