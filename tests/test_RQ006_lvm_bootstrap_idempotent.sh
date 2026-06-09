#!/usr/bin/env bash
# Test for homelab-llm.RQ006 - Idempotent LVM Bootstrap.
#
# DESTRUCTIVE-ADJACENT: this test re-runs scripts/01-create-lvm-volume.sh
# on a host that already has the LV bootstrapped. It refuses to run if the
# LV is missing, because creating an LV from scratch is destructive and
# out of scope for an idempotency test.
#
# Required precondition: scripts/01-create-lvm-volume.sh has already been
# run successfully at least once (i.e., ${LV_VG_NAME}/${LV_NAME} exists).
#
# After invocation, validates:
#   - Second run exits 0.
#   - Exactly one LV with the configured name exists.
#   - Exactly one /etc/fstab entry for ${LV_MOUNT_POINT}.
#   - ${LV_MOUNT_POINT} is mounted.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/assert.sh
source "${SCRIPT_DIR}/lib/assert.sh"

load_env

LV_VG_NAME="${LV_VG_NAME:-vg0}"
LV_NAME="${LV_NAME:-lv-ollama}"
LV_MOUNT_POINT="${LV_MOUNT_POINT:-/var/lib/ollama}"

REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
BOOTSTRAP_SCRIPT="${REPO_ROOT}/scripts/01-create-lvm-volume.sh"

if [ ! -x "${BOOTSTRAP_SCRIPT}" ] && [ ! -f "${BOOTSTRAP_SCRIPT}" ]; then
  fail "Bootstrap script not found at ${BOOTSTRAP_SCRIPT}"
fi

# Linux-only: LVM does not exist on macOS.
if [ "$(uname -s)" != "Linux" ]; then
  fail "RQ006 test must run on Linux (uname=$(uname -s))"
fi

command -v sudo >/dev/null 2>&1 || fail "sudo is required for LVM checks"
command -v lvs >/dev/null 2>&1 || fail "lvs is required (install lvm2)"
command -v mountpoint >/dev/null 2>&1 || fail "mountpoint is required (util-linux)"

# Precondition: LV must already exist. Otherwise refuse — bootstrapping
# from scratch is destructive and not what this test validates.
if ! sudo -n lvs --noheadings "${LV_VG_NAME}/${LV_NAME}" >/dev/null 2>&1; then
  fail "RQ006 requires bootstrap already run; create LV ${LV_VG_NAME}/${LV_NAME} first or run in sandbox"
fi
pass "Precondition: LV ${LV_VG_NAME}/${LV_NAME} exists"

# Re-run the bootstrap script. It must be idempotent: exit 0, no duplicates.
info "Re-running ${BOOTSTRAP_SCRIPT} (idempotency check)"
if ! sudo -n bash "${BOOTSTRAP_SCRIPT}"; then
  fail "Second invocation of 01-create-lvm-volume.sh did not exit 0"
fi
pass "Second invocation exited 0"

# Exactly one LV with the configured name.
LV_COUNT="$(sudo -n lvs --noheadings -o lv_name "${LV_VG_NAME}" 2>/dev/null \
  | awk -v n="${LV_NAME}" '$1 == n { c++ } END { print c+0 }')"
if [ "${LV_COUNT}" != "1" ]; then
  fail "Expected exactly 1 LV named '${LV_NAME}' in VG '${LV_VG_NAME}', got ${LV_COUNT}"
fi
pass "Exactly 1 LV named '${LV_NAME}' in VG '${LV_VG_NAME}'"

# Exactly one /etc/fstab entry referencing the mount point.
FSTAB_COUNT="$(awk -v mp="${LV_MOUNT_POINT}" '
  /^[[:space:]]*#/ { next }
  NF >= 2 && $2 == mp { c++ }
  END { print c+0 }
' /etc/fstab)"

if [ "${FSTAB_COUNT}" != "1" ]; then
  fail "Expected exactly 1 /etc/fstab entry for ${LV_MOUNT_POINT}, got ${FSTAB_COUNT}"
fi
pass "Exactly 1 /etc/fstab entry for ${LV_MOUNT_POINT}"

# The mount point must still be mounted.
if ! mountpoint -q "${LV_MOUNT_POINT}"; then
  fail "${LV_MOUNT_POINT} is not currently mounted"
fi
pass "${LV_MOUNT_POINT} is mounted"

info "RQ006 OK"
exit 0
