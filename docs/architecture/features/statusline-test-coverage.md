---
depends_on:
  - system/statusline.sh
  - system/hooks/post-tasks-validate.sh
---
# Statusline Test Coverage

## Test Files

All live in `system/hooks/tests/`. Only the epic suite is wired into `validate.sh`
(Check 65); the rest are standalone and must be run by hand.

| File | Scope | Tests | Status |
|------|-------|-------|--------|
| `test-statusline-cache.sh` | TSV cache fields, build_step extraction, mtime freshness | 12 | 8/12 — drifted |
| `test-statusline-width.sh` | Width detection, progressive segment dropping | 15 | 15/15 |
| `test-session-score.sh` | Session score counter lifecycle, statusline segment | 14 | 11/14 — drifted |
| `test-statusline-integration.sh` | End-to-end: cache flow, session lifecycle, staleness recovery, empty state, width+segments | 74 | 37/74 — drifted |
| `test-statusline-epic.sh` | Epic resolution ladder: branch epic → project-local `active_epic`; ADR-066 global-isolation guard; malformed/empty/null config; subdirectory resolution (t-2467) | 14 | 14/14 |

## Integration Test Scenarios

1. **Full render** — all segments present on wide terminal (model, project, branch, CTX%, lines, task, build step, bugs, phase, session score)
2. **Cache to statusline flow** — post-tasks-validate.sh creates cache, statusline.sh reads it without jq
3. **Session lifecycle** — reset counter at session start, increment on completions, verify statusline reflects updates
4. **Staleness recovery** — stale cache detected via mtime, jq fallback fires, cache refreshed inline
5. **Empty/missing state** — no tasks.json, no cache, no score file; statusline renders cleanly with exit 0
6. **Width + segments combined** — narrow terminal with task data drops low-priority segments while keeping model and CTX%

## Epic Resolution Ladder (t-2467)

The `🎯` slot resolves in strict order, first hit wins:

1. **Branch epic** — first segment of a 3-segment task branch (`{epic}/{work-type}/t-NNN-slug`).
2. **Project-local `active_epic`** — `$GIT_ROOT/.claude/tasks-config.json`, then
   `$GIT_ROOT/system/state/tasks-config.json` (thebrana's layout; it has no `.claude/` copy).
3. **Nothing** — the slot is omitted entirely.

The global `~/.claude/tasks-config.json` is **never** consulted: per
[ADR-066](../decisions/ADR-066-active-epic-project-scoped-only.md), `active_epic` is
project-scoped with exactly one authoritative source. `test-statusline-epic.sh` T7 pins
this by pointing `HOME` at a fixture whose global config carries a sentinel value.

Values from config are scrubbed of backslashes and newlines before rendering — the output
path uses `printf '%b'`, which interprets escapes, so an unscrubbed value could break the
one-line contract. Branch names cannot carry these (git forbids them in refs).

## Field Notes

### 2026-07-27: Three of four legacy statusline suites are drifted, not broken by change
`test-statusline-cache.sh` (8/12), `test-session-score.sh` (11/14) and
`test-statusline-integration.sh` (37/74) fail identically before and after t-2467. They
assert a much richer statusline — cache TSV, session score, build_step, bugs, phase — than
the current 61-line `system/statusline.sh` renders. The script was simplified and these
suites were never retired or updated. Baseline them before blaming a change; 44 failing
assertions are the pre-existing state, not a regression signal.
Source: t-2467, session 2026-07-27

### 2026-07-27: The 44 drifted assertions are retired; all statusline suites now gated by Check 66 (t-2470)
Resolved the entry above by retiring the stale assertions rather than restoring the
segments — `system/statusline.sh` is deliberately a single line of
`model │ project │ branch │ epic │ CTX bar`, and the tests, not the script, were the drift.

Removed: the cache fast-path/jq-fallback/refresh scenarios (`test-statusline-cache.sh`
tests 7–9), the session-score rendering assertions, and the integration suite's cache-flow,
session-lifecycle, staleness-recovery, width-dropping, slow-cache, knowledge-freshness/decay,
job-detection, learning-velocity and two-line-layout scenarios. `test-statusline-integration.sh`
went from 671 lines / 74 assertions to 194 / 14.

**Corrected, not deleted:** the CTX assertions. CTX *is* rendered — only its format changed
(the bar now sits between the label and the percentage), so the literal `"CTX 42%"` needle
was split into two rather than dropped. Deleting it would have silently given up real coverage.

Each removed scenario was replaced with a **negative** guard asserting the segment stays
absent, so the simplification is now itself under test — verified by re-adding an `S: 5✓`
segment to the script and confirming two suites go red.

All four suites (`width`, `cache`, `session-score`, `integration`) are wired into
`validate.sh` Check 66; the epic suite remains on Check 65. Both checks are self-contained
and run standalone under `--check` (t-2471).
Source: t-2470, session 2026-07-27

### 2026-04-10: Show both metrics — don't change units to resolve apparent contradiction
When two status displays seem contradictory (e.g., `CTX 78%` vs `7% until auto-compact`), the fix is to make their relationship explicit — add a complementary suffix (`·7c`) in the warning zone — not to change what the primary metric represents. Changing the metric breaks the user's mental model. The pair (used%, distance-to-threshold) is coherent; only the visual link was missing.
Source: t-1114, session 2026-04-10
