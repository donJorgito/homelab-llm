# Case study: hidra (homelab inference server)

A field log of how this stack actually came together on one specific machine, with the obstacles and trade-offs
that shaped each decision.

## Hardware encountered

The target machine is a desktop tower originally assembled around 2014 and repurposed as a homelab server:

- **CPU:** Intel i7-4770S (Haswell, 4 cores / 8 threads, 2013).
- **RAM:** 16 GB DDR3 + 8 GB swap.
- **GPU:** NVIDIA GeForce GTX 970 (Maxwell, compute capability 5.2, 4 GB VRAM, ~3.8 GB usable).
  This single number — 4 GB VRAM, cc 5.2 — drives every model choice that follows.
- **Storage:** 7.28 TiB raw in volume group `vg0`, 6.03 TiB unallocated extents available.
- **Network:** `eno1` (cabled) administratively DOWN — no Ethernet drop reaches the room. Connectivity is via a
  USB WiFi adapter (`wlx5091XXXXXXXX`).
- **OS:** Ubuntu 24.04.4 LTS, kernel 6.8.0-110.
- **NVIDIA driver:** 580.159.03 with CUDA 13.0 in userspace; the Ollama 0.30.6 binary auto-detects cc 5.2 and falls
  back to its `cuda_v12` build (the `cuda_v13` build is compiled with `archs="[750 800 860 ...]"` and refuses cc < 7.5).

## First obstacle: NVIDIA driver mismatch

The host had been on the cabled-DOWN setup for months; an `apt upgrade` had pulled in newer NVIDIA userspace libraries
without reloading the kernel module. The first `nvidia-smi` after Ollama install returned:

```text
NVIDIA-SMI has failed because it couldn't communicate with the NVIDIA driver.
Make sure that the latest NVIDIA driver is installed and running.
```

Diagnosis: `dmesg | grep -i nvidia` showed `Driver/library version mismatch` — the libraries on disk were a newer
release than the module currently loaded by the kernel. The fix was a reboot to load the matching module. The general
lesson, recorded for replication: after any `apt upgrade` that touches `nvidia-*` or `libnvidia-*` packages, reboot
before troubleshooting anything else. A live-patched kernel module is rare on consumer NVIDIA drivers.

## Storage choice: dedicated LVM volume

Ollama's default model location is `/usr/share/ollama/.ollama/models`, on the root filesystem. With root at 52 %
used and 6.03 TiB of free PEs in `vg0`, that default would have wasted the abundant capacity sitting one layer deeper
in LVM and entangled model storage with the rest of the OS for backup, snapshot, and uninstall purposes.

The chosen path: a dedicated logical volume `vg0/lv-ollama`, 128 GB, ext4, mounted at `/var/lib/ollama` with
`noatime,nodiratime` to match the mount-option convention of the other LVs on this host.

Sizing rationale: each Qwen2.5-Coder model occupies 2–7 GB on disk (3B Q4_K_M ~1.9 GB, 7B Q4_K_M ~4.7 GB,
14B Q4_K_M ~9 GB). A working set of 5–10 models lands in the 30–50 GB range. 128 GB gives a comfortable headroom
for experimentation (multiple quantizations of the same family, dropping in a 14B or 32B if hardware ever changes)
without committing TiB-scale chunks to a single workload. The LV can be grown on demand; shrinking ext4 is a worse
operation than living with overhead, so erring high makes sense at this size.

The trade-off accepted: one more entry in `/etc/fstab` and one more volume to remember during host upgrades, in
exchange for a clean uninstall path (unmount LV → `lvremove` → fstab cleanup) and the ability to snapshot model
state independently of the root filesystem.

## Sudo workflow without leaking the password

The hidra user has `sudo` privileges, but this repo runs many of its scripts from agent sessions that connect over
SSH. Two anti-patterns rejected up front:

- **`NOPASSWD` for the user.** Permanent privilege escalation with no time bound. Wrong default for a personal
  account.
- **`AskUserQuestion`-style password prompt routed through the agent.** The password would touch the agent
  conversation buffer.

The chosen mechanism: `/etc/sudoers.d/jorge-global-timestamp` with

```text
Defaults:jorge timestamp_type=global
Defaults:jorge timestamp_timeout=240
```

Jorge runs `sudo -v` once in a local terminal to refresh the timestamp; for the next 4 hours, any session running
as `jorge` (including SSH sessions driven by an agent) can use `sudo -n` without prompting. The password never
crosses the agent's session boundary. When the timestamp expires, scripts fail loudly with a clear message asking
for a fresh `sudo -v`.

## Model selection journey

The progression from "what I planned" to "what fits":

1. **Initial plan: Qwen2.5-Coder 32B.** Discarded immediately after running the math — even at Q4_K_M
   quantization the file is ~20 GB, far above the 4 GB VRAM ceiling. Would have required full CPU inference
   (single-digit tok/s) to run at all.
2. **Pulled Qwen2.5-Coder 7B Q4_K_M (~4.7 GB).** Fits with partial offload: 49 % of layers on GPU, 51 % on CPU.
   Measured **6.8–7.3 tok/s** generation, **~1 s TTFT** warm. Slow enough to feel the latency on long replies,
   fast enough to be the default for interactive editing.
3. **Pulled Qwen2.5-Coder 3B Q4_K_M (~1.9 GB).** Fits entirely on GPU. **32 tok/s, 0.3 s TTFT.** Five times faster
   than the 7B but visibly worse at multi-step reasoning.
4. **Decision: 7B as default, 3B available as fallback.** The 7B clears the bar for real agentic work
   (writing modules with tests, refactoring small files); the 3B is kept around for trivial completions and
   to verify behaviour under tight VRAM budgets.
5. **Bench Granite Code 3B / 8B.** Failed the tool-use gate: the Ollama `/api/show` capabilities array reports
   `["completion", "insert"]` with no `"tools"` capability. Confirmed by direct `/api/chat` test — the model emits
   prose, never structured tool calls. Excluded.
6. **Bench Granite 3.3 2B / 8B.** Capabilities array includes `"tools"`; isolated tests with a single tool
   definition return well-formed `tool_calls[]`. Kept as a candidate for clients that strictly require the
   structured shape.

## Client journey: OpenCode → aider

The client side took longer than the server side because every "obvious" choice failed first.

- **OpenCode 1.16.2 + Qwen2.5-Coder 7B.** Connection healthy, models listed. The agent loop ran one step,
  the model responded with a markdown code block embedding what would have been the tool call as JSON inside
  `content`, OpenCode found no `tool_calls[]` to execute, the loop terminated quietly. No file was written.
  Root cause: Ollama's OpenAI-compatible shim does not yet promote in-content tool calls to the structured field
  for the Qwen2.5-Coder family.
- **OpenCode + Granite 3.3 2B.** Granite emits structured `tool_calls[]` correctly in isolation, so the
  expectation was that swapping models would fix the loop. It did not. OpenCode's system prompt is large
  (~7 000 tokens for 16 default tools, skill registry, MCP wiring); the 2B model's effective attention budget was
  consumed by prompt parsing and it fell back to unstructured prose. The structured output that worked in a
  toy bench did not survive the production prompt.
- **aider 0.86.2 + Qwen2.5-Coder 7B.** Worked end-to-end on the first try with `--edit-format whole`. aider's
  prompt is tiny (a few hundred tokens of system instructions plus the repo map), it does not register tools
  and instead asks for filenames followed by full file contents in fenced code blocks, and it parses those
  blocks directly. The shape Qwen2.5-Coder happens to emit naturally is exactly what aider expects.

The general lesson encoded in [ADR-0003](decisions/0003-aider-as-cli-agent-not-opencode.md): for small local
models, the client with the smallest, most focused system prompt wins. Tool-rich clients designed around
frontier-model contexts saturate the cognitive window of a 2–8 B model long before the user message is
even processed.

## Shakedown — what aider can do

Five chained tasks against a fresh Python project (create module → add tests → refactor enum → fix a bug
introduced by the refactor → fix the fix). Detailed turn-by-turn results live in
[`docs/shakedown-results.md`](shakedown-results.md). Headlines:

- 4 of 5 tasks completed without human guidance beyond the initial prompt.
- The multi-file refactor needed two extra iterations with a human-supplied hint about which file held the stale
  enum reference.
- Per-turn latency was 90–180 s (prompt + generation + edit application).
- `pytest` runs end-to-end clean after every accepted turn.

The headline takeaway: this stack is good enough for localized edits and clear, single-file tasks. For broader
refactors, drive it with smaller, sequential prompts rather than a single large request.

## Notes for replication

If you are building the same setup on different hardware, calibrate against these:

- **More than 8 GB VRAM:** skip 7B and pull Qwen2.5-Coder 14B Q4_K_M instead. The quality jump is larger than the
  3B → 7B step, and you stop paying the partial-offload tax.
- **Less than 4 GB VRAM:** drop to the 3B model and stop trying to fit the 7B. Partial offload below 4 GB starts
  to feel like CPU inference.
- **WiFi USB on the server is a dead end.** Latency is variable, USB drops on suspend break wake-on-LAN, and
  remote clients feel the jitter. Run a cable to the cabled NIC if at all possible.
- **`aider --edit-format whole` is the validated pattern** for Qwen2.5-Coder. The `diff` format works on simple
  edits but produces invalid hunks on larger files; the `udiff` format is more robust on stronger models, less so
  here. Stick with `whole` until you benchmark a different model.
- **Local pre-commit success does not guarantee CI success.** Pinned hook versions in `.pre-commit-config.yaml`
  may differ from cached or default-installed versions on a developer machine. Run `pre-commit autoupdate`
  cautiously and only when you are ready to update the pins in the same commit.

## Anonymized identifiers used in this document

The IPs, MAC fragments, and email placeholders below replace real values from the lab; substitute your own when
adapting this case study.

| Placeholder | Replaces | Notes |
|---|---|---|
| `192.0.2.143` | The inference server's LAN IP. | RFC 5737 documentation block (`192.0.2.0/24`); never a real address. |
| `XX:XX:XX:XX:XX:XX` | MAC addresses of `eno1` and the WiFi USB adapter. | Generic placeholder. |
| `wlx5091XXXXXXXX` | The WiFi USB adapter's predictable interface name (driver + truncated MAC). | First four hex characters of the MAC are kept for shape; the rest is masked. |
| `hidra` | Hostname of the inference server. | Kept as written — generic enough to leak nothing useful. |
| `<jorge@example.com>` | Maintainer email. | The real address lives in `git config` and `SECURITY.md`, not in lab notes. |
