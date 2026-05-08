# thebrana — Design and Build the Brain

> The unified brana system repo. Design specs live in `docs/`, implementation lives in `system/`. One repo, one feedback loop. (Merged from enter + thebrana per ADR-006.)

## Two Workspaces, One Repo

| Workspace | Location | Purpose |
|-----------|----------|---------|
| **Architect** | `docs/` | Research, design, plan — dimension/reflection/roadmap docs |
| **Operator** | `system/` | Build, deploy, maintain — skills, hooks, rules, agents |

Branch conventions preserve the separation:
- `docs/*` branches: spec work (no `system/` edits)
- `feat/*` branches: implementation (should also touch `docs/` when behavior changes)

## Inbox

`inbox/` is a processing drop folder (gitignored). Drop files here for Claude to process: audio for transcription, docs for analysis, PDFs for review, data for import. Files are transient — process and delete or move to permanent storage.

> IMPORTANT: Before spec work, read [ARCHITECTURE.md](../docs/reflections/ARCHITECTURE.md) — layer diagram, Reflection DAG, spec lifecycle.

## Commands

### The 6 Jobs

| Job | Question | Entry Point |
|-----|----------|-------------|
| DECIDE | "What should I work on?" | `/brana:backlog`, `/brana:brainstorm` |
| UNDERSTAND | "What do I need to know?" | `/brana:research`, `/brana:onboard` |
| BUILD | "Make the thing" | `/brana:build` |
| SHIP | "Get it to users" | `/brana:ship`, `./bootstrap.sh`, `./validate.sh` |
| MAINTAIN | "Keep it healthy" | `/brana:reconcile`, `/brana:verify-docs` |
| GROW | "Build the business" | `/brana:review` |

> Full command reference: [docs/reference/skills.md](../docs/reference/skills.md)

## Specs Reference

| Topic | Doc |
|-------|-----|
| Architecture (layers, hooks, skills) | [ARCHITECTURE.md](../docs/reflections/ARCHITECTURE.md) |
| Lifecycle (DDD → SDD → TDD workflow) | [32-lifecycle.md](../docs/reflections/32-lifecycle.md) |
| Roadmap and next steps | [18-lean-roadmap.md](../docs/18-lean-roadmap.md) |
| Errata and corrections | [24-roadmap-corrections.md](../docs/24-roadmap-corrections.md) |
| ADR index | [docs/architecture/decisions/](../docs/architecture/decisions/) |

## Ecosystem

| Repo | Role | You go here to... |
|------|------|-------------------|
| **thebrana** (here) | Design + Build | Research, plan, implement, deploy |
| **brana-knowledge** | Knowledge base | General knowledge, research, backups |
| **clients/** | Paid work | External stakeholder projects (`~/enter_thebrana/clients/`) |
| **ventures/** | Your IP | Side projects, learning, monetizing (`~/enter_thebrana/ventures/`) |
| **personal/** | Personal OS | Journal, goals, identity (`~/enter_thebrana/personal/`) |

## Rules

- **Never edit `~/.claude/` directly** — edit `system/` (plugin loads it) or re-run `./bootstrap.sh` (identity layer)
- Changes propagate: dimension → reflection → roadmap (`/brana:maintain-specs`)
- Spec changes push to implementation (`/brana:reconcile`)
- Implementation changes update docs in the same commit (no separate back-propagation step)
- When adding new docs, update `docs/README.md`
- Ruflo namespaces: `specs` · `decisions` · `knowledge` (use `namespace: "all"` for cross-namespace search)
- After any code change, run the relevant test suite before marking the task done.

## Field Notes

### 2026-04-14: Errata sequential IDs unsafe under parallel sessions
Two worktrees both wrote E142 for different findings before merging — required 2 fix commits to untangle. Sequential numbers are safe for single-threaded append but break under parallel branches. Fix tracked as E153: use timestamp-based IDs (E2026-0414-1) to make collisions structurally impossible.
Source: close session 2026-04-14 / debrief-analyst

### 2026-04-20: Hook bugs come in pairs — pattern match + directory resolution
When fixing a hook's command-pattern matcher (e.g. `*"git commit"*` never matching `git -C <path> commit`), always audit the directory-resolution code immediately after. Both branch-verify.sh and main-guard.sh had the same dual failure: wrong glob AND `git -C "$CWD"` using the portfolio parent instead of the target repo. Fix: extract LOOKUP_DIR via sed from the `-C` flag and use it for all git operations. t-1310 tracks factoring this into a shared lib.
Source: close session 2026-04-20 / t-1153

### 2026-04-20: set -e + ((N++)) silently exits on zero counter
`((0++))` returns exit code 1 in bash arithmetic context. Under `set -e` this terminates the script on the very first `fail()` or `warn()` call when the counter starts at zero — no error message, just silent truncation. validate.sh was skipping Checks 23/24 entirely. Fix: always use `(( N++ )) || true` for counters in scripts using `set -e`.
Source: close session 2026-04-20 / validate.sh CVE work

### 2026-04-20: Sentinel file = clean bypass for procedure-authorized PreToolUse gates
When a PreToolUse hook blocks writes (e.g. `feedback-gate.sh` blocks `feedback_*.md`), but a procedure legitimately needs those writes: create `/tmp/brana-<context>-active` before the writes, gate checks `[ -f /tmp/... ]` and passes through, procedure removes sentinel after. Env vars don't work — CC hook subprocesses can't inherit CC's env vars. Sentinel is short-lived, scoped, and auditable.
Source: close session 2026-04-20 / feedback-gate conflict fix

### 2026-04-20: Auto-generated reference docs — fix upstream not output
`docs/reference/hooks.md` has a `Generated by brana reference generate — do not edit manually` banner. Manual edits are silently overwritten on next generation. Always grep for the banner before editing any file under `docs/reference/`. Fix must go to the generator source (e.g. `system/cli/rust/crates/brana-cli/src/commands/reference.rs`) or to the source hook script's header comment.
Source: close session 2026-04-20 / hooks.md manual edit overwritten

### 2026-04-20: CC PreToolUse continue:false stops agent loop, not just the tool
When a Write call is in a skill's `allowed-tools`, a PreToolUse hook returning `continue:false` does NOT prevent the write from executing — the file is still created. But the agent loop stops and Claude cannot continue. The sentinel fix is still required: with the sentinel, the hook returns `continue:true` and the loop continues normally.
Source: close session 2026-04-20 / feedback-gate sentinel behavior observed

### 2026-04-20: Merged worktrees accumulate — reap at session start not end
`/brana:close` does not prune worktrees. Starting a session with 4 merged worktrees cost ~5 min of orientation. Sitrep now surfaces them; next step is auto-reap in close (t-1315). Until then: `git branch --merged main` + `git worktree remove` at session start.
Source: close session 2026-04-20 / sitrep cleanup

### 2026-04-20: Verify task status via git log before implementing
`tasks.json` lags code state when `/brana:close` was skipped. Before starting any queued task: `git log --all --oneline -S '<key-symbol>'` or `git log --oneline | grep "t-NNN"`. Found t-1313/t-1314 already shipped — saved ~30 min.
Source: close session 2026-04-20 / t-1313 pre-verification

### 2026-04-20: Hook wave transition requires test audit, not just implementation
When flipping a hook from advisory (continue:true) to blocking (continue:false), grep `tests/hooks/` for the hook name and audit every assertion. Loose text-match assertions silently pass with the wrong `continue` value — only explicit `assert_contains '"continue".*false'` catches the regression.
Source: close session 2026-04-20 / feedback-gate t-1312

### 2026-04-22: filter predicates — raw field match only, never classify() output
`filter_tasks(status=...)` in `brana-core/src/tasks.rs` must compare the raw `task.status` field against the CLI `TaskStatus` enum value. It must **not** compare `classify()` output, which returns display synthetics (`done`/`active`/`blocked`/`parked`) that no user-facing enum exposes. Bug t-1323 silently contaminated every `brana backlog query --status completed|cancelled|in_progress` result with 40/96 incorrectly-matched items because `classify() != enum_input` was always true. Rule: any filter predicate compares **raw stored values**; computed/display values go in a post-hoc `retain` after the primary filter (see `cmd_next` — applies `classify(t) == "pending"` post-hoc to exclude blocked/parked).
Source: triage session 2026-04-22 / t-1323

### 2026-05-06: grep -E \| is NOT alternation — bare | required in ERE
In `grep -E` (ERE), alternation is bare `|`. Writing `\|` in ERE matches a literal pipe character. This is opposite of BRE where `\|` is alternation. Test assertions using `grep -qE "a\|b"` always fail (or behave unexpectedly). Use `grep -q "a"` and `grep -q "b"` separately, or `grep -qE "a|b"` with bare pipe.
Source: close session 2026-05-06 / test-backlog-plan-tdd-gate.sh assertions

### 2026-05-06: Full unstage = git restore --staged + git checkout
`git checkout -- <file>` restores the working tree from HEAD but does not clear the index. If a file is staged, it remains staged. To fully discard: `git restore --staged <file> && git checkout -- <file>`, or the single combined form `git restore --source=HEAD --staged --worktree <file>`.
Source: close session 2026-05-06 / sdd-tdd.md budget revert

### 2026-05-06: Statusline line 2 always exists — assert segment content, not line existence
The brana statusline `+N -N` lines-changed segment is added unconditionally via `add_l2` regardless of slow-cache availability. Line 2 is always emitted when there are git line changes. Knowledge freshness and corrections segments on line 2 are conditional on slow-cache. Test assertions must check what each line contains, not whether a line exists.
Source: close session 2026-05-06 / t-1084 statusline two-line test

### 2026-05-08: Bootstrap restart sentinel — /tmp file bridges bootstrap→session-start
`bootstrap.sh` now creates `/tmp/brana-bootstrap-pending-restart` after any hook config change. `session-start.sh` checks for it at startup, emits `[Bootstrap] Previous bootstrap changed hooks — restart CC to activate.` in `additionalContext`, then removes the file. This is a one-shot notification — cleared on the first CC start after bootstrap, regardless of whether the user acts on it. Pattern: use `/tmp/brana-*-pending-*` sentinels for any cross-invocation signaling; env vars don't work (CC hook subprocesses can't inherit CC env).
Source: t-1366 / 2026-05-08
