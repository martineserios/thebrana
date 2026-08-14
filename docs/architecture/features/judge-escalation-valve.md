# Feature: Judge Escalation Valve — sizing-ladder rungs 0–2 in the challenger gate

**Date:** 2026-08-14
**Status:** specifying
**Task:** t-2895
**Decision:** [ADR-082](../decisions/ADR-082-multi-agent-sizing-function.md) (frozen — this spec implements it, never restates it)

## Problem

The build framework judges every beat with a single fresh-context challenger
(`system/skills/_shared/challenger-gate.md`). The t-2887 probe proved a graded panel
finds verified misses a single challenger passes — but only pays for itself when
*triggered*. ADR-082 froze the contract (sizing ladder, hard signals, Claude-only
diversity, funnel shape); nothing implements it. This feature wires rungs 0–2 into
the challenger gate as data, plus the enforcement extensions the ADR assigns to
this task.

## Constraints

- ADR-082 is authoritative — this spec implements, never re-decides. Changing a
  rung is an ADR amendment, not a spec edit.
- Claude-only; no agy/Gemini anywhere.
- Rung 0 must be byte-identical to today's gate behavior (single challenger,
  existing lint, existing repair loop). Zero regression for XS/S mechanical work.
- The valve is deterministic: a table lookup over machine-readable inputs. No
  model chooses the shape.
- Human merge valve untouched; panel roles get subset-only allowlists (no verb a
  runner manifest denies).
- Max-2 challenger iteration cap unchanged; panel spawns do not consume it
  (same rule the mechanical lint already established).

## Scope (v1)

In: valve + rung computation in challenger-gate.md; sibling-verdict field in the
challenger prompt (signal 4 source); rung-1 sibling-path finder; rung-2 funnel
(2 finders → haiku filter → strongest-Claude default-refute verify) with
disagreement-surfacing; brief library + diff-type router; escaped-defect log;
content-hash pinning for blind-authored tests; M+ readiness ac_state surface;
loops-library contract reference.

Out: rung 3 / PLAN panels (t-2896); blind test-author *authoring* flow (pilot-gated,
separate task when the pilot is scheduled); wave/epic-runner JUDGE beats (they reuse
this gate via /brana:build, so they inherit the valve for free — no runner edits).

## Research

- Wiring target read end-to-end: challenger-gate.md has lint → spawn → blocking →
  repair-loop structure; the valve inserts between lint and spawn. The repair loop
  already implements ADR-082 §2's "re-judgment at raised rung" timing — iteration 2
  of an armed beat runs at the raised rung, no new loop machinery.
- Repo test pattern for procedure logic: extracted-block bash functions between
  HTML markers, sourced by `tests/procedures/test-*.sh` (branch-prefix, epic-walk
  precedents). The sizing function follows it exactly.
- Probe funnel (29→6→6) and brief yields: docs/research/2026-08-14-judge-panel-probe.md.

## Assumptions

- `nature` derivation: `kind` + diff file classes — code = any `*.rs`, `*.sh`,
  `*.py`, `*.ts`, `system/hooks/`, `system/scripts/`; procedure = `system/skills/`,
  `system/rules/`, `system/agents/` markdown; docs = everything else markdown.
  Chose file-class precedence code > procedure > docs on mixed diffs because the
  riskiest class governs — needs confirmation at spec review.
- Critical-section seed list (§1 ADR): `system/cli/rust/crates/*/src/**` paths
  matching lock/pull/lease code (`backlog.rs` wave/approve sections, `wave.rs`,
  `util.rs` tasks-file discovery), `system/hooks/**`, `bootstrap.sh`,
  `system/skills/_shared/challenger-gate.md` itself. Chose to store the list as
  data in the sizing block so amending it is a one-line diff — needs confirmation.
- Escaped-defect log at `docs/ops/escaped-defects.jsonl` (user-confirmed
  2026-08-14), append-only, one JSON object per line, seeded with the probe's 4
  verified misses.

## Behavior

- A build reaching the challenger gate computes its rung from (effort, nature,
  criticality, fired signals) via a sourced bash function; the beat report states
  the rung and shape armed — or why a shape did not arm (e.g. "did not arm: AC
  unapproved").
- Rung 0: exactly today's flow. Rung 1: a sibling-path finder runs in parallel
  with the challenger; both verdicts merge into the gate's blocking rules. Rung 2
  (hard signal fired): two narrow-brief finders (router by diff type) → haiku
  dedup/filter → strongest-model default-refute verification; split verdicts
  surface to the human as `SPLIT` — never suppressed to FALSE_POSITIVE.
- Every valve firing appends an escaped-defect log record; the log's area weights
  (30-day window) feed signal 5 on later beats.
- Success confirmed when: a rung-0 beat's transcript is indistinguishable from
  today's, and a forced-signal test beat arms rung 2, produces the funnel, and
  logs the firing.

## Edge Cases

- Signals table unreadable/empty → exit 2 like the lint's registry rule: the
  *valve* is broken, never skip silently, never default to rung 2 (cost) or rung 0
  silently (silent de-arming).
- Mixed-nature diff → highest-risk class governs (assumption above).
- Two signals fire → same rung 2 (signals select the row, they don't stack).
- Challenger returns no sibling-verdict field (prompt drift) → treat as signal
  NOT fired but log the omission; the lint-style contract test catches the drift.
- Log file absent → signal 5 evaluates false; first firing creates the file.

## Design

| Component | File | Shape |
|---|---|---|
| Sizing function + signals table + critical-path list | `system/skills/_shared/judge-sizing.md` (new) | `JUDGE-SIZING-BLOCK` extractable bash: `resolve_judge_rung(effort, nature, criticality_hit, signals_csv)` → prints `0|1|2`, exit contract like branch-prefix (never empty, exit 0; exit 2 on unreadable table) |
| Valve wiring | `challenger-gate.md` (edit) | New "Sizing valve" section between lint and spawn: compute inputs, call resolver, spawn per shape; beat-report line format |
| Sibling-verdict field | `challenger-gate.md` spawn prompt (edit) | Adds "(4) Does this fix have structural siblings outside the diff? Answer yes/no with paths — this is a recorded verdict field" |
| Brief library + router | `judge-sizing.md` §Briefs | 4 briefs from ADR-082 §4a; router: diff-type (code→second-variant+concurrency; procedure→read-only-claims+denied-verb) |
| Rung-2 funnel | `judge-sizing.md` §Funnel | Spawn contract per stage (model tier, stance, context access, blinding, "empty is respectable"); disagreement-surfacing verdict class `SPLIT` |
| Escaped-defect log | `docs/ops/escaped-defects.jsonl` (new) + append helper in `judge-sizing.md` | `{date, area, signal, rung_armed, verified_findings, cost_tokens}`; seeded with probe's 4 |
| Content-hash pinning | `system/hooks/red-verification.sh` + `goal-completion.sh` (edit) | Registration writes `{path, sha256}` into `tests_required[]`; goal-completion re-hashes registered paths, mismatch = block (closes ADR-082 §5 residual gap) |
| Readiness ac_state surface | `system/skills/build/phases/load.md` Step 0d (edit) | M+ soft-warn line: `⚠ ac_state is '{v}' — blind test-author cannot arm; approve via brana backlog ac {id} approve` |
| Loops-library reference | `docs/architecture/features/loops-library.md` (append) | JUDGE-step/model-per-beat schema cites the sizing function |

## Boundaries

| Always | Ask First | Never |
|--------|-----------|-------|
| Rung 0 = today's behavior byte-identical | Changing any rung trigger (ADR amendment) | Model-judgment sizing |
| Beat report states armed/unarmed + why | Widening a panel-role allowlist | agy/Gemini lanes |
| Split verdicts surface as SPLIT | New hard signals | Auto-merge; panel writes to backlog state |

## Testing Strategy

- **Unit (70%):** `tests/procedures/test-judge-sizing.sh` — extracted-block sourcing;
  table totality (every input combo → exactly one rung; rung-0 floor); signal
  precedence; exit-2 on empty table; nature precedence on mixed inputs. Content-hash:
  `tests/hooks/` case — register, weaken, expect block.
- **Integration (25%):** forced-signal dry beat — a fixture diff touching a
  critical path arms rung ≥1; challenger-prompt contract test greps the spawn
  prompt for the sibling-verdict field (drift guard).
- **E2E (5%):** one supervised proof-of-life beat on a real S task at rung 0
  (transcript unchanged) — t-2845 precedent.
- **Mock policy:** real files/fixtures; no model calls in tests (spawn contracts
  are text, tested as text).

## Documentation Plan

- [ ] **Tech doc** — this file (design rationale, extending the table).
- [ ] **User guide** — `docs/guide/features/judge-escalation-valve.md`: what arms,
  what the beat report lines mean, how to read SPLIT verdicts and the log.
- [ ] **Existing docs to update** — challenger-gate.md (in-place), loops-library.md
  (reference), CALIBRATION.md pointer if verdict classes grow `SPLIT`.

## Challenger findings

(pending — populated after spec challenger review)
