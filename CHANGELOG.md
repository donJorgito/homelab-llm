# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

See [`docs/roadmap.md`](docs/roadmap.md) for planned work (v0.1.1 compliance hardening, v0.2 RPi gateway, v0.3+ Ethernet / WoL / multi-client).

## [0.1.0] - 2026-06-08

### Added

- Initial scaffolding for the project's engineering practices: mandatory files in the first commit (`README.md`, `CHANGELOG.md`, `CONTRIBUTING.md`, `CLAUDE.md`, `LICENSE`, `SECURITY.md`, `CODEOWNERS`, `.gitignore`, `.pre-commit-config.yaml`, `.markdownlint.yaml`, `.yamllint.yaml`, `.github/workflows/ci.yml`, `.github/dependabot.yml`).
- Reproducible Ollama installation scripts: `scripts/00-prerequisites.sh`, `scripts/01-create-lvm-volume.sh`, `scripts/02-install-ollama.sh`, `scripts/03-pull-models.sh`, `scripts/99-uninstall.sh`. All scripts use `set -euo pipefail`; destructive operations support `--dry-run` and require interactive confirmation or `--force`.
- LVM-backed model storage with configurable volume name and size via `.env` (`LV_NAME`, `LV_SIZE`, `LV_MOUNTPOINT`). Default: `vg0/lv-ollama`, 128 GB, mounted at `/var/lib/ollama`.
- aider client install scripts for macOS (`scripts/04-install-aider-mac.sh`, Homebrew) and Linux (`scripts/05-install-aider-linux.sh`, pipx). Pre-configured for the Ollama-OpenAI-compatible endpoint with `AIDER_EDIT_FORMAT=whole`.
- 7 functional requirements with 1:1 test traceability (filename embeds the requirement ID, 1:1 with `requirements/`):
  - `RQ001` self-hosted inference endpoint responds.
  - `RQ002` aider CLI agent edits files end-to-end and resulting code passes `pytest`.
  - `RQ003` reproducible setup from a clean host.
  - `RQ004` no secrets committed (gitleaks gate).
  - `RQ005` multi-model switchable via `MODEL_TAGS` / `AIDER_MODEL`.
  - `RQ006` LVM bootstrap is idempotent once the LV exists.
  - `RQ007` `99-uninstall.sh` leaves no service, mount, fstab entry, or model artifacts.
- 5 critical Architecture Decision Records under `docs/decisions/` covering: choice of Ollama as the inference engine, dedicated LVM volume for model storage, aider as the CLI client (and OpenCode rejection due to non-structured `tool_calls`), Qwen2.5-Coder 7B as the default model, and Wake-on-LAN deferred due to the WiFi-USB current networking constraint.
- Documentation under `docs/`: architecture overview with a Mermaid diagram, hidra case study (anonymized to RFC 5737 documentation IPs), benchmarks for the four candidate models with tokens/second and tool-call verdicts, shakedown narrative for the 5-task end-to-end validation, compliance checklist covering 10 engineering rules with verdicts and evidence, roadmap to v1.0.
- Continuous Integration via GitHub Actions (`.github/workflows/ci.yml`): three parallel jobs — `secret-scan` (gitleaks), `lint` (`pre-commit run --all-files` covering markdownlint, yamllint, actionlint, shellcheck, shfmt, lychee, dotenv-linter, gitleaks), and `scripts-validate` (shellcheck and `bash -n` syntax check on `scripts/**/*.sh` and `tests/*.sh`). All third-party Actions and pre-commit hooks pinned to commit SHA per rule R7.
- Dependabot configuration (`.github/dependabot.yml`) for weekly auto-update of GitHub Actions, satisfying the minimal-viable automation surface for v0.1.0 (rule R10).
- Conventional Commits enforced as the commit-message convention; `Co-Authored-By: Claude <noreply@anthropic.com>` mandatory on AI-assisted commits per rule R10 (AI attribution).

[Unreleased]: https://github.com/donJorgito/homelab-llm/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/donJorgito/homelab-llm/releases/tag/v0.1.0
