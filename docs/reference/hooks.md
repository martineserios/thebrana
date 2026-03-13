# Hook Reference

Complete reference for all brana hook scripts. Hooks are event-driven shell scripts that Claude Code invokes at specific lifecycle points.

## Deployment Split (CC Bug #24529)

Claude Code v2.1.x silently drops `PostToolUse` and `PostToolUseFailure` events from plugin `hooks.json`. Only `PreToolUse`, `SessionStart`, and `SessionEnd` fire reliably from plugins.

**Workaround:** `bootstrap.sh` installs PostToolUse and PostToolUseFailure hooks into `~/.claude/settings.json` with absolute paths. The plugin `hooks.json` only declares PreToolUse, SessionStart, and SessionEnd.

| Event | Installed via | File |
|-------|--------------|------|
| PreToolUse | Plugin `hooks.json` | `system/hooks/hooks.json` |
| SessionStart | Plugin `hooks.json` | `system/hooks/hooks.json` |
| SessionEnd | Plugin `hooks.json` | `system/hooks/hooks.json` |
| PostToolUse | Bootstrap `settings.json` | `~/.claude/settings.json` |
| PostToolUseFailure | Bootstrap `settings.json` | `~/.claude/settings.json` |

When CC fixes plugin PostToolUse dispatch, all hooks move back to `hooks.json`.

## Shared Library

### lib/cf-env.sh

Locates the `ruflo` binary. Source it to get the `$CF` variable.

Search order: nvm global install, PATH lookup, npx fallback. Exported as `$CF` (empty string if not found).

Used by: `session-start.sh`, `session-end.sh`, `session-start-venture.sh`, `post-sale.sh`.

## Plugin Hooks (hooks.json)

### pre-tool-use.sh

| Field | Value |
|-------|-------|
| **Event** | PreToolUse |
| **Matcher** | `Write\|Edit` |
| **Timeout** | 5000ms |
| **Purpose** | Spec-before-code enforcement + cascade throttle |

**What it enforces:**

Blocks Write/Edit on implementation files when all three conditions are true:
1. Project has `docs/decisions/` directory (opt-in)
2. Current branch is `feat/*`
3. No spec or test activity exists on the branch yet (committed, staged, or unstaged)

Always allows writes to: `docs/*`, `test/*`, `tests/*`, `__tests__/*`, `*.test.*`, `*.spec.*`, `*.md`.

Additionally injects a cascade warning (not a deny) if `post-tool-use-failure.sh` flagged the target file as cascading (3+ consecutive failures).

**Input JSON:**

```json
{
  "tool_name": "Write|Edit",
  "tool_input": { "file_path": "/absolute/path" },
  "cwd": "/project/root",
  "session_id": "abc123"
}
```

**Output JSON (allow):**

```json
{"continue": true}
```

Or with cascade context:

```json
{"continue": true, "additionalContext": "[Cascade detected] This file has failed 3+ times..."}
```

**Output JSON (deny):**

```json
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "deny",
    "permissionDecisionReason": "Spec-first: create an ADR (/decide) or write tests before implementation on feat/* branches."
  }
}
```

**Graceful degradation:** Any git failure or missing data causes pass-through. Non-git repos, non-feat branches, and projects without `docs/decisions/` always pass through.

---

### session-start.sh

| Field | Value |
|-------|-------|
| **Event** | SessionStart |
| **Matcher** | `""` (all) |
| **Timeout** | 10000ms |
| **Purpose** | Recall patterns, inject task context, detect venture projects |

**What it does (synchronous, before JSON response):**

1. Derives project name from git root
2. Writes `BRANA_PROJECT` and `BRANA_SESSION_ID` to `CLAUDE_ENV_FILE` if set
3. Searches ruflo memory for `client:$PROJECT` patterns
4. Searches ruflo for high-confidence correction patterns (`confidence >= 0.8`)
5. Falls back to grepping native auto memory (`~/.claude/projects/*/memory/MEMORY.md`)
6. Reads `tasks.json` and injects task summary (current phase, progress, next unblocked task)
7. If no `tasks.json`, checks portfolio file and suggests creating one
8. Checks self-learning flags: `.needs-backprop`, `pending-learnings.md`
9. Detects venture projects (by directory presence or CLAUDE.md keywords)
10. For venture projects: checks weekly review staleness

**What it does (background fork, after JSON response):**

- Logs recalled patterns and venture detection to session JSONL file

**Input JSON:**

```json
{
  "session_id": "abc123",
  "cwd": "/project/root",
  "hook_event_name": "SessionStart",
  "matcher": ""
}
```

**Output JSON:**

```json
{
  "continue": true,
  "additionalContext": "[Recalled patterns...]\n[Active tasks...]\n[Venture...]"
}
```

---

### session-end.sh

| Field | Value |
|-------|-------|
| **Event** | SessionEnd |
| **Matcher** | `""` (all) |
| **Timeout** | 10000ms |
| **Purpose** | Flush session events, compute metrics, persist to memory |

**Strategy:** Responds immediately with `{"continue": true}`, then forks all heavy processing to background. CC cancels hooks during session teardown, so the response must come before any processing.

**Background processing:**

1. Reads `/tmp/brana-session-{SESSION_ID}.jsonl` (accumulated by PostToolUse hooks)
2. Computes compound metrics: corrections, test writes, cascades, PR creates, test/lint pass/fail counts
3. Computes flywheel metrics: correction_rate, auto_fix_rate, test_write_rate, cascade_rate, test_pass_rate, lint_pass_rate
4. Stores session summary to ruflo memory (namespace: `patterns`, tags include `confidence:quarantine`)
5. Stores flywheel metrics separately (namespace: `metrics`)
6. Falls back to `pending-learnings.md` if ruflo unavailable
7. Always writes session summary to `sessions.md` in project auto memory
8. Detects system file drift (last 10 commits touching skills/agents/hooks/rules) and writes `.needs-backprop` flag
9. Auto-generates minimal session handoff if not written today
10. Cleans up temp session file

**Input JSON:**

```json
{
  "session_id": "abc123",
  "cwd": "/project/root",
  "hook_event_name": "SessionEnd",
  "matcher": ""
}
```

**Output JSON:**

```json
{"continue": true}
```

## Bootstrap Hooks (settings.json)

### post-tool-use.sh

| Field | Value |
|-------|-------|
| **Event** | PostToolUse |
| **Matcher** | `Write\|Edit\|Bash` |
| **Timeout** | 5000ms |
| **Purpose** | Log tool successes, detect corrections and test writes, clear cascade flags |

**What it tracks:**

- **Bash commands:** Detects test runs (npm test, pytest, cargo test, etc.), lint runs (eslint, ruff, etc.), and `gh pr create`
- **Edit/Write:** Detects corrections (same file edited consecutively) and test-file writes (files matching test patterns)
- **Skill invocations:** Logs skill name

**Outcome classification:** `success`, `correction`, `test-write`, `test-pass`, `lint-pass`, `pr-create`, `skill-invoke`.

Clears cascade flags (set by `post-tool-use-failure.sh`) when a previously-failing file succeeds.

Appends a JSONL event to `/tmp/brana-session-{SESSION_ID}.jsonl`.

**Input JSON:**

```json
{
  "session_id": "abc123",
  "tool_name": "Edit",
  "tool_input": { "file_path": "/path/to/file" },
  "cwd": "/project/root"
}
```

**Output JSON:**

```json
{"continue": true}
```

---

### post-tool-use-failure.sh

| Field | Value |
|-------|-------|
| **Event** | PostToolUseFailure |
| **Matcher** | `Write\|Edit\|Bash` |
| **Timeout** | 5000ms |
| **Purpose** | Log tool failures, detect cascades, categorize errors |

**Cascade detection:** If the last 2 events in the session file were also failures on the same target, flags it as a cascade (3+ consecutive failures). For Edit/Write tools, writes a flag file to `/tmp/brana-cascade/` so `pre-tool-use.sh` can inject a warning on the next attempt.

**Error categories:** `edit-mismatch`, `write-fail`, `test-fail`, `lint-fail`, `command-fail`, `network-fail`, `tool-fail`.

**Outcome classification:** `failure`, `test-fail`, `lint-fail`.

Appends a JSONL event (with `error_cat` and `cascade` fields) to `/tmp/brana-session-{SESSION_ID}.jsonl`.

**Input JSON:**

```json
{
  "session_id": "abc123",
  "tool_name": "Edit",
  "tool_input": { "file_path": "/path/to/file" },
  "cwd": "/project/root"
}
```

**Output JSON:**

```json
{"continue": true}
```

---

### post-plan-challenge.sh

| Field | Value |
|-------|-------|
| **Event** | PostToolUse |
| **Matcher** | `ExitPlanMode` |
| **Timeout** | 5000ms |
| **Purpose** | Nudge challenger agent after plan finalization |

Fires when `ExitPlanMode` tool is used. Injects context telling the system to auto-delegate to the challenger agent for adversarial review of the plan.

Logs the event to session JSONL.

**Output JSON:**

```json
{
  "continue": true,
  "additionalContext": "A plan was just finalized. Auto-delegating to challenger agent..."
}
```

---

### post-tasks-validate.sh

| Field | Value |
|-------|-------|
| **Event** | PostToolUse |
| **Matcher** | `Write\|Edit` |
| **Timeout** | 5000ms |
| **Purpose** | Validate tasks.json schema and auto-rollup parent tasks |

Only triggers when the written/edited file matches `*/.claude/tasks.json`.

**Three-step validation:**

1. **JSON validity** -- checks `jq empty` passes
2. **Schema validation** -- checks required fields (version, project, tasks array), task-level fields (id, subject, status, type, stream), valid enum values for status and type, tags must be string array, context must be string
3. **Parent rollup** -- if all children of a phase/milestone are completed, auto-completes the parent

Injects schema errors or rollup messages as `additionalContext`.

**Output JSON (schema error):**

```json
{
  "continue": true,
  "additionalContext": "tasks.json schema errors: task t-015 missing subject; task t-016: invalid status wip. Fix these fields."
}
```

**Output JSON (rollup):**

```json
{
  "continue": true,
  "additionalContext": "Auto-rollup: completed parents [ph-002] -- all children done."
}
```

---

### post-sale.sh

| Field | Value |
|-------|-------|
| **Event** | PostToolUse |
| **Matcher** | `Write\|Edit` |
| **Timeout** | 5000ms |
| **Purpose** | Detect deal closures in pipeline files and snapshot to memory |

Only triggers when the written/edited file matches `*/docs/pipeline/deal-*.md`, `*/docs/pipeline/deals.md`, or `*/docs/pipeline/closed.md`, and the content contains "closed-won" (case-insensitive).

Extracts deal name from filename and deal value from content. Stores snapshot to ruflo memory (namespace: `business`, tags: `deal,closed-won,pipeline`). Logs to session JSONL.

**Output JSON:**

```json
{
  "continue": true,
  "additionalContext": "Deal closure detected: acme corp. Consider updating Google Sheets..."
}
```

---

### post-pr-review.sh

| Field | Value |
|-------|-------|
| **Event** | PostToolUse |
| **Matcher** | `Bash` |
| **Timeout** | 5000ms |
| **Purpose** | Nudge pr-reviewer agent after `gh pr create` |

Only fires when the Bash command matches `gh pr create`. Injects context to auto-delegate to the pr-reviewer agent for code review feedback.

Logs the event to session JSONL.

**Output JSON:**

```json
{
  "continue": true,
  "additionalContext": "A PR was just created. Auto-delegating to pr-reviewer agent..."
}
```

## Inactive Hook

### session-start-venture.sh

Standalone venture project detection hook. Its logic has been **absorbed into `session-start.sh`** (the venture detection and weekly review staleness check sections). This file is kept for reference but is not registered in `hooks.json` or `settings.json`.

## Session Event Format

All PostToolUse and PostToolUseFailure hooks append events to `/tmp/brana-session-{SESSION_ID}.jsonl`. Each line is a JSON object:

```json
{"ts": 1709856000, "tool": "Edit", "outcome": "success", "detail": "/path/to/file"}
```

Failure events include additional fields:

```json
{"ts": 1709856000, "tool": "Edit", "outcome": "failure", "detail": "/path/to/file", "error_cat": "edit-mismatch", "cascade": false}
```

The session file is consumed by `session-end.sh` for metrics computation, then deleted.
