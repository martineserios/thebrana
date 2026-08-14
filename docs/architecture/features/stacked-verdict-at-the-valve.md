# Feature: Stacked verdict at the valve

**Date:** 2026-08-14
**Status:** specifying
**Task:** t-2857

## Problem

Three evidence layers already exist in this codebase but nothing composes them at the
moment a human actually decides — `ac approve` or a merge:

1. **Deterministic** — AC-grammar machine verdicts (`ac-grammar.md` heuristics 1–10,
   executed today only inside `goal-completion.sh`'s Stop-hook loop).
2. **Judged** — Evaluator/Challenger gate grades, currently free-text prose appended to
   a task's `notes` field with no parseable structure.
3. **Executed** — ADR-076 build receipts (`brana receipt validate --json`), a real,
   shipped, git-anchored three-valued gate (`allow` / `scope-changed` / `invalidated`).

A human approving or merging today reads none of this in one place — they either trust
the agent's self-report or manually chase three different surfaces. The gap between a
rubber-stamp and a real re-review is exactly whether this composition is visible at the
decision point.

## Decision Record (frozen 2026-08-14)

> Do not modify after acceptance.

**Context:** the deterministic-check loop that actually runs each AC-grammar heuristic
lives only inside `goal-completion.sh`, wrapped in Stop-hook-specific policy (presence
interlock, grader-immutability, `active-goal.json` state). An on-demand render at
`ac approve` time has none of that context — no active goal, no session presence token
— so the loop cannot be called as-is.

**Decision:** extract the per-criterion **check-execution** logic (distinct from
`ac-lint.sh`'s existing shape-only classifier) into a new standalone,
read-only script, `system/scripts/ac-grade.sh <task-id> [--json]`. It reads
`acceptance_criteria` directly via `brana backlog get`, runs the same 10 heuristics
against the current working tree, and reports pass/fail/unknown per criterion — no
state mutation, no Stop-hook gates. `goal-completion.sh` is refactored to call this
script for its own check loop rather than carrying a second, independently-drifting
copy (the exact drift class t-2856 fixed for the H9 gap and the injection-guard
duplication — same lesson, applied at the module boundary this time instead of within
one file).

**Consequences:** `goal-completion.sh` shrinks to: call `ac-grade.sh`, then apply its
own Stop-hook-only policy layer (presence, immutability, audit jsonl) on top of the
grades it receives. Any future on-demand grading caller (this feature, a future TUI
pane, a CI check) gets the real heuristic execution for free instead of re-deriving it.

**Judged-layer convention (formalized, not invented):** `verify-gates.md` and
`challenger-gate.md` already instruct writing `"Evaluator: {verdict} ({date}), ..."`
and the Challenger Gate's blocking-rule verdicts (`PROCEED` / `PROCEED WITH CHANGES` /
`RECONSIDER`) into task `notes` — this session's own t-2840/t-2856 closes did exactly
this, unprompted, because it's what the skill procedures already say to write. This
feature makes that convention **load-bearing**: `stacked-verdict` parses `notes` for
lines matching `^Evaluator: (PASS|PASS WITH GAPS|FAIL)` and `^Challenger:
(PROCEED(?: WITH CHANGES)?|RECONSIDER)`, most-recent-per-source wins. No new storage —
existing free text, now also machine-read. If a task has no such lines, its judged
layer reports `0 judged` (not an error — many tasks skip these gates by size/strategy).

## Constraints

- **Gauge law (wave-pipeline.md §skeleton match):** "MEASURE — external validators —
  objective readout; **never self-assessment, never acts**." `stacked-verdict` reads
  and renders; it never writes to `acceptance_criteria`, `ac_state`, `status`, or any
  other task field. Verified by a boundary test asserting zero writes in the code path
  (mirrors t-2844's own AC #2, same law, same test shape).
- **Two call sites, one implementation** (t-2825 addendum item 6: "composition, not
  duplication"): `brana backlog ac <id> approve` prints the bundle before promoting;
  the merge moment is served by the same underlying command, not a second renderer.
  Wiring the bundle into the actual `dev→main` merge gate (t-2594's hook) is out of
  scope here — ADR-076 D4 already owns that mechanism; this feature only makes the
  bundle available to be shown there.
- **Unknown must never silently disappear** — a criterion that classifies UNKNOWN in
  `ac-grade.sh` (freeform prose, no matching heuristic) renders explicitly as `N
  needs-you`, distinct from `0 unknown` — dropping the count instead of showing zero
  would be indistinguishable from "everything checked out."

## Scope (v1)

- `system/scripts/ac-grade.sh <task-id> [--json]` — standalone per-criterion check
  execution (new, extracted from `goal-completion.sh`).
- `goal-completion.sh` refactored to call `ac-grade.sh` instead of its own inline loop
  (no behavior change to the Stop-hook contract — same tests must stay green).
- New CLI: `brana backlog stacked-verdict <task-id> [--json]` (Rust, `brana-cli`) —
  composes the three layers into one line:
  `{X}/{N} AC machine-green · {Y} judged-pass ({verdicts}) · {Z} needs-you · receipt: {result}`
  Shells to `ac-grade.sh --json` and `brana receipt validate --json`; reads `notes`
  directly for the judged layer (in-process, no shell-out).
- `brana backlog ac <id> approve` prints the bundle (via the same composition function)
  immediately before promoting — informational only, does not gate the promotion.

## Out of scope

- The `dev→main` merge hook itself (t-2594) — deferred, already owned by ADR-076.
- t-2825's TUI rendering (consumes this command's `--json` output as one pane, per its
  own "composition not duplication" note — not built here).
- t-2844's wave board (separate S-effort task, independent, no dependency either way).
- Any auto-advance / promotion-by-evidence policy — t-2855 decision 6 owns that; this
  feature is display-only by the gauge law above, full stop.

## Assumptions

- **Judged-verdict regex scope**: `PROCEED WITH CHANGES` counts as judged-pass (with
  the changes noted, not blocking) — chose this because `challenger-gate.md`'s own
  blocking table treats it identically to `PROCEED` for gate-passing purposes (only
  `RECONSIDER` blocks CLOSE). Needs confirmation if a future user wants
  `PROCEED WITH CHANGES` to render as its own third bucket instead of folding into
  judged-pass.
- **Most-recent-per-source wins** when a task has multiple Evaluator/Challenger lines
  (e.g. after a repair-loop iteration) — chose latest-timestamp because the repair loop
  explicitly supersedes iteration 1's verdict; older lines are history, not current
  state. Needs confirmation if audit trail (not just current state) turns out to matter
  for the eventual TUI pane.
- **Receipt layer optional**: a task with no minted receipt renders `receipt: none
  minted` rather than blocking or erroring — chose this because `brana receipt mint` is
  opt-in today (not every build strategy mints one), and the bundle's job is to show
  what evidence exists, not demand a specific evidence set exist.

## Design

**`system/scripts/ac-grade.sh`** — sibling to `ac-lint.sh`, same sourcing style. Reads
`brana backlog get <task-id> --field acceptance_criteria`, runs each criterion through
the 10-heuristic execution logic (moved here from `goal-completion.sh`, unchanged
behavior — a pure extraction, not a rewrite), emits:
```json
{"task_id":"t-123","graded":[{"criterion":"...","verdict":"pass|fail|unknown"}],
 "counts":{"pass":7,"fail":0,"unknown":2}}
```

**`goal-completion.sh`** calls `ac-grade.sh --json "$TASK_ID"`, parses the same counts
it used to compute inline, then applies its existing Stop-hook-only logic (presence
interlock, grader immutability, audit jsonl) unchanged. Test suite must stay 33/33
green with zero behavioral change to the Stop-hook contract — this is a refactor of
*where* the check runs, not *what* it checks.

**`brana backlog stacked-verdict`** (new Rust command, `brana-cli/src/commands/backlog.rs`
or a new `verdict.rs` module): shells to `ac-grade.sh --json` and `brana receipt validate
--json --at <candidate-ref>`; reads the task's `notes` in-process (already loaded via
existing `backlog_get`-equivalent internals) and regex-matches the Evaluator:/Challenger:
convention. Composes and prints one line; `--json` emits the structured form for t-2825's
future TUI pane to consume without re-parsing text.

## Boundaries

| Always | Ask First | Never |
|--------|-----------|-------|
| Render read-only from existing state (AC, notes, receipt) | Add a new judged-verdict source beyond Evaluator/Challenger | Write to any task field |
| Show unknown/needs-you explicitly, never as 0 | Wire into the actual merge git-hook (t-2594 territory) | Auto-advance ac_state or status |
| Keep `ac-grade.sh` behavior-identical to the code it replaces in goal-completion.sh | | Gate `ac approve`'s actual promotion on the bundle's contents |

## Testing Strategy

- **Unit (Rust):** stacked-verdict composition — count aggregation, notes-regex
  matching (latest-wins, PROCEED WITH CHANGES folds to judged-pass, no-match → 0
  judged), receipt-absent → "none minted", zero-writes boundary test.
- **Unit (bash):** `ac-grade.sh` — fixture criteria per heuristic (mirrors
  `test-ac-lint.sh`'s fixture set), JSON output shape.
- **Integration:** `test-goal-completion.sh` full suite must stay green after the
  refactor — this is the regression gate proving the extraction changed nothing.
- **Mock policy:** real `brana backlog`/`brana receipt` subprocess calls in Rust
  integration tests (matches existing `receipt_smoke.rs` pattern); no live git receipts
  needed for the "none minted" path.

## Documentation Plan

- [ ] **Tech doc** — this file, kept current through DECOMPOSE/BUILD/CLOSE.
- [ ] **Existing docs to update** — `docs/architecture/ac-grammar.md` gets a short
  pointer to `ac-grade.sh` as the execution-layer sibling of `ac-lint.sh`'s
  shape-layer classifier (avoid future readers assuming `ac-lint.sh` runs checks).
  `verify-gates.md`/`challenger-gate.md` get a note that their Evaluator:/Challenger:
  logging convention is now machine-read, not just human-readable — same text, now
  load-bearing.

## Challenger findings

{populated by pre-DECOMPOSE challenger review below}
