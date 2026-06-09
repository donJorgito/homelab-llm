### homelab-llm.RQ006 - Idempotent LVM Bootstrap

**Description:**

Running `scripts/01-create-lvm-volume.sh` more than once on the same host MUST NOT fail and MUST NOT create duplicate state. The script is the storage bootstrap for Ollama models and touches three system-level resources that are notoriously easy to corrupt with naive scripting: a logical volume in `${LV_VG_NAME}`, an `ext4` filesystem on top, and a `/etc/fstab` entry mounted at `${LV_MOUNT_POINT}`. Idempotency is the safety contract that lets operators re-run the script after partial failures or while debugging.

**Parent Requirement:** N/A (personal homelab repository).

**Acceptance Criteria:**

- A second invocation of `scripts/01-create-lvm-volume.sh` on a host where the LV already exists exits with status `0`.
- After the second invocation, `sudo lvs --noheadings ${LV_VG_NAME}/${LV_NAME}` reports exactly one logical volume with the configured name (no duplicates, no `_1` suffixes).
- `/etc/fstab` contains exactly one entry referencing `${LV_MOUNT_POINT}` (verified with `grep -c " ${LV_MOUNT_POINT} " /etc/fstab` returning `1`).
- `mountpoint -q ${LV_MOUNT_POINT}` returns `0` (the volume remains mounted after the re-run).
- The script does not destroy any data already present in `${LV_MOUNT_POINT}` on the second run.
