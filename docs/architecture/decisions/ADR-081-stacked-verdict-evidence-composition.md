---
status: accepted
---
# ADR-081: Stacked-Verdict Evidence Composition — Extraction Boundary and the Notes Contract

**Status:** Accepted (2026-08-14; challenged once, findings folded in before acceptance — see §Challenge record)
**Date:** 2026-08-14
**Deciders:** Martín Rios
**Tags:** contracts, gauge, valve, ac-grammar, receipts
**Tasks:** t-2857 (implements this)
**Relates:** [ADR-047](ADR-047-acceptance-criteria-schema.md) (AC schema, the deterministic layer's source) · [ADR-076](ADR-076-build-receipts-as-executed-evidence.md) (the receipt layer, already shipped) · [ac-grammar.md](../ac-grammar.md) (the 10 heuristics) · [challenger-gate.md](../../../system/skills/_shared/challenger-gate.md) / [verify-gates.md](../../../system/skills/build/phases/verify-gates.md) (the judged layer's notes convention)

## Context

Three evidence layers exist for grading a task's readiness at a human decision point
(`ac approve`, merge) but nothing composes them: deterministic AC-grammar verdicts
(executed only inside `goal-completion.sh`'s Stop-hook loop), judged Evaluator/Challenger
grades (free-text in `notes`), and executed build receipts (ADR-076, real and shipped).
t-2857's feature spec (`docs/architecture/features/stacked-verdict-at-the-valve.md`)
proposed the composition; this ADR records the two decisions in it that are load-bearing
— they constrain how other code depends on this feature going forward — rather than
leaving them embedded in the feature spec's non-authoritative Decision Record.

## Decisions

### D1 — `ac-grade.sh` is the one execution boundary; every allowlist-gated check lives there once

The per-criterion **check-execution** logic (as opposed to `ac-lint.sh`'s existing
shape-only classifier) is extracted from `goal-completion.sh` into a new standalone,
read-only script, `system/scripts/ac-grade.sh`. This is not a copy — `goal-completion.sh`
calls it and layers its own Stop-hook-only policy (presence interlock, grader
immutability, audit jsonl) on top.

**The shared command allowlist moves to a pinned, dedicated location — not "into
ac-grade.sh" implicitly.** `allowlisted_command()`/`CMD_ALLOWLIST_RE` (t-2856's
injection fix) exists today as two independently-authored copies — `goal-completion.sh`
and `ac-lint.sh` — proven by divergent syntax (`<<<"$cmd"` vs `echo "$cmd" |`) despite
one's comment claiming to mirror the other. A pure move of `goal-completion.sh`'s copy
alone, leaving `ac-lint.sh`'s untouched, would satisfy the letter of "extraction" while
leaving the exact drift class t-2856 fixed still open on a third file (challenger
finding, 2026-08-14, score 4 — folded in before acceptance).

**Round-2 verification refinement (2026-08-14):** the first fix said `ac-lint.sh`
"sources or calls" `ac-grade.sh` — re-verification correctly flagged this as an
unpinned mechanism (`ac-grade.sh`'s `<task-id> [--json]` interface has no code path for
classifying a bare command string, so neither literal reading is directly
implementable). Pinned: the guard lives in a new, standalone
`system/scripts/lib/cmd-allowlist.sh`; `ac-grade.sh` and `ac-lint.sh` both `source` it
(same directory, no cross-directory path needed); `ac-lint.sh` stays a pure classifier
and gains no execution capability. This follows the existing `system/scripts/lib/`
convention (already holds `orphan-guard.mjs`).

**Round-2 verification also flagged a second gap, fixed the same way:** `ac-grade.sh`
is called from the Stop-hook's untrusted PATH (via `goal-completion.sh`) *and*
standalone from a trusted CLI PATH — it must source `system/hooks/lib/resolve-brana.sh`
and use `$BRANA`, mirroring `goal-completion.sh`'s own `[ -x "${BRANA:-}" ]` gate, not
just inherit the check-execution logic without the environment hardening around it.

**Standalone invocation must resolve its own working directory — never assume the
caller's cwd.** `goal-completion.sh` trusts `active-goal.json`'s recorded cwd; a
standalone caller (`ac approve`, `stacked-verdict <task-id>`) has no such binding. This
repo runs concurrent per-task worktrees by hard rule (git-discipline.md), so
`ac-grade.sh` MUST resolve the target working directory from the task's own record
(`branch` field → `git worktree list` lookup) and refuse to run (loud error, not a
silent default to "current directory") if it cannot resolve unambiguously. Getting this
wrong means a human approving from the wrong worktree sees confidently wrong verdicts
at the exact moment the feature exists to make trustworthy (challenger finding,
score 4).

**Heuristics 7/9/10 execute subprocess commands — this is acting, not just reading, and
must be labeled as such.** The gauge law ("never acts," [the-brana.md §Scale](../the-brana.md) — originally wave-pipeline.md, superseded 2026-08-23
§skeleton match) is scoped to *task-field* writes in the feature spec's Constraints —
running `cargo test`/`validate.sh`/a `demoable:` command as a grading side effect is a
real action with real side effects (processes spawned, possibly files touched by the
command under test), even though no *task field* is written. `ac-grade.sh`'s
documentation and any UI surfacing it must say plainly that grading a task with
command-shaped criteria executes those commands — never imply the whole operation is
inert just because state fields aren't mutated.

### D2 — The Evaluator:/Challenger: notes convention is now a machine-read contract, symmetrically

`verify-gates.md` already carries an unconditional `Always log: "Evaluator: {verdict}
({date})..."` template — reliable, verified against real task history.
`challenger-gate.md` did **not** carry an equivalent template for its common
PROCEED/PROCEED WITH CHANGES path before this ADR (only the 2-iterations-unresolved and
skip cases had literal templates); the PROCEED path's logging was an emergent habit,
not an instructed guarantee (challenger finding, score 4 — the stacked-verdict feature
depends on exactly this path being reliable, and a silent undercount on a feature named
for composing verdicts is a direct contradiction of its own purpose).

**Fix, applied same-day:** `challenger-gate.md` now carries the matching `Always log`
template (`"Challenger: {verdict} ({date}), {N} finding(s), max severity {score}"`),
making both sources symmetric before `stacked-verdict`'s parser is built against them.

**Parsing contract:** `stacked-verdict` parses `notes` for lines matching
`^Evaluator: (PASS|PASS WITH GAPS|FAIL)` and `^Challenger: (PROCEED(?: WITH CHANGES)?|RECONSIDER)`,
most-recent-per-source wins (a repair-loop's later iteration supersedes an earlier
verdict; older lines are history, not current state). `PROCEED WITH CHANGES` folds into
judged-pass (matches `challenger-gate.md`'s own blocking-rule treatment: only
`RECONSIDER` blocks). No matching line → `0 judged` (not an error — many tasks skip
these gates by size/strategy; the count must render as zero, never be silently
dropped from the composed line).

**Consequence — this is now load-bearing text, not just human-readable prose.** Any
future edit to `verify-gates.md`'s or `challenger-gate.md`'s logging templates must
preserve this exact wording (or update `stacked-verdict`'s regex in the same change) —
the two are now coupled. Recorded here specifically so a future editor finds the
constraint before breaking it silently.

## Consequences

- `system/scripts/ac-lint.sh` changes from an independent classifier to a caller of
  `ac-grade.sh`'s shared allowlist guard — one definition, not two.
- `challenger-gate.md` gains a mandatory logging line on its most common path (PROCEED),
  closing a gap that existed before this feature needed to depend on it.
- Any tooling that scrapes task `notes` for Evaluator:/Challenger: verdicts (this
  feature, and potentially t-2825's future TUI pane) now has one documented, versioned
  contract to code against instead of reverse-engineering historical habit.

## Non-Actions

- Does not wire the composed bundle into the actual `dev→main` merge git-hook (t-2594) —
  that mechanism is owned by ADR-076 D4; this ADR only makes the bundle available to be
  shown there.
- Does not add a fourth evidence layer beyond deterministic/judged/receipt.
- Does not change `ac-lint.sh`'s or `goal-completion.sh`'s externally observable
  behavior — the Stop-hook contract (33/33 test suite) must stay green through the
  extraction; this is a boundary move, not a behavior change.

## Challenge record

**Round 1 (2026-08-14, context-isolated challenger, spec-level):** verdict RECONSIDER —
3 CRITICAL findings (score 4 each): the `ac-lint.sh` sibling copy left unconsolidated by
a literal reading of "extraction," the notes-convention treated as symmetric when only
the Evaluator half was actually guaranteed, and `ac-grade.sh`'s unanchored working
directory paired with unlabeled subprocess execution under a "read-only" claim. One
WARNING (score 3): the Decision Record belonged in a standalone ADR, not embedded and
self-declared frozen in the feature spec. All four folded into this ADR (D1, D2) and
the feature spec before acceptance — see `docs/architecture/features/stacked-verdict-at-the-valve.md`
for the full spec, now referencing this ADR by filename per the fix.

**Round 2 (2026-08-14, hard-cap re-verification):** verdict PROCEED WITH CHANGES — all
4 round-1 findings verified genuinely closed (code-level checks, not just text
presence). Two new WARNING-level (score 3) items surfaced during re-verification: the
consolidation mechanism was named but not pinned (D1's "sources or calls" had no
implementable literal reading), and the extracted script's environment-hardening
(`resolve-brana.sh`/`$BRANA`) wasn't named as transferring. Both folded into D1 above.

**Design-time caveat, carried forward to BUILD:** every decision above (D1's pinned
paths, D2's regex compatibility) was verified by reading the current repo state, not by
executing the not-yet-written code. DECOMPOSE/BUILD should re-check each pinned path
and interface against the actual files as they're touched — if reality diverges from
what's recorded here, fix the divergence and update this ADR in the same change, don't
silently work around it. This is the normal DDD→SDD→TDD posture (the spec narrows the
unknowns; the build still has to hit them), stated explicitly here because two rounds
of challenger review already found real gaps at this altitude — a third is plausible at
implementation altitude.
