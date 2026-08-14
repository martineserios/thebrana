# Loop+Goal-Native Backlog Planning

> Brainstormed 2026-06-21. Status: **implemented** (phase t-2198 complete, 2026-06-21).
> Shipped: `docs/architecture/ac-grammar.md`, `system/scripts/ac-lint.sh`, `plan.md` step 11b,
> build LOAD field-canonical normalization, ADR-047 §3 reconcile.

## Problem

`/brana:backlog plan` creates tasks that are not shaped for the loop+goal
auto-completion approach. The loop+goal contract has three parties:

```
backlog plan  ──writes──▶  acceptance_criteria  ──read by──▶  goal-completion.sh
  (producer)                  (the contract)                    (consumer)
```

The consumer is built (`goal-completion.sh`, 8 heuristics). The producer is the
hole: `plan` never emits criteria, so the loop is not self-propelling — every
task becomes a manual checkpoint instead of auto-advancing.

## Key finding — ADR-047 already decided this

`docs/architecture/decisions/ADR-047-acceptance-criteria-schema.md` (accepted
2026-06-02) already locks the entire design:

- **§1** `acceptance_criteria` structured array is **canonical**; each item a
  testable assertion. `AC:` lines in `context` are undocumented drift.
- **§1** "Max 10 items per task — >10 means split" — atomicity signal already exists.
- **§3** "Automated check heuristics" table = the producer/consumer grammar contract.
- **§2** `/goal` string is a deterministic template from the array (no LLM rewriting).
- **§5/Consequences** "`/brana:backlog plan` updated to prompt for criteria on
  implement tasks (non-blocking)" — **specified but never implemented.**

So this is not a new design. It is implementation of an accepted ADR plus drift
reconciliation.

## Three drifts to close

1. **plan integration missing** — ADR-047 §5 mandates it; `plan.md` has zero
   criteria logic. (The gap.)
2. **Grammar contract drifted** — ADR-047 §3 documents 4 heuristic patterns;
   `goal-completion.sh` implements 8 (file-contains, jq-returns, commit-message,
   hook-exists, allowlisted-cmd, …). Doc and hook diverged.
3. **Two parallel storage paths** — ADR-047 says the field is canonical, but the
   live impl treats `AC:` lines as co-equal (`build` LOAD merges field + AC: lines;
   `goal-completion.sh` validates `active-goal.json`).

## Decisions (this session)

- **Path:** implement + reconcile, **no new ADR** — close the loop ADR-047 opened.
- **AC storage:** field canonical; `AC:` lines become input shorthand normalized
  into the `acceptance_criteria` field.
- **AC generation:** template + LLM-fill per `work_type` (implement → `"<test cmd>"
  passes` + `validate.sh Check N passes`; design → `file <adr>.md exists`), user confirms.
- **Grammar enforcement:** lint + warn — check each generated criterion against the
  heuristic grammar; warn (don't block) when a criterion won't auto-complete.
- **Anti-drift:** extract the heuristic grammar to ONE source both `plan`-lint and
  `goal-completion.sh` cite, so §3 can't drift from the hook again.

## Constraints carried

- `acceptance_criteria` field already ships (t-1778 complete): `Vec<String>`,
  serde-default, CLI `--acceptance-criteria`, MCP param.
- `build` LOAD already reads the field (Source 1) — wiring exists on the consumer side.
- ADR-047 §2: deterministic `/goal` string template — LLM authors *criteria* at plan
  time, never rewrites criterion text into the goal string. Different stages.

## Next steps (task tree)

Phase **t-2198** filed from this idea (tasks t-2199..t-2203). Shape:
1. Reconcile ADR-047 §3 ↔ `goal-completion.sh` 8 heuristics; extract shared grammar reference.
2. `plan` generates `acceptance_criteria` per leaf task (template+LLM-fill, lint+warn).
3. Atomicity signal — flag leaf tasks >criteria-threshold or M+ effort for split.
4. `AC:` lines → field normalization (field canonical).
5. Tests for the heuristic lint classifier; docs sync.

## Risks

- **Grammar drift recurs** if §3 and the hook stay as two hand-maintained copies —
  mitigated by the single shared grammar reference (decision above).
- **Over-automation** — forcing every criterion into checkable grammar pushes authors
  toward weak-but-checkable AC (e.g. "changes committed") that auto-completes on thin
  signal. Lint+warn (not hard-enforce) preserves the escape hatch for genuine
  human-judgment criteria.
