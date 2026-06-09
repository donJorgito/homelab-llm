### homelab-llm.RQ004 - No Plaintext Secrets in Repository

**Description:**

The repository MUST NOT contain plaintext secrets, API keys, tokens, passwords, or any other credential material in any committed file, in either the working tree or git history. The repository is public, so a single leaked credential is irrecoverable. All sensitive variables MUST be referenced via `.env` (which is gitignored) and documented in `.env.example` using placeholder or example values only.

**Parent Requirement:** N/A (personal homelab repository; corresponds to rule R2 — no plaintext secrets — in `docs/compliance-checklist.md`).

**Acceptance Criteria:**

- `gitleaks detect --source . --no-git` exits with status `0` (no findings) on the working tree.
- `git log --all -p -- .env` returns no output (i.e., `.env` was never committed at any point).
- `.env` appears in `.gitignore`.
- `.env.example` exists and uses non-secret placeholder values (RFC 5737 IPs, generic hostnames, no real tokens).
- `gitleaks` is wired into the project pre-commit configuration so future commits are scanned automatically.
