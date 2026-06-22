---
status: accepted
---
# ADR-062: Sandbox the Autonomous Runner's Executor — Capability Isolation via bubblewrap

**Status:** Accepted (2026-06-21; spike-gated — bwrap proven to run `claude -p` to completion before this ADR was committed)
**Date:** 2026-06-21
**Deciders:** Martín Rios
**Tags:** security, runner, autonomy, sandbox, adr-060, lethal-trifecta
**Tasks:** t-2173 (this ADR + impl) · gates unattended `--run-batch` on real tasks
**Relates:** [ADR-060](ADR-060-two-tier-integration.md) (worktree isolation = the git layer this ADR completes at the OS layer) · [ADR-050](ADR-050-loop-request-protocol.md) (autonomy caps) · [substrate-end-state §Operating the Orbit](../substrate-end-state.md#operating-the-orbit) · idea: [runner-capability-isolation](../../ideas/runner-capability-isolation.md)

---

## Context

The autonomous runner (`system/scripts/autonomous-runner.sh`) dispatches the executor as
`claude -p --allowedTools "Read,Write,Edit,Bash"` (line ~198) with **Bash unscoped**, and
the OBSERVE planner (line ~80) calls `claude -p` too. A git worktree isolates *tracked
files in a checkout*, not the *OS process*. Every downstream gate — `git status
--porcelain`, `validate.sh`, `git add -A`, human diff review — inspects only the worktree's
tracked diff. So any side effect that never lands as a tracked file is **invisible to all
gates and the reviewer**: network egress, writes to `$HOME`, reads of
`~/.config/brana/*.env` secrets, `rm`, package installs, `git push`.

**Threat model — the Lethal Trifecta** (Willison 2025, now industry standard). The runner
simultaneously holds all three legs that make an agent indefensible:

1. **Private data** — `~/.config/brana/*.env` secrets, credentials on the host
2. **Untrusted input** — backlog task `subject`/`description`/`AC:` are author-controlled
   and flow verbatim into the executor prompt
3. **External communication** — unscoped Bash + full network

The realistic exploit is **prompt injection via task fields** steering the unscoped Bash
tool. Injection→exfiltration then needs **no code vulnerability** — just normal tool use.
Remove any one leg and the attack cannot cash out. Containment must live at the
**capability layer**, not the git layer.

**Why not filtering (rejected).** Hard red-team evidence (Trail of Bits 2025-10; Backslash
Security on Cursor):
- **Command denylist → ~100% bypass** via obfuscation (`c'a't`, `$'\x63at'`), subshells,
  write-then-run.
- **Command allowlist → RCE via flags** on allowed binaries (`git config
  core.fsmonitor=…`, `find -exec`).

Industry consensus (OpenAI, Anthropic, Google, OWASP): **sandboxing is mandatory;
filtering is defense-in-depth only.** Installed Claude Code 2.1.185 has **no `--sandbox`
flag** (the native feature is newer/cloud), so we replicate the mechanism with
**bubblewrap** — the same tool Anthropic's own feature uses internally, already present on
the box (`bwrap 0.11.1`), no SUID/root.

## Decision

**Sandbox both `claude -p` dispatches (executor line ~198 and OBSERVE planner line ~80) in
a bubblewrap jail with a minimal bind list, a cleared environment, and rlimits — and fix
the two host-execution escape paths in the runner itself.** Filtering is kept only as a
tripwire. The boundary is proven by an always-on escape test.

### The bwrap configuration (spike-validated 2026-06-21)

The spike ran `claude -p` to completion (auth OK, API reached, RC=0) with this shape. It
**corrects four flaws** in the idea doc's first-draft command (all found empirically):

```bash
CB="$(readlink -f "$CLAUDE_BIN")"                 # 222MB ELF; the symlink is not enough
RESOLV="$(readlink -f /etc/resolv.conf)"          # → /run/systemd/resolve/stub-resolv.conf
bwrap --unshare-ipc --unshare-pid \
  --ro-bind /usr /usr --ro-bind /bin /bin --ro-bind /lib /lib --ro-bind /lib64 /lib64 \
  --ro-bind /etc /etc --ro-bind "$RESOLV" /run/systemd/resolve/stub-resolv.conf \
  --ro-bind "$CB" /opt/claude \
  --ro-bind "$HOME/.cargo" "$HOME/.cargo" --ro-bind "$HOME/.gitconfig" /home/sb/.gitconfig \
  --bind "$WT" /workspace \
  --tmpfs /home --tmpfs /tmp --proc /proc --dev /dev \
  --ro-bind "$HOME/.claude/.credentials.json" /home/sb/.claude/.credentials.json \
  --chdir /workspace \
  env -i HOME=/home/sb PATH=/usr/bin:/bin \
  bash -c 'ulimit -u 200; ulimit -f 1024000; exec /opt/claude \
           -p --allowedTools "Read,Write,Edit,Bash" --output-format text' < /dev/null
```

Decisions encoded:
- **Minimal `--ro-bind` list, NOT `--ro-bind / /`** → `~/.aws`, `~/.ssh`, other users'
  files, and `~/.config/brana/*.env` are simply **absent** from the jail (the trifecta's
  "private data" leg, removed by omission).
- **`env -i`** → inherited env secrets (`LINEAR_API_KEY`, …) cleared; readable neither via
  `env` nor `/proc/self/environ`.
- **Writable `--tmpfs /home` with creds `--ro-bind` inside it** at the *jail's* HOME
  (`/home/sb/.claude/.credentials.json`) → claude authenticates and can write its own
  state; the worktree (`/workspace`) is the only host-backed writable path.
- **rlimits via an inner `ulimit`** (bwrap 0.11.1 has **no `--rlimit-*` flags**) →
  fork-bomb / disk-fill contained.

### Two runner-side fixes (C2 — de-circularize the boundary)

A network-blocked agent still gets **host RCE** by writing a malicious file the host then
executes. The runner must therefore:
1. Run `validate.sh` from a **pinned base-ref copy**, not the worktree's (line ~209
   `eval "$VALIDATE_CMD"` currently executes the agent's own validate).
2. `git commit --no-verify` (line ~216 currently runs the worktree's `.git/hooks`).

This also makes the escape test non-circular (it cannot be defeated by the very code under
test).

### Network egress — allowlist, OPEN sub-decision

Net egress **should** be restricted to `api.anthropic.com:443` only (Codex/Claude-cloud
pattern). The spike used the *shared* host net namespace (no `--unshare-net`), which
reaches **every** host — so egress is **not yet restricted**. `tinyproxy`/`pasta` are
absent; `socat` + `slirp4netns` are present. The mechanism (`--unshare-net` +
slirp4netns/proxy allowlist, or an nftables egress filter) is deferred to the impl phase
and tracked as the load-bearing open item. **Until egress is restricted, do not run
`--run-batch` unattended on untrusted tasks** — the default-deny scheduler job (ADR-060)
plus `brana orbit` staying in `observe` is the interim control.

### Filtering kept as a tripwire only

`--disallowedTools "Bash(curl:*) Bash(wget:*) Bash(git push:*) Bash(rm -rf:*)"` — fails
fast and emits an audit signal ("injection attempted"). **Not** relied on for containment.

### Deferred

Landlock + seccomp (Codex's extra layers) are deferred — bwrap namespaces + minimal binds
are the boundary for now; revisit if the threat model escalates.

## Consequences

**Positive.** The trifecta is broken at two legs (private data absent; egress restricted
once the open item lands). Prompt injection can no longer silently exfiltrate or write
outside the worktree. The boundary is machine-checked every `validate.sh` run, so erosion
fails loudly.

**Negative / risks.**
- **Compatibility erosion → silent re-opening (TOP risk, pre-mortem).** If the jail breaks
  real builds, an operator loosens it (`--bind $HOME`, drop `--unshare-net`) to "make it
  work," silently defeating the boundary. Mitigations are load-bearing: (a) a compatibility
  soak so the **default config just works** for rust/shell/python and nobody is tempted to
  loosen it; (b) the escape test runs **inside `validate.sh`** and fails loudly the moment
  a planted secret becomes readable or an egress call succeeds.
- **Supply-chain residue.** The sandbox stops out-of-band side effects, but a malicious
  *tracked* file that passes `validate.sh` still reaches the human reviewer — who is the
  last gate. The runner-PR reviewer checklist (scope-creep, new `eval`/network patterns)
  is part of the impl deliverable.
- **Egress is unrestricted until the open sub-decision is implemented** (see above).

## Build order (remaining, post-ADR)

1. **TDD:** 6-vector escape battery + fork-bomb test (home-read, `/proc/environ`,
   write-outside-worktree, curl, DNS-exfil, fd-inheritance), run from a pinned path — red
   against the current runner. Becomes a numbered `validate.sh` check.
2. **Implement:** wrap line-198 dispatch + line-80 OBSERVE in the config above; `env -i`;
   validate from base-ref copy; `commit --no-verify`; close inherited fds; resolve the
   egress-allowlist open item.
3. **Compatibility soak:** real rust + shell + python task; PASS = all tests green, no
   bwrap-caused errors, no new failures vs baseline; tune binds until the default works.
4. **Docs (SDD):** `docs/architecture/features/autonomous-runner.md` capability-isolation
   section + runner-PR reviewer checklist.

## Sources

Simon Willison — The Lethal Trifecta for AI agents (2025-06) · Trail of Bits — Prompt
injection to RCE (2025-10) · Backslash Security — The Denylist Delusion · Anthropic —
sandboxing Claude Code · OpenAI Codex — Landlock + seccomp · OWASP — AI Agent Security
Cheat Sheet · ArchWiki Bubblewrap.
