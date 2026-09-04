<!-- close phase: Step 9c: initiative accumulator — cross-day state upsert (ADR-044); continues from session-state.md's Step 9/9b; loaded per the PHASES registry in ../SKILL.md (t-1942) -->

## Steps (continued from session-state.md)

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
# Session-scoped window (t-2768): a flat `git log -20` is not scoped to this
# session's own boundary — on a low-commit session it overflows into a PRIOR
# DAY's unrelated session (live incident 1, 2026-08-12: 1 own commit, but the
# -20 tail picked up ~17 commits from the previous day's session), and on a
# high-concurrency shared branch it overflows into OTHER SESSIONS' commits
# landing in real time (live incident 2, same day: 3 slugs surfaced from
# concurrent peer commits on dev). Anchor on the SAME $LAST_CLOSE this
# session's gate-and-evidence.md Step 0 GATE (CLOSE-ANCHOR-BLOCK) already
# computed — the identical anchor its own COMMIT_COUNT/CHANGED_FILES/OLDEST
# already rely on — instead of recomputing a separate window here.
TIER2B_SLUGS=$(git log --oneline --since="${LAST_CLOSE:-6 hours ago}" 2>/dev/null \
  | grep -oE 't-[0-9]+' | sort -u \
  | while read -r id; do resolve_epic_ancestor "$id" || echo "$id" >> "$EPIC_FAIL_LOG"; done \
  | sort -u | grep -v '^$')

if [ -n "$TIER0_SLUG" ]; then
    if echo "$TIER2B_SLUGS" | grep -qx "$TIER0_SLUG"; then
        INITIATIVE_SLUG="$TIER0_SLUG"
    else
        echo "⚠ Persistent focus is \"$TIER0_SLUG\" but this session's own commits resolve to \"$(echo "$TIER2B_SLUGS" | tr '\n' ',' | sed 's/,$//')\" (or nothing) — not routing on an uncorroborated global focus file. Falling through to Tier 1." >&2
        # Same anchor as the CLOSE-ANCHOR-BLOCK, same truncation (t-2502): if that
        # block flagged an empty window, TIER2B_SLUGS is empty for the same reason
        # and this "mismatch" is an artefact of a concurrent lane's close, not
        # evidence against the focus. Say so instead of leaving it generic.
        if [ "${ANCHOR_ZERO_WINDOW:-0}" = "1" ]; then
            echo "  ↳ note: the close anchor window is EMPTY (ANCHOR_ZERO_WINDOW=1, t-2502) — TIER2B_SLUGS is empty because a concurrent lane's close post-dates this session's commits, so this corroboration miss is probably spurious. Verify with git log --since='6 hours ago' before trusting the fall-through." >&2
        fi
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
If the user skips: set `INITIATIVE_SLUG` to the literal sentinel string `(orphan)` —
**do not** leave it empty or omit `epic` from the Step 9 payload (t-3169). Omitting the field
is indistinguishable to `brana session write` from "let the CLI infer one," and it infers the
persistent Tier 0 focus marker even after that same marker was just rejected by Tier 0's own
corroboration gate above — the write silently lands in the focus marker's file instead of the
orphan one the user actually chose. The sentinel (`brana_core::session::ORPHAN_EPIC_SENTINEL`)
overrides the focus-marker fallback and routes straight to the orphan file, and is stripped
back to `null` before persistence, so it never shows up as a fake epic slug later. Skip Pass 2
and the "Write accumulator" step below entirely (no `brana session epic upsert` call) — the
sentinel only affects the Step 9 payload's `epic` field, there is no accumulator for "no
epic." Proceed to Step 10.

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

