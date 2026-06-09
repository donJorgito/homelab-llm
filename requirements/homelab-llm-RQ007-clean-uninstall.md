### homelab-llm.RQ007 - Clean Uninstall Leaves No Artifacts

**Description:**

Running `scripts/99-uninstall.sh --force --yes` MUST leave no system artifacts on the host. The uninstall script is the documented rollback path for partial installs, abandoned experiments, and host decommissioning; if it leaves behind a stale systemd unit, an unmounted LV referenced in `fstab`, or a dangling mount point, the next bootstrap run will fail in surprising ways. This requirement is destructive by nature — it tears down the inference layer and the storage layer — and is gated behind explicit operator confirmation.

**Parent Requirement:** N/A (personal homelab repository).

**Acceptance Criteria:**

- After running `scripts/99-uninstall.sh --force --yes`, `systemctl is-active ollama` reports `inactive` (or the unit no longer exists).
- `mount | grep " ${LV_MOUNT_POINT} "` produces no output (the LV is unmounted).
- `/etc/fstab` does not contain any entry referencing `${LV_MOUNT_POINT}` or `${LV_VG_NAME}/${LV_NAME}`.
- `${LV_MOUNT_POINT}` either no longer exists on the filesystem or exists and is empty (no leftover model files).
- `sudo lvs --noheadings ${LV_VG_NAME}/${LV_NAME}` exits non-zero or returns empty output (the LV has been removed).
- The test refuses to run unless the operator opts in via `ALLOW_DESTRUCTIVE=yes` because it is irrecoverable on a real host.
