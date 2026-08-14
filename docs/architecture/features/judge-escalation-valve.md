# Feature: Judge Escalation Valve — sizing-ladder rungs 0–2 in the challenger gate

**Date:** 2026-08-14
**Status:** shipped
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
disagreement-surfacing; **rung-2 in-loop fresh-context critic**; **blind
test-author mechanism, shipped opt-in/signal-armed** (rung ≥ 1 + AC-approval
precondition — per ADR-082 §6 the mechanism ships now; only its *default-on*
promotion waits for the pilot); **control-arm counters** (§6: first 6 rung-2
firings run rung-1-alone alongside, verified-miss delta recorded); brief library
+ diff-type router (all three natures); escaped-defect log (write AND read/query
side); content-hash pinning for blind-authored tests; M+ readiness ac_state
surface; loops-library contract reference.

Out: rung 3 / PLAN panels (t-2896); blind-test-author *default-on* promotion
(pilot gates the default, never the mechanism — ADR-082 §6); wave/epic-runner
JUDGE beats (they reuse this gate via /brana:build, so they inherit the valve
for free — no runner edits).

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

- `nature` derivation — two inputs, riskiest wins: `kind` maps to a floor class
  (feature/fix/refactor → code; design/docs/research → docs; ops → procedure),
  diff file classes map each file (code = `*.rs`, `*.sh`, `*.py`, `*.ts`,
  `system/hooks/`, `system/scripts/`; procedure = `system/skills/`,
  `system/rules/`, `system/agents/` markdown; docs = other markdown), and
  `nature = max(kind_class, max(file_classes))` by risk order code > procedure >
  docs. Mixed diffs and kind/file disagreements both resolve upward — needs
  confirmation at spec review.
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
- Success confirmed when: a rung-0 beat is mechanism- and cost-identical to
  today's (the challenger prompt does gain the SIBLINGS field on all rungs —
  that is the one deliberate rung-0 change, needed so signal 4 can ever fire),
  and a forced-signal test beat arms rung 2, produces the funnel, and logs the
  firing.

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
| Sizing function + signals table + critical-path list | `system/skills/_shared/judge-sizing.md` (new) | `JUDGE-SIZING-BLOCK` extractable bash: `resolve_judge_rung(effort, nature, criticality_hit, signals_csv)` → prints `0|1|2` at exit 0; exit 2 on unreadable/empty table (precedent: `exit-contract-lint.sh` registry rule, NOT branch-prefix — branch-prefix degrades and never errors; only its extracted-block *test pattern* is copied). Marked `# Exit contract` and registered in the exit-contract-lint registry so call sites are mechanically checked |
| Valve wiring | `challenger-gate.md` (edit) | New "Sizing valve" section between lint and spawn: compute inputs, call resolver, spawn per shape; beat-report line format (armed/unarmed + why) |
| Sibling-verdict field | `challenger-gate.md` spawn prompt (edit) + `parse_sibling_verdict()` helper in `judge-sizing.md` | Prompt adds "(4) Does this fix have structural siblings outside the diff? Answer yes/no with paths — recorded verdict field". Parser is extractable bash, unit-tested on fixture verdict text; missing field → not-fired + logged omission |
| Brief library + router | `judge-sizing.md` §Briefs | 4 briefs from ADR-082 §4a; router covers all three natures: code→second-variant+concurrency; procedure→read-only-claims+denied-verb; docs→read-only-claims+contract/AC-fidelity (the probe's own docs-capable brief) |
| Rung-2 funnel | `judge-sizing.md` §Funnel | Spawn contract per stage (model tier, stance, context access, blinding, "empty is respectable"); disagreement-surfacing verdict class `SPLIT` |
| Rung-2 in-loop critic | `judge-sizing.md` §Team + `build-loop.md` (edit) | Fresh-context critic spawn contract at beat boundaries during BUILD, rung-2 only (ADR-082 §5); explicitly spawned, Actor≠Evaluator |
| Blind test-author (opt-in) | `judge-sizing.md` §Team | Spawn contract: authors failing tests from approved AC only (never sees plan/diff); arms at rung ≥ 1 + `ac_state: approved`; ships opt-in — pilot gates *default-on* only (ADR-082 §6) |
| Control-arm counters | escaped-defect log fields + `challenger-gate.md` valve section | First 6 rung-2 firings also run rung-1-alone on the same beat; log record gains `control_arm: {rung1_findings, panel_findings}` — the §6 collapse decision's data |
| Escaped-defect log — write + read | `docs/ops/escaped-defects.jsonl` (new) + `append_escaped_defect()` and `judge_area_weight(area)` helpers in `judge-sizing.md` | Record: `{date, area, signal, rung_armed, verified_findings, cost_tokens, control_arm?}`; seeded with probe's 4. Read side: `judge_area_weight` filters records to the 30-day window and counts prefix-matches on `area` — signal 5 fires on count ≥ 1; absent file → 0 |
| Content-hash pinning | `system/hooks/red-verification.sh` + `goal-completion.sh` (edit) | **Backward-compatible parallel map**: `tests_required[]` stays a string array (all existing consumers untouched — red-verification idempotency `index()`, goal-completion audit/UNREG greps, test suites test-red-verification.sh / test-goal-completion.sh G7/G9/A1); a new sibling key `tests_hashes: {path: sha256}` is written at registration; goal-completion re-hashes registered paths and blocks on mismatch (closes ADR-082 §5 residual gap) |
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
  precedence; exit-2 on empty table; nature max() precedence (kind vs file class,
  mixed diffs); `parse_sibling_verdict()` on fixture verdict text (yes/no/missing
  field); `judge_area_weight()` window + prefix matching + absent-file → 0;
  **subset-only allowlist assertion** — every brief's allowlist intersected with
  the runner denied-verb list must be empty (ADR-082 §4e AC). Content-hash:
  register → weaken → expect block; plus regression run of the EXISTING suites
  (test-red-verification.sh, test-goal-completion.sh G7/G9/A1) proving the
  parallel-map design leaves string-array consumers untouched.
- **Integration (25%):** forced-signal dry beat — fixture diff touching a
  critical path arms rung ≥ 1; challenger-prompt contract test greps the spawn
  prompt for the sibling-verdict field (drift guard).
- **E2E (5%):** one supervised proof-of-life beat on a real S task at rung 0
  (transcript unchanged) — t-2845 precedent. Runtime missing-field fallback
  (Edge Case 4) is verified here, in the supervised beat — it is LLM-output
  behavior the bash-block pattern cannot capture.
- **Mock policy:** real files/fixtures; no model calls in tests (spawn contracts
  are text, tested as text).

## Documentation Plan

- [ ] **Tech doc** — this file (design rationale, extending the table).
- [ ] **User guide** — `docs/guide/features/judge-escalation-valve.md`: what arms,
  what the beat report lines mean, how to read SPLIT verdicts and the log.
- [ ] **Existing docs to update** — challenger-gate.md (in-place), loops-library.md
  (reference), CALIBRATION.md pointer if verdict classes grow `SPLIT`.

## Challenger findings

Spec challenge 2026-08-14 (context-isolated, RECONSIDER → repaired in place):
- **Sev 5:** blind test-author was written "pilot-gated" — the exact framing
  ADR-082 §6 rejects. Repaired: mechanism ships opt-in/signal-armed in this task;
  the pilot gates default-on promotion only.
- **Sev 4 ×2:** in-loop critic + control-arm counters (both ADR-assigned to
  t-2895) were undeclared → added to Scope In + Design; escaped-defect log had
  no read side → `judge_area_weight()` specified. (The task-context deliverables
  list predating this spec had the same two omissions — reconciled here.)
- **Sev 3-4:** content-hash schema change would have broken 4+ existing
  consumers → redesigned as a backward-compatible parallel `tests_hashes` map;
  existing suites added as regression tests.
- **Sev 3 ×4:** nature derivation dropped `kind` → max() rule stated; docs-nature
  had no router case → read-only-claims + contract/AC-fidelity; exit-contract
  precedent mis-cited (branch-prefix never errors — exit-2 follows
  exit-contract-lint's registry rule, and the resolver registers in that lint);
  §4e subset-only AC had no test → allowlist-intersection assertion added.
- **Sev ≤2:** Edge Case 4 runtime fallback assigned to the supervised E2E beat;
  `docs/ops/` placement kept (user-confirmed) with the workspace-taxonomy note
  acknowledged.

Gate challenge 2026-08-14 (rung-2 panel on this feature's own diff — challenger +
2 blind finders; 22 raw → 14 verified, 5 sev-4, all repaired same-day; the ADR's
Challenge record carries the §3 signal-3 amendment this pass produced):
- Fixed: unhashed-registration exemption (channel 3 walks `tests_required` now);
  hash re-pin on red re-commit; exit-contract marker within lint's 10-line bind
  window (lint polices 2 helpers, verified); judge-sizing.md in its own critical
  list; SPLIT defined in CALIBRATION.md; §4e detector de-vacuized (subset-vs-base);
  signal-3 narrowed to lock/pull (ADR amendment); valve diff base `dev...HEAD` +
  snapshot-once; `judge_area_weight` root-anchored default; goal-file temp rename
  same-dir; unreadable `tests_hashes` gates; `merge=union` for the log.
- Accepted residual risks (recorded, not silent): manual/CLOSE completion path
  can still complete a task with a weakened test — the hash gate governs
  AUTO-completion; the human valve is the intended backstop for manual paths.
  Partial multi-file registration on crash self-heals on the next commit
  (idempotent re-run). Control-arm may overshoot 6 samples under concurrency
  (harmless). Two sessions sharing one checkout can race the goal file —
  excluded by worktree discipline, not by code.
