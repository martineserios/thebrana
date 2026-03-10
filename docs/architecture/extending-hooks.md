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

Every hook must write valid JSON to stdout. Three response patterns:

**Pass through** — let execution proceed:
```json
{"continue": true}
```

**Inject context** — add information for Claude to see:
```json
{"continue": true, "additionalContext": "Relevant information for Claude."}
```

**Block** (PreToolUse only) — deny the tool call:
```json
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "deny",
    "permissionDecisionReason": "Explain why the tool call is blocked."
  }
}
```

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
| `event` (key) | The CC lifecycle event: `PreToolUse`, `PostToolUse`, `PostToolUseFailure`, `SessionStart`, `SessionEnd` |
| `matcher` | Pipe-separated tool names (`"Write\|Edit"`) or empty string (`""`) for all tools |
| `type` | Always `"command"` |
| `command` | Path to the script. Must use `${CLAUDE_PLUGIN_ROOT}` for plugin-relative resolution. |
| `timeout` | Max execution time in milliseconds. 5,000ms for tool hooks, 10,000ms for session hooks. |

### Event Types

| Event | When | Can block? | Typical use |
|-------|------|-----------|-------------|
| `SessionStart` | Session begins | No | Recall patterns, set env vars, detect project type |
| `SessionEnd` | Session ends | No | Flush events, compute metrics, write summaries |
| `PreToolUse` | Before a tool executes | Yes (deny) | Spec-first gate, cascade throttle |
| `PostToolUse` | After a tool succeeds | No | Log events, detect patterns, nudge agents |
| `PostToolUseFailure` | After a tool fails | No | Log failures, detect cascades |

Multiple hooks can register for the same event. They run sequentially. If any PreToolUse hook blocks, the tool call is denied.

## Plugin Hooks vs Bootstrap-Installed Hooks

CC v2.1.x has a bug (issue #24529) where `PostToolUse` and `PostToolUseFailure` events are not dispatched from plugin `hooks.json`. As a workaround:

- **Plugin `hooks.json`** handles: `PreToolUse`, `SessionStart`, `SessionEnd`
- **`bootstrap.sh`** installs `PostToolUse` and `PostToolUseFailure` to `~/.claude/settings.json`

When adding a new hook, check which event it uses:

| Event | Register in |
|-------|-------------|
| `PreToolUse` | `system/hooks/hooks.json` |
| `SessionStart` | `system/hooks/hooks.json` |
| `SessionEnd` | `system/hooks/hooks.json` |
| `PostToolUse` | `bootstrap.sh` (installs to `~/.claude/settings.json`) |
| `PostToolUseFailure` | `bootstrap.sh` (installs to `~/.claude/settings.json`) |

For PostToolUse/PostToolUseFailure hooks, add the registration to the `bootstrap.sh` Step 4b section and use absolute paths (`$HOME/.claude/hooks/my-hook.sh`) instead of `${CLAUDE_PLUGIN_ROOT}`.

See [posttooluse-workaround.md](posttooluse-workaround.md) for full details on CC #24529.

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

## Checklist

1. Create `system/hooks/{name}.sh` following the safety conventions
2. Make it executable: `chmod +x system/hooks/{name}.sh`
3. Register in `system/hooks/hooks.json` (PreToolUse/SessionStart/SessionEnd) or `bootstrap.sh` (PostToolUse/PostToolUseFailure)
4. Run `./validate.sh`
5. Test locally with piped JSON
6. Test in a live session with `claude --plugin-dir ./system`
7. Add entry to `docs/architecture/hooks.md`
