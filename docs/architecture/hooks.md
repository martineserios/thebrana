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

## Design principles

**Spec-first enforcement** -- `pre-tool-use.sh` is the strongest feedback mechanism (a "Stop hook"). A PERMISSION DENY cannot be ignored. Projects opt in by having `docs/decisions/`.

**Session event pipeline** -- PostToolUse/PostToolUseFailure hooks append JSONL events to `/tmp/brana-session-{SESSION_ID}.jsonl`. The session-end hook consumes this file, computes flywheel metrics (correction_rate, auto_fix_rate, test_write_rate, cascade_rate, test_pass_rate, lint_pass_rate), and persists to ruflo memory.

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
