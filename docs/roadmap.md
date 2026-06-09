# Roadmap

Version-by-version plan from initial scaffolding (`v0.1.0`) to a working portátil-from-other-domicilio setup (`v1.0.0`).

## v0.1.0 — Initial scaffolding (current)

What got us here: idempotent bootstrap scripts, Ollama on a dedicated LVM volume, Qwen2.5-Coder 7B as the default model, aider as the validated CLI client, the full set of project mandatory files, CI with secret-scan + lint + script validation, and the architecture/case-study/benchmarks/shakedown documentation that justifies each choice.

See [CHANGELOG.md](../CHANGELOG.md) for the full entry.

## v0.1.1 — Compliance hardening (housekeeping checklist items, no user-facing features)

Housekeeping pass on deferred checklist items. No user-facing features.

- Enable branch protection on `main` (rule R9 in `compliance-checklist.md`): require PR + passing status checks via `gh api repos/donJorgito/homelab-llm/branches/main/protection`.
- Add Renovate config to auto-update pre-commit hooks and pinned action SHAs.
- Add `semantic-release` (or `release-please`) for automated tag + GitHub Release creation (rule R10 escalation in `compliance-checklist.md`).
- Document and execute cleanup of obsolete NVIDIA packages on `hidra` (`nvidia-driver-550`, `libnvidia-compute-535-server`, stale firmware) in a new `docs/maintenance.md`.

## v0.2.0 — RPi 4 as gateway

Independent of the Ethernet work. Brings remote access without exposing `hidra` directly.

- Caddy on the RPi 4 with Let's Encrypt (HTTP-01 or DNS-01 depending on the ISP).
- LiteLLM in front of Ollama with API-key auth and per-key rate limits.
- Tailscale for remote access without opening WAN ports.
- Test plan: a client connecting from a different physical site exercises the full path end-to-end.

## v0.3.0 — Cable Ethernet for hidra

Replaces the USB WiFi dongle with a wired link.

- Run a cable to `eno1`; bring the interface up and disable the WiFi dongle.
- Re-measure latency and jitter; target ping jitter <5 ms versus the current 21-106 ms over WiFi.
- **Unblocks** WoL (v0.4) and the v1.0 acceptance criteria around remote latency.

## v0.4.0 — On-demand wake

**Depends on v0.3** (Ethernet must be in place; see [ADR-0005](decisions/0005-wol-deferred-due-to-wifi-usb.md)).

- Configure WoL on `eno1` (`ethtool -s eno1 wol g`, persist via systemd-networkd or NetworkManager).
- RPi 4 sends the magic packet on first request via the gateway, with a health-check loop until Ollama answers.
- `hidra` cron-driven auto-suspend after configurable idle period.
- New ADR-0011 to capture the wake-on-demand strategy in detail.

## v0.5.0 — Model optimization

- Try `aider --architect` with Qwen2.5-Coder 7B as planner and 3B as editor; measure end-to-end task completion time and quality.
- Evaluate Qwen3-Coder when a variant under 8 GB ships and offers credible tool-use behavior.
- Re-run the shakedown matrix with whatever new defaults emerge.

## v0.6.0 — Other clients

Conditional, not date-driven. Each item ships only when the upstream stack is stable enough for local Ollama.

- Cline in VS Code pointed at `hidra`.
- Continue.dev as an alternative IDE-first client.
- OpenClaw once upstream offers a stable release with first-class Ollama support.

## v1.0.0 — Producto: portátil 2012-2014 desde otro domicilio funcionando

**Depends on v0.2 (gateway) + v0.3 (Ethernet).**

Acceptance criteria (measurable):

- Client connects via the gateway with auth in <10 s from a cold start.
- A typical aider task (single-file edit, <500 LOC project) completes in <60 s.
- 7 consecutive days with zero gateway downtime.

When all three pass simultaneously over a representative session, this repository ships its v1.0.0.

## Out of scope (no plans)

- Multi-GPU inference.
- Training or fine-tuning models.
- Kubernetes or Docker Swarm orchestration.
- Production-grade SLA or multi-tenant access.

---

This roadmap is a living document. Versions are released when their acceptance criteria pass; no fixed dates.
