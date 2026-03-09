# Hooks Explained

> 10 shell scripts that fire on Claude Code lifecycle events. Hooks enforce discipline, log events, and nudge agents — all without requiring user action. They communicate through JSON on stdin/stdout.

## How Hooks Work

Claude Code supports five hook events:

| Event | When it fires |
|-------|---------------|
| `SessionStart` | At the beginning of every session |
| `SessionEnd` | At the end of every session |
| `PreToolUse` | Before a tool call executes (can block it) |
| `PostToolUse` | After a tool call succeeds |
| `PostToolUseFailure` | After a tool call fails |

Hooks are registered in `system/settings.json` with a **matcher** (which tool names trigger the hook) and a **timeout** (max execution time in ms). They receive session context as JSON on stdin and return JSON on stdout.

A hook can:
- **Pass through** — `{"continue": true}` — let execution proceed
- **Inject context** — `{"continue": true, "additionalContext": "..."}` — add information to Claude's context
- **Block** (PreToolUse only) — `{"continue": false, "reason": "..."}` — deny the tool call

All brana hooks follow a safety principle: they never fail fatally. Every hook uses `|| true` fallbacks and graceful degradation so a broken hook never blocks a session.

## SessionStart Hooks

### session-start.sh

**Matcher:** `""` (all events)
**Timeout:** 10,000ms

Fires at every session start. Derives the project name from the git root, sets environment variables (`BRANA_PROJECT`, `BRANA_SESSION_ID`), and queries claude-flow for recent patterns relevant to the current project.

**Output:** `additionalContext` with recalled patterns and project context.

**What it enables:** Claude starts each session already knowing the project, its history, and what patterns apply — instead of starting from zero.

Venture detection is built into `session-start.sh` — it checks for venture-specific directories (`docs/sops/`, `docs/okrs/`, `docs/metrics/`, `docs/pipeline/`, `docs/venture/`) and nudges the daily-ops agent when found.

## PreToolUse Hooks

### pre-tool-use.sh

**Matcher:** `Write|Edit`
**Timeout:** 5,000ms

The spec-first gate. Blocks implementation file writes on `feat/*` branches when:

1. The project has opted in (has `docs/decisions/` directory)
2. On a `feat/*` branch
3. No spec or test activity exists on the branch yet

Always allows writes to spec files (`docs/`), test files (`test/`, `tests/`, `*.test.*`, `*.spec.*`), and doc files.

**Output:** Either `{"continue": true}` (allowed) or `{"continue": false, "reason": "..."}` (blocked with explanation of what's needed first).

**What it enables:** Enforces the test-first, spec-first development discipline. You can't write implementation code until you've written a spec or test — the hook physically prevents it.

## PostToolUse Hooks

### post-tool-use.sh

**Matcher:** `Write|Edit|Bash`
**Timeout:** 5,000ms

The primary learning hook. Logs significant tool successes to a session-scoped JSONL file (`/tmp/brana-session-{id}.jsonl`). Detects:

- **Corrections** — edits to files created earlier in the same session (something went wrong the first time)
- **Test file creation** — writes to files matching test patterns

**Output:** `{"continue": true}` (async logging, no context injection).

**What it enables:** Accumulates raw event data that `session-end.sh` processes into flywheel metrics.

### post-pr-review.sh

**Matcher:** `Bash`
**Timeout:** 5,000ms

Detects `gh pr create` commands in Bash tool calls. When a PR is created, nudges the pr-reviewer agent for automated code review.

**Output:** `additionalContext` suggesting PR review delegation.

**What it enables:** Every PR automatically gets a code review suggestion — no manual invocation needed.

### post-plan-challenge.sh

**Matcher:** `ExitPlanMode`
**Timeout:** 5,000ms

Detects `ExitPlanMode` calls. Nudges the challenger agent for adversarial review of the finalized plan.

**Output:** `additionalContext` suggesting challenger delegation.

**What it enables:** Plans get stress-tested before implementation begins.

### post-sale.sh

**Matcher:** `Write|Edit`
**Timeout:** 5,000ms

Detects writes to pipeline deal files. When a deal moves to a closed stage, snapshots the event to claude-flow memory.

**Output:** `additionalContext` on deal closure events.

**What it enables:** Sales milestones are automatically captured in the knowledge system.

### post-tasks-validate.sh

**Matcher:** `Write|Edit`
**Timeout:** 5,000ms

Triggers on writes to any `*/brana:tasks.json` file. Performs three checks:

1. **JSON validity** — catches syntax errors immediately
2. **Schema validation** — checks required fields, valid types, valid status values
3. **Auto-rollup** — when subtasks complete, automatically updates parent task status

**Output:** `additionalContext` with validation errors or rollup notifications.

**What it enables:** Task files stay valid and parent tasks reflect their children's progress automatically.

## PostToolUseFailure Hooks

### post-tool-use-failure.sh

**Matcher:** `Write|Edit|Bash`
**Timeout:** 5,000ms

Logs tool failures to the session JSONL file. Categorizes errors by tool type (command failures, file write failures, edit failures). Tracks failure cascades — when multiple failures occur in sequence.

**Output:** `{"continue": true}` (async logging).

**What it enables:** Failure patterns surface at session end through flywheel metrics, helping identify recurring problems.

## SessionEnd Hooks

### session-end.sh

**Matcher:** `""` (all events)
**Timeout:** 10,000ms

Fires at every session end. Reads the accumulated session JSONL file (`/tmp/brana-session-{id}.jsonl`), computes flywheel metrics, and writes a session summary to claude-flow memory.

**Flywheel metrics computed:**
- `correction_rate` — fraction of writes that needed correction
- `auto_fix_rate` — corrections resolved without user intervention
- `test_write_rate` — fraction of implementation files with accompanying tests
- `cascade_rate` — how often changes propagate across files
- `delegation_count` — how many tasks were delegated to agents

**Output:** `{"continue": true}` (async flush to persistent storage).

**What it enables:** Session-level learning. Patterns that emerge from metrics (e.g., high correction rate on a particular file type) surface in future sessions via the session-start recall.

## Hook Registration

Hooks are registered in `system/settings.json`:

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Write|Edit",
        "hooks": [
          {
            "type": "command",
            "command": "$HOME/.claude/hooks/pre-tool-use.sh",
            "timeout": 5000
          }
        ]
      }
    ]
  }
}
```

- **matcher** — pipe-separated tool names (`"Write|Edit"`) or empty string for all
- **type** — always `"command"` (shell script)
- **command** — path to the hook script (uses `$HOME` for portability)
- **timeout** — max execution time in milliseconds

Multiple hooks can register for the same event. They run sequentially; if any PreToolUse hook blocks, the tool call is denied.
