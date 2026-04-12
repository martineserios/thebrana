# Hooks Architecture

> 10 shell scripts that fire on Claude Code lifecycle events. Hooks enforce discipline, log events, and nudge agents -- all without requiring user action. For complete I/O specs, see [Hook Reference](../reference/hooks.md).

## How hooks work

Claude Code supports five hook events:

| Event | When it fires | Can block? |
|-------|---------------|------------|
| `SessionStart` | Beginning of every session | No |
| `SessionEnd` | End of every session | No |
| `PreToolUse` | Before a tool call executes | Yes |
| `PostToolUse` | After a tool call succeeds | No |
| `PostToolUseFailure` | After a tool call fails | No |

Hooks receive session context as JSON on stdin, return JSON on stdout. A hook can pass through (`{"continue": true}`), inject context (`additionalContext`), or block (PreToolUse only, via `permissionDecision: "deny"`).

All brana hooks follow a safety principle: they never fail fatally. Every hook uses `|| true` fallbacks and graceful degradation.

## Plugin/bootstrap split (CC bug #24529)

CC v2.1.x silently drops PostToolUse and PostToolUseFailure events from plugin `hooks.json`. Only PreToolUse, SessionStart, and SessionEnd fire reliably from plugins.

| Installed via | Events | File |
|--------------|--------|------|
| Plugin `hooks.json` | PreToolUse, SessionStart, SessionEnd | `system/hooks/hooks.json` |
| Bootstrap `settings.json` | PostToolUse, PostToolUseFailure | `~/.claude/settings.json` |

When CC fixes #24529, all hooks move back to `hooks.json`. See [PostToolUse Workaround](posttooluse-workaround.md) for details.

## Shared library

**`lib/cf-env.sh`** -- Locates the `ruflo` binary. Source it to get `$CF`. Search order: nvm global install, PATH lookup, npx fallback. Used by session-start, session-end, session-start-venture, and post-sale hooks.

**`lib/ruflo-mcp.sh`** -- MCP server wrapper script that resolves the ruflo binary dynamically at launch time instead of hardcoding paths. Includes a PID lock (prevents concurrent SQLite corruption) and auto-restart on SIGTERM (up to 5 retries, mitigates CC bug #40207 which kills healthy MCP servers mid-session). `brana-mcp` uses a direct binary path in `.mcp.json` — no wrapper needed.

**`config-drift.sh`** -- Called by `session-start.sh` at every session start. Compares `system/` source files against deployed `~/.claude/` files (CLAUDE.md + rules/) and scans `~/.claude.json` for ADR-033 violations (npx/uvx in MCP server commands). Output JSON: `{status, count, drifted[], mcp_violations[], mcp_count}`. Any violations surface in `DRIFT_CONTEXT` at session start.

## Hook inventory

### Plugin hooks (hooks.json)

| Hook | Event | Matcher | Purpose |
|------|-------|---------|---------|
| `pre-tool-use.sh` | PreToolUse | `Write\|Edit` | Spec-before-code gate + cascade throttle |
| `tdd-gate.sh` | PreToolUse | `Write\|Edit` | TDD baseline — blocks impl writes when no test exists in project. Ordering enforcement (tests before impl) lives in procedure gates, not here |
| `plan-mode-gate.sh` | PreToolUse | `EnterPlanMode` | Enforce plan mode for non-trivial builds |
| `worktree-gate.sh` | PreToolUse | `Bash` | Gate A: block `git checkout -b` / `git switch -c` when dirty or worktrees active. Gate B: block `git commit` when /tmp >95% full; warn on cross-session staged files |
| `branch-verify.sh` | PreToolUse | `Bash` | Block `git add` of behavioral files when on main/master. Extracts `git -C <path>` from command to check target repo's branch (worktree-aware). Escape hatch: `# --force-main` comment |
| `guard-explore.sh` | PreToolUse | `Read\|Grep\|Glob` | Log reads without prior search (logging only, no blocking) |
| `subagent-context.sh` | SubagentStart | `""` (all) | Inject active task + branch + plan + recent decisions into spawned agents |
| `subagent-tracker.sh` | SubagentStart+SubagentStop | `""` (all) | Track agent spawns and completions to session JSONL |
| `step-completed.sh` | TaskCompleted | `""` (all) | Track CC Task completions for guided execution |
| `session-start.sh` | SessionStart | `""` (all) | Pattern recall (1 parallel job, 2s budget), task context, venture detection, recurring error surfacing |
| `session-end.sh` | SessionEnd | `""` (all) | Orchestrator — forks 3 sub-scripts: `session-end-metrics.sh` (flywheel metrics), `session-end-persist.sh` (ruflo + auto-memory), `session-end-drift.sh` (sync-state, spec graph, decisions log) |
| `stopfailure-logger.sh` | StopFailure | `""` (all) | Log API errors (rate limit, auth, billing) to JSONL |

### Bootstrap hooks (settings.json)

| Hook | Event | Matcher | Purpose |
|------|-------|---------|---------|
| `post-tool-use.sh` | PostToolUse | `Write\|Edit\|Bash` | Log successes, detect corrections and test writes |
| `post-tool-use-failure.sh` | PostToolUseFailure | `Write\|Edit\|Bash` | Log failures, detect cascades (3+ consecutive), track error recurrence across sessions |
| `post-plan-challenge.sh` | PostToolUse | `ExitPlanMode` | Nudge challenger agent after plan finalization |
| `post-tasks-validate.sh` | PostToolUse | `Write\|Edit` | Validate tasks.json schema + auto-rollup parents |
| `post-sale.sh` | PostToolUse | `Write\|Edit` | Detect deal closures in pipeline files |
| `post-pr-review.sh` | PostToolUse | `Bash` | Nudge pr-reviewer agent after `gh pr create` |

### Inactive

| Hook | Status |
|------|--------|
| `session-start-venture.sh` | Logic absorbed into `session-start.sh`. Kept for reference. |

## Hook profiles

Hooks support tiered execution via the `BRANA_HOOK_PROFILE` environment variable. This allows running lighter hook sets in contexts where speed matters more than full enforcement.

| Tier | What runs | Effort level | Use case |
|------|-----------|-------------|----------|
| `minimal` | Nothing (all profiled hooks skip) | `max` | Fast CI runs, debugging hook issues |
| `standard` | `pre-tool-use.sh`, `worktree-gate.sh` | `high` | Default — production behavior, backward compatible |
| `strict` | All standard + `guard-explore.sh` | `low` | Observation mode — collects read pattern data |

**Default:** `standard` (no env var needed, no behavior change from pre-profile state).

**Set it:** `export BRANA_HOOK_PROFILE=strict` in your shell, or add to `~/.claude/settings.json` env section.

**Effort level:** Each tier maps to a CC effort level via `get_profile_effort()`. Exported as `BRANA_EFFORT_LEVEL` at session start. Agents override via frontmatter `effort:` field; users override with `/effort`. Direct override: `export BRANA_EFFORT_LEVEL=medium`.

**Library:** `system/hooks/lib/profile.sh` provides `hook_should_run <tier>` and `get_profile_effort`. Any hook can source it:

```bash
source "${SCRIPT_DIR}/lib/profile.sh" 2>/dev/null || true
hook_should_run "standard" || { pass_through; exit 0; }
```

Only 3 hooks use profiles today. Hooks without profile gates (session-start, session-end, subagent-context, etc.) always run regardless of tier.

## Guard-explore (read pattern observability)

`guard-explore.sh` fires on every `Read`, `Grep`, and `Glob` call. It tracks whether agents search before reading implementation files — a quality signal from Agentic Scripts research (80% tool call reduction with search-first patterns).

**Current mode: logging only.** No blocking. After 1 week of data collection, enforcement can be enabled.

**How it works:**
1. **Grep/Glob calls** — recorded to `/tmp/brana-search-{SESSION_ID}.log`
2. **Read calls on impl files** (`src/`, `lib/`, `system/cli/`, `system/scripts/`) — checks if any search preceded it. If not, logs to `/tmp/brana-explore-{SESSION_ID}.log`
3. **Whitelisted files** always pass through: `*.md`, configs (`*.json`, `*.yaml`, `*.toml`), test files, `docs/`, `.claude/`, `system/skills/`, `system/hooks/`

**Analyzing results:** After a week, review `/tmp/brana-explore-*.log` files to see how often reads happen without searches. High counts indicate search-first enforcement would reduce wasted tool calls.

## Subagent context injection

`subagent-context.sh` fires on every `SubagentStart` event. Every scout, explorer, and delegated agent automatically receives context about the current work state — no manual briefing needed.

**What gets injected** (via `additionalContext`, capped at ~500 tokens):

| Data | Source | When included |
|------|--------|---------------|
| Active task (id, subject, strategy, build_step, tags) | `brana backlog query --status in_progress` | Always (if a task is active) |
| Current git branch | `git branch --show-current` | Always (if in a git repo) |
| Active plan title | First `*.md` in `~/.claude/plans/` | Only during plan mode |
| Last 3 decisions | `system/state/decisions/*.jsonl` (most recent) | Only if decision log exists |

If no in_progress task exists, the hook returns `{"continue": true}` with no injection — subagents start clean.

## Ruflo wiring in hooks

As of 2026-04-01, three hook scripts integrate with ruflo MCP via `cf-env.sh`:

- **`session-start.sh`** — Runs 1 parallel job (single `timeout 2` ruflo CLI query for patterns + corrections), down from 4 jobs with a 5s budget. Python dependencies (spec-graph staleness check, decisions.py) removed. Phase 5 launches `index-skills.sh --changed` in background. All `$CF` calls are preceded by `cd "$HOME"` to avoid CWD issues with npx resolution. As of 2026-04-06, also surfaces the next unblocked task's `context` field in the task summary output. As of 2026-04-08 (t-1034), reads `~/.claude.json` for `cachedExtraUsageDisabledReason` and emits `[Extra-usage]` warning when set — CC caches extra-usage state there, and if it's disabled at the org level, 1M-context models fail around the 200k-token mark mid-skill. Silence: `BRANA_1M_WARN_OFF=1`.
- **`session-end.sh`** — Same `cd "$HOME"` guard before `$CF` calls for metrics flush and session summary storage.
- **`post-sale.sh`** — Uses `cd "$HOME"` before ruflo CLI calls (fixed 2026-04-06 — previously used CWD-relative path, writing to wrong DB).
- **`cf-env.sh`** — Now exports a `cf_run()` wrapper function that handles `cd "$HOME"`, timeout, and error swallowing in one call. Hook scripts use `cf_run <args>` instead of raw `$CF` invocations.

## Design principles

**Spec-first enforcement** -- `pre-tool-use.sh` is the strongest feedback mechanism (a "Stop hook"). A PERMISSION DENY cannot be ignored. Projects opt in by having `docs/decisions/`.

**Session event pipeline** -- PostToolUse/PostToolUseFailure hooks append JSONL events to `/tmp/brana-session-{SESSION_ID}.jsonl`. The session-end hook consumes this file, computes 7 flywheel metrics (correction_rate, auto_fix_rate, test_write_rate, cascade_rate, test_pass_rate, lint_pass_rate, delegation_count), and persists to ruflo memory.

**Immediate response pattern** -- `session-end.sh` responds with `{"continue": true}` immediately, then forks heavy processing to background. CC cancels hooks during session teardown, so the response must come before any processing.

**Cascade detection** -- `post-tool-use-failure.sh` tracks consecutive failures on the same target. At 3+ failures, it flags a cascade so `pre-tool-use.sh` can inject a warning on the next attempt.

**Error recurrence tracking (t-679)** -- `post-tool-use-failure.sh` computes an error signature (md5 of tool_name + error_cat + first 80 chars of detail) and increments a counter in `~/.claude/logs/error-recurrence.jsonl`. When the same signature hits 3 occurrences across sessions, it stores to ruflo memory with tag `escalate:rule-candidate`. `session-start.sh` scans the recurrence file and surfaces errors with count >= 3 as "[Recurring errors -- rule/hook candidates]" in session context.

**Agent nudging** -- Several hooks inject `additionalContext` that triggers auto-delegation to agents: post-plan-challenge (challenger), post-pr-review (pr-reviewer), session-start (daily-ops for venture projects).

## Hook registration format

Plugin hooks use `${CLAUDE_PLUGIN_ROOT}` for paths:

```json
{
  "hooks": [
    {
      "event": "PreToolUse",
      "matcher": "Write|Edit",
      "command": "${CLAUDE_PLUGIN_ROOT}/hooks/pre-tool-use.sh",
      "timeout": 5000
    }
  ]
}
```

Bootstrap hooks use absolute paths in `~/.claude/settings.json`:

```json
{
  "hooks": {
    "PostToolUse": [
      {
        "matcher": "Write|Edit|Bash",
        "hooks": [
          { "type": "command", "command": "$HOME/.claude/hooks/post-tool-use.sh", "timeout": 5000 }
        ]
      }
    ]
  }
}
```

Multiple hooks can register for the same event. They run sequentially; if any PreToolUse hook blocks, the tool call is denied.

## Field Notes

### 2026-04-08: Defensive retry loops in MCP wrappers are net-negative
Background+restart logic added to `ruflo-mcp.sh` to survive CC's SIGTERM bug (#40207) never recovered in practice — `/mcp` was always the real recovery path. Worse, backgrounding silently broke stdin forwarding. Rule: if manual recovery is already documented, don't add an auto-retry — it creates hidden risk with no upside.
Source: t-1083

### 2026-04-08: Pre-flight warnings template for env constraints
When a deterministic failure condition is readable from a config file (e.g., `cachedExtraUsageDisabledReason` in `~/.claude.json`), surface it at session-start with: (a) what's wrong, (b) what breaks, (c) exact fix command, (d) opt-out env var. Implemented in `session-start.sh` for 1M context + disabled extra-usage (t-1034).
Source: t-1034

### 2026-04-09: Canonical CC hook event names
Full list of valid hook event names: `PreToolUse`, `PostToolUse`, `PostToolUseFailure`, `SessionStart`, `SessionEnd`, `SubagentStart`, `SubagentStop`, `TaskCompleted`, `StopFailure`. The failure event is `PostToolUseFailure` (not `ToolError` or `PostToolFailure`). Wire failure telemetry hooks under `PostToolUseFailure` with matcher `""`.
Source: /brana:reconcile --scope consistency, 2026-04-09

### 2026-04-12: worktree-gate now handles both `git checkout -b` and `git switch -c` (t-1120/t-1126)
Both commands create branches and are intercepted. Fix: strip quoted string args from command before detection (`CMD_UNQUOTED` via sed) to prevent false positives (e.g., `brana backlog add --json '{"description":"fix git switch -c"}'` no longer triggers the gate). Error messages now cite the actual command used (`git switch -c` errors say `git switch -c`, not `git checkout -b`). 10/10 tests pass. Hook JSON path for deny: `.hookSpecificOutput.permissionDecision` (not `.permissionDecision`).
Source: t-1120, t-1126 (2026-04-12)

### 2026-04-12: nvm PATH glob for scheduler scripts
Non-interactive shells (systemd, cron) don't source nvm, so `node` and `ruflo` binaries are missing from PATH. Sourcing full `nvm.sh` is slow and fragile. Reliable fix — 3 lines at top of any scheduler script needing node/ruflo:
```bash
for _nvm_bin in "$HOME"/.nvm/versions/node/*/bin; do
    [ -x "$_nvm_bin/node" ] && export PATH="$_nvm_bin:$PATH" && break
done
```
Validated in `system/scripts/feed-ruflo-index.sh` (t-1138).
Source: t-1138

### 2026-04-10: doc-gate blocks the entire Bash command, including pre-commit git add
When `git add <files> && git commit -m "..."` is in a single Bash call and the PreToolUse doc-gate blocks the commit, the `git add` also never runs — the hook fires before the entire shell command executes. Pattern: always stage files in a SEPARATE Bash call, then commit in a second call. The add call never triggers doc-gate; only the commit does.
Source: t-1109, 2026-04-10

### 2026-04-10: `git checkout HEAD -- <file>` is the reliable recovery form
After a failed `git stash pop` leaves a file in merge-conflict state, `git restore <file>` and bare `git checkout -- <file>` both fail. `git checkout HEAD -- <file>` succeeds because it explicitly names the commit. In recovery scenarios, always use the explicit HEAD form.
Source: t-1109, 2026-04-10

### 2026-04-10: Bash tool branch switches are invocation-ephemeral
`git switch -c <branch>` succeeds in one Bash call but subsequent calls revert to the previous branch — each invocation runs in a fresh subshell. Rule: after any branch create/switch, the VERY NEXT Bash call must be `git branch --show-current`. Do NOT stage or commit until branch is confirmed. Violated 3 times — feature work landed on main before main-guard caught it.
Source: t-1075

### 2026-04-10: main-guard + doc-gate is the strongest branch discipline combo
Two hooks in sequence reliably catch two distinct failure modes: doc-gate catches behavioral changes without documentation, main-guard catches behavioral commits on the wrong branch. Both fired correctly this session and blocked the commit before it persisted. Keep both hooks active.
Source: t-1075

### 2026-04-10: tasks.json stash-pop conflicts — always --theirs
`.claude/tasks.json` is machine-generated, 5900+ lines, changes every session. It will always conflict on `git stash pop` across branches. Resolution: `git checkout --theirs .claude/tasks.json && git add .claude/tasks.json`. The stash version (from main) is always the authoritative state.
Source: t-1075

### 2026-04-10: worktree-gate has two gates, not one
`worktree-gate.sh` intercepts ALL git commands via PreToolUse on Bash. Gate A (branch enforcement) fires on `git checkout -b` / `git switch -c` and blocks when dirty or worktrees active. Gate B (commit safety) fires on `git commit`: blocks if /tmp >95% full (prevents silent ENOSPC), warns if staged files weren't written in this session (cross-session displaced file detection). These are distinct concerns sharing one hook to minimize hook overhead. Error messages identify which gate fired.
Source: t-1075, t-1120, t-1126 (2026-04-12)

### 2026-04-12: Session handoff next[] items can be stale
Session state is written at close and read at session start — hours or days may pass. Items like "9 stale stashes" or "N pending X" reflect state at write time, not now. Always verify counts before acting (e.g., `git stash list`, `brana backlog query --status pending`). Don't assume handoff claims are current.
Source: maintenance session 2026-04-12

### 2026-04-12: Branch-checking hooks must follow `git -C <path>`, not session CWD
`branch-verify.sh` was checking `CWD` (the session working directory) to determine the git root and branch. When work is done via `git -C <worktree-path> add <files>`, the session CWD is the main repo (on `main`) — the hook falsely blocked. Fix: extract the `-C <path>` argument from the git command and use it as the lookup directory, falling back to CWD only when absent. This pattern applies to any hook that inspects git branch state (`main-guard.sh` has the same bug — tracked). Escape hatch: `# --force-main` as a bash comment (hook greps the full command string, bash ignores comments).
Source: t-1078, branch-verify-worktree-fix (2026-04-12)

### 2026-04-12: `cd <worktree> && git add` still triggers session-CWD hooks
PreToolUse hooks fire before the shell command executes. Even `cd ../repo-worktree && git add file` presents the session CWD (main repo root, branch `main`) to the hook — the `cd` never runs first. The `-C <path>` extraction in `branch-verify.sh` only helps when the command literally contains `git -C <path>`, not when `cd` is used. Escape hatch: `# --force-main` comment in the Bash call.
Source: t-1147 session 2026-04-12

### 2026-04-12: Mock PATH isolation — bash + minimal tools must be in mock bin
When testing bash scripts with a stripped PATH (to simulate missing tools), stripping PATH to just the mock dir causes "bash: command not found" when the script calls `bash <subscript>` or uses `dirname`/`pwd` for SCRIPT_DIR detection. Fix: symlink bash, dirname, and pwd from the system into the mock bin, then exclude only the specific tool being hidden. A `populate_bin <dir> [exclude...]` helper makes this reusable across tests. Rule: never strip PATH to only `$mock/bin` without first populating the tools the script needs to boot.
Source: tests/bootstrap/test-install.sh, t-1150 2026-04-12
