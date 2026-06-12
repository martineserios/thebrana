<!-- type: manual-procedure — not CI-automated -->
# Manual procedure: PROPAGATE 7-gap re-simulation (t-2003, ADR-056)

Human-graded checklist re-simulating the seven propagation gaps from the
origin case (proyecto_anita t-1306, 2026-06-12) that a clean close failed to
detect. The deterministic subset (gaps 1, 3, 7) is also CI-covered by
`test-close-propagate.sh`; this procedure grades the LLM-judgment layers
(L2/L3) that CI deliberately does not gate (ADR-056 Consequences).

**Convention note:** `.md` files in `tests/procedures/` are human-graded
manual procedures, distinguished from automated `.sh` tests by extension and
the `type: manual-procedure` marker above. `bash tests/procedures/*.sh`
correctly skips them.

## Fixture setup

In a scratch git repo with a `.claude/tasks.json` and one task `t-001`
(`in_progress`, subject "Feature X"), create state mirroring t-1306, then run
a session that touches these files (≥1 commit) and close with
`/brana:close --finish`:

| # | Origin gap | Fixture state | Layer expected to catch |
|---|-----------|---------------|------------------------|
| 1 | Spec Status obsolete ("live run pending" after 2 runs) | touched spec with `**Status:** live run pending` | L1 (`PROP-GAP\|status`) — CI-covered |
| 2 | Shape phase row outdated | touched shape with a phase table row claiming "F1 in progress" while F1's commits are in the session diff | L2 category (b) |
| 3 | test-strategy.md pointer promised, never written | touched spec Documentation Plan: `- [ ] **Existing docs to update** — test-strategy.md pointer` | L1 (`PROP-GAP\|checkbox`) — CI-covered |
| 4 | capture-format.md note routed by challenger, never written | conversation contains a challenger finding "route the compatibility note to capture-format.md"; no such edit exists | L2 category (e) — session-bounded |
| 5 | ADR committed "al cerrar F1", never created | touched shape containing "El ADR se creará al cerrar F1"; no ADR file exists | L1 candidate (`PROP-CANDIDATE\|promise`) → L2 category (a) confirms |
| 6 | Project memory stale ("pending go" after close) | `.claude/memory/feature-x.md` containing "estado: pending go" | L2 category (d) |
| 7 | tasks.json uncommitted | modify `.claude/tasks.json` after the last commit | L1 (`PROP-GAP\|tasksjson`) — CI-covered |

## Expected behavior — grade each line

### Gate

- [ ] Step 8b announces it runs (no `PROPAGATE: skip`) on `--finish`
- [ ] Re-running the close after compaction does NOT duplicate gaps
      (re-entry guard: `fix(propagate):` at HEAD or gaps already announced)
- [ ] Control: `/brana:close --abort "test"` on the same fixture skips
      PROPAGATE entirely

### Detection (per gap)

- [ ] Gap 1 flagged: `PROP-GAP|status|{spec}|Status 'live run pending' vs task t-001 'completed'`
- [ ] Gap 2 flagged by L2 as category (b) with the stale phase row quoted
- [ ] Gap 3 flagged: `PROP-GAP|checkbox|{spec}|N unchecked Documentation Plan item(s)`
- [ ] Gap 4 flagged by L2 as category (e), citing the in-conversation challenger routing
- [ ] Gap 5 surfaced as `PROP-CANDIDATE|promise` by L1 AND confirmed by L2 as
      category (a) (promise unfulfilled — no ADR exists)
- [ ] Gap 6 flagged by L2 as category (d), quoting the contradicted memory claim
- [ ] Gap 7 flagged: `PROP-GAP|tasksjson|...`

### Output contract — zero silent drops

- [ ] Every flagged gap ends as an inline fix (committed as
      `fix(propagate): ...`) or a `next[]` entry with `category: "maintenance"`
      in the session state (`brana session read` after close)
- [ ] Step 12 report shows `**Propagation gaps:** {N found} (...)` with
      N ≥ 7 minus inline-fixed count consistent
- [ ] On L2 success the queue entry's flag is cleared:
      `brana close-queue list` shows `"propagate": false` for this close

### L3 (deferred path)

- [ ] Repeat the fixture with a bare `/brana:close` (INSTANT, no `--finish`):
      entry queued with `"propagate": true`, L2 does not run
- [ ] Run `bash system/cron/close-extraction.sh` — gaps 2, 5, 6 (repo-state
      detectable) arrive as reminders tagged `propagation` with dedup keys
      `prop:{project}:{slug}`; gap 4 is correctly ABSENT (session-bounded,
      unavailable at cron time by design)
- [ ] Fix one gap manually, re-trigger the pass (re-queue a new range):
      the fixed gap is suppressed (post-close-resolution check)

## Pass criteria

All deterministic lines (gaps 1, 3, 7, gate, output contract) must pass.
LLM-judgment lines (gaps 2, 4, 5-confirm, 6, L3 suppression): ≥80% per run,
graded across two runs — LLM variance is expected; persistent misses are
prompt/bound defects, file them against the phase file.

## Record

| Date | Runner | Deterministic | LLM-judgment | Notes |
|------|--------|---------------|--------------|-------|
| | | | | |
