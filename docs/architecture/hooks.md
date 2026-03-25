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

## Hook inventory

### Plugin hooks (hooks.json)

| Hook | Event | Matcher | Purpose |
|------|-------|---------|---------|
| `pre-tool-use.sh` | PreToolUse | `Write\|Edit` | Spec-before-code gate + cascade throttle |
| `plan-mode-gate.sh` | PreToolUse | `EnterPlanMode` | Enforce plan mode for non-trivial builds |
| `worktree-gate.sh` | PreToolUse | `Bash` | Block `git checkout -b` when untracked files exist |
| `guard-explore.sh` | PreToolUse | `Read\|Grep\|Glob` | Log reads without prior search (logging only, no blocking) |
| `subagent-context.sh` | SubagentStart | `""` (all) | Inject active task + branch + plan + recent decisions into spawned agents |
| `step-completed.sh` | TaskCompleted | `""` (all) | Track CC Task completions for guided execution |
| `session-start.sh` | SessionStart | `""` (all) | Pattern recall, task context, venture detection |
| `session-end.sh` | SessionEnd | `""` (all) | Flywheel metrics, session summary, handoff |

### Bootstrap hooks (settings.json)

| Hook | Event | Matcher | Purpose |
|------|-------|---------|---------|
| `post-tool-use.sh` | PostToolUse | `Write\|Edit\|Bash` | Log successes, detect corrections and test writes |
| `post-tool-use-failure.sh` | PostToolUseFailure | `Write\|Edit\|Bash` | Log failures, detect cascades (3+ consecutive) |
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

| Tier | What runs | Use case |
|------|-----------|----------|
| `minimal` | Nothing (all profiled hooks skip) | Fast CI runs, debugging hook issues |
| `standard` | `pre-tool-use.sh`, `worktree-gate.sh` | Default — production behavior, backward compatible |
| `strict` | All standard + `guard-explore.sh` | Observation mode — collects read pattern data |

**Default:** `standard` (no env var needed, no behavior change from pre-profile state).

**Set it:** `export BRANA_HOOK_PROFILE=strict` in your shell, or add to `~/.claude/settings.json` env section.

**Library:** `system/hooks/lib/profile.sh` provides `hook_should_run <tier>`. Any hook can source it:

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

## Design principles

**Spec-first enforcement** -- `pre-tool-use.sh` is the strongest feedback mechanism (a "Stop hook"). A PERMISSION DENY cannot be ignored. Projects opt in by having `docs/decisions/`.

**Session event pipeline** -- PostToolUse/PostToolUseFailure hooks append JSONL events to `/tmp/brana-session-{SESSION_ID}.jsonl`. The session-end hook consumes this file, computes 7 flywheel metrics (correction_rate, auto_fix_rate, test_write_rate, cascade_rate, test_pass_rate, lint_pass_rate, delegation_count), and persists to ruflo memory.

**Immediate response pattern** -- `session-end.sh` responds with `{"continue": true}` immediately, then forks heavy processing to background. CC cancels hooks during session teardown, so the response must come before any processing.

**Cascade detection** -- `post-tool-use-failure.sh` tracks consecutive failures on the same target. At 3+ failures, it flags a cascade so `pre-tool-use.sh` can inject a warning on the next attempt.

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
