# Hooks Architecture

> 25+ shell scripts that fire on Claude Code lifecycle events. Hooks enforce discipline, log events, and nudge agents -- all without requiring user action. For complete I/O specs, see [Hook Reference](../reference/hooks.md).

## How hooks work

Claude Code supports these hook events:

| Event | When it fires | Can block? |
|-------|---------------|------------|
| `SessionStart` | Beginning of every session | No |
| `SessionEnd` | End of every session | No |
| `PreToolUse` | Before a tool call executes | Yes |
| `PostToolUse` | After a tool call succeeds | No |
| `PostToolUseFailure` | After a tool call fails | No |
| `UserPromptSubmit` | Before Claude processes user input | No |
| `SubagentStart` | When a subagent is spawned | No |
| `SubagentStop` | When a subagent completes | No |
| `TaskCompleted` | When a CC Task is marked complete | No |
| `StopFailure` | On API errors (rate limit, auth, billing) | No |
| `ConfigChange` | When a settings file is modified in-session | Yes (exit 2) |
| `PreCompact` | Before context compaction runs | Yes (exit 2 or `{"decision":"block"}`) |

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

**`lib/git-helpers.sh`** -- Shared utilities for hooks that inspect git branch state. Provides `extract_git_c_dir()` (path from `git -C <path>`), `extract_cd_prefix_dir()` (path from a leading `cd <path> &&` / `;` / `||`), and `resolve_lookup_dir()` (3-tier lookup: `-C` > `cd` prefix > CWD). Sourced by `branch-verify.sh` and `main-guard.sh`. Prevents hooks from checking the session CWD instead of the target repo when CC issues either `git -C <worktree> …` or `cd <worktree> && git …` commands. Spec: `system/hooks/lib/git-helpers.spec.md`.

**`lib/layer1-paths.sh`** -- Layer 1 file classification. Provides `is_layer1_file()` that returns 0 for files that must never be LLM-written (currently: any path ending in `CLAUDE.md`). Sourced by `feedback-gate.sh`. Centralizes the Layer 1 boundary so all enforcement hooks stay in sync when the definition expands.

## Hook inventory

### Plugin hooks (hooks.json)

| Hook | Event | Matcher | Purpose |
|------|-------|---------|---------|
| `pre-tool-use.sh` | PreToolUse | `Write\|Edit` | Spec-before-code gate + cascade throttle |
| `tdd-gate.sh` | PreToolUse | `Write\|Edit` | TDD baseline — blocks impl writes when no test exists in project. Ordering enforcement (tests before impl) lives in procedure gates, not here |
| `plan-mode-gate.sh` | PreToolUse | `EnterPlanMode` | Enforce plan mode for non-trivial builds |
| `worktree-gate.sh` | PreToolUse | `Bash` | Gate A: block `git checkout -b` / `git switch -c` when dirty or worktrees active — **exception**: if the only dirty file is `.claude/tasks.json`, emits a warn (continue:true) instead of deny (t-1320). Gate B: block `git commit` when /tmp >95% full; warn on cross-session staged files |
| `doc-gate.sh` | PreToolUse | `Bash` | Block `git commit` on any branch when behavioral files (skills, hooks, agents, commands, cli, rules) are staged but no docs change is present. Spec-before-code enforcement. |
| `main-guard.sh` | PreToolUse | `Bash` | Block behavioral commits on main/master. Forces work onto feat/fix/* branches for proper gate enforcement. Uses `lib/git-helpers.sh` → `resolve_lookup_dir()` for worktree-aware repo detection. |
| `branch-verify.sh` | PreToolUse | `Bash` | Block `git add` of behavioral files when on main/master. Uses `lib/git-helpers.sh` → `resolve_lookup_dir()` to extract `git -C <path>` from the command and check the target repo's branch. Escape hatch: `# --force-main` comment. |
| `feedback-gate.sh` | PreToolUse | `Write\|Edit` | Block writes to `feedback_*.md` files outside the auto-memory procedure. Layer 1 guard (via `lib/layer1-paths.sh`) blocks `CLAUDE.md` writes unconditionally. Sentinel bypass: `/tmp/brana-memory-active`. Spec: ADR-037. |
| `no-attribution-commit.sh` | PreToolUse | `Bash` | Block `git commit` and `gh pr create` calls containing forbidden attribution signatures (Co-Authored-By, Signed-off-by). Keeps commit history clean. |
| `commit-msg-verify.sh` | PreToolUse | `Bash` | Advisory (non-blocking): warns when commit message mentions filenames not in the staged diff. Catches commit messages that describe more than what was actually staged. |
| `guard-explore.sh` | PreToolUse | `Read\|Grep\|Glob` | Log reads without prior search (logging only, no blocking) |
| `subagent-context.sh` | SubagentStart | `""` (all) | Inject active task + branch + plan + recent decisions into spawned agents |
| `subagent-tracker.sh` | SubagentStart+SubagentStop | `""` (all) | Track agent spawns and completions to session JSONL |
| `step-completed.sh` | TaskCompleted | `""` (all) | Track CC Task completions for guided execution |
| `task-completed.sh` | PostToolUse | `Bash` | Task completion pipeline: parent task rollup, close linked GitHub issue, log to decision log. Triggers on `brana backlog set <id> status completed`. |
| `hallucination-detect.sh` | PostToolUse | `Bash` | Advisory: warns when a commit message contains completion keywords (fix/done/complete/close/resolve) but no test files were staged. Never blocks. |
| `preflight-model.sh` | UserPromptSubmit | `""` (all) | Advisory (non-blocking): warns when a heavy skill (`/brana:close`, `/brana:brainstorm`, `/brana:build`) is invoked while extra-usage is disabled. Silence: `BRANA_1M_WARN_OFF=1`. |
| `context-inject.sh` | UserPromptSubmit | `""` (all) | Advisory: detects t-NNN task IDs and file paths in the prompt. Injects task subject/description/context (max 3 IDs) and file `head -20` content (max 3 paths). Absolute, relative (resolved to project root), and `~` paths supported. |
| `signal-capture.sh` | UserPromptSubmit | `""` (all) | Advisory: detects explicit ratings (N/5, N/10, emoji) and implicit sentiment (English + Spanish phrases) in user prompts. Writes to `~/.claude/ratings/ratings.jsonl`; dumps failure context to `FAILURES/`. |
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

**CC-native effort.level (t-1402):** CC v2.1.133 adds `effort.level` to hook JSON input and `$CLAUDE_EFFORT` to Bash subprocess env. Both `session-start.sh` and `post-tool-use-failure.sh` now read this field (`jq -r '.effort.level // "normal"'`) and skip non-critical slow operations when effort is `"low"`: session-start skips the ruflo memory search; post-tool-use-failure skips the ruflo rule-candidate escalation. CC v2.1.132 added `CLAUDE_CODE_SESSION_ID` to Bash subprocess env — both hooks fall back to this env var if session_id is absent from JSON: `SESSION_ID="${SESSION_ID:-${CLAUDE_CODE_SESSION_ID:-}}"`. All local JSONL writes and cascade detection are unaffected by effort level.

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

**Enforcement vs advisory gate taxonomy (2026-05-15)** -- Every PreToolUse gate must declare its class at write time. Enforcement gates block unconditionally — bypassing them corrupts an invariant. Advisory gates reject but allow the agent loop to recover via `continueOnBlock: true`, feeding the rejection as context instead of terminating.

| Class | Gates | `continueOnBlock` |
|---|---|---|
| **Enforcement** | `tdd-gate.sh`, `main-guard.sh`, `branch-verify.sh`, `worktree-gate.sh`, `feedback-gate.sh` (Layer 1 path) | Never — hard stop |
| **Advisory** | `post-plan-challenge.sh`, `post-tasks-validate.sh`, `commit-msg-verify.sh`, `feedback-gate.sh` (non-Layer-1) | Yes — loop continues |

Differentiator: "Does bypassing this gate corrupt an invariant that cannot be repaired in the same session?" Yes → enforcement. No → advisory. When adding a new hook, declare its class in the hook file header comment.

**Spec-first enforcement** -- `pre-tool-use.sh` is the strongest feedback mechanism (a "Stop hook"). A PERMISSION DENY cannot be ignored. Projects opt in by having `docs/decisions/`.

**Session event pipeline** -- PostToolUse/PostToolUseFailure hooks append JSONL events to `/tmp/brana-session-{SESSION_ID}.jsonl`. The session-end hook consumes this file, computes 7 flywheel metrics (correction_rate, auto_fix_rate, test_write_rate, cascade_rate, test_pass_rate, lint_pass_rate, delegation_count), and persists to ruflo memory.

**Immediate response pattern** -- `session-end.sh` responds with `{"continue": true}` immediately, then forks heavy processing to background. CC cancels hooks during session teardown, so the response must come before any processing.

**Cascade detection** -- `post-tool-use-failure.sh` tracks consecutive failures on the same target. At 3+ failures, it flags a cascade so `pre-tool-use.sh` can inject a warning on the next attempt.

**Error recurrence tracking (t-679)** -- `post-tool-use-failure.sh` computes an error signature (md5 of tool_name + error_cat + first 80 chars of detail) and increments a counter in `~/.claude/logs/error-recurrence.jsonl`. When the same signature hits 3 occurrences across sessions, it stores to ruflo memory with tag `escalate:rule-candidate`. `session-start.sh` scans the recurrence file and surfaces errors with count >= 3 as "[Recurring errors -- rule/hook candidates]" in session context.

**File-targeted tool enumeration (promoted 2026-05-14, completed 2026-05-15)** -- The detail-extraction case statement in `post-tool-use-failure.sh` must explicitly enumerate every CC tool that takes a `file_path` or `notebook_path` input: `Read`, `Edit`, `Write`, `NotebookEdit`, `MultiEdit`. Any tool missing from the branch falls through to the `TOOL_NAME` fallback, making all its failures log `detail="<ToolName>"` — collapsing distinct failures into one indistinguishable signature bucket. History: `Read` was missing (572 failures, hash bc9058e8) before 4c21e36; `NotebookEdit` and `MultiEdit` were missing until 2026-05-15 (t-1397). Note: `NotebookEdit` uses `notebook_path` not `file_path` — extraction uses `.file_path // .notebook_path // empty`. Rule: when adding a new file-targeted tool to CC, update the case branch and the regression test. A regression test (`test-post-tool-use-failure-detail.sh`) guards this.

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

> Archived 2026-05-09: 5 oldest entries (2026-04-08 × 2, 2026-04-09, 2026-04-12 nvm PATH, 2026-04-12 worktree-gate checkout/switch) moved to ruflo field-notes namespace (t-1388).
> Archived 2026-05-11: 5 entries (2026-04-10 × 5: doc-gate bash command, git checkout HEAD recovery, branch switches ephemeral, main-guard+doc-gate combo, tasks.json stash theirs) moved to ruflo knowledge namespace.

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

### 2026-04-22: cd-prefix parsing closes the `cd <wt> && git …` gap (t-1324)
`lib/git-helpers.sh::resolve_lookup_dir` now runs a 3-tier lookup: `git -C <path>` > leading `cd <path> &&` > session CWD. `extract_cd_prefix_dir` parses the first token only (sed-based, supports `&&`, `;`, `||`). `branch-verify.sh` and `main-guard.sh` consume the extended resolver without local changes — all cd-prefix behavior lives in the shared helper. Hit organically during t-1323 (filter-fix worktree); same-session validation. Covered by 4 new tests in `test-branch-verify.sh` and 2 in `test-main-guard.sh`. Out of scope: shell-quoted paths, multi-stage `cd a && cd b`, `pushd`.
Source: t-1324, close follow-up to t-1153/t-1286/t-1316

### 2026-04-12: Mock PATH isolation — bash + minimal tools must be in mock bin
When testing bash scripts with a stripped PATH (to simulate missing tools), stripping PATH to just the mock dir causes "bash: command not found" when the script calls `bash <subscript>` or uses `dirname`/`pwd` for SCRIPT_DIR detection. Fix: symlink bash, dirname, and pwd from the system into the mock bin, then exclude only the specific tool being hidden. A `populate_bin <dir> [exclude...]` helper makes this reusable across tests. Rule: never strip PATH to only `$mock/bin` without first populating the tools the script needs to boot.
Source: tests/bootstrap/test-install.sh, t-1150 2026-04-12

### 2026-04-13: UserPromptSubmit hooks fire before Claude processes input
`UserPromptSubmit` is a CC hook event that fires before Claude sees the user's message — earlier than `PreToolUse` (which fires before a tool call). Input JSON: `{"prompt": "..."}`. Always returns `{"continue": true}` (cannot block). Use for: detecting which skill is being invoked before heavy work starts, pre-flight env checks, prompt-level advisory warnings. `preflight-model.sh` is the first brana `UserPromptSubmit` hook — it detects heavy skill invocations and warns if extra-usage is disabled. Register in `hooks.json` with matcher `""` (no tool matcher, fires on every user message).
Source: t-1085, 2026-04-13

### 2026-04-20: BRANA_RECAP_OFF — env-var opt-out for session-start hook output
`session-start.sh` injects `HANDOFF_CONTEXT` (previous session summary) and `VENTURE_CONTEXT` (auto-delegate to daily-ops) as `additionalContext`. Both sites are now gated behind `[ -z "${BRANA_RECAP_OFF:-}" ]`. Set `"BRANA_RECAP_OFF": "1"` in `~/.claude/settings.json` env section to suppress the recap. Pattern is reusable: any noisy hook section (CC changelog, intelligence feed nudges) can be silenced the same way — pick a descriptive env var name, add the guard inline. Removing the key re-enables immediately.
Source: 2026-04-20, feat/brana-recap-off

### 2026-04-21: Shared lib pattern for hook cross-cutting concerns (t-1310, t-1317)
When 2+ hooks duplicate the same logic, extract into `system/hooks/lib/<name>.sh`. Source with `source "${SCRIPT_DIR}/lib/<name>.sh" 2>/dev/null || true` — the `|| true` means the hook continues with degraded behavior if the lib is missing. Two libs now live there: `git-helpers.sh` (resolves `git -C <path>` in commands to the correct lookup dir) and `layer1-paths.sh` (classifies Layer 1 files). Pattern for adding a third: write the function in `lib/`, source it, replace the inline code, add a `validate.sh` Check Nb that verifies hooks using the helper actually source the lib.
Source: t-1310, t-1317, 2026-04-21

### 2026-04-21: worktree-gate non-behavioral dirty exception (t-1320)
When only `.claude/tasks.json` is dirty, `worktree-gate.sh` now emits a warn (continue:true with hint) instead of a deny on `git checkout -b` / `git switch -c`. The gate parses the full dirty file list and checks each against a non-behavioral allowlist (currently just `tasks.json`). Mixed dirty (behavioral + tasks.json) still denies. Pattern: classify dirty files by behavioral vs. state before deciding gate severity.
Source: t-1320, 2026-04-21

### 2026-04-13: commit-msg-verify.sh — advisory commit hygiene (non-blocking)
Warns when a git commit message mentions filenames (e.g. `fix auth.rs`) that are not in the staged diff (`git diff --cached --name-only`). This catches the common mistake of describing more than was actually staged. Implementation note: extracting filenames from `-m` commit messages requires grepping from `.tool_input.command` on stdin; use `python3 -c "import json,sys; ..."` not `printf` for JSON generation in tests (printf interprets `\n` as literal newline, breaking the JSON string). Test assertions on the "unstaged files" warning must exclude the "Staged files:" section, which legitimately contains hook filenames.
Source: t-1129, 2026-04-13

### 2026-05-09: Blocking hooks must write to stderr, not stdout
CC only surfaces hook output to the user via **stderr** when exit code is non-zero. Stdout is the protocol/JSON channel (`{"continue":false,"stopReason":"..."}`). `no-attribution-commit.sh` was exiting 2 with the violation message on stdout — CC showed "No stderr output" to the user while silently blocking the commit. Fix: wrap all user-facing violation output in `{ echo "BLOCKED: ..."; } >&2`. Audit every hook that exits non-zero and verify it writes to stderr.
Source: t-1380 session 2026-05-09

### 2026-05-09: Use jq instead of inline python3 for hook JSON encoding
`commit-msg-verify.sh` used `python3 -c 'import sys,json; print(json.dumps(...))'` for encoding `additionalContext`. This is fragile in non-interactive hook subprocesses (PATH differences, uv requirement). Replaced with `jq -n --arg ctx "$(printf '%b' "$WARNING")" '{"continue":true,"additionalContext":$ctx}'` with `|| echo '{"continue":true}'` fallback. Supersedes earlier advice above about using python3 in this hook.
Source: fix/hook-stderr-output 2026-05-09

### 2026-05-09: Script body edits activate immediately — only hooks.json wiring requires CC restart
When a hook script's body is edited and the updated file is copied to the plugin cache (`~/.claude/plugins/cache/brana/brana/1.0.0/hooks/`), the new behavior fires on the very next event. No CC restart required. CC restart is only needed when `hooks.json` itself changes (event registration, matchers) — that file is parsed once at session startup. Validated: signal-capture.sh phrase addition fired immediately after cache copy, same session.
Source: feat/ratings-spanish-phrases 2026-05-09

### 2026-05-09: Append-only test fixtures make TDD red phase lie
`test-signal-capture.sh` writes to a shared `$RATINGS_FILE`. New phrase assertions checked "does file contain 'positive'?" — passed trivially because earlier test cases had already written positive entries, even with no implementation for the new phrase. Got 49/49 green before a single line of impl existed. Fix: `rm -f "$RATINGS_FILE"` before each independent phrase assertion group. Rule: treat 100%-green-before-impl as a fixture-bleed alarm, not success. Re-run with cleared fixture or reverted impl to confirm red.
Source: feat/t-1386 2026-05-09

### 2026-05-11: Field notes live in docs/architecture/, not docs/reference/
Two files share the basename `hooks.md`: `docs/reference/hooks.md` (auto-generated, "Generated by brana reference generate — do not edit manually" banner) and `docs/architecture/hooks.md` (editable, owns the field-note log). Always target `docs/architecture/<topic>.md` for field notes and manual edits. Edits to `docs/reference/` are silently overwritten on next generation. Applies to hooks.md, skills.md, and any file with both an architecture and a reference version.

### 2026-05-14: PreCompact hook — brana has no immediate use case
CC v2.1.105 added `PreCompact` (exit 2 or `{"decision":"block"}` to block compaction). Evaluated for brana hooks: no immediate use case exists. Session state is written at session-end (not at compaction time), and compaction is not a predictable signal for flush operations. A future hook could block compaction when a structured session-state JSON is absent (forcing the user to run `/brana:close` first), but this would be intrusive and is not warranted. Added `PreCompact` to KNOWN_EVENTS table.
Source: t-1404, session 2026-05-14

### 2026-05-14: CC v2.1.126 removed per-file malware assessment on Read — explains Read x572
Prior to CC v2.1.126, each `Read` tool call triggered an internal malware-assessment step. These internal calls fired `PostToolUseFailure` when they hit errors, all logging `detail="Read"` (before the file_path extraction fix). This is the most likely explanation for the 572 Read tool-fail accumulation. Now on v2.1.141, this assessment is removed. Monitor `~/.claude/logs/error-recurrence.jsonl` for 2-3 sessions: if the Read count stops growing, root cause is confirmed (t-1405). If new Read failures appear with distinct file_paths (now captured post-fix), classify by path family to find the true source.
Source: t-1397/t-1405, CC changelog v2.1.126, session 2026-05-14
Source: reconcile / close session 2026-05-11

### 2026-05-15: Partial tool enumeration leaves silent diagnostic dark spots
When fixing a hook that enumerates file-targeted tools (`Edit|Write|Read`), stopping at the obvious cases leaves unlisted tools (e.g. `NotebookEdit`, `MultiEdit`) falling through to the `TOOL_NAME` fallback — producing `detail="NotebookEdit"` instead of the path. The dark spot is invisible until the missing tool fires in production. Rule: any enumeration fix must grep the full CC file-targeted tool list and assert all cases are covered in the same commit. Also add a test that loops over all listed tools. Applies to any hook with a case-based dispatch on tool names.
Source: t-1397, session 2026-05-15

### 2026-05-15: NotebookEdit uses notebook_path, not file_path
CC's `NotebookEdit` input uses `notebook_path` as the key, not `file_path`. Hooks extracting file targets from tool_input must handle both: `.file_path // .notebook_path // empty`. Same pattern likely applies to future tools with different path field names (e.g. `Glob`/`Grep` use `pattern`). Build the extraction as `jq -r '.file_path // .notebook_path // empty'` and document it in the case branch comment when adding any new file-targeted tool.
Source: t-1397, session 2026-05-15

### 2026-05-15: branch-verify.sh parent-dir glob fires on non-behavioral staged files [→ t-1424]
`is_behavioral()` has a reverse-direction check: `case "$bpath" in ${file}|${file}/*)`. If `file="system"` (bare dir name, e.g. from parsing text after a `git add` substring in a Bash command payload), `system/hooks` matches the glob `system/*` and the hook denies with "Files: system". Neither `.claude/tasks.json` nor `docs/ideas/*.md` is behavioral, but staging them alongside any command text containing "git add" + "system/" triggers this. Fix in t-1424: remove the reverse-direction case. Real staging always produces full blob paths (`system/hooks/foo.sh`), never bare parent dirs.
Source: t-1424, session 2026-05-15 (E2026-05-15-2)

### 2026-05-15: Worktree workflow confirmed for system/hooks/ changes — no friction
Feature branch via worktree + merge --no-ff with regression test included worked cleanly for a protected behavioral change. The worktree-gate fires, worktree is created, changes are committed and merged, worktree is reaped. No edge cases observed. Aligns with `feedback_worktree-for-rules.md`. Continue this pattern for all `system/hooks/` and `system/skills/` behavioral changes.
Source: t-1397, session 2026-05-15
