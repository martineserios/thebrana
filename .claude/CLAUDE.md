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
- Changes propagate: dimension → reflection → roadmap (run `/brana:reconcile --scope propagation` to check for drift)
- Spec changes push to implementation (`/brana:reconcile`)
- Implementation changes update docs in the same commit (no separate back-propagation step)
- When adding new docs, update `docs/README.md`
- Ruflo namespaces: query `knowledge` + `pattern` in parallel (use `namespace: "all"` only with `threshold: 0.55` in v3.6 — session records score constant 0.5 and contaminate below that). `specs` namespace is unindexed — skip.
- After any code change, run the relevant test suite before marking the task done.
- Use `.claude/CLAUDE.local.md` (gitignored) for personal/machine-specific overrides — loaded last, wins on conflict. Never commit it.

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

### 2026-05-17: User-level settings.json hook schema requires "command" string, not args[]
CC user-level `~/.claude/settings.json` validates hook entries with `command` (string) only. Attempting `"args": ["bash", "script.sh"]` returns `hooks.X.0.hooks.0.command: Expected string, but received undefined`. The exec-form `args[]` is supported only in plugin `hooks.json` files, not in user settings. Fix: use `"command": "bash /absolute/path/to/script.sh"` in settings.json. Plugin hooks.json supports both forms.
Source: t-1417 / 2026-05-17

### 2026-05-08: Bootstrap restart sentinel — /tmp file bridges bootstrap→session-start
`bootstrap.sh` now creates `/tmp/brana-bootstrap-pending-restart` after any hook config change. `session-start.sh` checks for it at startup, emits `[Bootstrap] Previous bootstrap changed hooks — restart CC to activate.` in `additionalContext`, then removes the file. This is a one-shot notification — cleared on the first CC start after bootstrap, regardless of whether the user acts on it. Pattern: use `/tmp/brana-*-pending-*` sentinels for any cross-invocation signaling; env vars don't work (CC hook subprocesses can't inherit CC env).
Source: t-1366 / 2026-05-08

### 2026-05-19: build.md step 4a — SKILL.md `keywords` field is the tech-domain gate
Step 4a now uses a deterministic 3-signal chain (task description/tags → project manifest files → file path extensions) to detect tech context, then matches installed skills by their SKILL.md `keywords` field. Gate fires only when no LOAD result key overlaps with the matched skill's keywords — meaning the skill knowledge was absent from LOAD despite the domain being relevant. A Rust task in a `Cargo.toml` project that produced only documentation-pattern LOAD results will now always prompt for `rust-skills`, regardless of whether ruflo returned non-empty results. If the user skips: `skill-gap-warning: {skill} available but not loaded` is appended to the task context, auditable via `brana backlog search "skill-gap-warning"`. This is an interim patch — the SUNSET comment in build.md step 4a references t-608 (Skill Registry), which replaces the entire detection chain with `skill_suggest(tech_context)` when it ships.
Source: t-1479 + t-1483 / 2026-05-19

### 2026-05-20: DoD grep for schema removals must be re-executed at close — not just stated
Stated grep is not executed grep. t-1564 fixed backlog_add.rs stream injection per the errata scope but the DoD grep (`grep -rn '"stream"' system/cli/rust/crates/`) was not re-run before closing. Debrief-analyst found feed.rs:298 still injecting `"stream": "research"` — filed as E2026-05-20-9. Rule: for any schema-field-removal task, the final step is running the grep and reviewing every remaining hit. If hits remain: fix in-scope or file child errata before close.
Source: t-1564 / debrief-analyst 2026-05-20

### 2026-05-20: Field removal — grep ALL crates fresh; errata scope ≠ grep scope
For schema field removal, the grep scope must be all crates (`grep -rn '"<field>"' system/cli/rust/crates/`), not just the surfaces named in the errata. t-1564 named backlog_add.rs; feed.rs:298 was a sibling producer in a different command crate — same injection pattern, not in scope, not grepped again. Survived as E2026-05-20-9. 5-surface checklist (core + cli + mcp-add + mcp-stats + tests) is a minimum, not a maximum. Grep bounds the scope.
Source: t-1564 / debrief-analyst 2026-05-20

### 2026-05-20: Squash-merge is wasteful for single-commit S features — use --ff-only after rebase
When a feature branch has exactly one commit (S effort, no WIP history worth preserving), `git merge --no-ff` produces a duplicate-message commit pair on main: the original commit + a merge commit with the same subject. Instead: `git rebase main && git merge --ff-only <branch>` — produces a single clean commit on main with no merge commit. Reserve `--no-ff` for multi-commit branches where the merge envelope documents the batch.
Source: session debrief 2026-05-20

### 2026-05-24: Cross-crate migration — re-export at wrapper boundary for call-site continuity
When moving a function from a thin wrapper crate (e.g. brana-cli) to a core crate (e.g. brana-core), sibling modules (e.g. main.rs) that called it via `commands::module::fn_name` will break at compile time. Fix: add `pub use brana_core::module::fn_name;` in the wrapper module as a re-export. After any cross-crate function migration, grep all sibling call sites — not just the module you refactored.
Source: t-1637 / debrief-analyst 2026-05-24

### 2026-05-24: Skill tool uses bare name, not brana: prefix (SUPERSEDED — see 2026-05-24 fix below)
`Skill("close")` works; `Skill("brana:close")` fails with "Unknown skill." Skills registered under the `brana` plugin namespace are invoked with the bare name in the Skill tool even though the slash-command form is `/brana:close`. When Skill tool fails, fall back to reading SKILL.md + the linked procedure file directly.
Source: t-1637 session close 2026-05-24

### 2026-05-24: plugin.json missing "skills" field — Skill() tool couldn't find brana skills (FIXED t-1671)
Root cause: `system/.claude-plugin/plugin.json` had no `"skills"` or `"commands"` field. The available-skills system-reminder IS populated (via SKILL.md scanning), but the Skill() tool routing requires the field in plugin.json. Fix: added `"skills": "./skills/"` and `"commands": ["./commands/repo-cleanup.md"]`. Cache synced at `~/.claude/plugins/cache/brana/brana/1.0.0/.claude-plugin/plugin.json`. **Requires CC restart to activate.** After restart, invocation form is `Skill("brana:close")` (namespace-prefixed). Bare `Skill("close")` behavior unconfirmed.
Source: t-1671 / 2026-05-24

### 2026-05-24: Edit closing-brace anchor — use full last-test context, not bare `}` lines
In Rust test modules, inserting content before closing `}` blocks by matching just `}\n}` hits multiple locations. Fix: use the closing assertion of the last test plus both closing braces as the `old_string` anchor — provides enough unique context for a single match. Applies to any Rust file with uniform brace patterns.
Source: t-1637 / debrief-analyst 2026-05-24

### 2026-05-24: Invariants belong in the write function, not at the call site
When a field has a semantic invariant that must hold after every write (e.g. `consumed_at = None`), enforce it inside the write function, not by requiring every caller to set it. The CLI surface cleared `consumed_at` before calling `write_state` but the MCP surface missed it (E2026-05-24-5). Rule: invariants enforced at call sites are fragile across surfaces; enforce at the single canonical write path.
Source: t-1637 / debrief-analyst 2026-05-24

### 2026-05-25: Scheduler skill jobs spawn full CC processes — OOM guard required
`brana-scheduler-runner.sh` runs skill-type jobs (`knowledge-decay`, `weekly-review`, `knowledge-review`) via `claude -p "$PROMPT"`, each spawning a full CC process (~350MB) plus its own ruflo MCP instance (~70MB). Before `d712f95` there was no concurrency guard — the scheduler fired unconditionally regardless of active CC sessions. On a 14GB machine with Firefox (~3GB) and 3–4 active CC sessions already open, the 5th scheduler-spawned CC triggered OOM kill and terminal crash. Fix: skill jobs now skip when `pgrep -fc "claude --plugin-dir" ≥ 2` or `MemAvailable < 3GB`. Rule: any subsystem that spawns `claude -p` must gate on session count + available RAM. Diagnostic: the scheduler log at `system/scheduler/logs/<job-name>/` is the canonical record of what ran and when — read it first when investigating scheduler-related OOM.
Source: E2026-05-25-1 / debrief-analyst 2026-05-25

### 2026-05-25: agy version pin upgrade protocol
* The agy binary version pin (`AGY_PINNED_VERSION` in [agy_delegate.rs](file:///home/martineserios/enter_thebrana/thebrana/system/cli/rust/crates/brana-mcp/src/tools/agy_delegate.rs)) must be updated in the same commit as upgrading the agy binary.
* This Rust MCP server (`brana-mcp`) wraps the agy CLI (Gemini Flash worker) and uses the version pin to prevent running against untested CLI versions.
* If the pin lags behind the installed binary, every `mcp__brana__agy_delegate` call will hard-error.
* Upgrades to the agy CLI must always pair with a corresponding update to `AGY_PINNED_VERSION` in the same commit.
Source: operational finding / 2026-05-25

### 2026-05-25: Rust char-boundary-safe string slicing — use char_indices().nth(N)
`&s[..N]` is a **byte** index, not a character index. Panics immediately on any multi-byte codepoint at or near position N (em dash `—` = 3 bytes, accented chars = 2 bytes). The correct "first N characters" bound: `s.char_indices().nth(N).map(|(i, _)| i).unwrap_or(s.len())`. Applies to any string truncation by character count. Caught on first real unicode input in session_initiative.rs learning dedup (60-char prefix key). Transferable to all Rust projects handling user text.
Source: Fix C session_initiative.rs / debrief-analyst 2026-05-25

