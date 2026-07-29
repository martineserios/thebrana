# Feature: validate.sh Check 68 — worktree/task divergence

**Date:** 2026-07-29
**Status:** specifying
**Task:** t-2545

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

**D1 — Idle threshold: 14 days.** Justified by this repo's own rule rather than fitted to
the sample. `git-discipline.md` §Keep branches short-lived states "Features: days. Fixes:
hours. Docs: one session." — 14 days is already several times the longest sanctioned life,
so a branch crossing it has left the regime the rule describes.

The measured distribution *corroborates* but does not *set* the threshold. Worktree HEAD
ages on 2026-07-29 were 0, 0, 0, 4 — then nothing at all until 37, 39. Every value in
(4, 37] classifies today's tree identically, so the sample cannot discriminate between
candidate thresholds and must not be used to pick one. 14d sits inside that gap, which
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
on a worktree minutes old — training people to ignore the check, which is precisely the
failure `t-2531` diagnosed in the WIP cap ("a cap that never enforces trains the operator
to ignore warnings"). Rejected: **all-four-warn**, which is that same failure by construction.

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
  for one problem inflates the count.
- **Branch with no `t-NNN`** — reported as `NO-TASK-ID` (warn), not silently skipped.
- **Task id in the branch but absent from the backlog** — a lookup failure, not a negative.
  Reported as a distinct case; must never be collapsed into "no divergence" (t-2487 class,
  `pattern_exit-code-is-not-evidence-of-work`).
- **Detached HEAD worktree** — no branch line in `git worktree list --porcelain`; skipped
  with a warning.
- **Empty worktree with no commits** — `git log -1` fails; idle age is unknown, not 0.

## Design

Two files, mirroring the Check 67 precedent so the logic is testable outside validate.sh
(`feedback_extract-from-for-testability`):

- `system/scripts/check-worktree-divergence.sh` — all logic. Takes an optional repo root.
  Exit 0 = no contradictions; exit 1 = at least one ORPHAN or FIELD-MISMATCH. Warnings go
  to stdout and do not affect exit status.
- `validate.sh` — a ~12-line `should_run 68` block that runs the script, indents its output,
  and maps its exit status onto `pass`/`fail`, exactly as Check 67 does.

Backlog reads use `brana backlog get <id> --field <f>`, one field at a time — the same
no-jq form the epic-ancestor walk adopted in t-2487, chosen because a command substitution
piped to `jq` exits 0 on unparseable input and fails open.

**Implementation trap (recorded on t-2545):** this loop lost `PATH` mid-iteration when
written inline in the zsh harness (`command not found: head/tr/basename`). It runs correctly
as a bash script file. Do not port it back to an inline one-liner.

## Boundaries

| Always | Ask First | Never |
|--------|-----------|-------|
| Report divergence and name its category | Removing or pruning a worktree | Write to tasks.json / call `backlog set` |
| Distinguish lookup failure from "no divergence" | Changing the 14d threshold | Auto-correct a stale `task.branch` field |
| Exclude the main checkout | — | Alter the WIP cap or its inputs |

## Testing Strategy

- **Unit (70%):** category classification driven by fixture inputs — orphan, mismatch,
  field-null, idle, clean, no-task-id, unknown-task. Pure decision logic, no git.
- **Integration (25%):** a temporary git repo with real `git worktree add` worktrees and a
  stub `brana` on `PATH`, asserting exit status and emitted categories end to end.
- **E2E (5%):** one `./validate.sh --check 68` smoke run.
- **Mock policy:** real git (cheap, and the porcelain parsing is what's under test); `brana`
  stubbed at the process boundary since the real backlog is mutable global state.

## Documentation Plan

- [ ] **Tech doc** — this file.
- [ ] **User guide** — none. Check 68 surfaces through `./validate.sh` output; no new command
      or config for a user to learn.
- [ ] **Existing docs to update** — `docs/architecture/validate-checks.md` if a check
      inventory exists there; verify during CLOSE.

## Challenger findings

_pending_
