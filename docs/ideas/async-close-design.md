# Async-First Close — Design Spec

> Research spike t-1961. Branch: async-close/research/t-1961-async-close-queue-schema.
> Idea doc: docs/ideas/async-first-close.md

## Questions answered

### Q1: Is git diff + commit log sufficient for nightly extraction?

**Answer: 80% yes — sufficient to start.**

| Learning type | Captured in diff+log? | Notes |
|---|---|---|
| Code patterns (reusable solutions) | ✓ | Visible in diff content |
| Bug fixes / errata | ✓ | Commit msg + diff |
| Workarounds | ✓ | Usually commented in code |
| Rejected approaches | ✗ | Lives in conversation only |
| Debugging insights | ✗ | Conversation context, not code |
| "Aha moments" | ✗ | Conversation-level |

The 20% gap (conversation-level insights) is addressed separately via an optional "session notes" mechanism — a lightweight scratch file the user or hooks write to during the session. This is additive and not required for v1.

**Decision:** diff + `git log --oneline` is the v1 extraction input. Add `session_notes_path` to the queue schema as optional from day one so it can be populated later.

---

### Q2: close-queue.json schema

**File location:** `~/.claude/close-queue.json` (per-user, cross-project)

```json
{
  "version": 1,
  "entries": [
    {
      "id": "close-20260610T231500Z-thebrana",
      "timestamp": "2026-06-10T23:15:00Z",
      "branch": "feat/t-1234-feature",
      "project": "thebrana",
      "git_root": "/home/martineserios/enter_thebrana/thebrana",
      "git_range": "abc123def..789012abc",
      "commit_count": 3,
      "snapshot_path": "~/.claude/sessions/snap-20260610-2315.diff",
      "session_notes_path": null,
      "processed": false,
      "processed_at": null,
      "summary_path": null,
      "failed": false,
      "retry_count": 0,
      "error": null
    }
  ]
}
```

**Field rationale:**
- `id`: deterministic — `close-{ISO8601}-{project}` — idempotent on replay
- `git_range`: `HEAD~N..HEAD` captured at close time (not relying on HEAD at cron time — N commits might have accumulated by then)
- `snapshot_path`: full diff saved locally; cron reads it without requiring git access at the same commit
- `session_notes_path`: null in v1; populated if a session-notes feature ships later
- `failed` + `retry_count` + `error`: failure tracking for the cron retry loop

**Snapshot format:** plain text (`git diff HEAD~N..HEAD` output), saved to `~/.claude/sessions/snap-{YYYYMMDD}-{HHMM}.diff`. Kept 14 days, deleted by cron after successful processing.

---

### Q3: Cron handling multiple queued sessions

**Processing order:** chronological (oldest first) — ensures learnings are extracted in the order they happened, preventing temporal confusion in errata docs.

**Concurrency:** sequential, not parallel — one LLM pass at a time. Keeps cost predictable.

**Algorithm:**
```
READ close-queue.json
FOR each entry WHERE processed=false AND failed_retries<3:
  1. Read snapshot_path
  2. LLM pass: extract learnings (errata / patterns / field-notes)
  3. Route SMALL learnings → ruflo/memory (auto)
  4. Route LARGE/novel learnings → reminders.json (for human review)
  5. Mark entry processed=true, set summary_path, set processed_at
  6. Delete snapshot file if >14 days old OR mark for deletion
WRITE daily-summary-{date}.md with all extracted learnings
WRITE close-queue.json with updated entries
```

**Failure handling:**
- If LLM call fails: `failed=true`, `retry_count++`, `error=message`
- Next cron run: retries up to 3x
- After 3 failures: writes a "processing failed" reminder → human resolves manually

**Retention:** entries older than 30 days (processed or failed) are pruned from the queue on each cron run.

---

### Q4: Reminder system — hook integration design (per user addition)

**Core insight from user:** the reminder system must be hook-friendly so that any event can trigger a reminder. Two layers:

```
┌─────────────────────────────────────────────────────────┐
│ Layer 1: Event-based (hooks, real-time during session)  │
│   PostToolUse → condition match → write reminder        │
│   session-end hooks → check patterns → write reminder   │
│   PreToolUse → overdue check → surface reminder         │
└────────────────────┬────────────────────────────────────┘
                     │ both write to
┌────────────────────▼────────────────────────────────────┐
│ ~/.claude/reminders.json  (append-only, cross-project)  │
└────────────────────┬────────────────────────────────────┘
                     │ surfaced by
┌────────────────────▼────────────────────────────────────┐
│ Layer 2: Batch-based (nightly cron — async close)       │
│   session snapshot → LLM extraction → large patterns   │
│   → reminders.json (pending human review)               │
└─────────────────────────────────────────────────────────┘
                     │ read by
┌────────────────────▼────────────────────────────────────┐
│ Surfacing: session-start hook / sitrep / brana remind   │
└─────────────────────────────────────────────────────────┘
```

**reminders.json schema:**

```json
{
  "version": 1,
  "reminders": [
    {
      "id": "r-20260610T231500Z-hooks-edit",
      "created": "2026-06-10T23:15:00Z",
      "source": "hook:PostToolUse",
      "trigger": "edit:system/hooks/*.sh",
      "project": "thebrana",
      "text": "Edited hooks 3× this session. Run validate.sh before next session.",
      "action": "brana validate --scope hooks",
      "priority": "medium",
      "status": "pending",
      "snoozed_until": null,
      "resolved_at": null,
      "tags": ["hooks", "validation"]
    }
  ]
}
```

**Hook write contract (shell helper — `system/hooks/lib/remind.sh`):**

```bash
#!/usr/bin/env bash
# write_reminder TEXT ACTION PRIORITY [PROJECT] [TAGS_CSV]
# Usage: write_reminder "Run validate.sh" "brana validate" "medium" "thebrana" "hooks,validation"
write_reminder() {
    local text="$1" action="$2" priority="${3:-medium}"
    local project="${4:-unknown}" tags="${5:-}"
    local reminder_file="$HOME/.claude/reminders.json"
    local id="r-$(date -u +%Y%m%dT%H%M%SZ)-$(echo "$text" | md5sum | cut -c1-6)"

    # Init file if missing
    [ -f "$reminder_file" ] || echo '{"version":1,"reminders":[]}' > "$reminder_file"

    jq --arg id "$id" --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
       --arg src "${HOOK_NAME:-hook:unknown}" \
       --arg project "$project" --arg text "$text" \
       --arg action "$action" --arg priority "$priority" \
       --argjson tags "$(echo "$tags" | jq -Rc 'split(",") | map(select(length>0))')" \
    '.reminders += [{
      "id": $id, "created": $ts, "source": $src,
      "project": $project, "text": $text, "action": $action,
      "priority": $priority, "status": "pending",
      "snoozed_until": null, "resolved_at": null, "tags": $tags
    }]' "$reminder_file" > /tmp/reminders.tmp && mv /tmp/reminders.tmp "$reminder_file"
}
```

**Example hook triggers:**
- `PostToolUse` on `Edit/Write` matching `system/hooks/*.sh` ≥3 times → "Run validate.sh"
- `session-end.sh` → task in_progress with no commits on that branch → "t-NNN left in_progress with no commits"
- Nightly cron → LARGE pattern needing classification → "Pattern from [date] session needs routing"
- `PostToolUse` on `Bash` matching `git stash push` → "You stashed changes — remember to pop or clean up"

**Surfacing:**
- `session-start.sh`: if `pending` reminders > 0 → `"Reminders: N pending. Run 'brana remind list' to view."` in additionalContext
- `brana remind list`: shows all pending/snoozed reminders, sorted by priority+created
- `brana remind resolve <id>`: marks resolved
- `brana remind snooze <id> 3d`: sets `snoozed_until` to 3 days from now
- `/brana:sitrep`: surfaces top 1-2 `high` priority reminders in focus section

---

## Reminder system — full design (t-1963)

> Extends Q4 above. Covers lifecycle, sources, dedup, and surfacing contracts.

### Lifecycle state machine

```
                    ┌──────────┐
   write_reminder → │ pending  │ ←──────────────┐
                    └────┬─────┘                │
              ┌──────────┼──────────┐           │ snooze expires
              ▼          ▼          ▼           │ (cron or session-start
        ┌──────────┐ ┌─────────┐ ┌─────────┐    │  flips back to pending)
        │ resolved │ │ snoozed ─┼─┘         │
        └──────────┘ └─────────┘ ┌──────────┐
                                 │ expired  │ ← auto after 30 days pending
                                 └──────────┘
```

| State | Meaning | Transition |
|-------|---------|-----------|
| `pending` | Active, surfaced at session start / sitrep | → resolved, snoozed, expired |
| `snoozed` | Hidden until `snoozed_until` | → pending (auto, when timestamp passes) |
| `resolved` | Done — kept 14 days for audit, then pruned | terminal |
| `expired` | 30 days pending without action — auto-archived, surfaced once in a weekly digest | terminal |

**Expiry is not deletion.** Expired reminders get one last surfacing in `/brana:review weekly` ("N reminders expired unactioned — were they noise?") — this is the feedback loop that tunes trigger conditions over time. Repeatedly-expired trigger types are candidates for removal.

### The four sources — trigger conditions

| # | Source | Trigger condition | Example reminder | Priority |
|---|--------|------------------|------------------|----------|
| 1 | **Nightly cron — pattern routing** | Extraction finds LARGE/novel pattern (scope ≥5 or novelty ≥5 on EVALUATE axes) | "Pattern from 06-10 session needs classification: 'hook sentinel dual-write'" | high |
| 2 | **Accumulated errata** | Same errata topic appears in ≥3 sessions within 30 days (cron greps errata doc dates) | "Errata 'tasks.json stash conflict' hit 3× this month — promote to rule?" | high |
| 3 | **Deferred doc updates** | Close/build writes `doc update deferred` to next[] AND ≥3 sessions pass without the doc changing (cron checks git log for the file) | "docs/architecture/hooks.md flagged stale 3 sessions ago, still unchanged" | medium |
| 4 | **Stale close queue** | Queue entry `processed=false` AND `timestamp` >3 days old (cron self-monitoring) | "2 close snapshots unprocessed >3 days — extraction cron may be failing" | high |

Plus the open layer: **any hook** can write via `remind.sh` (event-based, layer 1). The four above are the built-in batch sources (layer 2).

### Cross-project dedup

Reminders carry a `dedup_key` (optional): `{source}:{topic-slug}`. Before appending, `write_reminder` checks for an existing `pending` reminder with the same `dedup_key`:

- **Match found:** increment its `occurrences` counter and update `last_seen` — do NOT append a duplicate
- **No match:** append as new

```json
{
  "dedup_key": "errata-accumulation:tasks-json-stash",
  "occurrences": 3,
  "last_seen": "2026-06-10T23:15:00Z"
}
```

Occurrence count feeds priority escalation: `occurrences ≥3 AND priority=medium` → auto-bump to `high`. Cross-project patterns (same dedup_key from different `project` values) get a `cross-project: [p1, p2]` annotation — these are the strongest rule candidates.

### Surfacing contracts

| Surface | What it shows | Contract |
|---------|--------------|----------|
| `session-start.sh` | Count only: "Reminders: N pending (M high)" | Read-only, <50ms budget, never blocks startup |
| `brana remind list` | Full table: id, age, priority, text, action | Sorted: priority desc, then created asc |
| `brana remind resolve <id>` | Marks resolved | Writes `resolved_at`, keeps 14 days |
| `brana remind snooze <id> <dur>` | Sets `snoozed_until` | Accepts 1d/3d/1w format |
| `/brana:sitrep` | Top 2 high-priority pending | Inline in focus section, with `action` command shown |
| `/brana:review weekly` | Expired digest + occurrence stats | Feedback loop for trigger tuning |

### File locking

Both hooks (layer 1, mid-session) and cron (layer 2, 2am) write `reminders.json`. Concurrent write risk is low (different times) but non-zero (parallel sessions). Contract: write via `jq ... > tmp && mv tmp file` (atomic rename, already in remind.sh) — last-writer-wins is acceptable for append-mostly data since appends read-modify-write the full file within one jq call. If corruption is ever observed, upgrade to `flock`.

---

## Implementation plan — t-1962 shape (2026-06-10)

Shaping decisions, superseding the earlier "Implementation order" draft:

1. **Rust directly, no shell v1.** The earlier lean ("shell v1, Rust v2") is reversed: the schema is now stable, the brana Rust CLI has the serde/JSON infra, and a shell version would be throwaway work violating the CLI-composable convention.
2. **Scope of t-1962 = the reminder subsystem**, not just the CLI. A CLI with nothing writing to the store has no value. Ships: store schema + `remind.sh` + Rust CLI + session-start surfacing.
3. **Cron batch sources excluded.** The four batch sources (§above) ship with async-close Track 2 — its task tree is planned after t-1962 proves the store.

### Task tree (epic: async-close)

```
t-1962  brana remind — reminder system (M)
├─ t-1964  ADR: reminder store architecture          (S, docs)   gates all impl
├─ t-1965  remind.sh write helper — tests + impl     (S)  blocked_by: t-1964
├─ t-1966  brana remind CLI (Rust) — TDD             (M)  blocked_by: t-1964
├─ t-1967  session-start.sh count surfacing          (S)  blocked_by: t-1965, t-1966
└─ t-1968  Docs: architecture + user guide           (S)  blocked_by: t-1967
```

t-1965 and t-1966 are parallelizable after the ADR. M+ disciplines: DDD = t-1964, TDD = embedded in t-1965/t-1966 acceptance criteria, SDD + Docs = t-1968.

### Remaining open questions (deferred)

- Session notes mechanism — how does the user/hook write notes during a session? (v2 of extraction input)
- Track 1 (close-instant) + cron script tasks — planned after t-1962 ships
