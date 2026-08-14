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

## ⚠ Challenge corrections (2026-06-21) — the naive command was broken

A 3-lens adversarial review (containment / operability / completeness) found the original
bwrap command would produce *a sandbox containing a dead, still-escapable executor*. All
claims verified against the live `autonomous-runner.sh` + this machine. Four flaws:

- **F1 (FATAL) — `--unshare-net` bricks the executor.** `claude -p` IS the network client;
  it needs `api.anthropic.com`. Block-all-egress → every task fails "no changes" every run.
  **Fix:** egress *allowlist proxy* (only `api.anthropic.com:443`) + `HTTPS_PROXY` into the
  sandbox — the Codex/Claude-Code-cloud pattern this doc's own research table cited.
- **F2 (FATAL) — `--tmpfs /home` destroys claude's own creds** at `~/.claude/.credentials.json`
  (verified present). Auth fails before the first token. **Fix:** `--ro-bind` claude's auth
  read-only; keep `~/.config/brana` hidden (those are the *attacker's* target, a different set).
- **C1 (CRITICAL) — env-borne secrets bypass everything.** No `env -i` → `LINEAR_API_KEY` etc.
  inherited, readable via `env` / `/proc/self/environ`. **Fix:** `env -i` + explicit allowlist.
- **C2 (CRITICAL) — worktree write → unsandboxed host execution.** The agent's one writable
  path is read back and executed on the HOST: line 209 `eval "$VALIDATE_CMD"`, line 216 `git
  commit` (runs worktree `.git/hooks`). A network-blocked agent still gets host RCE by writing
  a malicious `validate.sh`/`pre-commit`. Also makes "escape-test in validate.sh" **circular**.
  **Fix:** run validate from a PINNED base-ref copy (not the worktree's) + `commit --no-verify`.

Process fixes: **spike before ADR** (prove bwrap can run claude -p at all — F1+F2 show why);
**6-vector escape battery** not one curl (home-read, /proc/environ, write-outside-worktree,
curl, DNS-exfil, fd-inheritance) + fork-bomb test. Plus: `--rlimit-nproc/as/fsize`, close
inherited fds, minimal bind list (not `--ro-bind / /` — leaks `~/.aws`/`~/.ssh`), sandbox the
OBSERVE call (line 80) too, and name the supply-chain class (malicious tracked files passing
validate → human reviewer is the last gate) in the ADR Consequences.

## Proposed solution — layered, marathon (build-it-right) — CORRECTED

### Layer 1 — bwrap OS sandbox around the executor dispatch (the real boundary)
```bash
# Start an egress-allowlist proxy first (only api.anthropic.com:443), e.g. tinyproxy on 127.0.0.1:3128
bwrap --unshare-ipc --unshare-pid \
  --ro-bind /usr /usr --ro-bind /bin /bin --ro-bind /lib /lib --ro-bind /lib64 /lib64 \
  --ro-bind /etc/alternatives /etc/alternatives --ro-bind /etc/ssl /etc/ssl \
  --ro-bind "$HOME/.claude/.credentials.json" "$HOME/.claude/.credentials.json" \
  --ro-bind "$HOME/.cargo" "$HOME/.cargo" --ro-bind "$HOME/.gitconfig" "$HOME/.gitconfig" \
  --bind "$WT" /workspace \
  --tmpfs /tmp --proc /proc --dev /dev \
  --rlimit-nproc 50 --rlimit-fsize 500M \
  --chdir /workspace \
  env -i HOME=/tmp PATH=/usr/bin:/bin HTTPS_PROXY=http://127.0.0.1:3128 \
  "$CB" -p --allowedTools "Read,Write,Edit,Bash" --output-format text
```
- **Egress allowlist proxy** (not `--unshare-net`) → only `api.anthropic.com` reachable; the
  executor still works, arbitrary IPs blocked at the proxy.
- **Minimal `--ro-bind` list** (not whole `/`) → `~/.aws`, `~/.ssh`, other users' files unreadable.
- **`--ro-bind` claude creds + `~/.cargo`/`~/.gitconfig`** → executor authenticates + builds.
- **`env -i`** → inherited env secrets cleared.
- **`~/.config/brana` is NOT bound** → brana secrets stay hidden.
- **rlimits** → fork-bomb / disk-fill contained.
- **C2 fix (in the runner, not bwrap):** run `validate.sh` from the base-ref copy, not the
  worktree; `git commit --no-verify`. Sandbox the OBSERVE call (line 80) the same way.

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

## Next steps (CORRECTED build order — spike before ADR)
0. **SPIKE (NEW, gates everything):** prove `bwrap` + egress-proxy + `--ro-bind` claude creds
   can run a trivial `claude -p` prompt to completion with auth working. F1/F2 show an
   unspiked ADR would commit to a config that can't run the executor. Gate ADR on spike pass.
1. **ADR (DDD):** record "sandbox = bwrap; egress = allowlist proxy (NOT --unshare-net);
   creds bind-mounted RO; env -i; validate from base-ref; filtering = tripwire only". Name the
   supply-chain class (malicious tracked files passing validate → human reviewer is last gate)
   in Consequences. Note Landlock/seccomp deferred + why.
2. **Test-first (TDD):** write the 6-vector escape battery + fork-bomb test, run from a PINNED
   path (not the worktree). See it fail against the current runner. Name which validate.sh
   check number it becomes.
3. **Implement:** wrap line-198 dispatch (and line-80 OBSERVE) in the corrected bwrap; add
   `env -i`; run validate from base-ref copy + `commit --no-verify`; close inherited fds.
4. **Compatibility soak:** run a real rust + real shell + real python task; define PASS
   criteria up front (all tests green, no bwrap-caused errors, no new failures vs baseline);
   fix binds until the DEFAULT config "just works" (so nobody loosens it under friction).
5. **Docs (SDD):** update `docs/architecture/features/autonomous-runner.md` capability-isolation
   section + add a runner-PR reviewer checklist (scope-creep, new eval/network patterns).

## Sources
- Simon Willison — The Lethal Trifecta for AI agents (2025-06)
- Trail of Bits — Prompt injection to RCE in AI agents (2025-10)
- Backslash Security — The Denylist Delusion (Cursor auto-run)
- Anthropic — Making Claude Code more secure and autonomous with sandboxing; How we contain Claude
- OpenAI Codex — Linux Landlock and seccomp; agent approvals & security
- OWASP — AI Agent Security Cheat Sheet
- ArchWiki Bubblewrap/Examples; containers/bubblewrap; "Claude Code constrained by Bubblewrap" (patrickmccanna.net)
