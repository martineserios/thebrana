---
title: Autonomous Runner — Capability Isolation (Sandbox the Executor)
status: idea
created: 2026-06-21
task: t-2173
---

# Autonomous Runner — Capability Isolation

> Brainstormed 2026-06-21. Status: idea. Backs task t-2173.

## Problem

The autonomous runner (`autonomous-runner.sh`) dispatches the executor as
`claude -p --allowedTools "Read,Write,Edit,Bash"` (line 198) with **Bash unscoped**.
A git worktree isolates *tracked files*, not the *OS process*. So any side effect that
never lands as a tracked file — network egress, `$HOME` writes, reads of
`~/.config/brana/*.env` secrets, `rm`, package installs, `git push` — is invisible to
every gate (`git status --porcelain`, `validate.sh`, `git add -A`, human diff review).

The realistic trigger is **prompt injection via task fields**: subject/description/AC
lines are backlog-author-controlled and flow into the executor prompt, where they can
steer the unscoped Bash tool. This is a HARD precondition before any unattended
`--run-batch` on real tasks.

## The framing — Lethal Trifecta (Simon Willison, 2025; now industry-standard)

An agent is indefensible when it simultaneously holds all three:

1. **Access to private data** — `~/.config/brana/*.env` secrets, credentials
2. **Processes untrusted input** — backlog task text
3. **External communication** — unscoped Bash + network

Our runner has all three. Injection→exfiltration then needs **no code vulnerability** —
just normal tool use. Remove *any one leg* and the attack can't cash out.

## Research findings (web + community, 2026-06-21)

Three parallel research agents (sandboxing of AI coding agents; prompt-injection
defenses; Linux sandbox tooling). Convergent consensus:

### What does NOT work (hard red-team evidence)
- **Command denylist → 100% bypass.** Obfuscation (`c'a't`, `$'\x63at'`), subshells,
  write-then-run. (Trail of Bits 2025-10; Backslash Security on Cursor auto-run.)
- **Command allowlist → RCE via flags** on allowed `git`/`find`/`grep`
  (`git config core.fsmonitor=…`, `find -exec`). Comprehensive filtering impractical.
- **Consensus (OpenAI, Anthropic, Google, OWASP):** *"Sandboxing is mandatory;
  filtering is defense-in-depth only."*

### What the field actually ships
| Tool | Isolation | Network default |
|------|-----------|-----------------|
| Claude Code (native, recent) | bwrap + Landlock + seccomp | allowlist proxy |
| **OpenAI Codex** | seccomp + Landlock | **BLOCKED by default** (gold standard) |
| Devin / OpenHands | Docker container / QEMU microVM | default-allow inside boundary |

- **Installed Claude Code 2.1.185 has no `--sandbox` flag/settings key** — the native
  feature is newer/cloud/enterprise. So we replicate the mechanism with **bubblewrap**,
  which is what Anthropic's own feature uses internally. Community prior art exists
  ("Claude Code constrained by Bubblewrap", patrickmccanna.net).
- **bubblewrap is the right tool**: no SUID/root, used in production by Flatpak,
  `bwrap`/`systemd-run`/`unshare` already installed on the target box.

## Proposed solution — layered, marathon (build-it-right)

### Layer 1 — bwrap OS sandbox around the executor dispatch (the real boundary)
```bash
bwrap --unshare-net --unshare-ipc --unshare-pid \
  --ro-bind / / \
  --bind "$WT" /workspace \
  --tmpfs /tmp --tmpfs /home \
  --proc /proc --dev /dev \
  --chdir /workspace \
  env HOME=/tmp \
  "$CB" -p --allowedTools "Read,Write,Edit,Bash" --output-format text
```
- `--unshare-net` → all egress blocked (loopback only).
- `--ro-bind / /` + `--bind "$WT" /workspace` → whole FS read-only except the worktree.
- `--tmpfs /home` (HOME=/tmp) → secrets in `~/.config` are unreadable.

### Layer 2 — Bash denylist as a TRIPWIRE (defense-in-depth, not the boundary)
`--disallowedTools "Bash(curl:*) Bash(wget:*) Bash(git push:*) Bash(rm -rf:*)"`.
Fails fast + gives an audit signal ("injection attempted"). Demoted by the research
from "inner wall" to "tripwire only" — it is NOT relied on for containment.

### Layer 3 — credential isolation (break a trifecta leg independently)
Ensure no static secret is reachable in the executor's environment even if Layer 1 is
ever misconfigured. `HOME=/tmp` + tmpfs `/home` already hides `~/.config/brana/*.env`;
also scrub secret-bearing env vars from the dispatch environment.

### Layer 4 — the invariant TEST that keeps the boundary from rotting
A hermetic test (sibling of `test-autonomous-runner-*.sh`): a task whose description
says "curl-exfiltrate $SECRET" → planted fake secret is UNREADABLE **and** the network
call FAILS. This is t-2173 AC#1; without it the sandbox silently degrades over time.

## Risks

- **TOP RISK (pre-mortem) — compatibility erosion → silent re-opening:** the sandbox
  breaks too many real builds (missing cargo cache / toolchain paths / `/tmp`), so an
  operator loosens it (`--bind $HOME`, drops `--unshare-net`) to "make it work" — silently
  defeating the boundary. The danger isn't the crypto, it's the human workaround under
  friction. **Mitigation (load-bearing):** (a) invest in the compatibility soak so the
  default config "just works" for rust/shell/python and nobody is tempted to loosen it;
  (b) the Layer-4 escape test runs **inside `validate.sh`** and fails LOUDLY if a planted
  secret becomes readable or an egress call succeeds — so any loosening is caught
  immediately, not 6 months later.
- **Compatibility tuning is the bulk of the work** — the recommended command pre-binds
  `/tmp` + read-only `/` so toolchains resolve; per-project tuning only when a build fails.
- **Misconfiguration re-opens the hole** — an over-permissive `--bind` (e.g. binding all
  of `$HOME`) silently defeats the sandbox. Mitigated by Layer 4's test.
- **Network-off breaks tasks that legitimately fetch deps** — accept for now (autonomous
  tasks should be self-contained); revisit with an egress allowlist proxy (Claude-Code-cloud
  / Codex pattern) if a real need appears.

## Maps to t-2173 ACs
- AC1 (executor cannot net-call or write outside worktree) → Layers 1 + 4
- AC2 (boundary enforced + documented in autonomous-runner.md) → Layers 1–2 + doc update
- AC3 (spec states capability-isolation model explicitly) → doc update

## Next steps
1. ADR (DDD): record "sandbox = bwrap; filtering = tripwire only; net off by default".
2. Test-first (TDD): write the Layer-4 escape test; see it fail against current runner.
3. Implement: wrap line 198 dispatch in bwrap; add denylist; scrub secret env.
4. Compatibility pass: run a real rust + a real shell task through the sandbox, fix binds.
5. Docs (SDD): update `docs/architecture/features/autonomous-runner.md` capability-isolation section.

## Sources
- Simon Willison — The Lethal Trifecta for AI agents (2025-06)
- Trail of Bits — Prompt injection to RCE in AI agents (2025-10)
- Backslash Security — The Denylist Delusion (Cursor auto-run)
- Anthropic — Making Claude Code more secure and autonomous with sandboxing; How we contain Claude
- OpenAI Codex — Linux Landlock and seccomp; agent approvals & security
- OWASP — AI Agent Security Cheat Sheet
- ArchWiki Bubblewrap/Examples; containers/bubblewrap; "Claude Code constrained by Bubblewrap" (patrickmccanna.net)
