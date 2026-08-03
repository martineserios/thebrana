<!-- close phase: Steps 9-9c: session state, consolidation counter, ruflo mirror, initiative accumulator — loaded per the PHASES registry in ../SKILL.md (t-1942) -->

<!-- ruflo preamble -->
ToolSearch("select:mcp__ruflo__claims_release,mcp__ruflo__hive-mind_memory,mcp__ruflo__memory_store")

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

**Epic ancestor walk (backlog-v3, t-2375):** Tier 0's corroboration gate and Tier 2a/2b all
resolve a task's epic by walking its `parent` chain to the nearest `type: "epic"` ancestor,
instead of reading the retired flat `epic` field. Read and follow
[`../../_shared/epic-ancestor-walk.md`](../../_shared/epic-ancestor-walk.md) **before Tier 0
below** — it defines `resolve_epic_ancestor()`, reused as-is by Tier 0's gate and by Tier 2a/2b.

**Lookup failures are not negatives (t-2487).** `resolve_epic_ancestor` exits non-zero when
the lookup itself breaks, as distinct from exiting 0 with an empty string for "this task has
no epic ancestor." Tier 0's gate and Tier 2a below record failures to `$EPIC_FAIL_LOG` instead
of letting them silently drop out of the signal set — a dropped slug is how `brana-v3-redesign`
went missing from a live close, leaving a single surviving slug that then looked unambiguous.

```bash
EPIC_FAIL_LOG=$(mktemp)
```

**Tier 0 (persistent focus):** Read the persistent focus file written by `brana session epic focus`:
```bash
TIER0_SLUG=$(brana session epic status --json 2>/dev/null | jq -r '.focus // empty')
```
If empty, fall through to Tier 1 (still compute `$TIER2B_SLUGS` below — Tier 2b needs it
regardless of Tier 0's outcome).

**Corroboration gate (t-2618).** The focus file is global and persistent — whichever concurrent
session last called `brana session epic focus` captures routing for every session that closes
afterward, with no check that the slug belongs to *this* session. `brana session write` keys
handoffs by epic and **replaces** rather than merges, so a wrong slug destroys another epic's
live state (the exact t-2263 clobber class Tier 2a/2b's corroboration was added to prevent —
see the Converge note below). Tier 0 ran first and skipped every other tier, so it had no gate
at all. Before trusting a non-empty `$TIER0_SLUG`, corroborate it against this session's OWN
recent commits — the identical signal Tier 2b uses, computed once here and reused there:
<!-- TIER0-CORROBORATION-BLOCK -->
```bash
TIER2B_SLUGS=$(git log --oneline -20 2>/dev/null \
  | grep -oE 't-[0-9]+' | sort -u \
  | while read -r id; do resolve_epic_ancestor "$id" || echo "$id" >> "$EPIC_FAIL_LOG"; done \
  | sort -u | grep -v '^$')

if [ -n "$TIER0_SLUG" ]; then
    if echo "$TIER2B_SLUGS" | grep -qx "$TIER0_SLUG"; then
        INITIATIVE_SLUG="$TIER0_SLUG"
    else
        echo "⚠ Persistent focus is \"$TIER0_SLUG\" but this session's own commits resolve to \"$(echo "$TIER2B_SLUGS" | tr '\n' ',' | sed 's/,$//')\" (or nothing) — not routing on an uncorroborated global focus file. Falling through to Tier 1." >&2
    fi
fi
```
<!-- /TIER0-CORROBORATION-BLOCK -->
If corroborated (`$INITIATIVE_SLUG` now set): use it silently and skip Tier 1/2a/2b/2c/3. Do NOT
clear the focus file — it is persistent and only removed by `brana session epic unfocus`.
If corroboration failed or `$TIER0_SLUG` was empty: fall through to Tier 1.

**Per-worktree focus file? (AC, t-2618 — considered, not adopted.)** A per-worktree focus file
was considered as an alternative to corroboration. Rejected: this very session worked across
three worktrees (t-2593, t-2618, t-2603) as one continuous unit of work — a per-worktree file
would lose the focus signal on every worktree hop within a single session, which is the common
case here, not the exception. The corroboration gate fixes the clobber risk without giving up
cross-worktree continuity.

**Tier 1 (session-start marker):** Read the marker written by `brana run` at session start:
```bash
TIER1_SLUG=$(brana session epic read-marker 2>/dev/null)
```
If non-empty, use it as `$INITIATIVE_SLUG` silently and skip Tier 2a/2b/2c/3. Then clear the marker:
```bash
brana session epic clear-marker 2>/dev/null || true
```
If empty, fall through to Tier 2a.

**Tier 2a:** Query in-progress tasks and walk each to its epic ancestor:
```bash
TIER2A_SLUGS=$(brana backlog query --status in_progress --json 2>/dev/null \
  | jq -r '.[].id' \
  | while read -r id; do resolve_epic_ancestor "$id" || echo "$id" >> "$EPIC_FAIL_LOG"; done \
  | sort -u | grep -v '^$')
```
Collect non-empty results into the signal set; continue regardless. **Caveat:** this
queries in-progress tasks across the *whole portfolio*, including concurrently active
worktrees on completely unrelated epics — a hit here is not by itself evidence that the
slug belongs to *this* session (see Converge below).

**Tier 2b:** `$TIER2B_SLUGS` was already computed above, alongside Tier 0's corroboration gate
(identical extraction: task IDs from recent commits, walked to their epic ancestor) — do not
recompute it here. Fixes false Tier 3 prompts when all in_progress tasks completed before close
but this session's commits reference tasks whose parent chain resolves to an epic. Unlike Tier
2a, this is scoped to *this session's own* recent git history — a hit here means a task/commit
this session actually touched resolves to that epic.

**Check for lookup failures BEFORE converging (t-2487):**
```bash
if [ -s "$EPIC_FAIL_LOG" ]; then
    echo "⚠ epic lookup failed for: $(tr '\n' ' ' < "$EPIC_FAIL_LOG")" >&2
fi
```
If that log is non-empty the signal set is **incomplete, not narrow**. Do not take the
"exactly 1 unique slug" branch below — an unknown number of slugs were dropped, so a lone
survivor is not evidence of unambiguity. Fall through to the Tier 3 prompt and let the
user confirm, naming the failed task IDs. Routing on a mis-resolved slug is the t-2263
clobber class: `brana session write` keys handoffs by epic and **replaces** rather than
merges, so a wrong slug destroys another epic's state.

**Converge 2a + 2b:** Deduplicate the union of `$TIER2A_SLUGS` and `$TIER2B_SLUGS`.
- Exactly 1 unique non-empty slug **AND that slug also appears in `$TIER2B_SLUGS`** →
  use it silently as `$INITIATIVE_SLUG`. Done.
- Exactly 1 unique non-empty slug but it does **not** appear in `$TIER2B_SLUGS` (i.e. the
  only hit came from Tier 2a alone, with no corroborating task/commit this session
  touched) → **discard it — do not carry it into Tier 2c's signal set.** Fall through to
  Tier 2c treating the signal set as empty (see t-2263 note below — Tier 2c's own gate and
  re-converge would otherwise silently re-accept this same uncorroborated slug).
- 0 or 2+ → fall through to Tier 2c with that signal set unchanged.

**Why the corroboration requirement (t-2263):** Tier 2a alone found the sole slug
`"orbit"` from an in-progress task in a completely unrelated, concurrently active
worktree; Tier 2b was empty because the session's own tasks (created via an MCP tool
that had no `epic` parameter at the time, t-2263 AC1) carried no epic field. The old rule
accepted "orbit" silently — since it was the only slug found — and `brana session write`
then routed this session's handoff into `session-state-orbit.json`, clobbering the live
orbit session's state (the same failure class as the 2026-05-19 "same-day parallel close
loses data" field note, `close/SKILL.md`, t-1461 — replace-not-merge on shared state,
just keyed by epic instead of day). Requiring Tier 2b corroboration means a lone Tier 2a
hit with nothing in this session's own git history now falls through to Tier 2c (branch
name) instead of being trusted blindly.

**Tier 2c (branch name):** Parse branch name for a slug:
```bash
git branch --show-current | sed 's|.*/||'
```
Use result if it matches a known epic slug (non-empty, no special chars) **and the 2a+2b
signal set is empty at this point** — which per Converge above now includes the discarded
uncorroborated-single-hit case, not just a literally-empty union. (t-2263: this gate must
read the *post-discard* signal set, not the raw 2a∪2b union — otherwise an uncorroborated
Tier 2a hit like "orbit" would skip the branch-name check here and instead hit the
re-converge clause below on its own, silently re-accepting the exact slug Converge just
rejected.) Add the branch-name result to the (now-empty, or still-conflicting) signal set
and re-converge: exactly 1 unique → use silently. 0 or 2+ → fall through to Tier 3.

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

