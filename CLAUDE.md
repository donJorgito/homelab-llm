# CLAUDE.md

This repository follows the engineering practices documented in [`docs/compliance-checklist.md`](docs/compliance-checklist.md).

## Development Standards

Refer to [CONTRIBUTING.md](CONTRIBUTING.md) as the source of truth. Key rules:

- Follow [Conventional Commits](https://www.conventionalcommits.org/) for all commit messages.
- Pin all dependency versions. Never use `latest` or point to `main` (runtime components Ollama and aider are an explicit, documented exception — see README "Deviations").
- Never commit secrets. Use `.env` (gitignored) and the `gitleaks` pre-commit hook.
- No business logic in CI/CD pipelines — orchestration only.
- Test filenames must include the Requirement ID: `test_<REQ-ID>_<description>.sh`. **One test file per requirement.**
- Tests are POSIX shell, no junit reporter — deliberate exception to the structured-Test-Report and 80% coverage practice, documented in [`docs/compliance-checklist.md`](docs/compliance-checklist.md).

## Approval Rules

This is a single-maintainer personal repository. The project's approval scaling:

- Self-review is acceptable for Patch/Minor; the discipline that replaces peer review is *time delay* (sleep on the PR, re-read with fresh eyes).
- CI must pass before merge. Branch protection on `main` is enabled from v0.1.1 onwards (deferred at v0.1.0 first push — see roadmap).
- Major / breaking changes warrant an explicit migration note in the PR description and the CHANGELOG before merge.
- Dependency bot updates (Dependabot for GitHub Actions): reviewed manually, no auto-merge, because the personal-repo scale doesn't justify the auto-merge governance overhead.

## AI Attribution

AI-generated code must be attributed in the commit message using the `Co-Authored-By` trailer.

## Project-Specific Context

When working on this repo, load the following context first:

- **Architecture diagram and component overview:** [`docs/architecture.md`](docs/architecture.md). The Mermaid diagram is the canonical view of how the homelab pieces fit together (server, clients, models, future RPi gateway).
- **Architectural decisions:** [`docs/decisions/`](docs/decisions/) — five [MADR](https://adr.github.io/madr/)-format ADRs covering the choice of Ollama as inference engine, dedicated LVM storage, aider as CLI client (and OpenCode rejection), Qwen2.5-Coder 7B as default model, and Wake-on-LAN deferral. Read the relevant ADR before changing the design it documents.
- **Engineering practices:** [`docs/compliance-checklist.md`](docs/compliance-checklist.md) — explicit table of the 10 engineering rules with verdicts, evidence, and N/A justifications. If you propose a change that touches a rule, update this checklist in the same PR.
- **Roadmap and version planning:** [`docs/roadmap.md`](docs/roadmap.md) — what's deferred to which version (v0.1.1 compliance hardening, v0.2 RPi gateway, etc.). When in doubt about scope, the roadmap dictates whether work belongs in this PR or the next milestone.
- **Author's private project memory:** `~/.claude/memory/project_yo_claudio.md` (local only, not in this repo). Contains hardware-specific notes, sudo workflow, real IPs, and unverified hypotheses the author keeps as personal notes. **The repo is the public source of truth; the memory is private notes.** When the two disagree, the repo is canonical — the memory may be stale or speculative.

When generating code, documentation, or commit messages: use the existing files in this repo as the source of truth. Do not improvise governance content from general knowledge.
