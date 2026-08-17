<!-- close phase: Steps 0-3b: goal injection, gate check (CLOSE_MODE), gather evidence, extract+classify findings, doc-update check — loaded per the PHASES registry in ../SKILL.md (t-1942) -->

## Steps

### Step 0: Goal injection

Call `/goal "session closed: errata filed, learnings stored, tasks.json committed"` at close start. Fixed goal — no task context needed. Keeps every response during a long close oriented to completion rather than drifting into new work.

### Step 1: Gate check

Assess what happened this session:

```bash
git diff --stat HEAD~5..HEAD 2>/dev/null
git log --oneline --since="6 hours ago" 2>/dev/null
```

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

**If both empty** (no commits, no changes in 6 hours):
- This branch is decided by the wall-clock 6h listing above, NOT by the anchored
  `COMMIT_COUNT` — so a concurrent lane's close truncating the anchor (t-2502) can never
  route you here. That case surfaces instead inside the CLOSE-ANCHOR-BLOCK below as the
  `⚠ close window is EMPTY` warning with `ANCHOR_ZERO_WINDOW=1`: recent commits exist,
  the anchored window is empty, and Step 1b would queue nothing. When you see it, give
  Step 1b an explicit `--git-range <first-own-commit>^..HEAD` rather than trusting the
  computed window.
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
# SESSION_EPICS runs BEFORE LAST_CLOSE exists (it feeds LAST_CLOSE's own file
# filter above) so it cannot bound itself on LAST_CLOSE — a chicken-and-egg. Use
# the same 6h fallback window this block's own first-session-fallback comment
# already documents, not a flat commit-count window (t-2784): a low-commit
# session's `-20` tail has no relationship to session boundaries and can
# overflow into an unrelated PRIOR close's commits, resolving that close's epic
# as if it were this session's own (confirmed live 2026-08-12, this session's
# own close).
#
# Stopgap, not a fix for the class (t-2784): bounding by time closes the
# overflow-into-an-older-close failure above, but per ADR-069 (D0-D3, not yet
# shipped) no window — time or count — prevents a CONCURRENT session's commits
# landing on the shared `dev` checkout within the same window from being picked
# up here too (confirmed live twice more the same day: t-2764's close and this
# session's own close). That class needs per-commit/per-lane attribution
# (ADR-069 D3), not a narrower window. A clean SESSION_EPICS here is not proof
# this session's epics are uncontaminated in a shared checkout.
#
# Second tradeoff, disclosed (challenger gate, t-2784): trading a count window
# for a time window doesn't just close over-reach, it opens the opposite
# failure — a session running LONGER than 6h whose epic-identifying commit
# landed near session start now falls OUTSIDE the window, so that epic never
# enters SESSION_EPICS and its session-state file loses corroboration here.
# Not yet observed live; flagged so it isn't mistaken for solved.
#
# Sibling instance still open: session-state.md's Step 9c COMPLETED
# accumulator has the identical flat `-20` shape and is tracked separately as
# t-2480 (concurrent-session over-reach; not fixed by this change).
SESSION_EPICS=$(git log --oneline --since="6 hours ago" 2>/dev/null \
  | grep -oE 't-[0-9]+' | sort -u \
  | while read -r id; do resolve_epic_ancestor "$id" 2>/dev/null; done \
  | sort -u | grep -v '^$')

# `--all` surfaces every session file; the default one appears as epic "(orphan)".
# Sort on the first 19 chars: writers emit UTC in two shapes ("...:01Z" and
# "...:31.372637410+00:00") which order correctly by their fixed-width
# YYYY-MM-DDTHH:MM:SS prefix but not as whole strings.
ALL_SESSIONS_JSON=$(brana session read --all --json 2>/dev/null)
LAST_CLOSE=$(echo "$ALL_SESSIONS_JSON" \
  | jq -r --arg epics "$SESSION_EPICS" '
      ($epics | split("\n") | map(select(. != ""))) as $mine |
      [.[] | select(.epic == "(orphan)" or (.epic as $e | $mine | index($e) != null)) | .state.written_at // empty]
      | map(select(. != "")) | sort_by(.[0:19]) | last // empty' 2>/dev/null)
# Fallback for an older binary without --all, or no session files yet.
[ -z "$LAST_CLOSE" ] && LAST_CLOSE=$(brana session read --json 2>/dev/null | jq -r '.written_at // empty' 2>/dev/null)

# AC2 (t-2603): don't trust the scoped anchor silently — the epic-scope filter
# above is a heuristic (a session whose commits reference no task IDs degrades
# to the orphan-only window, which is often but not always right). Compute the
# pre-t-2603 UNSCOPED max too and surface a visible warning on divergence,
# rather than reporting success either way. This never blocks the close.
UNSCOPED_LAST_CLOSE=$(echo "$ALL_SESSIONS_JSON" \
  | jq -r '[.[].state.written_at // empty] | map(select(. != "")) | sort_by(.[0:19]) | last // empty' 2>/dev/null)
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
RECENT_COMMITS=$(git log --oneline --since="6 hours ago" 2>/dev/null | wc -l | tr -d ' ')
ANCHOR_ZERO_WINDOW=0
if [ "${COMMIT_COUNT:-0}" -eq 0 ] && [ -n "$LAST_CLOSE" ] && [ "${RECENT_COMMITS:-0}" -gt 0 ]; then
    ANCHOR_ZERO_WINDOW=1
    LAST_CLOSE_EPIC=$(echo "$ALL_SESSIONS_JSON" \
      | jq -r --arg ts "${LAST_CLOSE:0:19}" \
          '[.[] | select((.state.written_at // "")[0:19] == $ts) | .epic] | unique | join(",")' 2>/dev/null)
    echo "⚠ close window is EMPTY: anchor $LAST_CLOSE (session-state epic: ${LAST_CLOSE_EPIC:-unknown}) post-dates all $RECENT_COMMITS commit(s) of the last 6h. If any of those commits are this session's, a CONCURRENT lane's close truncated the window (t-2502 — do not re-file). Do NOT treat this as a read-only session on this signal alone: confirm this session made no commits, or re-run Step 1b with an explicit --git-range <first-own-commit>^..HEAD (git log --since='6 hours ago' to find it)." >&2
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
> `tests/procedures/test-close-gate-foreign-epic.sh` and
> `tests/procedures/test-close-gate-concurrent-anchor.sh` (t-2502 visibility guards). Keep the
> markers and fences intact.
> This block calls `resolve_epic_ancestor` — the extracting test must source
> `system/skills/_shared/epic-ancestor-walk.md`'s `EPIC-WALK-BLOCK` first.

**Orientation flags (ADR-053, t-1980).** `$ARGUMENTS` may carry an orientation — `--continue`, `--finish`, `--patterns`, `--abort` — saying WHY the session is closing. close-classify.sh maps orientation to a forced weight (continue/finish → INSTANT, patterns → LIGHT-INLINE, abort → NANO); the call above already passes `--arguments`, so the orientation reaches the classifier with no extra wiring (programmatic callers can equivalently pass `--mode-override <orientation>` — same mapping, same precedence). Set `ORIENTATION` to the flag name when present, `auto` otherwise.

| Orientation | Weight | Task state (Step 9, session-state.md) | Cleanup (Steps 11b/11d) |
|---|---|---|---|
| `--continue` | INSTANT | stays `in_progress` — resumable handoff | skipped |
| `--finish` | INSTANT | → `completed` | runs |
| `--patterns` | LIGHT-INLINE | unchanged | skipped |
| `--abort` | NANO | → `pending` + reason (via close-abort.sh) | script handles branch |

**`--finish` runs the in-session L2 propagation audit** (Step 8b, ADR-056) even though its weight is INSTANT — expect a short LLM pass over touched specs/memories before the handoff. This is the one deliberate exception to "INSTANT = no in-session LLM work"; surface it in the picker's `--finish` description so the user isn't surprised by the latency. Other INSTANT closes run only the ~1s deterministic L1 checks and defer the deep audit to the nightly cron.

**HARD GUARD — flag given means decision made.** If `$ARGUMENTS` contains ANY orientation or weight flag (`--continue`, `--finish`, `--patterns`, `--abort`, `--light`, `--full`, `--nano`): SKIP the entire "Bare-invocation detection and picker" block below. Do not show a picker, do not run detection — execute the flagged close immediately.

**Bare-invocation detection and picker** (no flag in `$ARGUMENTS` only):

1. Compute hard signals (each individually best-effort — a failed command is "no signal", never a block):
   ```bash
   DIRTY=$(git status --porcelain 2>/dev/null | head -1)
   MERGED=$(git branch --merged dev 2>/dev/null | grep -vE 'main|dev' | grep -c "$(git branch --show-current)" || true)
   TASK_STATUS=$(brana backlog query --status in_progress --output json 2>/dev/null | jq -r '.[0].status // empty' 2>/dev/null || true)
   ```
2. Candidate set from signals: task in flight or dirty tree → `--continue`; branch merged or task completed → `--finish`; both kinds of signal present (conflict — likely stale task state) → all candidates, NO recommended option. `--patterns` is NEVER an auto-detected candidate (git state cannot signal "discoveries happened") — include it only if the conversation shows pattern-worthy material (a workaround found, a gotcha documented, a reusable approach discussed).
3. From conversation context, pick the recommended candidate ("done"/"bye" → `--finish`; "break"/"switching"/context pressure → `--continue`; abandoned approach → `--abort`).
4. Ask — options labeled with their flags (the picker teaches the flags; the user graduates to typing them):
   ```
   AskUserQuestion:
     question: "How should this session close?"
     header: "Close mode"
     options:
       - label: "{Recommended orientation} (--{flag}) (Recommended)"   # omit "(Recommended)" entirely on signal conflict
         description: "{why the signals point here}"
       - label: "{next-likely} (--{flag})"
         description: "..."
       # 2-4 options; AskUserQuestion's built-in Other covers the rest
   ```
5. Treat the chosen flag as if it had been passed in `$ARGUMENTS`: append it to `$ARGUMENTS` and re-run the close-classify.sh line above so `CLOSE_MODE` reflects the choice.

**`--abort` execution:** before anything else, require a reason (free text follows the flag, e.g. `/brana:close --abort "approach invalidated"`; none given → ask). If the tree is dirty, ask: stash / hard reset (show what's lost) / leave. Then run the tested sequence — never inline git commands:
```bash
bash "$HOME/.claude/scripts/close-abort.sh" \
    --task-id "{active task id}" --reason "{reason}" --dirty "{stash|reset|leave}"
```
The script archives the branch as a pushed `aborted/*` tag, lands on main, returns the task to pending. After it succeeds: write the minimal handoff (Step 9, reason only) and skip everything else.

Ambiguous cases (authoritative — do not infer):
- `.sh` edit → INSTANT (behavioral, high-stakes — cron extracts tonight; `--full` for in-session debrief)
- `tasks.json` only → NANO (state file, single commit — write handoff and skip Steps 4-8)
- `settings.json` → INSTANT (behavioral config — matches `^\.claude/.*\.json$`)

**NANO mode:** write handoff note (Step 9) only. Skip Steps 3–8 entirely (no debrief agent, no errata, no patterns, no field notes, no ideation, no drift). NANO sessions have nothing worth extracting — the overhead costs more than the signal. **NANO does not queue** (ADR-052 §5).

Announce: `Close mode: $CLOSE_MODE (orientation: $ORIENTATION)` before proceeding to Step 1b. The orientation is REQUIRED in the announcement — `--continue` and `--finish` share the INSTANT weight token, and downstream phases (session-state.md task-state mapping, cleanup.md skip rules) resolve behavior from the orientation, not the weight.

### Step 1b: Snapshot + queue (INSTANT / LIGHT / FULL — never NANO, never LIGHT-INLINE)

LIGHT-INLINE (`--patterns`) is structurally excluded here: extraction runs NOW in Step 3, so queueing the same session for the nightly cron would double-extract — the documented exception to ADR-052 §5 (ADR-053 §3). Skip this step entirely for LIGHT-INLINE.

Queue the session diff for tonight's extraction cron (ADR-052; never blocks).

**Compute the range explicitly (t-2242)** — never let the script re-derive it via
`HEAD~N`: the Step 1 `COMMIT_COUNT` is topological (`git log --oneline` counts
commits brought in by `--no-ff` merges) while `HEAD~N` walks first-parent only,
so any merge commit inside the window makes the queued range over-reach and
swallow a concurrent session's commits (two live hits, proyecto_anita 2026-07-02).
Anchor on the oldest session commit from the SAME listing that produced
`COMMIT_COUNT`:

<!-- SNAPSHOT-INVOCATION-BLOCK -->
```bash
OLDEST=$(git log --format=%H --since="${LAST_CLOSE:-6 hours ago}" 2>/dev/null | tail -1)
if [ -n "$OLDEST" ] && git rev-parse -q --verify "${OLDEST}^" >/dev/null 2>&1; then
    SESSION_RANGE="$(git rev-parse --short "${OLDEST}^")..$(git rev-parse --short HEAD)"
else
    SESSION_RANGE=""   # root commit or empty session — let the script fall back
fi

# Pass --git-range UNCONDITIONALLY (t-2478). The previous form was
# ${SESSION_RANGE:+--git-range "$SESSION_RANGE"} — but zsh does not word-split
# unquoted parameter expansions, so close-snapshot.sh received the single
# argument '--git-range A..B' and exited "unknown argument". The snapshot then
# silently fell back to the known-wrong HEAD~N..HEAD range this very step exists
# to avoid. An EMPTY value is already equivalent to omitting the flag
# (close-snapshot.sh gates on `[ -n "$GIT_RANGE_ARG" ]`), so no ${:+} is needed.
# Same class as pattern_zsh-for-loop-no-word-split; Step 11c below already
# carries the sibling workaround.
bash "$HOME/.claude/scripts/close-snapshot.sh" \
    --git-root "$(git rev-parse --show-toplevel)" \
    --branch "$(git branch --show-current)" \
    --project "$(basename "$(git rev-parse --show-toplevel)")" \
    --commit-count "${COMMIT_COUNT:-0}" \
    --git-range "$SESSION_RANGE"
```
<!-- /SNAPSHOT-INVOCATION-BLOCK -->

> `SNAPSHOT-INVOCATION-BLOCK` is extracted verbatim by
> `tests/procedures/test-close-gate-zsh-argv.sh`, which runs it under both bash and zsh.
> Keep the markers and fences intact.

The script diffs `--git-range` verbatim (falling back to the known-wrong
`HEAD~N..HEAD` only when the range is absent), saves it to
`~/.claude/sessions/snap-*.diff` (500KB cap), appends a queue entry via
`brana close-queue append` (dedup-safe — re-running close on the same range is
a no-op), and degrades to a stderr warning + exit 0 if the brana binary is
missing. Do not gate close on its output. Zero commits → it exits silently
without queueing.

### Step 2: Gather evidence

Collect from multiple sources:

1. **Git log + diffs** (same `written_at` anchor as Step 0 — reuse `$LAST_CLOSE`):
   ```bash
   git log --oneline --since="${LAST_CLOSE:-6 hours ago}" 2>/dev/null
   git diff --stat HEAD~5..HEAD 2>/dev/null
   ```
2. **Conversation context** — review for: errors hit, workarounds used, surprises, things that didn't match expectations
3. **If `$ARGUMENTS` provided** — use as focus hint (e.g., `/brana:close hooks` focuses on hook-related findings)
4. **Scheduler sweep outputs** — check for unprocessed agy sweep results:
   ```bash
   ls system/scheduler/outputs/*.md 2>/dev/null
   ```
   If files exist: read each, extract findings (same EXTRACT rules as Step 3), then remove:
   ```bash
   rm system/scheduler/outputs/<processed-file>.md
   ```
   Fire-and-forget sweeps write here overnight; close is the only consumer.

### Step 3: Extract and classify findings

Branch on `$CLOSE_MODE` from Step 1.

**INSTANT mode** — skip Steps 3–8 entirely. No debrief agent, no errata, no
patterns, no field notes, no ideation, no drift: the queued snapshot carries the
session's diff to tonight's extraction cron (Track 2), which routes findings to
the reminder store. Proceed directly to Step 9 (handoff — `brana session write`
runs as always).

**FULL mode** (explicit `--full` only) — spawn `debrief-analyst` (Sonnet):

```
Agent(subagent_type="debrief-analyst", prompt="Debrief this session. Focus on: what was built, any errata or spec mismatches found, process learnings. Check git log and conversation context.")
```

**LIGHT mode** — inline scan, no agent spawn:
1. `git log --oneline -10` — list what was committed
2. Review conversation for: errors, workarounds, surprises
3. Classify into the three buckets below

**LIGHT-INLINE mode** (`--patterns` orientation) — the user explicitly asked to extract NOW. Run the same inline scan as LIGHT (steps 1–3 above), then Steps 4–5 (errata + patterns) inline. Skip Steps 6–8 (field notes, ideation, drift), skip Step 1b (no queue — ADR-053 §3), skip Step 9c and Steps 10–11, no task-state change, no cleanup. This mode is extraction and nothing else.

If debrief-analyst is unavailable in FULL mode, fall back to the LIGHT inline scan.

**Classification buckets:**

| Bucket | What it is | Example |
|--------|-----------|---------|
| **Errata** | Spec says X, reality is Y | "Spec says `hooks recall`, actual API is `memory search`" |
| **Learning** | Reusable insight about how to work | "DB schema drift breaks things silently" |
| **Issue** | Something broken, not a spec mismatch | "Deploy script doesn't handle symlinks" |

### Step 3b: Doc-update check

Detect behavioral changes that lack corresponding documentation updates.

**Skip if:** session was read-only (no commits).

1. **Get files changed this session:**
   ```bash
   git diff --name-only HEAD~10..HEAD 2>/dev/null
   ```

2. **Classify changed files:**

   | Category | Glob patterns |
   |----------|--------------|
   | **Behavioral** | `system/skills/**`, `system/hooks/**`, `system/agents/**`, `system/commands/**`, `system/cli/**`, `**/rules/**` |
   | **Documentation** | `docs/architecture/**`, `docs/guide/**`, `docs/reference/**`, `*CLAUDE.md` |

   Walk the changed file list and tag each matching file as `behavioral` or `documentation`. Files matching neither are ignored.

3. **Hook script additions check (t-1490):** If any `system/hooks/*.sh` files appear in the changed file list AND `docs/architecture/hooks.md` is NOT in the changed file list, warn — even if other docs were updated:

   ```bash
   HOOK_SCRIPTS=$(git diff --name-only HEAD~10..HEAD 2>/dev/null | grep '^system/hooks/.*\.sh$')
   HOOKS_MD_UPDATED=$(git diff --name-only HEAD~10..HEAD 2>/dev/null | grep -c 'docs/architecture/hooks\.md')
   ```

   If `HOOK_SCRIPTS` is non-empty AND `HOOKS_MD_UPDATED` is 0:
   ```
   ⚠ Hook script(s) added/modified without updating docs/architecture/hooks.md:
   {list of hook .sh files}
   Fix: update the inventory table and gate classification in docs/architecture/hooks.md.
   ```
   Add to `next[]` regardless of user choice:
   ```json
   {"text": "hooks.md update needed for: {hook scripts}", "task_id": null, "category": "maintenance"}
   ```

4. **If behavioral files changed but NO documentation files changed**, prompt:

   Build a mapping of each behavioral file to its most likely doc target. Use these heuristics:
   - `system/skills/{name}/SKILL.md` → `docs/architecture/skills.md`
   - `system/hooks/**` → `docs/architecture/hooks.md`
   - `system/agents/**` → `docs/architecture/agents.md`
   - `system/commands/**` → `docs/architecture/commands.md`
   - `system/cli/**` → `docs/reference/brana-cli.md`
   - `**/rules/**` → `docs/architecture/rules.md`

   Present via AskUserQuestion:
   ```
   AskUserQuestion:
     question: "Behavioral files changed without docs. Update now?"
     header: "Doc-update check"
     options:
       - label: "Draft doc updates now"
         description: "Read changed behavioral files and write doc updates inline."
       - label: "Add to session handoff (defer)"
         description: "Record doc update as a next[] item for the next session."
       - label: "Skip"
         description: "Defer with a low-priority reminder in next[] (not silently dropped)."
     context: |
       Changed behavioral files:
       - {file} → {suggested doc target}
       ...
   ```

   **If "Draft doc updates now":**
   - For each behavioral file, read it and draft a concise doc update suggestion
   - Present the drafted updates for approval before writing
   - Write approved updates via Edit

   **If "Add to session handoff (defer)":**
   - Add an entry to the session state `next` array (Step 9) with `category: "maintenance"`:
     ```json
     {"text": "Doc update needed: {behavioral file} → {doc target}", "task_id": null, "category": "maintenance"}
     ```

   **If "Skip":** still add a low-priority reminder to `next[]` (never silently drop):
   ```json
   {"text": "Doc update skipped at close: {behavioral file} → {doc target}", "task_id": null, "category": "maintenance"}
   ```
   Then continue to Step 5.

5. **If both behavioral AND documentation files changed**, or no behavioral files changed, skip silently.

6. **Track metrics** for session state (Step 9):
   - `behavioral_files_changed`: count of behavioral files in the diff
   - `doc_files_changed`: count of documentation files in the diff
   - `doc_prompts_accepted`: 1 if "Draft now", 0 otherwise
   - `doc_prompts_skipped`: 1 if "Skip", 0 otherwise

