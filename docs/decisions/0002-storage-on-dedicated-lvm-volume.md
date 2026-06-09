# ADR-0002: Dedicate an LVM volume to Ollama models

- Status: Accepted
- Date: 2026-06-08
- Deciders: donJorgito (Owner)

## Context

By default, Ollama stores models under `/usr/share/ollama/.ollama/`, which lives on the root logical volume. On `hidra`, the root LV sits around 52% of 125 GB. Each coding model weighs 2-7 GB, and a realistic test matrix (multiple sizes and quants) easily reaches 15-30 GB. Filling `/` with model weights is operationally fragile.

The `vg0` volume group has roughly 6.03 TiB unallocated, so there is no storage pressure — just a need for separation of concerns.

## Decision

Create a dedicated logical volume `vg0/lv-ollama`, formatted as `ext4`, sized at **128 GB**, mounted at `/var/lib/ollama` with `noatime,nodiratime`, and persisted in `/etc/fstab` by **UUID** (never by device path). Configure Ollama via `systemd` override to use `OLLAMA_MODELS=/var/lib/ollama/models`.

- 128 GB is a deliberate fixed size: ample for the current model matrix, trivially extensible via `lvextend` + `resize2fs` when needed.
- Mount by UUID survives device reordering across reboots.

## Consequences

### Positive

- Models cannot fill the root filesystem.
- Hard upper bound (128 GB) on model storage; no surprise growth.
- Easy expansion (`lvextend -L +N -r`).
- Clean teardown via `lvremove`; no scattered files across `/`.
- `fstab` ensures the mount survives reboots without manual intervention.

### Negative

- One extra step in bootstrap versus a plain `apt install ollama`.
- Requires `sudo` for `lvcreate`/`mkfs.ext4`/`mount`.
- Idempotency of the bootstrap script is critical (covered by `RQ006`); a buggy script could create duplicate LVs or stale `fstab` entries.
- Changing the filesystem (e.g. ext4 → xfs) after the LV is in use is non-trivial — requires data migration.

## Alternatives considered

- **Default `/usr/share/ollama`** — Simplest, but pollutes the root filesystem and risks `/` filling under heavy use.
- **LVM thin provisioning** — More flexible but unnecessary complexity for a fixed 128 GB allocation.
- **Bind mount from `/home/jorge/ollama-data`** — Violates separation of concerns, depends on home-directory permissions, and couples model storage to the user account.
- **ZFS dataset** — Technically superior (snapshots, compression, checksums), but `hidra` does not run ZFS today and adding a second filesystem stack is not justified for this use case.

## References

- [scripts/01-create-lvm-volume.sh](../../scripts/01-create-lvm-volume.sh)
- [requirements/homelab-llm-RQ006-idempotent-lvm-bootstrap.md](../../requirements/homelab-llm-RQ006-idempotent-lvm-bootstrap.md)
- [docs/case-study-hidra.md](../case-study-hidra.md)
- [ADR-0001](0001-ollama-as-inference-engine.md)
