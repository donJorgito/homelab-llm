# homelab-llm

## Self-hosted LLM agentic stack — Ollama on home GPU + aider as CLI client (homelab automation, public personal repo)

![ci](https://github.com/donJorgito/homelab-llm/actions/workflows/ci.yml/badge.svg)

Quick links: [Architecture](docs/architecture.md) · [Compliance checklist](docs/compliance-checklist.md) · [Roadmap](docs/roadmap.md) · [Case study (hidra)](docs/case-study-hidra.md) · [Benchmarks](docs/benchmarks.md) · [Decisions](docs/decisions/)

## Quick start

```bash
git clone https://github.com/donJorgito/homelab-llm.git
cd homelab-llm
cp .env.example .env && $EDITOR .env       # adjust OLLAMA_HOST, LV_NAME, LV_SIZE, model tags
# Server side (run in order, on the inference host):
./scripts/00-prerequisites.sh
./scripts/01-create-lvm-volume.sh --dry-run     # review BEFORE without --dry-run
./scripts/02-install-ollama.sh
./scripts/03-pull-models.sh
# Client side (Mac or Linux workstation):
./scripts/04-install-aider-mac.sh   # or 05-install-aider-linux.sh
```

> **WARNING:** `scripts/01-create-lvm-volume.sh` creates LVM volumes and modifies `/etc/fstab`. Run with `--dry-run` first. NOT idempotent without the LV pre-existing — the bootstrap path assumes a clean target. See `tests/test_RQ006_lvm_bootstrap_idempotent.sh` for the idempotency contract once the LV exists.

## Introduction

`homelab-llm` provisions a personal, self-hosted LLM agentic stack: an Ollama inference server on commodity NVIDIA hardware, served on the LAN, plus a CLI agent (aider) on the workstation that drives code edits against a real repository. The repo materializes the bootstrap, configuration, models pulled, validation tests, and architectural decisions into a reproducible scaffold so the setup can be rebuilt on another machine with any NVIDIA GPU of comparable VRAM.

The implementation orchestrates four operational tasks via shell scripts:

1. **Server bootstrap** (`scripts/00-03-*.sh`) — verify prerequisites, carve a dedicated LVM volume for model storage, install Ollama via its official installer, pin the systemd override (`OLLAMA_HOST`, `OLLAMA_MODELS`, `OLLAMA_CONTEXT_LENGTH`, `OLLAMA_KEEP_ALIVE`), pull the configured model set.
2. **Client install** (`scripts/04-05-*.sh`) — install aider on macOS (Homebrew) or Linux (pipx), configure `OLLAMA_API_BASE`, smoke-test the connection.
3. **Uninstall** (`scripts/99-uninstall.sh`) — full rollback: stop the service, unmount the LV, remove the fstab entry, purge `/var/lib/ollama`, with `--dry-run` and confirmation prompts.
4. **Benchmarks** (`scripts/bench/*.sh`) — measure tokens/second and tool-call behavior per model, output to a Markdown table for `docs/benchmarks.md`.

This repo follows the project's engineering practices: scripts are idempotent (where reasonable, see `RQ006`), versioned, and pass secret-scanning + linting gates on every push. It is a personal homelab project — no formal change-management workflow, no junit-format Test Reports — see [`docs/compliance-checklist.md`](docs/compliance-checklist.md) for the full set of engineering rules and where this repo applies them or deliberately scopes them down.

## Framework or Coding Technology

The implementation is shell-first: bash for orchestration scripts and tests, with Python as auxiliary tooling for benchmarks parsing. CI runs on GitHub Actions.

-----BEGIN TECH-----\
TECH-Main: bash\
TECH-Testing: bash\
TECH-Auxiliary: python\
TECH-CICD: github-actions\
-----END TECH-----

## Prerequisites

| **Prerequisite** | **Description** |
|:---:|:---:|
| NVIDIA GPU with ≥ 4 GB VRAM | Maxwell (cc 5.2) or newer. Verified on GTX 970; cc < 7.5 falls back to the legacy `cuda_v12` Ollama binary. |
| Ubuntu 24.04 LTS or newer | Kernel ≥ 6.8. Other distros likely work but are not validated by this repo. |
| NVIDIA proprietary driver ≥ 535 | `nvidia-smi` must report a healthy device before running `02-install-ollama.sh`. |
| `sudo` access on the inference host | Scripts use `sudo -n` where possible; document the sudoers timestamp policy in [`docs/case-study-hidra.md`](docs/case-study-hidra.md). |
| LVM volume group with ≥ 64 GB free | Models are stored on a dedicated LV (`vg0/lv-ollama` by default, size in `.env`). |
| LAN connectivity between server and clients | TCP/11434 reachable from the workstation. Adjust `OLLAMA_HOST` if exposing on different interfaces. |
| Workstation: macOS 13+ or Ubuntu 22.04+ | For the aider client. Homebrew on macOS, pipx on Linux. |
| `git`, `curl`, `jq` | Available on both server and workstation. |

## Execution methods

The repo is consumed as a set of ordered shell scripts, executed manually by the operator. There is no orchestration pipeline that targets the homelab — the inference host is not a CI-accessible runner. CI in this repo validates **the repo itself** (lint, secret-scan, scripts syntax), not the deployed infra.

| Method | Scripts | When |
|---|---|---|
| Server bootstrap | `scripts/00-prerequisites.sh` → `scripts/01-create-lvm-volume.sh` → `scripts/02-install-ollama.sh` → `scripts/03-pull-models.sh` | First-time install on a clean Ubuntu host. |
| Client install (macOS) | `scripts/04-install-aider-mac.sh` | On the workstation, after the server is reachable. |
| Client install (Linux) | `scripts/05-install-aider-linux.sh` | On a Linux workstation. |
| Uninstall / rollback | `scripts/99-uninstall.sh --dry-run` then `scripts/99-uninstall.sh --force` | When decommissioning the host or starting over. |
| Benchmarks | `scripts/bench/bench-perf.sh` and `scripts/bench/bench-toolcall.sh` | After a model pull, to update [`docs/benchmarks.md`](docs/benchmarks.md). |
| Tests | `./tests/test_RQ00N_*.sh` (1:1 with `requirements/`) | Locally, against the inference host. CI runs only syntax + shellcheck. |

## Variables

All operator-tunable values live in `.env` (gitignored). The committed `.env.example` documents every variable with a sensible default. Key variables:

| Variable | Purpose | Example default |
|---|---|---|
| `OLLAMA_HOST` | Address Ollama listens on. `0.0.0.0:11434` to expose on the LAN. | `0.0.0.0:11434` |
| `OLLAMA_MODELS` | Filesystem path where Ollama stores models. Should point inside the dedicated LV mount. | `/var/lib/ollama/models` |
| `OLLAMA_CONTEXT_LENGTH` | Default context window in tokens. Tuned per VRAM budget. | `16384` |
| `OLLAMA_KEEP_ALIVE` | How long Ollama keeps a model resident in VRAM after last request. | `30m` |
| `LV_NAME` | LVM logical volume name for model storage. | `vg0/lv-ollama` |
| `LV_SIZE` | Size of the LV created by `01-create-lvm-volume.sh`. | `128G` |
| `LV_MOUNTPOINT` | Where the LV is mounted; `OLLAMA_MODELS` should sit underneath. | `/var/lib/ollama` |
| `MODEL_TAGS` | Comma-separated list of Ollama model tags to pull. | `qwen2.5-coder:7b,qwen2.5-coder:3b` |
| `AIDER_MODEL` | Model the aider client uses by default. | `ollama_chat/qwen2.5-coder:7b` |
| `AIDER_EDIT_FORMAT` | Edit strategy. `whole` is validated end-to-end with Qwen2.5-Coder; `diff` works for some prompts. | `whole` |
| `OLLAMA_API_BASE` | URL the aider client points at. | `http://192.0.2.143:11434` |

See [`.env.example`](.env.example) for the complete, commented set.

## External components

The "components" here are external software pulled at install time by the bootstrap scripts. Versions are intentionally **not pinned in this repo** — Ollama and aider are tracked at upstream-stable; the repo records the exact versions verified end-to-end in [`docs/case-study-hidra.md`](docs/case-study-hidra.md) and bumps them via the changelog. This is a deliberate exception to the project's strict-pinning practice, justified in [`docs/compliance-checklist.md`](docs/compliance-checklist.md).

| **Component** | **Version (verified)** | **Source** |
|:---:|:---:|:---:|
| Ollama | 0.30.6 (rolling, see CHANGELOG) | Official installer: `curl -fsSL https://ollama.com/install.sh \| sh` |
| aider | 0.86.2 (rolling, see CHANGELOG) | Homebrew (macOS) or pipx (Linux) |
| Qwen2.5-Coder 7B Q4_K_M | tag `qwen2.5-coder:7b` | Pulled via `ollama pull` from registry |
| Qwen2.5-Coder 3B Q4_K_M | tag `qwen2.5-coder:3b` | Pulled via `ollama pull` from registry |

GitHub Actions and pre-commit hooks **are** pinned to commit SHAs in `.github/workflows/ci.yml` and `.pre-commit-config.yaml` per the project's strict-pinning rule, since those affect repo correctness directly. Renovate / Dependabot management of the pinned references is on the roadmap (see v0.2 in [`docs/roadmap.md`](docs/roadmap.md)).

## Environments

Personal homelab — a single inference server on a residential LAN, plus one or more workstations as clients. **Not a production environment.** No staging, no DR, no formal SLAs. See [ADR-0001](docs/decisions/0001-ollama-as-inference-engine.md) for the rationale and [`docs/compliance-checklist.md`](docs/compliance-checklist.md) for which engineering rules apply and which are scoped down.

## Tests

Tests live in [`/tests`](tests/) as POSIX shell scripts (`.sh`), with a strict 1:1 mapping to requirement files in [`/requirements`](requirements/) — the filename embeds the `RQ-ID`, so the traceability matrix is visible directly from the filesystem.

- Unit tests: small, focused checks — `set -euo pipefail`, exit 0 on pass, descriptive output on fail.
- Integration tests: cover the full server + client flow against the real inference host (e.g., `RQ002` runs aider end-to-end and asserts a generated file imports cleanly).
- **No junit reporter.** Tests are shell, run by the operator post-deploy, and produce human-readable output rather than a structured report. CI in this repo validates *script syntax and lint* only; functional tests run locally against the homelab because the inference host is not a CI-accessible runner. See [`docs/compliance-checklist.md`](docs/compliance-checklist.md) for the rationale.

## Deviations and Open Defects

The following deliberate exceptions to the project's engineering practices are tracked explicitly:

| Area | Deviation | Justification | Resolution |
|---|---|---|---|
| Test Report (junit + 80% coverage) | Tests are shell, no junit output, no coverage metric. | Personal homelab repo; coverage of shell scripts via shell tests is meaningful but not measurable in the canonical sense. | Documented in [`docs/compliance-checklist.md`](docs/compliance-checklist.md). |
| Branch protection on `main` | Not enabled at v0.1.0 first push. | Single-maintainer repo; protection is set up post-creation. | Deferred to **v0.1.1** — see [`docs/roadmap.md`](docs/roadmap.md). |
| Automated dependency management + automated releases | Only `dependabot.yml` for GitHub Actions at v0.1.0; no Renovate, no semantic-release. | Minimal-viable automation surface at first commit. | Renovate + semantic-release scheduled for **v0.2** — see [`docs/roadmap.md`](docs/roadmap.md). |
| Strict pinning for runtime components | Ollama and aider not pinned; pulled at install time. | Upstream installers and Homebrew formulae move; pinning would freeze the homelab at a stale version with manual bump overhead. | Versions recorded in CHANGELOG per release; see [ADR-0001](docs/decisions/0001-ollama-as-inference-engine.md). |

No open defects at v0.1.0.

## Author Information

Jorge Lazaro Molina (GitHub: `@donJorgito`). Personal project, not affiliated with any employer. Contact via GitHub issues; security reports per [`SECURITY.md`](SECURITY.md).
