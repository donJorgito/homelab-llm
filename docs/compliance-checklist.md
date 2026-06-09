# Compliance checklist

10 engineering rules this repository holds itself to. Rules are evaluated against the current tree on every minor release. The rules themselves are house standards informed by widely-adopted industry practices (Conventional Commits, Keep a Changelog, MADR, SemVer, OWASP secret-scanning); the audit *protocol* — every rule, every release — is a habit borrowed from regulated-software work and adapted for personal scope.

## Repo classification

This repository is a **homelab automation collection**: idempotent bootstrap scripts for personal infrastructure. It is not a reusable library, and it is not a regulated production system. The rules below are scaled to that scope: they apply where they make sense and are explicitly waived where they don't.

## The 10 rules

| Rule | Verdict | Evidence | Action if ✗ or ⚠ |
|---|---|---|---|
| **R1: No external code committed** | ✓ | Ollama and aider download at runtime on the target machine; the repo never bundles third-party code. `git ls-files` contains only first-party scripts, docs, and config. | — |
| **R2: No plaintext secrets** | ✓ | `gitleaks` is wired into `.pre-commit-config.yaml` (pinned by SHA) and runs as the `secret-scan` job in `.github/workflows/ci.yml`. | — |
| **R3: Separate credentials per environment** | N/A | Personal repo, no production environment with separate credentials. | Justified N/A; revisit if scope ever changes. |
| **R4: No hardcoded values** | ✓ | IPs, hostnames, ports, paths, and sizes live in `.env.example` and are consumed via `${VAR:-default}` patterns inside `scripts/`. Documentation uses RFC 5737 ranges (`192.0.2.0/24`). | — |
| **R5: No business logic in CI** | ✓ | The CI workflow only orchestrates: it runs `pre-commit`, `gitleaks`, and validates scripts via `shellcheck` + `bash -n`. The inline bash in `scripts-validate` is orchestration (find + lint), not component logic. | — |
| **R6: Immutable execution environment** | ✓ | GitHub Actions pins `ubuntu-24.04` and all third-party actions by SHA. Bootstrap scripts assume the target environment is prepared; CI does not `apt install` dependencies at runtime beyond the pinned runner image baseline. | — |
| **R7: Deterministic versioning (SHA pinning)** | ✓ | Pre-commit hooks pinned by SHA (no `@v4`, no `@latest`). Models referenced by concrete tags (`qwen2.5-coder:7b`, `qwen2.5-coder:3b`), never `:latest`. GitHub Actions pinned by SHA. `CHANGELOG.md` follows Keep a Changelog. | — |
| **R8: Documentation + linting** | ✓ | Mandatory files present (see table below). `.pre-commit-config.yaml` runs `markdownlint`, `yamllint`, `actionlint`, `shellcheck`, `shfmt`, `dotenv-linter`, plus `lychee` for link integrity. | — |
| **R9: Branch protection** | ⚠ deferred to v0.1.1 | `main` is unprotected at the time of this evaluation. Documented as deferred work in [roadmap.md](roadmap.md) v0.1.1. Interim mitigation: only the repo owner has push rights; account-level GitHub Secret Scanning is enabled. | Enable required PR + status checks via `gh api repos/donJorgito/homelab-llm/branches/main/protection` in v0.1.1. |
| **R10: Automation + AI attribution** | ✓ minimal | Conventional Commits enforced via pre-commit hook. `Co-Authored-By: Claude` mandatory on AI-assisted commits (documented in `CONTRIBUTING.md` and `CLAUDE.md`). `dependabot.yml` updates GitHub Actions weekly. Renovate / semantic-release scheduled for v0.2. | Add Renovate + semantic-release in v0.2. |

## Mandatory files

These files are present in the repository root because every reasonably-rigorous project I've worked with had them; the list is informed by `keepachangelog.com`, GitHub's recommended community standards, and personal habit.

| File | Present | Path |
|---|---|---|
| `README.md` | ✓ | `README.md` |
| `CHANGELOG.md` | ✓ | `CHANGELOG.md` |
| `CONTRIBUTING.md` | ✓ | `CONTRIBUTING.md` |
| `.gitignore` | ✓ | `.gitignore` |
| `CODEOWNERS` | ✓ | `.github/CODEOWNERS` |
| Pipeline config | ✓ | `.github/workflows/ci.yml` |
| `/requirements` folder | ✓ | `requirements/` (RQ001-RQ007) |
| `/tests` folder | ✓ | `tests/` (1:1 with requirements) |
| `.pre-commit-config.yaml` | ✓ | `.pre-commit-config.yaml` |
| `LICENSE` | ✓ | `LICENSE` (MIT) |
| `SECURITY.md` | ✓ | `SECURITY.md` |
| `CLAUDE.md` | ✓ | `CLAUDE.md` |

## Justified exceptions

- **No JUnit reporter** — Tests are shell, not Python; the operator runs them post-deploy. The repo is small enough that human-readable shell output is preferable to structured XML for diagnosis.
- **No 80% coverage metric** — Coverage tooling for shell is awkward (`kcov` / `bashcov` are fragile). The 7 RQ tests provide functional traceability, which is the actual goal.
- **No ticketing / change-record automation** — This is a personal homelab. There is no ticketing system to integrate with.
- **No regulatory risk-assessment artifacts (threat models / formal review docs)** — Not applicable to personal scope. OWASP secret-scanning + the 10 rules cover what's reasonable for the threat surface.
- **No Renovate / semantic-release at v0.1.0** — `dependabot.yml` covers the minimum (Actions, weekly). Semantic-release escalation in v0.2.

## Re-audit policy

This checklist MUST be re-evaluated before every minor release (`v0.X.0`). Patch releases (`v0.X.Y`) inherit the prior result unless they touch CI, secrets handling, or rules R1–R10 directly.

---

Last evaluated: 2026-06-09. Tree: initial scaffolding.
