<!-- close phase: Steps 9-9c: session state, consolidation counter, ruflo mirror, initiative accumulator — loaded per the PHASES registry in ../SKILL.md (t-1942) -->

<!-- ruflo preamble -->
ToolSearch("select:mcp__ruflo__claims_release,mcp__ruflo__hive-mind_memory,mcp__ruflo__memory_store")

### Step 9: Write session state via CLI

**Orientation → task-state mapping (ADR-053 §1, t-1990).** Read the orientation from the gate's Step 1 announcement (`Close mode: ... (orientation: ...)`) — NOT from the weight token, which `--continue` and `--finish` share. Apply to the session's active task before writing session state:

| Orientation | Active task action |
|---|---|
| `--continue` | leave `in_progress` — handoff must be resumable (next[] carries the exact resume point) |
| `--finish` | `brana backlog set {id} status completed` + completed date |
| `--patterns` | no task-state change (this step still writes session state only if reached — LIGHT-INLINE normally skips Steps 9c–11, not Step 9) |
| `--abort` | nothing here — close-abort.sh already set the task to pending with the reason |
| `auto` (bare) | existing behavior: completion only when the work actually completed |

Build a JSON object from all evidence gathered in previous steps, write it to a temp file, and call `brana session write`. The LLM never writes session files directly — the CLI validates the schema and handles atomic writes + history archival.

**Build the JSON payload:**

```json
{
  "version": 1,
  "written_at": "",
  "session_label": "<brief label from conversation context>",
  "accomplished": ["<from git log + conversation>"],
  "learnings": ["<from Step 3 classified findings>"],
  "next": [
    {"text": "<follow-up action>", "task_id": "t-NNN or null", "category": "follow-up|maintenance|suggestion"}
  ],
  "blockers": [
    {"text": "<blocker description>", "task_id": "t-NNN or null"}
  ],
  "backprop": {
    "needed": true,
    "files": ["<system files changed, from Step 8>"]
  },
  "doc_drift": {
    "detected": true,
    "stale_docs": ["<docs affected, from Step 8>"]
  },
  "auto_reconcile": {
    "triggered": false,
    "scope": null,
    "reason": null,
    "issues_found": 0
  },
  "state": {
    "key_files": ["<from git diff --stat>"],
    "test_status": {"passing": 0, "failing": 0}
  },
  "metrics": {
    "events": 0, "corrections": 0, "test_writes": 0,
    "correction_rate": 0.0, "test_write_rate": 0.0,
    "cascade_rate": 0.0, "delegation_count": 0,
    "behavioral_files_changed": 0, "doc_files_changed": 0,
    "doc_prompts_accepted": 0, "doc_prompts_skipped": 0,
    "propose_count": 0, "ask_open_count": 0, "propose_rate": 0.0,
    "extract_metrics": {
      "learnings_classified": 0,
      "patterns_presented": 0,
      "patterns_accepted": 0,
      "patterns_skipped": 0,
      "field_notes_presented": 0,
      "field_notes_kept": 0
    }
  }
}
```

**Metrics field:** Leave the `metrics` object with zero defaults. The `session-end.sh` hook computes actual metrics from the session JSONL telemetry and patches them into session-state.json after the session ends (via `session-end-persist.sh`). The zero defaults are safe fallbacks if the hook doesn't run.

**extract_metrics field (Gate B/C measurement — ADR-027 §10):** Count during close Steps 3–6. Track from conversation context, not telemetry:
- `learnings_classified`: count of findings classified in Step 3 EXTRACT
- `patterns_presented` / `patterns_accepted` / `patterns_skipped`: from Step 5 PATTERNS AskUserQuestion responses
- `field_notes_presented` / `field_notes_kept`: from Step 6 FIELD-NOTES AskUserQuestion responses (kept = any action other than Skip/Archive)
Write the actual counts before calling `brana session write`.

**Propose-first metrics** — count from conversation context (no telemetry file needed):
- `propose_count`: AskUserQuestion calls where the first option had "(Recommended)" or was a clear default
- `ask_open_count`: AskUserQuestion calls where all options were equal weight (no recommendation)
- `propose_rate`: `propose_count / (propose_count + ask_open_count)`. Target: > 0.90.
If propose_rate < 0.90, add a learning: "Propose-first rate below target ({rate}). Review decision points for missing defaults."

**Step 9a: Persist referenced task IDs (run before writing)**

For each item in `next[]` where `task_id` is non-null:

1. Check existence: `backlog_get(task_id: "{id}")` (MCP) or `brana backlog get {id}` (CLI).
2. If the task **does not exist**, create it immediately:
   ```bash
   brana backlog add --json '{"subject":"{text}","work_type":"chore","type":"task","effort":"S"}'
   ```
   Use the item's `text` field as the subject. Update the `task_id` field in the payload with the returned ID if it differs.
3. If the task **already exists**, continue without creating a duplicate.
4. If both MCP and CLI are unavailable, log a warning and proceed — missing IDs are non-fatal.

This step prevents task IDs emitted during ideation or follow-up planning from being lost when session state is written without a corresponding backlog entry.

**Write via CLI:**

```bash
# Write JSON to temp file (avoids shell escaping issues)
cat > /tmp/session-close-$$.json << 'JSON'
{ ... the payload above ... }
JSON

# CLI validates schema, archives previous state, writes atomically
brana session write --file /tmp/session-close-$$.json

# Clean up
rm -f /tmp/session-close-$$.json
```

The CLI auto-fills `written_at` (if empty) and `branch` (from git). `consumed_at` is set to null — the next session-start marks it consumed.

**`next` category values** (validated enum):
- `follow-up` — action items from this session
- `maintenance` — routine tasks (run reconcile, verify-docs, etc.)
- `suggestion` — non-urgent ideas worth considering
- `watch` — passive items to monitor (no immediate action required)

**Rules:**
- Write to temp file first, never pass JSON inline via shell arguments
- If `brana session write` fails, log error and continue — the session-end hook will capture a minimal fallback
- Do NOT write to `session-handoff.md` — it's deprecated (read-only archive)
- Do NOT write `.needs-backprop` — absorbed into the backprop field

### Step 9a-ii: Increment memory-consolidation session counter

After `brana session write` completes, atomically increment `session_count_since_run` in
`~/.swarm/lint-heal-state.json`. This feeds the OR-trigger for `memory-consolidation.sh`.

```bash
python3 - << 'PYEOF'
import json, os, tempfile
STATE = os.path.expanduser("~/.swarm/lint-heal-state.json")
try:
    with open(STATE) as f:
        d = json.load(f)
except (FileNotFoundError, json.JSONDecodeError):
    d = {"last_run_ts": 0, "session_count_since_run": 0, "last_run_date": "", "last_consolidation_ts": 0}
d["session_count_since_run"] = d.get("session_count_since_run", 0) + 1
d.setdefault("last_consolidation_ts", 0)
tmp = STATE + ".tmp"
with open(tmp, "w") as f:
    json.dump(d, f, indent=2)
    f.write("\n")
os.replace(tmp, STATE)
print(f"session_count_since_run → {d['session_count_since_run']}")
PYEOF
```

Skip silently if the state file directory doesn't exist or Python fails — non-critical.

### Step 9b: Ruflo MCP — session mirror + cross-session signals

> Additive — all 3 calls are best-effort. If MCP is unavailable, skip silently.
> Local session state (Step 9) is the primary record. This step adds searchability and cross-session awareness.

**Call 1: Session state to ruflo (searchable mirror)**

```
mcp__ruflo__memory_store(
  key: "session:{PROJECT}:{YYYY-MM-DD}T{HH:MM}",
  value: "<JSON string of the same payload written in Step 9>",
  namespace: "session",
  tags: ["client:{PROJECT}", "branch:{BRANCH}", "tier:episodic"],
  upsert: true
)
```

This makes session history semantically searchable: `memory_search(namespace: "session", query: "JWT auth")` finds past sessions by topic.

**Call 2: Cross-session close announcement (transient)**

```
mcp__ruflo__hive-mind_memory(
  action: "set",
  key: "client:{PROJECT}:session:closed:{YYYY-MM-DD}",
  value: {"status": "closed", "summary": "<1-line session label>", "next": ["<top 3 next items>"], "closed_at": "<ISO timestamp>"}
)
```

Other terminals see the session ended + what's next via `/brana:sitrep`. Transient (in-memory, lost on MCP restart) — OK for session announcements.

**Call 3: Task claim release (guarded)**

Only if an active task was being worked on this session:

```
# SESSION_ID = current branch name (git branch --show-current)
# claimant must match the value used at claims_claim time (backlog start step 7b)
mcp__ruflo__claims_release(
  issueId: "task:{active_task_id}",
  claimant: "agent:{SESSION_ID}:session",
  reason: "session closed"
)
```

If no task was claimed or `claims_release` fails (MCP down), skip silently.

**Fallback:** If any MCP call fails, log the failure and continue. The CLI-based session state from Step 9 is the authoritative record. MCP failures are non-fatal.

### Step 9c: Initiative accumulator — upsert cross-day state (ADR-044)

> Skip entirely if `$CLOSE_MODE` is `NANO` or `LIGHT-INLINE` (ADR-053 — `--patterns` is extraction only).

**Detect active epic (4-tier cascade, run in order, stop at first hit):**

**Tier 0 (persistent focus):** Read the persistent focus file written by `brana session epic focus`:
```bash
TIER0_SLUG=$(brana session epic status --json 2>/dev/null | jq -r '.focus // empty')
```
If non-empty, use it as `$INITIATIVE_SLUG` silently and skip Tier 1/2a/2b/2c/3. Do NOT clear it — the focus file is persistent and only removed by `brana session epic unfocus`.
If empty, fall through to Tier 1.

**Tier 1 (session-start marker):** Read the marker written by `brana run` at session start:
```bash
TIER1_SLUG=$(brana session epic read-marker 2>/dev/null)
```
If non-empty, use it as `$INITIATIVE_SLUG` silently and skip Tier 2a/2b/2c/3. Then clear the marker:
```bash
brana session epic clear-marker 2>/dev/null || true
```
If empty, fall through to Tier 2a.

**Tier 2a:** Query in-progress tasks for a common epic:
```bash
brana backlog query --status in_progress --json 2>/dev/null \
  | jq -r '.[].epic // empty' | sort -u
```
Collect non-empty results into the signal set; continue regardless.

**Tier 2b:** Extract task IDs from recent commits and look up their epic fields:
```bash
git log --oneline -20 \
  | grep -oE 't-[0-9]+' | sort -u \
  | while read id; do
      brana backlog get "$id" --json 2>/dev/null | jq -r '.epic // empty'
    done \
  | sort -u | grep -v '^$'
```
Add all non-empty results to the signal set. Fixes false Tier 3 prompts when all
in_progress tasks completed before close but this session's commits reference tasks that
carry an epic field.

**Converge 2a + 2b:** Deduplicate the signal set.
- Exactly 1 unique non-empty slug → use it silently as `$INITIATIVE_SLUG`. Done.
- 0 or 2+ → fall through to Tier 2c.

**Tier 2c (branch name):** Parse branch name for a slug:
```bash
git branch --show-current | sed 's|.*/||'
```
Use result if it matches a known epic slug (non-empty, no special chars) and the 2a+2b signal set was empty. Add to signal set and re-converge: exactly 1 unique → use silently. 0 or 2+ → fall through to Tier 3.

**Tier 3 (ask):** If all tiers returned 0 or conflicting results, ask once:
```
AskUserQuestion(
  question: "Which epic does this session belong to? (skip = no epic file)",
  options: ["<detected slugs if any>", "Skip"]
)
```
If the user skips: proceed to Step 10 without writing an epic file.

**Pass 2 — LLM pruning of text-only next[] items (run before upsert):**

Read the current accumulator's text-only `next[]` items:
```bash
brana session epic read "$INITIATIVE_SLUG" --json \
  | jq -r '.next[] | select(.task_id == null) | .text'
```

For each item, check whether this session addressed it — scan `accomplished[]` and the
recent git log for evidence. Build a JSON array of resolved items:
```json
[
  {"text": "<exact text from next[]>", "resolution": "<one-line note on how it was addressed>"}
]
```
Items with no evidence of being addressed → omit (they carry forward automatically).
If no items were addressed, pass `"[]"` as `$RESOLVED_TEXTS`.

**Write accumulator:**
```bash
# completed_task_ids = comma-separated IDs of tasks completed this session
COMPLETED=$(git log --oneline -20 | grep -oE 't-[0-9]+' | sort -u | tr '\n' ',' | sed 's/,$//')

brana session epic upsert "$INITIATIVE_SLUG" \
  --completed "$COMPLETED" \
  --resolved-texts "$RESOLVED_TEXTS"
```

Also add `"epic": "$INITIATIVE_SLUG"` to the Step 9 JSON payload so the session-state.json carries the slug (used by sitrep §4b to load the accumulator).

**Fallback:** If `brana session epic upsert` fails, log and continue. Session-state.json and session-history.jsonl are the authoritative records.

