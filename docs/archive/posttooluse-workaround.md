# PostToolUse Workaround (CC #24529) — RESOLVED

> **Status: RESOLVED** — Workaround removed in t-235 (2026-05-08). CC fixed PostToolUse dispatch from plugin `hooks.json`. All PostToolUse hooks moved to `system/hooks/hooks.json`; bootstrap.sh Step 4b removed. This document is archived for historical reference only.

---

> Original documentation of the Claude Code bug that prevents PostToolUse hooks from firing in plugins, the workaround, and what changes when CC fixes it.

## The Bug

Claude Code issue #24529: the hook executor does not set `CLAUDE_PLUGIN_ROOT` for `PostToolUse` and `PostToolUseFailure` events dispatched from a plugin's `hooks.json`. The result is that these events are silently dropped — the hooks never fire.

`PreToolUse`, `SessionStart`, and `SessionEnd` work correctly from plugin `hooks.json`.

### Affected Versions

CC v2.1.x (confirmed). Fixed in a later version (exact version not pinned; confirmed working 2026-05-08 after t-235).

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

## The Workaround (Historical)

`bootstrap.sh` installed PostToolUse and PostToolUseFailure hooks to `~/.claude/settings.json` instead of relying on the plugin's `hooks.json`. Hooks in `settings.json` are dispatched correctly by all CC versions.

### How It Worked

1. The hook scripts still lived in `system/hooks/` (part of the plugin source)
2. `bootstrap.sh` Step 4b read these scripts and registered them in `~/.claude/settings.json`
3. The `settings.json` hooks used absolute paths (`$HOME/.claude/hooks/...`) instead of `${CLAUDE_PLUGIN_ROOT}`
4. CC dispatched PostToolUse/PostToolUseFailure from `settings.json` and they fired correctly

### settings.json Hook Format (Historical)

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

## Resolution (t-235, 2026-05-08)

All steps from "What Changes When CC Fixes It" were executed:

| File | Change |
|------|--------|
| `system/hooks/hooks.json` | PostToolUse + PostToolUseFailure entries added |
| `bootstrap.sh` | Step 4b removed |
| `validate.sh` | PostToolUse warning in Check 9 removed |
| `~/.claude/settings.json` | Hooks entries removed |
| `docs/architecture/posttooluse-workaround.md` | Moved to archive (this file) |
