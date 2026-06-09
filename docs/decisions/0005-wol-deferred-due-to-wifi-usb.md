# ADR-0005: Wake-on-LAN (WoL) deferred due to WiFi USB connectivity

- Status: Accepted
- Date: 2026-06-08
- Deciders: donJorgito (Owner)

## Context

The original plan included a Raspberry Pi 4 always-on as the gateway, which would wake `hidra` on demand using a Wake-on-LAN magic packet. While bringing up `hidra` we discovered that its only working network interface is a **USB WiFi dongle** (`wlx5091...`); the wired NIC `eno1` is `DOWN` because no Ethernet cable is attached.

Classic WoL requires the magic packet to arrive at an Ethernet PHY that stays powered while the system is suspended. USB devices typically lose power on suspend, so WoL over the USB WiFi dongle is not viable.

## Decision

Defer wake-on-demand. `hidra` stays **manually powered on** during use. The RPi 4 gateway (roadmap v0.2) ships **without** WoL in its first iteration. Once an Ethernet cable is run to `eno1` (roadmap v0.3), WoL is enabled in v0.4.

## Consequences

### Positive

- Simplifies v0.1 and v0.2: no magic-packet flow, no health-check-with-retry-after-wake state machine.
- Lets us tackle higher-blast-radius problems first (gateway, auth, model selection).
- Defers a non-trivial design decision until the underlying network constraint is resolved.

### Negative

- `hidra` running 24/7 idles around ~15 W (GTX 970 at P8). That is ~360 Wh/day — negligible in cost, not negligible environmentally.
- Postpones automatic suspend; the host stays warm and powered between uses.
- Requires user discipline (manual power-off when leaving on a long break).

## Alternatives considered

- **WiFi-controlled smart plug driven by the RPi 4** — Cuts mains power instead of suspending. Works without WoL but is brutal: hard power cycles instead of clean suspend/resume. Kept on the table as a fallback in roadmap v0.4 if running an Ethernet cable proves impractical.
- **Hidra always-on (interim)** — Chosen for now. Acceptable for the ~1 month until v0.3 ships.
- **Cable Ethernet + classic WoL** — The correct long-term plan, slated for v0.3-v0.4.

## References

- [docs/roadmap.md](../roadmap.md) — v0.3 and v0.4
- [docs/case-study-hidra.md](../case-study-hidra.md)
