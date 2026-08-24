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
| `test-statusline-epic.sh` | Epic resolution ladder: branch epic → dynamic in_progress-task epic → nothing (no config fallback, ADR-088); local/global config always inert; malformed tasks/config files; subdirectory resolution; same-day tie-break; control-byte scrub (t-2467, t-2639, revised t-3196) | 19 | 19/19 |

## Integration Test Scenarios

1. **Full render** — all segments present on wide terminal (model, project, branch, CTX%, lines, task, build step, bugs, phase, session score)
2. **Cache to statusline flow** — post-tasks-validate.sh creates cache, statusline.sh reads it without jq
3. **Session lifecycle** — reset counter at session start, increment on completions, verify statusline reflects updates
4. **Staleness recovery** — stale cache detected via mtime, jq fallback fires, cache refreshed inline
5. **Empty/missing state** — no tasks.json, no cache, no score file; statusline renders cleanly with exit 0
6. **Width + segments combined** — narrow terminal with task data drops low-priority segments while keeping model and CTX%

## Epic Resolution Ladder (t-2467, t-2639, revised t-3196/ADR-088)

The `🎯` slot resolves in strict order, first hit wins:

1. **Branch epic** — first segment of a 3-segment task branch (`{epic}/{work-type}/t-NNN-slug`).
2. **Dynamic in_progress-task epic** (t-2639) — the flat `.epic` field of the
   most-recently-started `in_progress` task in `$GIT_ROOT/.claude/tasks.json` (ties on
   `.started`, which is date-only in practice, broken by higher numeric task id). Only the
   pre-v3 flat `.epic` field is read — thebrana's own tasks.json has none (v3 moved epics to
   parent-chain ancestors, ADR-065/t-2284), so this step is a confirmed permanent no-op for
   thebrana's own repo and only fires for client/venture projects still on the flat schema.
3. **Nothing** — the slot is omitted entirely.

**The static `tasks-config.json`/`active_epic` fallback step is retired** (ADR-088, t-3196) —
`active_epic` is no longer a config-file concept anywhere in the codebase, statusline included.
Neither the project-local config (`.claude/` or thebrana's `system/state/` layout) nor the
global `~/.claude/tasks-config.json` is ever consulted for this slot; `test-statusline-epic.sh`
T5-T7 pin this (malformed/leftover config files are inert, local AND global both never surface).
This mirrors `resolve_focus_epic()` in `brana-core` — the same task-derived resolution,
expressed twice (shell for the hot-path render, Rust for `cmd_focus`/MCP), not unified into one
code path (a `brana`-subprocess-per-render would very likely blow the statusline's latency
budget).

Values from the dynamic task-derived source are scrubbed of backslashes and all raw control
bytes before rendering — the output path uses `printf '%b'`, which interprets backslash
escapes, so an unscrubbed value could break the one-line contract. Branch names cannot carry
these (git forbids them in refs), but a task's `.epic` field is automation-written JSON. The
scrub originally stripped only literal `\n`/`\r` sequences; t-2639 widened it to strip all
control bytes after the challenger gate found a raw control byte decoded from a JSON string
escape has no backslash character left for the narrower strip to catch.

## Field Notes

### 2026-08-24: Static active_epic fallback removed — retired along with the config file it read (ADR-088, t-3196)
The step-3 static fallback added 2026-08-05 (below) is gone — not just deprioritized, deleted
entirely. `active_epic` stopped being a config-file concept anywhere in the codebase (session-
scoped, task-derived resolution replaces it — see `session-scoped-epic-focus.md`), so the two-
path `tasks-config.json` lookup this fallback did (`.claude/`, then `system/state/`) had nothing
left to read. No new statusline logic was needed: steps 1-2 already implemented the exact
resolution `resolve_focus_epic()` (brana-core) generalizes into Rust for `cmd_focus`/MCP
`backlog_focus` — this file's own dynamic-fallback design (2026-08-05 entry) turned out to be
the correct long-term mechanism, just not yet reused elsewhere until this build. Test suite
went from 21 to 19 assertions (2 tests whose entire purpose was the now-deleted config-read path
were removed rather than retargeted — no equivalent behavior exists to test).

### 2026-08-11: Added a session-id segment (🪪); a first close mistakenly marked the task done before it was ever built
`system/statusline.sh` gained a `🪪 {8-char-session-id-prefix}` segment, sourced from the
statusline hook's own stdin JSON (`.session_id`) — never `BRANA_SESSION_ID`, which is set
but not exported to child processes. Placed between `🎯 epic` and `CTX` in render order.
Value is truncated to 8 chars, then scrubbed of backslashes and raw control bytes before the
`printf '%b'` sink — same two-line pattern `EPIC` already uses (challenger gate caught the
scrub missing on the first implementation pass; see the finding trail on t-2731).
`test-statusline-integration.sh` gained 3 new scenarios (render, control-byte-scrub
regression mirroring `test-statusline-epic.sh`'s B8, and graceful degradation when
`session_id` is absent) — 20 → 22 assertions, still 22/22.

Notable: the task (t-2731) had already been marked `completed` once before this build, by a
close/reconcile step that read the branch's "0 commits ahead, 8 behind dev" as "already
merged" — the branch had in fact never had any commits, BUILD had never run. Ahead=0 doesn't
distinguish "fully merged" from "nothing was ever committed"; see
`pattern_branch-ahead-zero-is-ambiguous-merged-vs-never-worked` in project memory.

### 2026-08-05: Static active_epic went stale without a task-branch checkout — added a dynamic fallback
Reported bug: proyecto_anita's statusline stayed on `anita-envios` for days while the user
worked `env-hardening`/`agent-memory` tasks on `main` — nothing recuts the branch when work
shifts epics without a task-branch checkout, so the static `active_epic` fallback (step 3
above) never updates on its own. Added step 2 (dynamic in_progress-task epic) ahead of it.
Challenger gate on t-2639 found two real, non-blocking gaps in the first pass: production
`.started` values are date-only, so same-day ties (a realistic occurrence given this
project's own concurrent-work style — 10 simultaneous in_progress tasks at review time) were
breaking on arbitrary array order; and the pre-existing `active_epic` scrub, now reused for
the wider-reach dynamic source, only stripped literal `\n`/`\r` and missed raw control bytes
with no backslash character for it to catch. Both fixed same-day: tie-break by numeric task
id, scrub widened to strip all control bytes.
Source: t-2639, session 2026-08-05

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
