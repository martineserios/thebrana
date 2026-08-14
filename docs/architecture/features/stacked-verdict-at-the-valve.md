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

## Decision Record

The load-bearing decisions (extraction boundary, allowlist consolidation, cwd
resolution, and the notes-parsing contract) are recorded in
[ADR-081](../decisions/ADR-081-stacked-verdict-evidence-composition.md) — promoted out
of this spec per pre-DECOMPOSE challenger review (DDD: a decision that constrains other
code's future dependencies belongs in a standalone ADR, referenced by filename, not
embedded and self-declared frozen here). Read ADR-081 D1/D2 before touching any file in
Scope below.

## Constraints

- **Gauge law (wave-pipeline.md §skeleton match):** "MEASURE — external validators —
  objective readout; **never self-assessment, never acts**." `stacked-verdict` never
  writes to `acceptance_criteria`, `ac_state`, `status`, or any other task field —
  verified by a boundary test asserting zero writes in the code path (mirrors t-2844's
  own AC #2). **This is narrower than "never acts" in the literal sense** (ADR-081 D1):
  grading a command-shaped criterion (heuristics 7/9/10) executes that command as a
  subprocess — real action, real side effects, just not a task-field write. Docs and
  any caller-facing surface must say this plainly; the gauge-law claim in this feature
  is scoped to state mutation, not to "nothing happens."
- **cwd resolution is not optional** (ADR-081 D1): `ac-grade.sh` MUST resolve its
  working directory from the target task's own record (`branch` → `git worktree list`)
  and refuse to run with a loud error on ambiguity — never fall back to the caller's
  current directory. Concurrent per-task worktrees are a hard rule in this repo; a
  silent-cwd default would let a human approve one task while grading a different
  worktree's tree.
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
  execution (new, extracted from `goal-completion.sh`). Resolves its own `WORK_DIR`
  from the task's `branch` field via `git worktree list` (ADR-081 D1); errors loudly,
  never defaults, if resolution is ambiguous or the task has no worktree.
- `system/scripts/ac-lint.sh` **modified** (not just referenced) — its inline
  `CMD_ALLOWLIST_RE`/allowlist-guard copy is removed; it sources/calls the single
  definition that moves to `ac-grade.sh` (ADR-081 D1 — this is the actual
  consolidation the t-2856 lesson requires, not just a `goal-completion.sh`-side move).
- `goal-completion.sh` refactored to call `ac-grade.sh` instead of its own inline loop
  (no behavior change to the Stop-hook contract — same tests must stay green).
- `system/skills/_shared/challenger-gate.md` — `Always log` template for the
  PROCEED/PROCEED WITH CHANGES path (ADR-081 D2). *Already applied* (2026-08-14,
  ahead of DECOMPOSE, since `stacked-verdict`'s parser depends on it existing).
- New CLI: `brana backlog stacked-verdict <task-id> [--json]` (Rust, `brana-cli`) —
  composes the three layers into one line:
  `{X}/{N} AC machine-green · {Y} judged-pass ({verdicts}) · {Z} needs-you · receipt: {result}`
  Shells to `ac-grade.sh --json` (which resolves its own worktree per ADR-081 D1) and
  `brana receipt validate --json`; reads `notes` directly for the judged layer
  (in-process, no shell-out).
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
| Never write to any task field (`acceptance_criteria`, `ac_state`, `status`, `notes`) | Add a new judged-verdict source beyond Evaluator/Challenger | Fall back to the caller's cwd when the target worktree can't be resolved |
| Disclose that command-shaped criteria (H7/H9/H10) execute subprocesses when graded | Wire into the actual merge git-hook (t-2594 territory) | Auto-advance ac_state or status |
| Show unknown/needs-you explicitly, never as 0 | | Gate `ac approve`'s actual promotion on the bundle's contents |
| Keep `ac-grade.sh` behavior-identical to the heuristic logic it replaces in goal-completion.sh | | |

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

Pre-DECOMPOSE review (2026-08-14): RECONSIDER, 3 CRITICAL (score 4) + 1 WARNING (score 3).
All folded in before acceptance:
1. **ac-lint.sh sibling copy unconsolidated** — fixed: Scope now names the file and the
   consolidation explicitly; ADR-081 D1 records why.
2. **Notes convention asymmetric** — fixed: `challenger-gate.md` now carries the
   matching `Always log` template (ADR-081 D2); applied same-day, ahead of DECOMPOSE.
3. **ac-grade.sh cwd unanchored + execution mislabeled "read-only"** — fixed: Scope and
   Constraints now require branch/worktree resolution with a loud-error fallback, and
   the gauge-law claim is scoped correctly to state mutation, not subprocess execution.
4. **WARNING — Decision Record should be a standalone ADR** — fixed: promoted to
   ADR-081, spec now references it by filename.
