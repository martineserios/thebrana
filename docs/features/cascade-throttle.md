# Feature: Cascade Throttle

**Task:** [t-196](../../.claude/tasks.json)
**Status:** implemented (2026-03-05)
**Related:** [t-043](../../.claude/tasks.json) (feedback hook), [test-lint-feedback-hook](test-lint-feedback-hook.md)

---

## What It Does (Plain English)

Sometimes Claude gets stuck in a loop: it edits a file, the edit fails, it tries again slightly differently, fails again, and keeps going — burning context and making no progress. Before this feature, the failure detection existed (post-tool-use-failure.sh counted consecutive failures) but nothing acted on that information.

Now, when a file fails 3+ times in a row (a "cascade"), the system plants a flag. The next time Claude tries to touch that same file, the pre-tool-use hook sees the flag and injects a stop-and-reassess message directly into Claude's context:

> This file has failed 3+ times consecutively. Stop and reassess your approach — the current strategy is not working. Consider: different edit strategy, reading the file first, or asking the user for guidance.

This closes the feedback loop: failures are no longer just logged — they change behavior.

## How It Works (Non-Technical)

```
Claude edits auth.ts --> fails
Claude edits auth.ts --> fails again
Claude edits auth.ts --> fails a third time
       |
       v
post-tool-use-failure.sh detects: "3 consecutive failures on auth.ts"
       |
       v
Writes a flag file: /tmp/brana-cascade/{session}-auth.ts
       |
       v
Claude tries to edit auth.ts again
       |
       v
pre-tool-use.sh finds the flag BEFORE the edit happens
       |
       v
Injects warning into Claude's context:
"Stop. This file has failed 3+ times. Try a different approach."
       |
       v
Claude reads the file first, rethinks, tries a different strategy
```

The flag is per-file AND per-session — a cascade on `auth.ts` doesn't affect `utils.ts`, and a cascade in one session doesn't bleed into another.

## How It Works (Technical)

### Step 1: Flag Creation (post-tool-use-failure.sh)

After the existing cascade detection logic (which already counted consecutive failures), a new block writes a flag file:

```bash
# After the JSONL append block
if [ "$CASCADE" = true ] && [ -n "$DETAIL" ]; then
    CASCADE_DIR="/tmp/brana-cascade"
    mkdir -p "$CASCADE_DIR" 2>/dev/null || true
    SAFE_DETAIL=$(echo "$DETAIL" | tr '/' '-' | sed 's/^-//')
    echo "$DETAIL" > "$CASCADE_DIR/${SESSION_ID}-${SAFE_DETAIL}" 2>/dev/null || true
fi
```

- `CASCADE` is set to `true` by the existing consecutive-failure counter (3+ same target)
- `DETAIL` is the file path that's failing
- Flag filename: `/tmp/brana-cascade/{session_id}-{sanitized-file-path}`
- Flag content: the original file path (for logging/debugging)

### Step 2: Flag Check (pre-tool-use.sh)

Before any Edit/Write operation proceeds, the pre-tool-use hook checks for cascade flags:

```bash
# Step 3b: Cascade throttle check
CASCADE_CONTEXT=""
if [ -n "$SESSION_ID" ] && [ -n "$FILE_PATH" ]; then
    SAFE_DETAIL=$(echo "$FILE_PATH" | tr '/' '-' | sed 's/^-//')
    CASCADE_FLAG="/tmp/brana-cascade/${SESSION_ID}-${SAFE_DETAIL}"
    if [ -f "$CASCADE_FLAG" ]; then
        CASCADE_CONTEXT="[Cascade detected] This file has failed 3+ times..."
    fi
fi
```

### Step 3: Context Injection

The `pass_through()` function conditionally includes `additionalContext`:

```bash
pass_through() {
    if [ -n "${CASCADE_CONTEXT:-}" ]; then
        local escaped
        escaped=$(echo "$CASCADE_CONTEXT" | jq -Rs '.' 2>/dev/null) || escaped='""'
        echo "{\"continue\": true, \"additionalContext\": $escaped}"
    else
        echo '{"continue": true}'
    fi
    exit 0
}
```

Key design decisions:
- **`continue: true`** — the hook warns, it doesn't block. Claude can still proceed if the new approach is genuinely different. This is a nudge, not a gate.
- **`additionalContext`** — Claude Code's mechanism for injecting text into the model's context alongside tool results. The warning appears as if the system is telling Claude to stop.
- The hook does NOT deny the tool call. A denied Edit would just error out and Claude would retry blindly. Injecting context gives Claude the *reason* to change strategy.

### Isolation Model

```
/tmp/brana-cascade/
  session-abc-src-auth.ts          <-- session abc, file src/auth.ts
  session-abc-src-utils.ts         <-- session abc, file src/utils.ts
  session-xyz-src-auth.ts          <-- session xyz, file src/auth.ts
```

- **Per-file**: cascade on `auth.ts` doesn't trigger warnings for `utils.ts`
- **Per-session**: cascade in session `abc` doesn't affect session `xyz`
- **Ephemeral**: `/tmp/` is cleared on reboot, and session-end.sh can clean up

### Hook Response Format

Without cascade:
```json
{"continue": true}
```

With cascade:
```json
{
  "continue": true,
  "additionalContext": "[Cascade detected] This file has failed 3+ times consecutively. Stop and reassess your approach..."
}
```

## Testing

`tests/hooks/test-cascade-throttle.sh` — 8 assertions:

| # | Test | Validates |
|---|------|-----------|
| 1 | Non-cascade failure returns valid JSON | Hook baseline |
| 2 | Non-cascade failure creates no flag | No false positives |
| 3 | Cascade (3+ failures) returns valid JSON | Hook handles cascade |
| 4 | Cascade creates flag file | Flag writing works |
| 5 | PreToolUse continues (doesn't deny) | Warn, don't block |
| 6 | PreToolUse injects cascade warning | Context injection works |
| 7 | Different file has no cascade flag | Per-file isolation |
| 8 | Different session has no cascade flag | Per-session isolation |

Run: `bash tests/hooks/test-cascade-throttle.sh`

## Interaction with Other Hooks

```
post-tool-use-failure.sh          pre-tool-use.sh
  |                                  |
  +-- counts consecutive failures    +-- checks spec-first gate (feat/* branches)
  +-- writes cascade flag   -------> +-- checks cascade flag
  +-- logs to JSONL                  +-- injects additionalContext if either triggers
                                     +-- returns continue:true or deny
```

The cascade check runs BEFORE the spec-first gate. Both can inject `additionalContext` independently — they address different problems (cascade = stuck loop, spec-first = missing tests/specs).

## Implementation Files

| File | Role |
|------|------|
| `system/hooks/post-tool-use-failure.sh` | Cascade detection + flag writing |
| `system/hooks/pre-tool-use.sh` | Flag reading + context injection |
| `tests/hooks/test-cascade-throttle.sh` | 8-assertion test suite |

## Future Work

- **Flag cleanup**: session-end.sh could remove cascade flags for the ending session
- **Cascade metrics**: session-end.sh already computes `cascade_rate` — this feature makes that metric actionable
- **Escalation**: after 5+ cascades in a session, could suggest `/challenge` or user escalation
- **HTTP hooks migration** (t-205): when brana moves to HTTP hooks, cascade state could live in the server instead of flag files
