# Extending Hooks

> How to add a hook to the brana system. Hooks are shell scripts that fire on Claude Code lifecycle events. They enforce discipline, log events, and nudge agents automatically.

## Hook Script Anatomy

Every hook lives at `system/hooks/{name}.sh`. It receives JSON on stdin and must write JSON to stdout.

```bash
#!/usr/bin/env bash
# No strict mode — hooks must never fail and block the session.

# Description of what this hook does.
# Input:  stdin JSON (session_id, tool_name, tool_input, cwd)
# Output: stdout JSON

# Ensure valid CWD (may be in deleted worktree)
cd /tmp 2>/dev/null || true

INPUT=$(cat) || true
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null) || true
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // empty' 2>/dev/null) || true

# Fast exit for irrelevant tools
if [ "${TOOL_NAME:-}" != "TargetTool" ]; then
    echo '{"continue": true}'
    exit 0
fi

# ... your logic here ...

echo '{"continue": true, "additionalContext": "Hook found something relevant."}'
```

### Input JSON

Claude Code passes a JSON object on stdin with these fields:

| Field | Type | Present in |
|-------|------|-----------|
| `session_id` | string | All events |
| `cwd` | string | All events |
| `hook_event_name` | string | All events |
| `tool_name` | string | PreToolUse, PostToolUse, PostToolUseFailure |
| `tool_input` | object | PreToolUse, PostToolUse, PostToolUseFailure |

### Output JSON

Every hook must write valid JSON to stdout. Four response patterns:

**Pass through** — let execution proceed:
```json
{"continue": true}
```

**Inject context** — add information for Claude to see:
```json
{"continue": true, "additionalContext": "Relevant information for Claude."}
```

**Block (PreToolUse) — permission deny format:**
```json
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "deny",
    "permissionDecisionReason": "Explain why the tool call is blocked."
  }
}
```

**Block (ConfigChange and non-tool events) — stopReason format:**
```json
{"continue": false, "stopReason": "Explain why execution is stopped."}
```

Use the `permissionDecision` format for PreToolUse (blocking a specific tool call). Use `stopReason` for ConfigChange and non-tool-use events where you want to halt the session. Most existing hooks use the `permissionDecision` format — prefer that for any new PreToolUse gate.

### Exit Codes

Always exit 0. A non-zero exit code causes Claude Code to treat the hook as failed, which may disrupt the session. Handle errors internally and fall back to `{"continue": true}`.

## Safety Conventions

These conventions exist because a broken hook can block every session:

1. **Never use `set -e`** or `set -euo pipefail`. A single failing command would crash the hook with no JSON output.
2. **Append `|| true`** to every command that might fail: `jq`, `git`, `grep`, file reads.
3. **`cd /tmp`** at the top. The CWD might be a deleted worktree or a directory Claude is actively modifying.
4. **Fast exit** for irrelevant tool calls. Check `tool_name` early and return `{"continue": true}` immediately for non-matching tools.
5. **Stay under the timeout.** Plugin hooks get 5,000ms or 10,000ms. Keep processing fast. For heavy work, use the background-fork pattern (see below).

## hooks.json Registration

Hooks are registered in `system/hooks/hooks.json` with this structure:

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Write|Edit",
        "hooks": [
          {
            "type": "command",
            "command": "${CLAUDE_PLUGIN_ROOT}/hooks/my-hook.sh",
            "timeout": 5000
          }
        ]
      }
    ]
  }
}
```

### Registration Fields

| Field | Description |
|-------|-------------|
| `event` (key) | The CC lifecycle event. See Event Types table above for all valid values. |
| `matcher` | Pipe-separated tool names (`"Write\|Edit"`) or empty string (`""`) for all tools. Not applicable to session events — leave `""`. |
| `type` | Always `"command"` |
| `command` | Path to the script. Must use `${CLAUDE_PLUGIN_ROOT}` for plugin-relative resolution. |
| `timeout` | Max execution time in milliseconds. 5,000ms for tool hooks, 10,000ms for session hooks, 3,000ms for lightweight gates. |
| `async` | Optional boolean. When `true`, CC does not wait for the hook to complete before continuing. Use for fire-and-forget work (memory indexing, telemetry) where blocking the session is unacceptable. Output and return value are ignored. |

### Event Types

| Event | When | Can block? | Typical use |
|-------|------|-----------|-------------|
| `SessionStart` | Session begins | No | Recall patterns, detect project type, inject startup context |
| `SessionEnd` | Session ends | No | Flush events, compute metrics, write session summary |
| `UserPromptSubmit` | Before each user prompt is processed | Yes | Pre-flight checks, model/env warnings |
| `PreToolUse` | Before a tool executes | Yes (deny) | Spec-first gate, worktree guard, TDD gate |
| `PostToolUse` | After a tool succeeds | No | Log events, detect patterns, nudge agents |
| `PostToolUseFailure` | After a tool fails | No | Log failures, detect cascades |
| `SubagentStart` | Before a subagent (Agent tool) begins | No | Inject subagent context, track spawns |
| `SubagentStop` | After a subagent finishes | No | Track completion, log results |
| `TaskCompleted` | When a CC Task is marked done | No | Step-level tracking, progress hooks |
| `StopFailure` | When the session stops due to an error | No | Log error state, flush partial work |
| `ConfigChange` | When CC config changes mid-session | Yes | Block unauthorized config mutations (e.g. ANTHROPIC_BASE_URL override) |

Multiple hooks can register for the same event and matcher. They run sequentially. If any PreToolUse hook blocks, the tool call is denied. `UserPromptSubmit` can also block — returning `{"continue": false}` stops the prompt from being processed.

## Plugin Hooks vs Bootstrap-Installed Hooks

All events now work via the plugin `hooks.json` (CC #24529 was resolved — PostToolUse and PostToolUseFailure previously required bootstrap workaround). Register all new hooks in `system/hooks/hooks.json` using `${CLAUDE_PLUGIN_ROOT}` paths.

| Event | Register in |
|-------|-------------|
| All events | `system/hooks/hooks.json` |

`bootstrap.sh` may still install some hooks to `~/.claude/settings.json` for identity-layer needs (hooks that must run even without the plugin). Check `bootstrap.sh` if you need a hook that survives plugin reinstall.

> **Historical note:** Before CC #24529 was fixed, PostToolUse and PostToolUseFailure required bootstrap installation. Some legacy references to this workaround may still exist in docs and scripts — they reflect past state, not current requirements. See [posttooluse-workaround.md](posttooluse-workaround.md) for the full history.

## The 10-Second Timeout Constraint

Hook timeouts are hard limits. If a hook exceeds its timeout, CC kills it. For SessionStart and SessionEnd, the timeout is 10,000ms. For tool hooks, it is 5,000ms.

### Background-Fork Pattern

When a hook needs to do slow work (memory storage, metric computation), use the background-fork pattern: emit the JSON response immediately, then fork the heavy work to a background process.

```bash
#!/usr/bin/env bash
cd /tmp 2>/dev/null || true

INPUT=$(cat) || true
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // empty' 2>/dev/null) || true

# Emit response immediately
echo '{"continue": true}'

# Fork heavy work to background
(
    # This runs after the hook has already responded
    # Do slow things here: memory storage, file writes, API calls
    some_slow_operation "$SESSION_ID" 2>/dev/null
) &

exit 0
```

The `session-end.sh` hook uses this pattern: it responds immediately to CC, then forks metric computation and memory storage to a background process.

## Testing Hooks Locally

Test a hook by piping JSON to it directly:

```bash
# Test a PreToolUse hook
echo '{"session_id":"test-123","tool_name":"Write","tool_input":{"file_path":"/tmp/test.py"},"cwd":"/home/user/project"}' \
  | bash system/hooks/my-hook.sh

# Test a SessionStart hook
echo '{"session_id":"test-123","cwd":"/home/user/project","hook_event_name":"SessionStart"}' \
  | bash system/hooks/session-start.sh

# Verify the output is valid JSON
echo '{"session_id":"test-123","tool_name":"Edit","tool_input":{"file_path":"src/main.py"},"cwd":"/tmp"}' \
  | bash system/hooks/my-hook.sh | jq .
```

Test edge cases:
- Empty stdin: `echo '' | bash system/hooks/my-hook.sh`
- Missing fields: `echo '{}' | bash system/hooks/my-hook.sh`
- Invalid JSON: `echo 'not json' | bash system/hooks/my-hook.sh`

All should return valid JSON without crashing.

## Validation

`validate.sh` checks hooks automatically:

- Script has a valid shebang (`#!/usr/bin/env bash` or `#!/bin/bash`)
- Script passes `bash -n` syntax check
- `hooks.json` is valid JSON
- Event names in `hooks.json` are known CC events
- Commands use `${CLAUDE_PLUGIN_ROOT}` (not relative paths)
- Referenced scripts exist and are executable
- Warns if `PostToolUse`/`PostToolUseFailure` appear in `hooks.json` (CC #24529)

```bash
./validate.sh
```

## Real-World Example: branch-name-warn.sh

`system/hooks/branch-name-warn.sh` is the canonical hard-block PreToolUse gate in this repo. It intercepts `git switch -c`, `git checkout -b`, and `git branch` and blocks branch creation when the name does not follow `{epic}/{work-type}/t-{NNN}-{slug}`. Useful as a reference for any blocking gate.

Key patterns it uses:
- Fast exit for non-`Bash` tools
- Escape hatch (`--force-name` in the command) for authorized bypasses
- Hard-block via stderr message + `{"continue": false}`
- `case` exemptions for special branches (`main`, `docs/*`, `hotfix/*`)

Reference: `system/hooks/branch-name-warn.sh`, tests: `system/hooks/tests/test-branch-name-warn.sh`.

## Checklist

1. Create `system/hooks/{name}.sh` following the safety conventions
2. Make it executable: `chmod +x system/hooks/{name}.sh`
3. Register in `system/hooks/hooks.json` (all events — CC #24529 resolved). Only use `bootstrap.sh` for identity-layer hooks that must survive plugin reinstall.
4. Run `./validate.sh`
5. Test locally with piped JSON
6. Test in a live session with `claude --plugin-dir ./system`
7. Add entry to `docs/architecture/hooks.md`
