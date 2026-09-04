<!-- close phase: Steps 9-9b: session state, consolidation counter, ruflo mirror — continues in initiative-accumulator.md (Step 9c); loaded per the PHASES registry in ../SKILL.md (t-1942) -->

<!-- ruflo preamble -->
ToolSearch("select:mcp__ruflo__claims_release,mcp__ruflo__memory_store")

### Step 9: Write session state via CLI

> **Routing (ADR-060 / t-2154):** `brana session write` routes the handoff by a stable unit key — the payload `epic` (set in Step 9c) → the initiative/focus marker → the branch. Closing from `main` with no epic no longer silently orphans: the CLI falls back to the marker, or warns. Set the `epic` field (Step 9c) so the handoff lands in its unit bucket.

**Orientation → task-state mapping (ADR-053 §1, t-1990).** Read the orientation from the gate's Step 1 announcement (`Close mode: ... (orientation: ...)`) — NOT from the weight token, which `--continue` and `--finish` share. Apply to the session's active task before writing session state:

| Orientation | Active task action |
|---|---|
| `--continue` | leave `in_progress` — handoff must be resumable (next[] carries the exact resume point) |
| `--finish` | `brana backlog set {id} status completed` + completed date |
| `--patterns` | no task-state change (this step still writes session state only if reached — LIGHT-INLINE normally skips Steps 9c–11, not Step 9) |
| `--abort` | nothing here — close-abort.sh already set the task to pending with the reason |
| `auto` (bare) | existing behavior: completion only when the work actually completed |

Build a JSON object from all evidence gathered in previous steps, write it to a temp file, and call `brana session write`. The LLM never writes session files directly — the CLI validates the schema and handles atomic writes + history archival. Evidence feeders include Step 8b PROPAGATE: every propagation gap that wasn't fixed inline lands here as a `next[]` entry with `category: "maintenance"` (ADR-056 — zero silent drops; this is the single `next[]` write, which is why PROPAGATE runs before this step).

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

**Step 9a-bis: SEARCH BEFORE FILING any new follow-up (t-2578)**

This applies to every `next[]` item you are about to file as a *new* task — i.e. items with
`task_id: null` that describe a defect, gap, or follow-up. **File them here, before the state
write, not after.**

1. **Search first — always, one call:**
   ```bash
   brana backlog search "{2-4 distinctive terms from the item}"
   ```
   (or `backlog_search(query: "...")` via MCP). Search the *mechanism*, not your phrasing of the
   symptom — a recurring bug gets described differently every time it recurs.
2. **If a live (`pending`/`in_progress`) match exists: do NOT file.** Append your evidence to it
   instead, and point the `next[]` item at that id:
   ```bash
   brana backlog set {existing-id} context --append "$(date +%Y-%m-%d): {reproduction, measurement, workaround}"
   ```
   Before appending, **read the existing context** — if it already records a fix direction, do not
   propose a competing one without saying why the recorded one is wrong. A duplicate that argues
   for an already-rejected approach is worse than no task at all.
3. **Only if there is no match, file a new task** — then put the returned id on the `next[]` item.

**Why this step exists.** Two duplicates were filed against `t-2502` in four days — `t-2533`
(2026-07-28) and `t-2576` (2026-07-31) — both by closes that had just hit that bug live and filed
straight from the symptom without searching. Both proposed a fix direction `t-2502` and ADR-069's
Rejected section had already ruled out, so each duplicate sat in the backlog as *misleading
guidance*, not merely noise. A close is the single most likely moment to re-file a known bug,
because it runs right after you have been bitten by one.

**Ordering matters too.** Filing here — before the payload is composed — means real ids land on
the **first** write. Filing afterwards forces a second same-day write, whose merge semantics are
lossy (t-2506), which in practice makes closes skip the write and leave `task_id: null`. A null
id is unreachable by sitrep's staleness filter, so the item then resurfaces as an open follow-up
forever, even after the work ships.

**Step 9b: Capture the CAS token (required for a second close on the same day)**

A same-day, same-branch write **merges** with the existing state. By default `next[]` is
**unioned**, which means an entry can be added but never corrected and never withdrawn. To
make your `next[]` authoritative, read the state you are about to merge with and pass its
`written_at` back as `base_written_at` (t-2506):

**Read the base from the SAME key the write will use.** This is the whole correctness
condition, and it is easy to get wrong:

```bash
# $EPIC is the value Step 9c puts in the payload's `epic` field.
BASE=$(brana session read --all --json 2>/dev/null \
  | jq -r --arg e "$EPIC" '.[] | select(.epic==$e) | .state.written_at // empty')
# include "base_written_at": "$BASE" in the payload (omit the field entirely if empty)
```

> **Do NOT use a bare `brana session read` for this.** It resolves by **branch**, while the
> write routes by **epic** (`write_state` is epic-first; `read_state` is branch-only). On a
> branch that does not match the epic convention — `dev`, notably — the bare read prints
> *"branch ... does not match epic convention, falling back to session-state.json"* on stderr
> and returns the **orphan** file's `written_at`, which belongs to a different lane. Passing
> that guarantees a CAS miss: the write silently degrades to union, nothing can be withdrawn,
> and the response still says `ok:true`. Measured live 2026-07-29 — bare read gave
> `16:55:03Z` while the epic file this close wrote to was at `19:42:20Z`.
>
> Empty `$BASE` means no prior state for this epic; omit `base_written_at` rather than sending
> an empty string. A first write has nothing to compare against and needs no token.

Run it from the repo root, and confirm the `mode` in the write response is `replace` — not
`union-stale-base` — before believing an entry was corrected or withdrawn.

**Same-day merge semantics — what MERGES, what REPLACES:**

| Field | Rule | Why |
|---|---|---|
| `accomplished[]`, `learnings[]`, `blockers[]` | always **union** | append-only logs of what happened |
| `next[]` with matching `base_written_at` | **replace** | current forward-looking state; must be correctable |
| `next[]` with stale/absent `base_written_at` | **union** + warning | caller cannot be shown to have read current content |
| `session_label` | combined with ` \| ` | breadcrumb across closes |

**To express "this item is done, drop it":** omit it from `next[]` and pass a matching
`base_written_at`. Omission alone does nothing — without the token the write unions and the
entry survives. There is no separate delete verb.

> ⚠️ **This table is the documented contract, not a guarantee — treat it as unreliable and
> ALWAYS read+merge (t-2674).** Two independent live incidents on the same epic
> ("anita-envios"), two days apart, both destroyed a prior session's `next[]` wholesale
> (`mode: replace`, `retained_from_existing: 0`, `warning: null`, `ok: true` — no signal of
> loss anywhere in the response) under two DIFFERENT trigger conditions: once with a
> **correctly-matching** `base_written_at` (2026-08-11 — that one IS the documented "replace"
> row above, the destructive part is that nothing warns you your `next[]` wasn't exhaustive),
> and once with `base_written_at` **omitted entirely** (2026-08-13 — that one contradicts the
> "absent → union" row above). A controlled repro against an isolated throwaway epic
> (sequential omitted-base writes, and a concurrent two-writer race) reproduced only the
> documented **union** behavior — the destructive path could NOT be reproduced in isolation,
> meaning it depends on some real-session precondition not yet identified (candidates:
> `consumed_at` state of the prior write, a genuine concurrent writer on the SAME epic from a
> different live session, or something else entirely). **Do not trust `base_written_at`
> presence/absence/match as a safety signal in either direction.** Before every write, read
> the epic's current `next[]` (`brana session read --all --json | jq ...`, see
> `pattern_session-write-replace-wipes-prior-next_2026-08-11` in project memory) and always
> compose your `next[]` as "everything still live from the read, plus what's new" — never rely
> on the CLI to preserve anything you didn't re-state, regardless of which merge mode you
> expect to get. Root cause is still open — no CLI source was available to this investigation
> to fix it directly; see t-2674.

**Write via CLI:**

```bash
# Write JSON to temp file (avoids shell escaping issues)
cat > /tmp/session-close-$$.json << 'JSON'
{ ... the payload above, including base_written_at ... }
JSON

# CLI validates schema, archives previous state, writes atomically
brana session write --file /tmp/session-close-$$.json

# Clean up
rm -f /tmp/session-close-$$.json
```

The CLI auto-fills `written_at` (if empty) and `branch` (from git). `consumed_at` is set to null — the next session-start marks it consumed. `base_written_at` is a request parameter and is never persisted.

**CHECK THE RESPONSE — it reports what actually landed:**

```json
{"ok":true,"path":"...","next":{"incoming":8,"written":7,"dropped_duplicates":1,
                                "retained_from_existing":0,"mode":"replace"}}
```

`incoming` != `written` means entries did not land. `mode` tells you which rule applied;
`union-stale-base` means another session wrote while you were composing, your `next[]` was
unioned rather than replaced, and anything you meant to withdraw is still there — re-read
and write again. A warning also goes to stderr. **Do not send stderr to `/dev/null` on this
call** — it is the only place the concurrency downgrade is announced.

**Dedup key:** `next[]` entries are deduplicated by **case-folded trimmed `text` only**.
`task_id` does not participate, so `task_id: null` and a populated `task_id` behave
identically — null was never special, it merely escaped a key it should not have been in.
Two entries with the same `task_id` and different text are two entries; two entries with the
same text are one, whatever their `task_id`.

> Historical note (t-2506): `task_id` used to be a dedup key, so two `next[]` entries
> referencing the same task silently collapsed to one and the *incumbent* text won. Several
> distinct next steps legitimately concern one task; `task_id` is a reference, not a unique
> key. Folding multiple points into one entry, or setting `task_id: null` to dodge the drop,
> are no longer necessary.

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

> Additive — all 2 calls are best-effort. If MCP is unavailable, skip silently.
> Local session state (Step 9) is the primary record. This step adds searchability and cross-session awareness.
>
> **Removed 2026-08-12 (t-2754):** a "Call 2 — Cross-session close announcement" used to run here via `hive-mind_memory(action:"set", key:"client:{PROJECT}:session:closed:...")`, claiming "other terminals see the session ended + what's next via `/brana:sitrep`." That claim went false the moment sitrep's reader for this exact key pattern was removed in the same task (sitrep's former "Source 7"): the store is in-memory and resets per MCP restart, so it never delivered cross-session awareness in the first place. Removed rather than left as a write nobody reads.

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

**Call 2: Task claim release (guarded)**

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


Continues in `initiative-accumulator.md` — Step 9c (initiative accumulator, cross-day state upsert, ADR-044).
