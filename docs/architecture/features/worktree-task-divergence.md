# Feature: validate.sh Check 68 — worktree/task divergence

**Date:** 2026-07-29
**Status:** shipped
**Task:** t-2545

## Changelog
- 2026-07-31: Check 68 implemented and merged to `dev` (t-2545). Threshold 7d (revised from 14 on 2026-07-31);
  contradictions fail, omissions warn. Remediated the two live contradictions found by
  the check itself — t-2138's orphaned worktree removed, t-2173's branch field corrected
  from a branch that did not exist.

## Problem

Three signals claim to answer "what work is in flight" and none is authoritative: the WIP
cap counts backlog depth, `status:in_progress` counts what someone remembered to set, and
live git worktrees count what was actually started. t-2541 measured them on 2026-07-28 and
found they disagreed in every direction.

Nothing detects the disagreement. t-2541 grepped all 67 existing validate checks and
`system/hooks/session-end-drift.sh` and found zero references to worktree staleness or
orphan detection. The 39-day-old orphan below was found by eye, while listing worktrees for
an unrelated reason.

Measured again on 2026-07-29, **2 of 5 worktrees are clean**:

| worktree | task | status | idle | divergence |
|---|---|---|---|---|
| `thebrana-orbit-t2173` | t-2173 | in_progress | 37d | FIELD-MISMATCH + IDLE |
| `thebrana-t2138` | t-2138 | completed | 39d | ORPHAN |
| `thebrana-t2443` | t-2443 | in_progress | 4d | clean |
| `thebrana-t2492` | t-2492 | in_progress | 0d | FIELD-NULL |
| `thebrana-t2545` | t-2545 | in_progress | 0d | clean |

## Decision Record

The four load-bearing decisions were made and recorded on **t-2541** (operator, 2026-07-28)
and are **not re-opened here**. This spec implements them. In summary:

- **Derived is authoritative.** Worktree + branch + commit recency outrank the task field.
  The field is a cache to be corrected, not trusted. Declared state is retained only for
  work that has no branch yet.
- **Fail loud, never auto-correct.** A silent auto-fix would have rewritten t-2173's branch
  field to match the repo and destroyed the evidence the two had diverged for 37 days.
  Auto-correct is *right* in all observed cases and still *wrong*, because it erases the
  drift rate.
- **Lives in validate.sh**, not in `session-end-drift.sh` (per `rules-over-hooks-for-gates.md`).
- **Does not touch the WIP cap.** The cap stays anti-sprawl over live children (t-2535).
  This is a separate measure.

Two decisions were left open by t-2541 and are settled here (operator, 2026-07-29):

**D1 — Idle threshold: 7 days** (revised from 14 on 2026-07-31 — see below). Justified by
this repo's own rule rather than fitted to the sample. `git-discipline.md` §Keep branches
short-lived states "Features: days. Fixes: hours. Docs: one session." — a week is already
generous against that, so a branch crossing it has left the regime the rule describes.

**Revision (2026-07-31, from t-2547's measurement).** The value was first set to 14 as
"several times the longest sanctioned life" — a qualitative argument the build evaluator
flagged as the softest point in this spec. Measuring the repo's actual promotion cadence
made 14 look loose: ship happens at a **median of 2 commits, roughly twice a day** (79 ship
events; mean 7, only 2 batches ≥ 50). In a workflow moving that fast, a worktree untouched
for two weeks is not stale but abandoned. 7d still sits inside the empty 5–36 day span of
the observed distribution, so the tightening costs no false positives on the observed tree.
This is the spec's own revisit trigger firing on new evidence — which is what it was for.

The measured distribution *corroborates* but does not *set* the threshold. Worktree HEAD
ages on 2026-07-29 were 0, 0, 0, 4 — then nothing at all until 37, 39. Every value in
(4, 37] classifies today's tree identically, so the sample cannot discriminate between
candidate thresholds and must not be used to pick one. 7d sits inside that gap, which
means it fires on zero false positives today; that is a property of the choice, not the
reason for it.

**D2 — Contradictions fail, omissions warn.**

| Category | Severity | Why |
|---|---|---|
| ORPHAN | `fail` | The record asserts the work is finished while the worktree is still there. A contradiction. |
| FIELD-MISMATCH | `fail` | `task.branch` names a branch the worktree is not on. The record asserts something false. |
| FIELD-NULL | `warn` | The record is incomplete, not wrong. Nothing false is asserted. |
| IDLE | `warn` | A judgment about elapsed time, not a contradiction. Legitimately paused work exists. |

Rejected: **all-four-fail**. It would go red on t-2492, whose only fault is an unset field
on a worktree minutes old — training people to ignore the check. Rejected: **all-four-warn**,
which is that failure by construction.

`t-2531` made the same *diagnosis* about the WIP cap ("a cap that never enforces trains the
operator to ignore warnings"), and the reasoning is shared. It is deliberately **not** cited
as evidence that this split works: the WIP cap's actual remedy (t-2535) narrowed the
counting predicate rather than adding a fail/warn split, and its own closing note records
that "the cap remains ADVISORY — D4's warn-vs-hard-block promotion review is untouched and
still open," with zero tasks parked at merge. The repo's nearest analogue is itself
unresolved, so D2 stands on the contradiction-vs-omission logic alone.

## Constraints

- Read-only with respect to the backlog. The check never issues a `backlog set`.
- Must not require network or the MCP server — validate.sh runs standalone.
- Must be green on a clean tree (AC5), so the two live offenders are remediated as part of
  t-2545 rather than merged red.

## Scope (v1)

- Detect and distinctly report ORPHAN, FIELD-MISMATCH, FIELD-NULL, IDLE.
- Report `in_progress`-with-no-worktree as information only.
- Ship as `system/scripts/check-worktree-divergence.sh` + a validate.sh wrapper, following
  the Check 67 / `check-adr-uniqueness.sh` precedent.

Out of scope: suggesting or performing remediation; per-epic derived WIP counts (t-2541 Q4
kept these separate from the cap).

## Assumptions

- **Task id is derivable from the branch name** (`t-NNN`). Guaranteed going forward by
  t-2540 (epic segment mandatory) + t-2542 (guard enforces it on `git worktree add -b`).
  All 5 current worktrees conform. A branch with no `t-NNN` is reported as its own case
  rather than skipped, so the assumption fails loudly if it ever stops holding.
- **The main checkout is excluded.** It tracks `dev`, has no `t-NNN`, and is not "work in
  flight" in the sense being measured.
- **Commit recency is measured on the worktree's HEAD**, not on divergence from `dev`. A
  worktree whose branch was merged but never removed still reads as idle from its last
  commit, which is the signal wanted.
- **`brana` resolves the canonical `tasks.json` regardless of which worktree it runs from.**
  Verified 2026-07-29: `.claude/tasks.json` is git-tracked, so every worktree carries its own
  copy at a different inode, and this branch's copy was two hours stale — yet a read issued
  from inside the worktree returned the main checkout's current value. The check therefore
  reports the same answer from any worktree. Had it read the local copy instead, it would
  grade live worktrees against a snapshot frozen at branch-cut time and manufacture
  divergences that do not exist.

## Behavior

- Running `./validate.sh` reconciles every live worktree against its task record and prints
  one line per divergent worktree, naming the category.
- ORPHAN or FIELD-MISMATCH increments the error count and turns the run red; FIELD-NULL and
  IDLE increment warnings only.
- `in_progress` tasks with no worktree print under an informational heading and affect
  neither count.
- On a tree where every worktree agrees with its task, the check prints a single PASS line.

## Edge Cases

- **Overlapping categories.** A worktree can qualify for several at once (t-2138 is orphan,
  field-null and idle simultaneously). ORPHAN suppresses the others for that worktree: once
  the task is closed, the state of its branch field is moot, and reporting three findings
  for one problem inflates the count. **Suppression must not discard the idle age**, which
  says something a bare orphan does not — a 39-day orphan is a different problem from a
  1-day one. The line reads `ORPHAN (task completed, idle 39d)`: one finding, no lost datum.
- **Branch with no `t-NNN`** — reported as `NO-TASK-ID` (warn), not silently skipped.
- **Task id in the branch but absent from the backlog** — a lookup failure, not a negative.
  Reported as a distinct case; must never be collapsed into "no divergence" (t-2487 class,
  `pattern_exit-code-is-not-evidence-of-work`).
- **Detached HEAD worktree** — no branch line in `git worktree list --porcelain`; skipped
  with a warning.
- **Commit-date lookup fails** — `git log -1` returns nothing for the worktree. Idle age is
  reported as unknown, never as 0, so a failed lookup cannot read as "fresh". (A worktree
  with genuinely no history is near-unreachable, since `git worktree add -b` inherits the
  base ref; the guard is against the lookup failing, not against an empty repo.)

## Design

Two files, mirroring the Check 67 precedent so the logic is testable outside validate.sh
(`feedback_extract-from-for-testability`):

- `system/scripts/check-worktree-divergence.sh` — all logic. Takes an optional repo root.
  Exit 0 = no contradictions; exit 1 = at least one ORPHAN or FIELD-MISMATCH. Warnings go
  to stdout and do not affect exit status.
- `validate.sh` — a ~12-line `should_run 68` block that runs the script, indents its output,
  and maps its exit status onto `pass`/`fail`, exactly as Check 67 does.

**`set -uo pipefail` — no `-e`.** Copy this verbatim from `check-adr-uniqueness.sh:20`, not
from validate.sh, which uses `set -euo pipefail` (validate.sh:2). Under `-e` the first
non-zero `brana` exit aborts the loop mid-iteration: the remaining worktrees are never
examined and the script exits on whatever partial output happened to land. That is the
"collapse into no divergence" failure this spec forbids, arriving at the control-flow level
rather than the single-lookup level. The Check 67 wrapper's `if C67_OUT=$(bash ...); then`
guard exists for the same reason.

Backlog reads use `brana backlog get <id> --field <f>`, one field at a time — the same
no-jq form the epic-ancestor walk adopted in t-2487, chosen because a command substitution
piped to `jq` exits 0 on unparseable input and fails open.

**Schema self-test before trusting any `null`.** `cmd_get` indexes the task JSON directly,
so a *missing key* and a key whose value *is* null both print `null` at exit 0 — verified
2026-07-29: `brana backlog get t-2443 --field totally_bogus_field` returns `null`, exit 0,
indistinguishable from `--field branch` on a task with no branch. Inheriting the
epic-walk's collapse of both cases (`[ "$out" = "null" ] && out=""`) is correct *there*,
where both mean "keep walking," and wrong *here*, where the FIELD-NULL bucket is defined by
"genuinely unset."

Consequence if unguarded: this repo has renamed or retired backlog fields three times
already (Checks 62/63/64 — tags, level/epic, stream). The next rename of `branch` or
`status` would silently classify every worktree as FIELD-NULL forever — no crash, no loud
signal, a permanently wrong warning bucket.

So the script first fetches one full task object and asserts that `status` and `branch` are
present as literal keys. Absent → exit non-zero with "schema drift: field <name> not present
on <task>", before any classification runs. One extra subprocess call.

**Cost.** Each `--field` read reparses tasks.json in a fresh subprocess: ~0.09s measured,
2 reads per worktree plus the one self-test — ~1s at today's 5 worktrees, growing linearly.
Acceptable now; if worktree count grows materially, batch to a single full-JSON read.

**Implementation trap (recorded on t-2545):** this loop lost `PATH` mid-iteration when
written inline in the zsh harness (`command not found: head/tr/basename`). It runs correctly
as a bash script file. Do not port it back to an inline one-liner.

## Boundaries

| Always | Ask First | Never |
|--------|-----------|-------|
| Report divergence and name its category | Removing or pruning a worktree | Write to tasks.json / call `backlog set` |
| Distinguish lookup failure from "no divergence" | Changing the 7d threshold | Auto-correct a stale `task.branch` field |
| Exclude the main checkout | Promoting IDLE/FIELD-NULL to `fail` | Alter the WIP cap or its inputs |

**Revisit triggers** (the Ask-First rows are otherwise untestable intentions):
- Reconsider the 7d threshold if IDLE fires on the same worktree across 3+ consecutive
  validate runs — that means the warning is being read and ignored, not acted on.
- Reconsider the warn severity of IDLE/FIELD-NULL under the same condition. This is the
  gap t-2531 left open in the WIP cap: a warning with no stated path to teeth stays
  advisory forever by default.

## Testing Strategy

- **Unit (70%):** category classification driven by fixture inputs — orphan, mismatch,
  field-null, idle, clean, no-task-id, unknown-task. Pure decision logic, no git.
- **Integration (25%):** a temporary git repo with real `git worktree add` worktrees and a
  stub `brana` on `PATH`, asserting exit status and emitted categories end to end.
- **E2E (5%):** one `./validate.sh --check 68` smoke run.
- **Mock policy:** real git (cheap, and the porcelain parsing is what's under test); `brana`
  stubbed at the process boundary since the real backlog is mutable global state.

## Documentation Plan

- [x] **Tech doc** — this file. Written and kept current through the 7d revision.
- [x] **User guide** — none, deliberately. Check 68 surfaces through `./validate.sh` output; no new command
      or config for a user to learn.
- [x] **Existing docs to update** — none. Verified at close 2026-07-31:
      `docs/architecture/validate-checks.md` does not exist, so there is no check
      inventory to keep in sync.

## Challenger findings

Reviewed 2026-07-29 (context-isolated). Verdict **RECONSIDER**, on two Sev-4 findings —
both mechanical gaps with an in-repo precedent to copy, not a design fault. Both were
independently reproduced before being accepted.

| Sev | Finding | Disposition |
|-----|---------|-------------|
| 4 | `set -e` unstated; copying validate.sh's `set -euo pipefail` would abort the loop on the first `brana` non-zero — the forbidden collapse, one level up | **Accepted.** Design now mandates `set -uo pipefail` verbatim from `check-adr-uniqueness.sh:20`. |
| 4 | A missing key and a null value both print `null` at exit 0, so a field rename would silently mean FIELD-NULL forever | **Accepted, reproduced:** `--field totally_bogus_field` → `null`, exit 0. Design now requires a schema self-test before any `null` is trusted. |
| 3 | t-2531 cited as evidence the fail/warn split works, but the WIP cap's remedy never added such a split and remains advisory | **Accepted.** Citation demoted to shared diagnosis; D2 now rests on its own logic. |
| 2 | ORPHAN suppression discards the idle age | **Accepted.** Age embedded in the ORPHAN line. |
| 2 | threshold has no revisit trigger | **Accepted.** Revisit triggers added to Boundaries. |
| 2 | Subprocess cost grows linearly with worktree count | **Accepted as a note**, not a change — ~1s today; batching recorded as the remedy if it grows. |
| 2 | "Empty worktree with no commits" is near-unreachable | **Accepted.** Reworded to "commit-date lookup fails". |
