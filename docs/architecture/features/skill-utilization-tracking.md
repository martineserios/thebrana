# Feature: Skill Utilization Tracking

**Task:** [t-198](../../.claude/tasks.json)
**Status:** implemented (2026-03-05)
**Related:** [t-184](../../.claude/tasks.json) (research), [t-196](../../.claude/tasks.json) (cascade throttle)

---

## What It Does (Plain English)

Brana has 37+ skills — `/brana:tasks`, `/brana:research`, `/build-phase`, etc. Before this feature, there was no way to know which skills were actually being used, how often, or which ones were dead weight.

Now, every time a skill is invoked, the system silently records it: which skill, when, during which session. Over time this builds a usage picture that answers:

- Which skills earn their keep?
- Which ones are never touched (candidates for retirement)?
- Are skills being used more after we changed the routing rules?

Alongside this, the **delegation routing rule** was strengthened. Previously, the system would "suggest" a skill once and move on — research showed this produces only 4% utilization. The new rule tells Claude to **use the skill directly** when the trigger matches, not just mention it. This simple change drove utilization from 4% to 61% in external testing (Alvaro Garcia / rudel.ai, 6 users, 500+ sessions).

## How It Works (Non-Technical)

```
You invoke /brana:tasks status
       |
       v
Claude uses the Skill tool internally
       |
       v
post-tool-use.sh sees "Skill" was used
       |
       v
Logs: "skill-invoke: tasks" to the session file
       |
       v
At session end, session-end.sh counts skill invocations
alongside other flywheel metrics
```

You don't need to do anything differently. The tracking is invisible and automatic. The data feeds future decisions about which skills to keep, improve, or retire.

## How It Works (Technical)

### Detection Logic

In `post-tool-use.sh`, the tool-name switch now includes a `Skill` case:

```bash
case "${TOOL_NAME:-}" in
    Bash)
        DETAIL=$(echo "$TOOL_INPUT" | jq -r '.command // empty')
        ;;
    Edit|Write)
        DETAIL=$(echo "$TOOL_INPUT" | jq -r '.file_path // empty')
        ;;
    Skill)                                                          # <-- NEW
        DETAIL=$(echo "$TOOL_INPUT" | jq -r '.skill_name // empty')
        OUTCOME="skill-invoke"
        ;;
    *)
        DETAIL="${TOOL_NAME:-unknown}"
        ;;
esac
```

When `tool_name == "Skill"`, the hook:
1. Extracts `skill_name` from `tool_input` (e.g., "tasks", "research", "build-phase")
2. Sets `outcome` to `"skill-invoke"` (distinct from generic `"success"`)
3. Logs to `/tmp/brana-session-{id}.jsonl` with the skill name in the `detail` field

### JSONL Event Format

```json
{"ts":1772743007,"tool":"Skill","outcome":"skill-invoke","detail":"tasks"}
```

### Outcome Classification (Updated)

| Condition | Outcome | Detail |
|-----------|---------|--------|
| Bash + test runner | `test-pass` | command |
| Bash + linter | `lint-pass` | command |
| Bash + `gh pr create` | `pr-create` | command |
| Edit/Write + same file as previous | `correction` | file path |
| Edit/Write + test file pattern | `test-write` | file path |
| **Skill tool** | **`skill-invoke`** | **skill name** |
| Everything else | `success` | tool name |

### Delegation Routing Change

`system/rules/delegation-routing.md` was changed from:

> Nudge once per trigger. Don't nag.

To:

> When a trigger matches, **invoke the skill** -- don't just suggest it. Only nudge when the match is ambiguous or the user is mid-flow.

This is a behavioral rule, not code — it changes how Claude decides whether to use a skill. The previous "suggest and move on" pattern is the exact anti-pattern that produced 4% utilization in external research.

## Data Flow

```
post-tool-use.sh                    session-end.sh                   future: dashboard
  |                                    |                                |
  +-- skill-invoke events -->  /tmp/brana-session-{id}.jsonl           |
                                       |                                |
                                       +-- delegation_count metric -->  |
                                       +-- per-skill breakdown -------> skill lifecycle decisions
```

### What Session-End Computes

The existing `delegation_count` flywheel metric now captures skill invocations (previously it only counted Task tool delegations). The JSONL can also be queried for per-skill breakdown:

```bash
grep 'skill-invoke' /tmp/brana-session-*.jsonl | jq -r '.detail' | sort | uniq -c | sort -rn
```

## Testing

`tests/hooks/test-skill-tracking.sh` — 5 assertions:

| # | Test | Validates |
|---|------|-----------|
| 1 | Skill tool call returns valid JSON | Hook doesn't break on Skill input |
| 2 | Outcome is `skill-invoke` | Correct classification (not generic `success`) |
| 3 | Detail has skill name | Extracts `skill_name` from `tool_input` |
| 4 | Regular Bash is NOT skill-invoke | No false positives on non-Skill tools |
| 5 | Multiple skills tracked (>=4) | Accumulation across invocations |

Run: `bash tests/hooks/test-skill-tracking.sh`

## Implementation Files

| File | Role |
|------|------|
| `system/hooks/post-tool-use.sh` | Skill detection + JSONL logging |
| `system/rules/delegation-routing.md` | Active skill invocation policy |
| `tests/hooks/test-skill-tracking.sh` | 5-assertion test suite |

## Future Work

- **t-058** (skill distribution analysis): aggregate skill-invoke data across sessions
- **t-205** (brana dashboard): visualize skill utilization rates
- **t-070** (parameterizable skills): optimize high-usage skills first
- Skill retirement: data-driven decisions to remove unused skills
