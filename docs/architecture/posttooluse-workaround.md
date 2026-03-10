# PostToolUse Workaround (CC #24529)

> Documentation of the Claude Code bug that prevents PostToolUse hooks from firing in plugins, the workaround, and what changes when CC fixes it.

## The Bug

Claude Code issue #24529: the hook executor does not set `CLAUDE_PLUGIN_ROOT` for `PostToolUse` and `PostToolUseFailure` events dispatched from a plugin's `hooks.json`. The result is that these events are silently dropped — the hooks never fire.

`PreToolUse`, `SessionStart`, and `SessionEnd` work correctly from plugin `hooks.json`.

### Affected Versions

CC v2.1.x (confirmed). Status of later versions is unknown — test before assuming a fix.

### Impact on Brana

Brana has 6 PostToolUse hooks and 1 PostToolUseFailure hook:

| Hook | Event | What it does |
|------|-------|-------------|
| `post-tool-use.sh` | PostToolUse | Logs tool successes, detects corrections and test writes |
| `post-pr-review.sh` | PostToolUse | Detects PR creation, nudges pr-reviewer agent |
| `post-plan-challenge.sh` | PostToolUse | Detects plan finalization, nudges challenger agent |
| `post-sale.sh` | PostToolUse | Detects deal closures, snapshots to memory |
| `post-tasks-validate.sh` | PostToolUse | Validates tasks.json, auto-rolls-up parent status |
| `post-tool-use-failure.sh` | PostToolUseFailure | Logs failures, detects cascades |

Without the workaround, none of these fire. The learning loop (correction detection, flywheel metrics) and auto-nudging (PR review, plan challenge) stop working entirely.

## The Workaround

`bootstrap.sh` installs PostToolUse and PostToolUseFailure hooks to `~/.claude/settings.json` instead of relying on the plugin's `hooks.json`. Hooks in `settings.json` are dispatched correctly by all CC versions.

### How It Works

1. The hook scripts still live in `system/hooks/` (part of the plugin source)
2. `bootstrap.sh` Step 4b reads these scripts and registers them in `~/.claude/settings.json`
3. The `settings.json` hooks use absolute paths (`$HOME/.claude/hooks/...`) instead of `${CLAUDE_PLUGIN_ROOT}`
4. CC dispatches PostToolUse/PostToolUseFailure from `settings.json` and they fire correctly

### settings.json Hook Format

```json
{
  "hooks": {
    "PostToolUse": [
      {
        "matcher": "Write|Edit|Bash",
        "hooks": [
          {
            "type": "command",
            "command": "$HOME/.claude/hooks/post-tool-use.sh",
            "timeout": 5000
          }
        ]
      },
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "$HOME/.claude/hooks/post-pr-review.sh",
            "timeout": 5000
          }
        ]
      }
    ],
    "PostToolUseFailure": [
      {
        "matcher": "Write|Edit|Bash",
        "hooks": [
          {
            "type": "command",
            "command": "$HOME/.claude/hooks/post-tool-use-failure.sh",
            "timeout": 5000
          }
        ]
      }
    ]
  }
}
```

### Plugin hooks.json

The plugin's `hooks.json` only registers the events that work:

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Write|Edit",
        "hooks": [
          {
            "type": "command",
            "command": "${CLAUDE_PLUGIN_ROOT}/hooks/pre-tool-use.sh",
            "timeout": 5000
          }
        ]
      }
    ],
    "SessionStart": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "${CLAUDE_PLUGIN_ROOT}/hooks/session-start.sh",
            "timeout": 10000
          }
        ]
      }
    ],
    "SessionEnd": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "${CLAUDE_PLUGIN_ROOT}/hooks/session-end.sh",
            "timeout": 10000
          }
        ]
      }
    ]
  }
}
```

## Files Involved

| File | Role in workaround |
|------|-------------------|
| `system/hooks/hooks.json` | Only registers PreToolUse, SessionStart, SessionEnd |
| `bootstrap.sh` (Step 4b) | Installs PostToolUse + PostToolUseFailure to settings.json |
| `~/.claude/settings.json` | Runtime location for PostToolUse/PostToolUseFailure hooks |
| `system/hooks/post-tool-use.sh` | Source script (copied to `~/.claude/hooks/` by bootstrap or referenced directly) |
| `validate.sh` (Check 9) | Warns if PostToolUse/PostToolUseFailure appear in hooks.json |

## What Changes When CC Fixes It

When a CC version properly dispatches PostToolUse from plugin `hooks.json`, the fix is straightforward:

### Step 1: Test the new CC version

```bash
# Create a minimal test hook
cat > /tmp/test-posttooluse.sh << 'EOF'
#!/usr/bin/env bash
cd /tmp 2>/dev/null || true
INPUT=$(cat) || true
echo "$INPUT" > /tmp/posttooluse-fired.json
echo '{"continue": true}'
EOF
chmod +x /tmp/test-posttooluse.sh
```

Add to `hooks.json` temporarily:
```json
"PostToolUse": [
  {
    "matcher": "Bash",
    "hooks": [
      {
        "type": "command",
        "command": "${CLAUDE_PLUGIN_ROOT}/hooks/test-posttooluse.sh",
        "timeout": 5000
      }
    ]
  }
]
```

Run a session, execute a Bash command, then check:
```bash
cat /tmp/posttooluse-fired.json
```

If the file exists and contains valid JSON, PostToolUse is working from the plugin.

### Step 2: Move hooks to hooks.json

Add PostToolUse and PostToolUseFailure entries to `system/hooks/hooks.json`, using `${CLAUDE_PLUGIN_ROOT}` paths:

```json
"PostToolUse": [
  {
    "matcher": "Write|Edit|Bash",
    "hooks": [
      {
        "type": "command",
        "command": "${CLAUDE_PLUGIN_ROOT}/hooks/post-tool-use.sh",
        "timeout": 5000
      }
    ]
  }
]
```

### Step 3: Remove from bootstrap.sh

Delete Step 4b from `bootstrap.sh` (the section that installs PostToolUse/PostToolUseFailure to `settings.json`).

### Step 4: Clean up settings.json

Remove the `hooks` key from `~/.claude/settings.json` (or just the PostToolUse/PostToolUseFailure entries if other hooks exist there).

### Step 5: Update validate.sh

Remove the warning in Check 9 that flags PostToolUse/PostToolUseFailure in hooks.json.

### Step 6: Update docs

- Remove the workaround section from `docs/architecture/hooks.md`
- Update `docs/architecture/extending-hooks.md` to register all events in hooks.json
- Archive this document or mark it as resolved

### Files to Change

| File | Change |
|------|--------|
| `system/hooks/hooks.json` | Add PostToolUse + PostToolUseFailure entries |
| `bootstrap.sh` | Remove Step 4b |
| `validate.sh` | Remove PostToolUse warning in Check 9 |
| `docs/architecture/hooks.md` | Remove workaround section |
| `docs/architecture/extending-hooks.md` | Simplify registration (all events in hooks.json) |
| `docs/architecture/posttooluse-workaround.md` | Mark as resolved |
| `~/.claude/settings.json` | Remove hooks entries (manual or via bootstrap) |
