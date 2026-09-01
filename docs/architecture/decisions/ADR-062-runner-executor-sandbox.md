---
status: accepted
---
# ADR-062: Sandbox the Autonomous Runner's Executor — Capability Isolation via bubblewrap

**Status:** Accepted (2026-06-21; spike-gated — bwrap proven to run `claude -p` to completion before this ADR was committed). Amended 2026-08-31: docker fallback (Amendment 1, not adopted, t-2173 P3); verify gate = trusted inspection, C2 §1 superseded (Amendment 2, shipped, t-3256); supervised is the supported model, headless is phase-2.
**Date:** 2026-06-21 (amended 2026-08-31)
**Deciders:** Martín Rios
**Tags:** security, runner, autonomy, sandbox, adr-060, lethal-trifecta
**Tasks:** t-2173 (this ADR + impl) · gates unattended `--run-batch` on real tasks
**Relates:** [ADR-060](ADR-060-two-tier-integration.md) (worktree isolation = the git layer this ADR completes at the OS layer) · [ADR-050](ADR-050-loop-request-protocol.md) (autonomy caps) · [substrate-end-state §Operating the Orbit](../substrate-end-state.md#operating-the-orbit) · idea: [runner-capability-isolation](../../ideas/drained/runner-capability-isolation.md)

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
1. ~~Run `validate.sh` from a **pinned base-ref copy**, not the worktree's~~ — **superseded
   2026-08-31, see Amendment 2 (t-3256).** The base-ref-copy idea proved fragile (`validate.sh`
   is a 72-check whole-repo suite that self-sources dozens of files and needs the host git
   dir). Replaced by a **trusted inspection gate**: the runner never executes worktree code as
   the gate at all — `verify_diff` reads the diff with hardened read-only git; tests/build run
   at PR review. `RUNNER_VALIDATE_CMD` became opt-in/off.
2. `git commit --no-verify` (shipped — the worktree's `.git/hooks` never run on the host).

This also makes the escape test non-circular (it cannot be defeated by the very code under
test).

### Network egress — allowlist (RESOLVED 2026-06-21, see Addendum)

Net egress is restricted to `api.anthropic.com:443` only (Codex/Claude-cloud pattern). The
original ADR left the *mechanism* open. A 2026-06-21 spike proved the slirp4netns/nft path
**infeasible** for the unprivileged runner on Ubuntu 24.04+ (AppArmor
`apparmor_restrict_unprivileged_userns`), and resolved it to a **single-level
`bwrap --unshare-net` + bind-mounted unix socket → host CONNECT allowlist proxy** —
unprivileged, AppArmor-compatible, and validated end-to-end with real subscription
`claude -p`. See the **Addendum** below for the full record.

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

## Addendum (2026-06-21): Egress sub-decision RESOLVED — unix-socket CONNECT proxy

**Status:** Accepted (spike-validated end-to-end with real subscription `claude -p`).
**Supersedes** the "Network egress — OPEN sub-decision" section above.

### What the spike found (all empirical, this host = Ubuntu 26.04, `bwrap 0.11.1`)

1. **The slirp4netns/nft path is infeasible unprivileged here.** Ubuntu 24.04+ ships
   `kernel.apparmor_restrict_unprivileged_userns=1`, which neuters the capabilities needed
   for network-namespace work *inside* an unprivileged user namespace. Proven: as uid 1000
   (init userns, `CapEff=0`) `setns(CLONE_NEWNET)` fails (`nsenter` into our own netns →
   EPERM); creating a nested netns fails; `nft` netlink fails — **even with `--cap-add
   CAP_SYS_ADMIN`** inside the bwrap userns (`CapEff=0x200000`, ops still EPERM). No
   passwordless sudo. So nft-egress-firewall **and** any slirp4netns/pasta proxy bridge
   (both need `setns`) are out without privileged provisioning.
2. **Anthropic's own `@anthropic-ai/sandbox-runtime` (srt) also fails here** — it nests a
   userns for its seccomp layer (`apply-seccomp: write /proc/self/setgroups … nested userns
   is capability-restricted`), which the same AppArmor control blocks. srt would need
   `sysctl=0` or a privileged AppArmor profile. (srt remains the reference for the
   *technique* — bwrap `--unshare-net` + unix-socket + allowlist proxy.)
3. **A single-level `bwrap --unshare-net` works** (no nesting, no netns ops) and gives the
   jail only loopback. Proven: direct egress blocked (`curl 1.1.1.1` → rc=7), while a
   request over a **bind-mounted unix socket** reached the outside (http 301).

### Decision (the egress leg, layered on the existing fs/secret/env jail)

Egress is enforced by a **host-side HTTP CONNECT allowlist proxy reachable only through a
bind-mounted unix socket** — no privileged setup, no `setns`, no nested userns:

```
single bwrap --unshare-net                 # jail = loopback only; all direct egress blocked
  + writable per-run HOME copy             # .credentials.json + sanitized .claude.json
  + --bind <unix-socket> /egress.sock      # the jail's ONLY path out
  + in-jail: socat TCP-LISTEN:<hi-port>,bind=127.0.0.1 → UNIX-CONNECT:/egress.sock
  + env HTTPS_PROXY=http://127.0.0.1:<hi-port>
host side: a ~40-line python3 CONNECT proxy on the unix socket, allowlist = {api.anthropic.com:443}
```

Validated: jailed **real subscription** `claude -p` → `PONG` RC=0, with the proxy logging
`ALLOW api.anthropic.com` and `DENY example.com / mcp-proxy.anthropic.com /
http-intake…datadoghq.com` (claude tolerates the telemetry/MCP denials). DNS is not needed
in the jail — the proxy resolves host-side from the CONNECT hostname.

### Two corrections this forces

- **Writable HOME copy (not RO cred bind).** `claude` **rewrites `~/.claude.json` on
  startup**; the original RO bind made it bail `Not logged in · Please run /login` (this is
  the subscription-OAuth path — creds live in `~/.claude/.credentials.json` +
  `~/.claude.json` account state; *not* the system keyring, disproven). The runner now
  stages a **writable per-run copy** of those two files into the jail HOME and `rm -rf`s it
  after the run (mode 700, under `/tmp`). The copied `.claude.json` is **sanitized** — strip
  `mcpServers`, `mcpOAuth`, and `history` — so (a) third-party MCP tokens (linear, supabase,
  …) never enter the jail and (b) MCP servers don't load, shrinking egress to
  `api.anthropic.com`.
- **Cred-copy is safe *only because* egress is locked.** A writable copy of the live OAuth
  token is readable by the (possibly injected) executor — acceptable **only** under the
  egress allowlist, which makes the token unexfiltratable. This couples the two controls:
  the runner must never stage real creds without the egress proxy active. (It also closes a
  latent hole in the pre-egress config, where RO-but-readable creds + shared net namespace
  left the token exfiltratable.)

### Knobs / fallback

- `RUNNER_EGRESS=1` (default) enforces the proxy; `RUNNER_EGRESS_ALLOW` overrides the
  allowlist (default `api.anthropic.com`). `RUNNER_SANDBOX=0` remains the full
  unsandboxed escape hatch (loud warning).
- Dependencies (all present, unprivileged): `bwrap`, `socat`, `python3`. No `tinyproxy`/
  `pasta`/`slirp4netns`/`nft` needed.
- **Privileged hosts** (no AppArmor userns restriction, or with the `bwrap` AppArmor profile
  / `sysctl=0`) could alternatively adopt `srt` directly or an nft egress firewall — recorded
  as future options, not required.

### Escape test

V5/V6 (egress/DNS) graduate from documented KNOWN GAP to **hard asserts**: an injected stub
that `curl`s a non-allowlisted host must be **blocked**, while the allowlisted endpoint is
reachable. Runs in `validate.sh` Check 61 so egress erosion fails loudly.

## Amendment 1 (2026-08-31): docker executor jail — documented fallback, NOT adopted

A `/brana:challenge` deep review (3 lenses, all RECONSIDER on docker) evaluated replacing the
in-tree bwrap jail with a docker-container executor. **Decision: keep bwrap (Option A); docker
is a documented fallback for privileged/future hosts, same standing as srt/nft above — not
adopted now.**

- **Spiked and proven (2026-08-31):** a real subscription `claude -p` runs to completion
  (`PONG`, rc=0) inside a `--internal` docker network reaching Anthropic only through the same
  committed `runner-egress-proxy.py` (host socat→unix bridge); direct container egress blocked;
  proxy audit identical to the bwrap config (ALLOW `api.anthropic.com`, DENY the rest). Docker
  sidesteps the AppArmor nested-userns wall that blocks nft/slirp4netns/srt on this host.
- **Why not adopt:** the user is in the `docker` group on a **rootful** daemon = root-equivalent
  host capability, which **reopens the exact unprivileged-host-RCE leg this ADR was written to
  close** — the *orchestrator* holds standing root regardless of what any container mounts.
  bwrap's proven worst case is worktree-scoped; docker's is host root. The spike also proved
  only the egress leg — not the worktree-write path, secret isolation, or an escape battery.
- **If ever adopted** (rootless podman/docker provisioned): hard constraints — never mount
  `docker.sock` into the jail; never build `docker` argv from task-controlled fields; carry a
  docker escape-battery analogue in Check 61. Tracked as **t-2173** (P3, phase-2).

## Amendment 2 (2026-08-31, t-3256): verify gate is trusted inspection, not host execution

The C2 §1 fix above (base-ref validate copy) was **reconceived and shipped differently.** Root
cause of the host-RCE was not *which* validate ran but that the gate executed executor-writable
worktree code on the host at all. The fix removes execution from the gate:

- **`verify_diff`** (always on) inspects the diff with **hardened read-only git**
  (`core.fsmonitor=`, `core.hooksPath=/dev/null`, `protocol.file.allow=never`): `git diff
  --check`, deny-paths (`RUNNER_DENY_PATHS`), a best-effort secret-scan (`RUNNER_SECRET_SCAN`),
  and a size guard. It never runs worktree code and never mutates the index.
- **Gitlink-tamper guard:** the worktree's `.git` gitlink is executor-writable, so a redirect at
  a fake git dir would run its config's `core.fsmonitor`/textconv on the host during any
  `git -C "$WT"` call. `run_task` pins the gitlink at creation and refuses a tampered one after
  dispatch, before any host git runs (challenger finding; `test-…-validate-jail.sh` V7d).
- **`RUNNER_VALIDATE_CMD`** is now opt-in and off by default; when set it runs worktree code on
  the host and warns — safe only for a trusted command or a sandboxed runner.
- Correctness (tests/build) moves to **PR review**, which always happens: `--run-batch` never
  auto-merges. Machine-checked by `validate.sh` Check 61 (a second, always-on assertion).

## Scope note (2026-08-31): supervised is the supported model; headless is phase-2

The full OS jail (Amendment 1 / t-2173) gates only **headless, unattended `--run-batch`**. The
supported model today is **supervised** drain — in-session workers + worktrees, a human present
and operating the merge valve — where task text is the operator's own and the prompt-injection
threat is bounded. Keep `brana orbit` in `observe`; do not run `--run-batch` walk-away until
t-2173 lands. Amendment 2 (the inspection gate) is a real hardening that ships regardless, since
it also removes a class of bug and simplifies the runner.

## Sources

Simon Willison — The Lethal Trifecta for AI agents (2025-06) · Trail of Bits — Prompt
injection to RCE (2025-10) · Backslash Security — The Denylist Delusion · Anthropic —
sandboxing Claude Code · OpenAI Codex — Landlock + seccomp · OWASP — AI Agent Security
Cheat Sheet · ArchWiki Bubblewrap · Matt Pocock — sandcastle (container-provider agent isolation).
