### homelab-llm.RQ003 - Reproducible Setup Across Fresh Hosts

**Description:**

The setup scripts under `scripts/` MUST be reproducible across fresh Ubuntu 24.04 LTS installs equipped with an NVIDIA GPU and a working CUDA driver. Reproducibility means: an operator who clones the repository, copies `.env.example` to `.env`, and runs the numbered scripts `00-` through `03-` in order obtains a working Ollama service serving the configured models on the LAN, with no manual editing of scripts. Re-running any script on an already-bootstrapped machine MUST be a safe no-op.

**Parent Requirement:** N/A (personal homelab repository).

**Acceptance Criteria:**

- Each of `scripts/00-prerequisites.sh`, `scripts/01-create-lvm-volume.sh`, `scripts/02-install-ollama.sh`, `scripts/03-pull-models.sh` is executable shell with `set -euo pipefail` at the top.
- Each of those scripts supports a `--dry-run` flag (string match) that prints intended actions without applying them.
- Each script passes `bash -n` (syntax check) without errors.
- Running the scripts a second time on an already-bootstrapped host completes with exit code `0` and does not duplicate state (no second LV with the same name, no duplicate `/etc/fstab` entry, no error from `ollama pull` of an already-present model).
- The list of scripts and their order is documented in `README.md`.
