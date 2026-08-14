# Judge Escalation Valve — user guide

> The build framework's challenger gate now sizes its review to the beat: a single
> challenger by default, growing to a panel only when hard evidence says the beat
> needs one. Decision: ADR-082. Implementation: t-2895.

## What you'll see

Every build beat reaching the challenger gate prints a beat-report line:

```
judge rung: 0 — single challenger
```

- **Rung 0** (almost all beats): exactly the flow you know — one fresh-context
  challenger. Nothing changed for XS/S mechanical work.
- **Rung 1** (M+ effort, or a code diff touching a critical section): a
  *sibling-path finder* runs in parallel with the challenger — a narrow-brief
  agent hunting for the same fix's unaudited second variant, the class the t-2887
  probe showed single reviewers miss most.
- **Rung 2** (a hard signal fired): the full funnel — two nature-routed finders →
  haiku filter → strongest-model verification. Expect ~2.5–3.5× the review cost
  on that beat only.

When a mechanism *doesn't* arm, the report says so and why:

```
blind test-author did not arm: AC unapproved
in-loop critic: did not arm: rung < 2
```

An unarmed mechanism is always visible — silence never means "checked and clean."

## What arms rung 2 (hard signals)

Only recorded events, never model self-confidence: a prior RECONSIDER verdict at
severity ≥ 4; an evaluator PASS-WITH-GAPS; the diff landing in a critical section
(locks, hooks, the gate itself); the challenger's own `SIBLINGS: yes` verdict
line; or a fresh escaped-defect log entry in the same area.

## Reading verdicts

- Challenger verdicts now end with `SIBLINGS: yes — {paths}` or `SIBLINGS: no` —
  a recorded answer to "does this fix have an unaudited twin?" A `yes` raises the
  next pass to rung 2.
- **`SPLIT`** is a new verdict class at rung 2: the verifiers disagreed. It is
  routed to you as its own signal — disagreement is diagnostic, never suppressed
  into a false-positive bucket.

## The escaped-defect log

`docs/ops/escaped-defects.jsonl` — append-only, one JSON record per valve firing
(and per defect you catch at the merge valve that the challenger passed; please
keep recording those). Recent entries make their area arm more readily for 30
days, then decay. Grep it by area:

```bash
jq 'select(.area | startswith("system/hooks"))' docs/ops/escaped-defects.jsonl
```

## Blind test-author (opt-in)

On M+ code tasks with **approved** acceptance criteria (`brana backlog ac <id>
approve`), a blind agent can author the failing tests from the AC alone — it never
sees the implementation plan. Its tests are content-hash-pinned at registration;
weakening one after the fact now blocks auto-completion (you'll see
`hash mismatch` in the goal gate reason). Default-off until the pilot
(t-2890/91/93) reports.

## For contributors

The ladder, signals, briefs, and helpers are data in
`system/skills/_shared/judge-sizing.md` — changing a rung is an ADR-082 amendment
plus a one-line edit there, verified by `tests/procedures/test-judge-sizing.sh`.
Design rationale: `docs/architecture/features/judge-escalation-valve.md`.
