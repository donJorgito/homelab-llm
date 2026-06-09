# Security Policy

`homelab-llm` is a personal, single-maintainer open-source project. This policy describes how to report a security issue and what response you can reasonably expect. There is **no formal SLA** — this is a best-effort policy for a personal repo.

## Supported Versions

| Version | Supported |
|---|---|
| `0.1.x` | Yes (current) |
| `< 0.1.0` | No releases below this version exist |
| Future `0.2.x`, `1.x` | Will be supported once released; see [`docs/roadmap.md`](docs/roadmap.md) |

Only the latest patch on the most recent minor line receives security fixes. Older minor lines are unsupported once a newer minor is released.

## Reporting a Vulnerability

Please report security issues **privately**, not via public GitHub issues. Two acceptable channels, in order of preference:

1. **GitHub Private Vulnerability Reporting** (preferred). Open a private advisory on this repository: <https://docs.github.com/en/code-security/security-advisories/guidance-on-reporting-and-writing-information-about-vulnerabilities/privately-reporting-a-security-vulnerability>. This keeps the report visible to the maintainer and to GitHub Security without exposing it to the public.
2. **Email** to `<jorge@example.com>` (replace with the maintainer's verified address from the GitHub profile). Subject line: `[homelab-llm SECURITY] <short summary>`. Encrypt with the maintainer's public key if disclosing exploit details — request the key in a first message before sending sensitive content.

Please include in your report:

- The version (commit SHA or tag) you tested against.
- A clear description of the issue and its impact.
- Steps to reproduce, ideally with a minimal proof-of-concept.
- Any suggested mitigation if you have one.

## Response Time

Best-effort, **target 7 days** to first acknowledgement. This is a personal project; there is no on-call rotation and **no formal SLA**. If the issue is critical (active exploitation, secret disclosure in commit history, code-injection vulnerability in a script users are running), I will prioritize accordingly, but please understand the response time constraints of a single-maintainer project.

After acknowledgement:

- A fix or formal "won't-fix with rationale" decision typically lands within 14 days for non-critical issues.
- Disclosure timing is coordinated with the reporter. Default: public advisory at the same time as the patch release. Earlier or later disclosure on request, within reason.
- Reporters are credited in the advisory and the CHANGELOG unless they request anonymity.

## Scope

**In scope** for a security report on this repository:

- Secrets accidentally committed to the repository (current `HEAD` or any historical commit).
- Vulnerabilities in the shell scripts under `scripts/` and `tests/` — for example, command injection via unsanitized variable expansion, path traversal in `99-uninstall.sh`, race conditions in `01-create-lvm-volume.sh`.
- Vulnerabilities in the GitHub Actions workflow `.github/workflows/ci.yml` — for example, untrusted input passed to `run:` steps, supply-chain risks from unpinned actions.
- CVEs affecting pinned versions of pre-commit hooks or GitHub Actions used in this repo (please report so we can bump the pin).
- Misconfigurations in the documented setup (`.env.example`, README quick-start) that lead to sensitive data exposure if a user follows the instructions verbatim.

**Out of scope** for this repository's policy (please report upstream):

- Bugs or vulnerabilities in **Ollama** itself — report at <https://github.com/ollama/ollama/security>.
- Bugs or vulnerabilities in **aider** itself — report at <https://github.com/Aider-AI/aider/security>.
- Bugs in the **Qwen2.5-Coder** models or any other LLM model — report to the model publisher.
- Bugs in **NVIDIA drivers**, **CUDA**, or the **Linux kernel** — report to the respective vendor.
- General security hardening recommendations for the user's homelab network or LAN — outside the scope of this code-only repository.
- Issues that require local administrative access to a machine the attacker already controls (e.g., "if I'm root I can read `.env`"). Local privilege from local admin is not a vulnerability in this scope.

If you are unsure whether your finding is in scope, report it via the private channels above and the maintainer will triage and redirect upstream if appropriate.
