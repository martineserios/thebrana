# PROPAGATE — propagation-debt audit at close

Every `/brana:close` now checks whether the knowledge around your work kept up
with the work itself: spec Status fields, Documentation Plan checkboxes,
"al cerrar X" promises, project memories, challenger findings. Gaps are fixed
inline or land in your handoff's `next[]` — never silently dropped.

## What runs when

| Your close | What you get |
|------------|--------------|
| `/brana:close` (bare, INSTANT) | ~1s deterministic checks (L1); deep audit deferred to the nightly cron (L3) — findings arrive as reminders at your next session start |
| `/brana:close --finish` | L1 + an in-session LLM audit (L2) over the docs your session touched. Expect a short pass before the handoff — finishing is when unfulfilled promises matter most |
| `/brana:close --full` | L1 + L2 (with the full debrief) |
| `/brana:close --continue` | L1 only; L3 covers the deep audit overnight |
| `/brana:close --abort`, NANO closes | skipped entirely |

## What it checks

- **L1 (deterministic, every non-skipped close):** uncommitted `tasks.json`;
  unchecked `- [ ]` items in touched specs' Documentation Plans; `Status:`
  fields contradicting your task's post-close state; "al cerrar" / "on close"
  promise candidates.
- **L2 (`--finish`/`--full`):** the five ADR-056 categories over *bounded*
  inputs — touched specs, docs they name, your project's `.claude/memory/`,
  and challenger verdicts from the current conversation only.
- **L3 (nightly):** the L2-equivalent audit for closes that skipped it,
  reading repo state at cron time and suppressing gaps you already fixed.

## Reading the output

In the close report:

    **Propagation gaps:** 3 found (1 fixed inline + committed, 2 → next[])

- *Fixed inline* — small doc edits, committed as `fix(propagate): ...`.
- *→ next[]* — in your handoff as `category: "maintenance"` entries.
- *L3 findings* — reminders tagged `propagation` (`brana remind list`),
  surfaced at session start.

## Worth knowing

- Works in client repos too — L1 is plain git/grep, no thebrana
  infrastructure required.
- `reconcile --scope propagation` is a different tool: it cascades errata and
  validates the spec graph on demand. PROPAGATE audits close-time debt.
- The queue flag is fail-safe: if the in-session audit dies mid-way, the
  nightly pass covers that close automatically.

Design: [ADR-056](../../architecture/decisions/ADR-056-propagate-close-step.md) ·
Tech doc: [propagate-close-step](../../architecture/features/propagate-close-step.md)
