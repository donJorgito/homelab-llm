# Contributing to homelab-llm

This repository follows the engineering practices documented in [`docs/compliance-checklist.md`](docs/compliance-checklist.md). Conventional Commits + Keep a Changelog + MADR ADRs + Semantic Versioning.

## Getting Started

1. Clone the repository: `git clone https://github.com/donJorgito/homelab-llm.git`
2. Install pre-commit hooks: `pre-commit install` (also installs `commit-msg` hook for Conventional Commits validation if configured).
3. Copy `.env.example` to `.env` and adjust for your environment. `.env` is gitignored — never commit it.
4. Create a feature branch following the convention `<user>-<short-description>` (e.g., `donJorgito-fix-uninstall-fstab`): `git checkout -b donJorgito-<descr>`.

## Development Standards

- Follow Conventional Commits per [conventionalcommits.org](https://www.conventionalcommits.org/) for **all** commit messages — mandatory in this repo, not a recommendation. Valid types: `feat`, `fix`, `chore`, `docs`, `ci`, `refactor`, `test`, `perf`, `build`, `revert`. Examples:
  - `feat(scripts): add bench-toolcall harness for arbitrary model tag`
  - `fix(uninstall): remove stale fstab entry when mountpoint already gone`
  - `chore(deps): bump actions/checkout to <pinned-sha>`
  - `docs(roadmap): defer Renovate to v0.2 with rationale`
  - `ci(workflow): cache pre-commit hooks across runs`
- All code must pass linting, secret scanning, and the repo test suite before opening a PR. Run `pre-commit run --all-files` locally before pushing — failing in local is free, failing in CI burns minutes and breaks flow.
- Pin all dependency versions explicitly to a commit SHA where possible — this is rule R7 in `docs/compliance-checklist.md`. `@v4` and `@latest` are not acceptable for GitHub Actions or pre-commit hooks. The runtime components Ollama and aider are an explicit, documented exception (see README "Deviations" section).
- Never commit secrets — rule R2. `gitleaks` runs as a pre-commit hook and as a CI gate. If a secret is committed by accident, treat the commit as a security incident: rotate the credential first, then rewrite history.
- No business logic in CI/CD pipelines — rule R5. The CI workflow orchestrates: it invokes scripts and reports results. Logic that decides *how* to do something belongs in `scripts/` and is exercised by `tests/`.
- No hardcoded IPs, hostnames, ports, paths, or thresholds in shell scripts — rule R4. Every operator-tunable value must be sourced from `.env` (with `${VAR:-default}` defaults documented in `.env.example`).

## Testing

- Tests live in `/tests` as POSIX shell scripts (`.sh`).
- Test filenames must include the Requirement ID — the 1:1 test traceability convention used in this repo (filename embeds the requirement ID): `test_<REQ-ID>_<short-description>.sh`. Example: `test_RQ002_aider_writes_file_and_pytest_passes.sh`.
- One test file per requirement — if you add a new functional requirement under `requirements/`, you must add the matching test file in the same PR.
- Tests start with `set -euo pipefail`, exit `0` on pass, non-zero on fail, and emit human-readable progress output to stdout/stderr.
- **No junit reporter** is produced. Tests are shell scripts run by the operator post-deploy, not by CI against the homelab. This is a deliberate exception to the structured-Test-Report and 80% coverage practice — both documented as N/A with rationale in [`docs/compliance-checklist.md`](docs/compliance-checklist.md). CI runs only `shellcheck` and `bash -n` syntax validation; functional tests run locally.
- Destructive tests (`RQ006` LVM idempotency, `RQ007` uninstall completeness) must be run against a sandbox host or a snapshot, never against a production homelab without a recovery path.

## Review Process

This is a single-maintainer personal repository. The project's approval scaling:

- **Self-review acceptable.** The Owner reviews their own PRs given the single-maintainer scope. The discipline that protects quality here is *time delay*: open the PR, sleep on it, re-read with fresh eyes the next day, then merge.
- **CI must pass before merge.** Branch protection on `main` enforcing required status checks is configured at v0.1.1 (deferred from v0.1.0 first push — see [`docs/roadmap.md`](docs/roadmap.md)). Until then, the maintainer manually verifies CI is green before clicking merge.
- **Conventional Commits validated** by `commitlint` or equivalent regex pre-commit hook on every push.
- **Major version bumps** (e.g., breaking changes to script flag conventions, `.env` schema changes that break existing setups) still warrant an explicit reflection before merge: open the PR, write a clear migration note in the description, update the CHANGELOG with `### Changed` and a migration paragraph, then merge.
- External contributors: please open an issue first to discuss scope before submitting a PR. Given the personal-homelab nature of the project, breaking changes that suit one operator may not suit others.

## Automation Bots

This repository uses the following bots, configured in `.github/`:

- **Dependabot** (`.github/dependabot.yml`): weekly check for updates to GitHub Actions used in `.github/workflows/ci.yml`. Auto-merge is **not** enabled — every PR is reviewed manually because the personal-repo scale doesn't justify the auto-merge governance overhead.
- **Renovate**: not configured at v0.1.0. Scheduled for **v0.2** to manage pre-commit hook version pins and any future runtime deps. Rationale for the deferral and the v0.2 plan are in [`docs/roadmap.md`](docs/roadmap.md).
- **Semantic Release / release-please**: not configured at v0.1.0. CHANGELOG is maintained manually per [Keep a Changelog](https://keepachangelog.com/). Automated releases are scheduled for **v0.2** alongside Renovate.

## AI-Assisted Development

AI assistants (Claude Code primarily, GitHub Copilot occasionally) are used for code generation in this repository under these conditions:

- All AI-generated code must pass the same review, testing, and security gates as human-written code. There is no relaxed standard for "AI did it".
- AI-generated code must be clearly attributed in the commit message via the `Co-Authored-By` trailer in the commit body. Example:

```text
feat(scripts): add bench-toolcall harness with model-tag parameter

Implemented per ADR-0004; uses /api/chat endpoint and asserts that
tool_calls is structured (not embedded in the content field).

Co-Authored-By: Claude <noreply@anthropic.com>
```

- AI must not be used to bypass security controls or generate secrets, plausible-sounding fake versions, or values that look reasonable but are not verified against upstream.

### Project-Specific AI Standards

These standards are mandatory for this repository and override any default AI-assistant convention to the contrary:

- **Mandatory `Co-Authored-By` trailer.** All AI-generated commits in this repo MUST include `Co-Authored-By: Claude <noreply@anthropic.com>` (or the equivalent trailer for the AI used) in the commit body. This is non-negotiable, applies to one-line `chore:` commits as much as to feature work, and is enforced by self-discipline (no automated check at v0.1.0 — adding a `commit-msg` hook to assert this is on the v0.1.1 wishlist).
- **Diff review before commit.** Before delegating implementation to Claude Code (or any AI), the contributor must confirm understanding of the proposed change by reviewing the diff in full *before commit*. "Run it and see if tests pass" is not a substitute for understanding what the AI just wrote. If the diff is too large to review meaningfully in one sitting, ask the AI to split it.
- **Same gates, no exceptions.** AI-generated code follows the project's engineering practices identically to human code. There is no "this is just a quick thing" exception. If the AI proposes a shortcut that would violate rule R4 (hardcoded values), R5 (logic in CI), R7 (unpinned versions), or any other rule, reject it and have the AI redo the work compliantly.
- **No AI-generated mandatory files without project-context review.** When asking an AI to draft governance files, point it at the existing files in this repo as the source of truth — not at general knowledge. Do not accept "I drafted this from general knowledge".
