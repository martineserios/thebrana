<!-- close phase: Steps 0-1: goal injection, gate check (CLOSE_MODE classification via CLOSE-ANCHOR-BLOCK) — continues in close-mode-and-evidence.md; loaded per the PHASES registry in ../SKILL.md (t-1942) -->

## Steps

### Step 0: Goal injection

Call `/goal "session closed: errata filed, learnings stored, tasks.json committed"` at close start. Fixed goal — no task context needed. Keeps every response during a long close oriented to completion rather than drifting into new work.

### Step 1: Gate check

**Bare orientation word normalization (t-3247).** Every orientation check in
this step — the close-classify.sh `--arguments` scan below, the HARD GUARD,
and the `ORIENTATION` derivation — matches on a literal `--flag` substring
(e.g. `--continue`). A bare word (`/brana:close continue`, no leading `--`)
silently misses all three and falls through to weaker fallback behavior with
no error: close-classify.sh degrades to file/commit-count heuristics, the
HARD GUARD fails to skip the picker it exists to skip, and `ORIENTATION`
derives `auto` instead of the intended flag (session-state.md and
cleanup.md key task-state transitions and cleanup skip-rules off that
derived value — the highest-blast-radius of the three). Normalize once,
here, before any of them run, so all three see the same corrected value for
the rest of Step 1:

<!-- ORIENTATION-NORMALIZE-BLOCK -->
```bash
# Only the four exact bare orientation words normalize — free-form focus text
# ($ARGUMENTS used as a Step 2 hint, e.g. "/brana:close hooks") passes through
# untouched, and an already-flagged $ARGUMENTS (e.g. "--continue") is left as-is.
case "$ARGUMENTS" in
    continue|finish|patterns|abort) ARGUMENTS="--$ARGUMENTS" ;;
esac
```
<!-- /ORIENTATION-NORMALIZE-BLOCK -->

> `ORIENTATION-NORMALIZE-BLOCK` is extracted verbatim by
> `tests/procedures/test-close-orientation-normalize.sh`. Keep the markers and
> fences intact.

Assess what happened this session:

<!-- GATE-WINDOW-BLOCK -->
```bash
# Widen the "both empty -> read-only" wall-clock window the same way t-3004
# widened SESSION_EPICS's window (CLOSE-ANCHOR-BLOCK below) — anchored on the
# newest session-state write across all epic files (UNSCOPED_LAST_CLOSE),
# floored at 6h so it only ever WIDENS, never narrows (a concurrent lane's
# fresher close can't shrink this window below the safe default — same
# narrowing-hazard invariant as t-3004; see that block's comment for the full
# rationale). Deliberately self-contained (does not source CLOSE-ANCHOR-BLOCK)
# so this gate stays independently testable and the "both empty" decision
# below stays purely wall-clock-derived — it still never consults the
# anchored COMMIT_COUNT, so t-2502's decoupling (see the note right after
# this block) is unaffected: widening the clock is not the same as trusting
# the anchor.
#
# Bug closed by this (t-3006, live 2026-08-22, this session's own close): the
# system clock had jumped ~20h overnight relative to this session's own
# commit timestamps. This flat `--since="6 hours ago"` came back empty even
# though the session had 7 of its own commits and had just merged 3 completed
# tasks — the "both empty -> write minimal handoff, skip to Step 9" shortcut
# below would have silently discarded a substantial, non-read-only session as
# if nothing happened. Caught only because CLOSE-ANCHOR-BLOCK's SESSION_EPICS
# (fixed in t-3004) was cross-checked manually; this gate had no equivalent
# safeguard of its own.
GATE_ALL_SESSIONS_JSON=$(brana session read --all --json 2>/dev/null)
GATE_UNSCOPED_LAST_CLOSE=$(echo "$GATE_ALL_SESSIONS_JSON" \
  | jq -r '[.[].state.written_at // empty] | map(select(. != "")) | sort_by(.[0:19]) | last // empty' 2>/dev/null)
GATE_SIX_HOURS_AGO_EPOCH=$(date -d '6 hours ago' +%s 2>/dev/null)
GATE_UNSCOPED_LAST_CLOSE_EPOCH=""
[ -n "$GATE_UNSCOPED_LAST_CLOSE" ] && GATE_UNSCOPED_LAST_CLOSE_EPOCH=$(date -d "$GATE_UNSCOPED_LAST_CLOSE" +%s 2>/dev/null)
if [ -n "$GATE_UNSCOPED_LAST_CLOSE_EPOCH" ] && [ -n "$GATE_SIX_HOURS_AGO_EPOCH" ] \
   && [ "$GATE_UNSCOPED_LAST_CLOSE_EPOCH" -lt "$GATE_SIX_HOURS_AGO_EPOCH" ]; then
  GATE_SINCE="@$GATE_UNSCOPED_LAST_CLOSE_EPOCH"
else
  GATE_SINCE="6 hours ago"
fi

git diff --stat HEAD~5..HEAD 2>/dev/null
git log --oneline --since="$GATE_SINCE" 2>/dev/null
```
<!-- /GATE-WINDOW-BLOCK -->

> `GATE-WINDOW-BLOCK` is extracted verbatim by `tests/procedures/test-close-gate-step1-window.sh`
> (t-3006). Keep the markers and fences intact. It duplicates ~10 lines of t-3004's
> UNSCOPED_LAST_CLOSE/floor-at-6h formula from CLOSE-ANCHOR-BLOCK rather than sourcing it,
> because CLOSE-ANCHOR-BLOCK is extracted and run in isolation by five other tests
> (test-close-gate-epic-anchor.sh, test-close-gate-foreign-epic.sh,
> test-close-gate-concurrent-anchor.sh, test-close-gate-session-epics-window.sh,
> test-close-gate-session-epics-duration.sh) — an inter-block dependency would silently
> break their isolated sourcing. If the widening formula changes, update both copies.

**State-file dirty check:** After the git commands above, also run:

```bash
git status --porcelain system/state/ 2>/dev/null
```

If any lines are returned (uncommitted changes in `system/state/`), warn and offer to auto-commit before proceeding:

```
AskUserQuestion:
  question: "system/state/ has uncommitted edits. Commit now before closing?"
  header: "State files dirty"
  options:
    - label: "Yes — auto-commit (chore(state): commit state files at session close)"
      description: "Stage and commit all system/state/ edits with standard message."
    - label: "No — skip and continue"
      description: "Leave state files uncommitted and proceed with close."
```

If "Yes":
```bash
git add system/state/
git commit -m "chore(state): commit state files at session close"
```

**If both empty** (no commits, no changes in the widened window above):
- This branch is decided by the wall-clock listing above (GATE_SINCE — widened same as
  SESSION_EPICS, floored at 6h; t-3006), NOT by the anchored `COMMIT_COUNT` — so a
  concurrent lane's close truncating the anchor (t-2502) can never route you here. That
  case surfaces instead inside the CLOSE-ANCHOR-BLOCK below as the `⚠ close window is
  EMPTY` warning with `ANCHOR_ZERO_WINDOW=1`: recent commits exist, the anchored window
  is empty, and Step 1b would queue nothing. When you see it, give Step 1b an explicit
  `--git-range <first-own-commit>^..HEAD` rather than trusting the computed window.
- Write a minimal handoff entry: `## YYYY-MM-DD — read-only session`
- Add only a **Next:** section from conversation context
- Skip to Step 9 (Write handoff note)

**Weight classification (NANO / LIGHT / INSTANT / FULL) — ADR-052 §5:**

Classify the session depth before spawning any agent. Use `git diff --name-only` — not
`--stat`, which outputs line counts requiring fragile extension parsing.

Since Track 1 (t-1973), sessions that previously auto-classified FULL now classify
**INSTANT**: snapshot + queue + handoff, no in-session extraction — the nightly cron
extracts from the queued diff instead. FULL (the in-session deep debrief) runs **only**
on explicit `--full`.

The classification logic lives in `system/scripts/close-classify.sh` — the
**single source of truth**, executed directly by both this gate and
`tests/procedures/test-close-weight-adaptive.sh`. Never inline or replicate the
matrix here (a replicated copy rotted silently once — t-1978).

**Path resolution — `$HOME/.claude/scripts/`, not `$(git-root)/system/scripts/`.**
`close-classify.sh`/`close-snapshot.sh`/`close-abort.sh` are thebrana-authored
scripts, but this skill runs inside whatever project the session is closing
(proyecto_anita, other clients, etc.) — those repos don't vendor a copy under
`system/scripts/`. `bootstrap.sh` deploys thebrana's `system/scripts/` →
`~/.claude/scripts/` (identical content, confirmed byte-for-byte) as the one
location guaranteed to exist regardless of project. Resolve from `$HOME`, matching
the convention already used elsewhere in this skill (`cf-env.sh`,
`backup-knowledge.sh` in metadata-and-memory.md / errata-and-patterns.md /
notes-and-ideation.md) — never `$(git rev-parse --show-toplevel)/system/scripts/`,
which only happens to resolve when the git-root IS thebrana itself.

<!-- CLOSE-ANCHOR-BLOCK -->
```bash
# Window anchored on the previous close's session-state written_at (t-1979 #11) —
# wall-clock windows miss long sessions and double-count short gaps. The 6h
# window is only the first-session fallback (no prior session state).
# Anchor on the NEWEST session state across the default AND epic-keyed files
# (t-2491). `brana session read` with no flags reads ONLY session-state.json —
# but a close that set an epic (Step 9c) routes its handoff to the epic-keyed
# file instead, leaving the default file stale. Anchoring on it made the window
# over-reach (32 commits instead of 4, live 2026-07-27) and re-queued commits an
# earlier close had already queued under a different range string, which
# close-snapshot.sh does NOT dedup. Every epic-routed close poisoned the next one.
#
# SECOND, INDEPENDENT TRIGGER — concurrency (t-2502, reproduced 7+ times
# 2026-07-27..2026-08-17): the store carries no lane identity (ADR-069), so any
# file this session may legitimately anchor on — the "(orphan)" default, or a
# same-epic peer's — can have been written minutes ago by a DIFFERENT concurrent
# session. No timestamp anchor can be right for "my work" on a shared checkout,
# and no anchor heuristic is allowed here (ADR-069 Rejected; three withdrawn in
# t-2502). What this block CAN do is refuse to fail silently — see the two
# visibility guards after COMMIT_COUNT below. The real fix is lane identity
# (ADR-069 D0-D3; t-2517/t-2520/t-2521).
#
# Epic-scoped corroboration (t-2603): taking the max written_at across ALL
# epic-keyed files unconditionally reintroduced a different bug — a CONCURRENT
# session on a completely unrelated epic that happens to close LATER than this
# one post-dates this session's own commits, and the window collapses (2/13
# commits queued, live 2026-08-02, confirmed 3x same day). `--all` files are
# only trustworthy anchors for THIS close if they belong to an epic this
# session's own recent commits actually resolve to (same resolve_epic_ancestor
# primitive used by close/phases/session-state.md Step 9c Tier 2b/t-2618) —
# or the orphan/default file, which every session can legitimately fall back to.
# Read ../../_shared/epic-ancestor-walk.md for resolve_epic_ancestor() if not
# already sourced this session.
#
# SESSION_EPICS used to run BEFORE LAST_CLOSE existed, bounded by a flat
# `--since="6 hours ago"` (t-2784), because the epic-SCOPED LAST_CLOSE below
# depends on SESSION_EPICS and can't be used to bound it — a chicken-and-egg.
# But the UNSCOPED max computed for AC2 further below has NO such dependency
# (it doesn't reference SESSION_EPICS at all) — it's just "the newest write
# across every session-state file, any epic" — so it's hoisted above
# SESSION_EPICS (t-3004) and reused as a widening signal, breaking the
# chicken-and-egg without inventing new state.
#
# Bug closed by this (t-3004, live 2026-08-20 and 2026-08-21, this session's
# own close both times): a session whose own commits landed 6.5h, then 16h,
# before close time fell entirely outside the flat 6h window — SESSION_EPICS
# resolved empty, LAST_CLOSE fell back to an orphan file 3 weeks stale, and
# COMMIT_COUNT computed as the entire history since that stale anchor (679,
# then 686 commits). This is exactly the tradeoff flagged below as
# "disclosed... not yet observed live" — now confirmed live twice.
#
# `--all` surfaces every session file; the default one appears as epic "(orphan)".
# Sort on the first 19 chars: writers emit UTC in two shapes ("...:01Z" and
# "...:31.372637410+00:00") which order correctly by their fixed-width
# YYYY-MM-DDTHH:MM:SS prefix but not as whole strings.
ALL_SESSIONS_JSON=$(brana session read --all --json 2>/dev/null)
UNSCOPED_LAST_CLOSE=$(echo "$ALL_SESSIONS_JSON" \
  | jq -r '[.[].state.written_at // empty] | map(select(. != "")) | sort_by(.[0:19]) | last // empty' 2>/dev/null)

# Floor at 6h, never narrow below it — do NOT just use UNSCOPED_LAST_CLOSE
# directly as SESSION_EPICS's `--since`. UNSCOPED_LAST_CLOSE can also be
# NEWER than 6h ago (e.g. a concurrent session on the shared checkout closes
# 5 minutes ago while this session's own commits landed 40 minutes ago).
# Anchoring on that closer timestamp would shrink the window to 5 minutes and
# silently drop this session's own 40-minute-old commits from corroboration —
# reintroducing, in smaller form, exactly the concurrency-narrowing class
# ADR-069 rejects anchor heuristics for (t-2502; see
# test-close-gate-concurrent-anchor.sh Case A, which exercises this and must
# keep passing). Taking the OLDER of {6h ago, UNSCOPED_LAST_CLOSE} only ever
# WIDENS the window, never narrows it — a concurrent close can widen the
# search but can never shrink it below the safe 6h default.
SIX_HOURS_AGO_EPOCH=$(date -d '6 hours ago' +%s 2>/dev/null)
UNSCOPED_LAST_CLOSE_EPOCH=""
[ -n "$UNSCOPED_LAST_CLOSE" ] && UNSCOPED_LAST_CLOSE_EPOCH=$(date -d "$UNSCOPED_LAST_CLOSE" +%s 2>/dev/null)
if [ -n "$UNSCOPED_LAST_CLOSE_EPOCH" ] && [ -n "$SIX_HOURS_AGO_EPOCH" ] \
   && [ "$UNSCOPED_LAST_CLOSE_EPOCH" -lt "$SIX_HOURS_AGO_EPOCH" ]; then
  SESSION_EPICS_SINCE="@$UNSCOPED_LAST_CLOSE_EPOCH"
else
  SESSION_EPICS_SINCE="6 hours ago"
fi

# Stopgap, not a fix for the class (t-2784, still true after t-3004): bounding
# by time — flat or widened — closes the overflow-into-an-older-close failure,
# but per ADR-069 (D0-D3, not yet shipped) no window prevents a CONCURRENT
# session's commits landing on the shared `dev` checkout within the same
# window from being picked up here too (confirmed live twice more the same
# day: t-2764's close and a prior close of this same session). That class
# needs per-commit/per-lane attribution (ADR-069 D3), not a wider window. A
# clean SESSION_EPICS here is not proof this session's epics are
# uncontaminated in a shared checkout.
#
# Sibling instance still open: session-state.md's Step 9c COMPLETED
# accumulator has the identical flat `-20` shape and is tracked separately as
# t-2480 (concurrent-session over-reach; not fixed by this change).
SESSION_EPICS=$(git log --oneline --since="$SESSION_EPICS_SINCE" 2>/dev/null \
  | grep -oE 't-[0-9]+' | sort -u \
  | while read -r id; do resolve_epic_ancestor "$id" 2>/dev/null; done \
  | sort -u | grep -v '^$')

LAST_CLOSE=$(echo "$ALL_SESSIONS_JSON" \
  | jq -r --arg epics "$SESSION_EPICS" '
      ($epics | split("\n") | map(select(. != ""))) as $mine |
      [.[] | select(.epic == "(orphan)" or (.epic as $e | $mine | index($e) != null)) | .state.written_at // empty]
      | map(select(. != "")) | sort_by(.[0:19]) | last // empty' 2>/dev/null)
# Fallback for an older binary without --all, or no session files yet.
[ -z "$LAST_CLOSE" ] && LAST_CLOSE=$(brana session read --json 2>/dev/null | jq -r '.written_at // empty' 2>/dev/null)

# AC2 (t-2603): don't trust the scoped anchor silently — the epic-scope filter
# above is a heuristic (a session whose commits reference no task IDs degrades
# to the orphan-only window, which is often but not always right). Compare
# against UNSCOPED_LAST_CLOSE (computed above, ahead of SESSION_EPICS since
# t-3004) and surface a visible warning on divergence, rather than reporting
# success either way. This never blocks the close.
if [ -n "$UNSCOPED_LAST_CLOSE" ] && [ "${UNSCOPED_LAST_CLOSE:0:19}" != "${LAST_CLOSE:0:19}" ]; then
    EXCLUDED_EPICS=$(echo "$ALL_SESSIONS_JSON" \
      | jq -r --arg epics "$SESSION_EPICS" '
          ($epics | split("\n") | map(select(. != ""))) as $mine |
          [.[] | select(.epic != "(orphan)" and (.epic as $e | ($mine | index($e)) == null)) | .epic]
          | unique | join(",")' 2>/dev/null)
    echo "⚠ scoped close anchor ($LAST_CLOSE) differs from the unscoped max across all session-state files ($UNSCOPED_LAST_CLOSE, epic(s): ${EXCLUDED_EPICS:-unknown}) — that file's epic isn't corroborated by this session's own commits (SESSION_EPICS: ${SESSION_EPICS:-none}). If it actually belongs to this session, its epic-detection must have missed it. Not treating this close as a clean success without a look: $HOME/.claude/sessions/session-state-*.json" >&2
fi

COMMIT_COUNT=$(git log --oneline --since="${LAST_CLOSE:-6 hours ago}" 2>/dev/null | wc -l | tr -d ' ')

# ── Visibility guards (t-2502) ────────────────────────────────────────────────
# Implements the INTENT of ADR-069 D3's out-of-scope note ("make the over-reach
# visible rather than silent — the reachable win"), NOT D3.2's reflog-attribution
# mechanism, which the ADR itself marks "do not implement as specified". These
# guards read only what this block already computed; they add no attribution.
# Neither guard moves the anchor or the window. They exist because the two
# concurrency failure shapes below are otherwise INVISIBLE, and an invisible
# miss is worse than a visible double-extraction. Both print to stderr only;
# neither blocks the close.
#
# (a) ZERO WINDOW. The anchor exists and post-dates every commit in the
#     fallback window, so COMMIT_COUNT=0. Two causes are indistinguishable
#     without lane identity: this session genuinely made no commits since its
#     own last close (read-only), or a CONCURRENT lane's close truncated the
#     window to nothing. The second has been observed live 4+ times and, left
#     silent, COMMIT_COUNT=0 makes CHANGED_FILES a null diff and Step 1b's
#     snapshot exits without queueing anything — the session's work is never
#     extracted, and nothing says so. So: name the anchor's source, set
#     ANCHOR_ZERO_WINDOW=1, and let the closer decide (Step 1b with an explicit
#     --git-range). Quiet when there are no recent commits at all (nothing
#     could have been truncated — that is the genuine read-only case, which
#     Step 1's wall-clock listing above already routes).
# Widened flat fallback (24h, t-3017) — NOT the UNSCOPED_LAST_CLOSE-anchored
# formula t-3004/t-3006 use elsewhere in this block. That formula cannot fix
# this specific check: LAST_CLOSE is always <= UNSCOPED_LAST_CLOSE by
# construction (LAST_CLOSE is chosen from a subset of the same
# ALL_SESSIONS_JSON that UNSCOPED_LAST_CLOSE maxes over), so whenever
# COMMIT_COUNT==0 below (the only case RECENT_COMMITS matters for),
# LAST_CLOSE already postdates every recent commit — and so does
# UNSCOPED_LAST_CLOSE. No UNSCOPED_LAST_CLOSE-anchored widening can ever
# reach back further than the very anchor that caused the zero window in the
# first place (verified by direct construction, not just argued — see
# test-close-gate-recent-commits-window.sh). A generous FLAT fallback,
# independent of any session-state anchor, is the only mechanism that can
# actually widen this specific check. Safe because RECENT_COMMITS is
# diagnostic-only: it feeds the stderr warning below, never gates real
# behavior. 24h comfortably covers both live clock-skew magnitudes recorded
# so far (16h t-3004, 20h t-3006) with margin; widen further if a session
# exceeds it.
#
# Disclosed tradeoff (challenger review, t-3017): the mirror image of fixing
# the silent-miss case is that the ⚠ EMPTY warning below now fires on more
# shared-checkout noise too — any commit from ANY lane in the last 24h can
# trigger it, not just the last 6h. Acceptable: the guard is stderr-only,
# advisory, and never blocks (same accepted tradeoff shape as the
# over-reach guard right below this one).
RECENT_COMMITS=$(git log --oneline --since="24 hours ago" 2>/dev/null | wc -l | tr -d ' ')
ANCHOR_ZERO_WINDOW=0
if [ "${COMMIT_COUNT:-0}" -eq 0 ] && [ -n "$LAST_CLOSE" ] && [ "${RECENT_COMMITS:-0}" -gt 0 ]; then
    ANCHOR_ZERO_WINDOW=1
    LAST_CLOSE_EPIC=$(echo "$ALL_SESSIONS_JSON" \
      | jq -r --arg ts "${LAST_CLOSE:0:19}" \
          '[.[] | select((.state.written_at // "")[0:19] == $ts) | .epic] | unique | join(",")' 2>/dev/null)
    echo "⚠ close window is EMPTY: anchor $LAST_CLOSE (session-state epic: ${LAST_CLOSE_EPIC:-unknown}) post-dates all $RECENT_COMMITS commit(s) of the last 24h. If any of those commits are this session's, a CONCURRENT lane's close truncated the window (t-2502 — do not re-file) or this session's clock/commits are older than 6h (t-3006/t-3017 — do not re-file that either). Do NOT treat this as a read-only session on this signal alone: confirm this session made no commits, or re-run Step 1b with an explicit --git-range <first-own-commit>^..HEAD (git log --since='24 hours ago' to find it)." >&2
fi

# (b) OVER-REACH. On the shared checkout the window contains other lanes'
#     commits (measured live 2026-08-17: 24 commits, 2 own, SESSION_EPICS=4).
#     A contiguous range cannot exclude them and no anchor change helps; but
#     SESSION_EPICS resolving to >1 epic is the visible symptom, so say so.
SESSION_EPIC_COUNT=$(printf '%s\n' "$SESSION_EPICS" | grep -c . || true)
if [ "${SESSION_EPIC_COUNT:-0}" -gt 1 ]; then
    echo "⚠ close window spans $SESSION_EPIC_COUNT epics ($(printf '%s\n' "$SESSION_EPICS" | paste -sd, -)) — on a shared checkout this window very likely holds concurrent lanes' commits (over-reach, t-2502 — do not re-file). Step 1b will queue them all; narrow with an explicit --git-range if you know this session's own commits. Real fix: lane identity (ADR-069 D3, t-2521)." >&2
fi
# ── end visibility guards ─────────────────────────────────────────────────────

CHANGED_FILES=$(git diff --name-only HEAD~"${COMMIT_COUNT:-1}"..HEAD 2>/dev/null)

CLOSE_MODE=$(echo "$CHANGED_FILES" | bash "$HOME/.claude/scripts/close-classify.sh" \
    --commit-count "${COMMIT_COUNT:-0}" --arguments "$ARGUMENTS")
```
<!-- /CLOSE-ANCHOR-BLOCK -->

> `CLOSE-ANCHOR-BLOCK` is extracted verbatim by `tests/procedures/test-close-gate-epic-anchor.sh`,
> `tests/procedures/test-close-gate-foreign-epic.sh`,
> `tests/procedures/test-close-gate-concurrent-anchor.sh` (t-2502 visibility guards),
> `tests/procedures/test-close-gate-session-epics-window.sh` (t-2784 overflow-exclusion),
> `tests/procedures/test-close-gate-session-epics-duration.sh` (t-3004 long-session widening) and
> `tests/procedures/test-close-gate-recent-commits-window.sh` (t-3017 RECENT_COMMITS widened
> fallback). Keep the markers and fences intact.
> This block calls `resolve_epic_ancestor` — the extracting test must source
> `system/skills/_shared/epic-ancestor-walk.md`'s `EPIC-WALK-BLOCK` first.


Continues in `close-mode-and-evidence.md` — Step 1's orientation/picker/abort handling, Step 1b (snapshot+queue), Step 2 (gather evidence), Step 3 (extract+classify), Step 3b (doc-update check).
