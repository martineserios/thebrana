# Epic-ring gauge probe — retrospective CHECK: sets on shipped waves (t-3159)

> Spike deliverable, 2026-08-24. Guide L7 #3 / L3.7 rung-1 precondition; ADR-086 §6, T4
> (t-3162) blocked_by this probe. Same probe-before-build discipline as
> [2026-08-14-judge-panel-probe.md](2026-08-14-judge-panel-probe.md) and
> [2026-08-24-plan-panel-probe.md](2026-08-24-plan-panel-probe.md).
> Question: for each shipped wave, hand-write the `CHECK:` lines an Epic-ring contract would
> have carried (allowlist vocabulary: task-state predicates, merge-base, named
> `validate.sh --check N` / `cargo test -p <crate>`), then measure what those checks would have
> caught that the human-only ship gate did not. Evidence: `docs/ops/escaped-defects.jsonl` +
> live selector/branch state.

## Verdict: GO for T4 — with two vocabulary-v1 amendments the probe itself forced

**1 of 5 shipped waves fails its most basic CHECK today** (wave-4: `shipped`, yet its selector
`parent:t-2839` still matches t-2846 = `pending` — the human gate resolved the carve-out in
contract prose and never narrowed the selector). **0 of 4 escaped code defects were catchable**
by any expressible CHECK set — that class belongs to the judge ladder, not the gauge, exactly as
§6's rung-1 framing predicts. ~⅔ of shipped-contract clauses are expressible in vocabulary v1;
the remainder must render as visible "unevaluated prose — needs you", never be silently dropped.
T4 is a one-time S/M display-only build (no recurring panel cost), and the probe found a real,
current, catchable drift — the bar for a gauge is met.

## Hand-written CHECK sets vs what actually happened

| Wave (shipped) | Contract gist | Hand-written CHECK set (v1 vocabulary) | Retro-evaluated today | Not expressible in v1 |
|---|---|---|---|---|
| wave-1 drain-1 | t-2813 merged, build gates passed | `CHECK: all selector tasks completed` · `CHECK: merged to dev` | both PASS | "all build gates passed" (judged verdicts live in task notes → stacked-verdict bundle t-2857 is the wave-level sibling, not this vocabulary) |
| wave-2 drain-2 | 7 tasks drained, gates green, merged, completed | `CHECK: all selector tasks completed` · `CHECK: selector count == 7` · `CHECK: merged to dev` | all PASS (7/7 completed, branches merged/deleted) | "gates green" (judged) |
| wave-3 adr080-core | t-2840/41/42 merged, gates passed; AtLimit-on-parent regression green | `CHECK: all selector tasks completed` · `CHECK: merged to dev` · `CHECK: cargo test -p brana-core green` (owns the named AtLimit regression) | all PASS | "build gates passed" (judged) |
| wave-4 adr080-consumers | t-2843/44/45 ship; t-2846 carved out to wave-5 in prose | `CHECK: all selector tasks completed` · `CHECK: merged to dev` | **`all selector tasks completed` FAILS — t-2846 pending, wave shipped.** True positive: the selector was never narrowed after the split; contract prose and selector contradict each other to this day | fixture dry-run + "3 supervised proof-of-life beats" (beat-record counts — v2 candidate) |
| wave-11 time-tracking-decision | ADR written+approved; idle-cap re-validated vs ≥3 session shapes | `CHECK: all selector tasks completed` · `CHECK: merged to dev` | both PASS | both substantive clauses ("ADR approved", "re-validated against ≥3 shapes") — research-wave contracts are vocabulary-resistant end to end |

## What the checks would NOT have caught — and must not claim to

`escaped-defects.jsonl` lines 1–4 (2026-08-14, probe-t2887): four verified sev-3/4 defects on
wave-3/wave-4 diffs (`yes|` auto-confirm all batches; MCP partial-apply + false error; cancelled
absent from denied-verbs; "read-only" wave board auto-creates tasks.json). Every one shipped past
the human gate. **No CHECK set catches any of them**: the vocabulary can only assert that *named,
existing* tests/checks ran green, and these defects were precisely the untested classes. The
catch mechanism for that class is the judge ladder (ADR-082) — which did catch them, later, at
rung 2. Measured division of labor: **gauge owns process drift; ladder owns defect discovery.**
T4's display must not be read (or sold) as a defect gate.

## Miss-rate summary (AC)

- Process-drift class: **1 catchable miss / 5 shipped waves** (wave-4 selector-vs-status
  contradiction, still live at probe time). Merge-base checks: 0 misses (9/9 wave branches
  merged or deleted). Count checks: 0 misses.
- Escaped-defect class: **0 / 4 catchable** — out of the gauge's reach by construction.
- Vocabulary coverage: **~⅔ of contract clauses expressible**; per-wave from 3/3 (wave-2) down
  to ~0/2 substantive (wave-11, research wave).

## Allowlist vocabulary v1 (refined from real waves — AC)

1. `CHECK: all selector tasks completed` — task-state predicate over the resolved selector.
2. `CHECK: selector count == N` / `>= N` — pins the release-unit size (wave-2 shape).
3. `CHECK: merged to dev` — every selector task's `branch` is an ancestor of dev or deleted.
4. `CHECK: validate.sh --check N green` — named check id only.
5. `CHECK: cargo test -p <crate> green` — named crate only.

**Amendments the probe forced (both from wave-4/wave-11 evidence):**

- **A1 — explicit exemption, not silent prose:** a carve-out must be machine-visible:
  `CHECK-EXEMPT: t-NNN <reason>` (or the selector gets narrowed at split time). Without it, the
  gauge either cries wolf on every prose carve-out or gets ignored — wave-4 shows carve-outs are
  real and currently invisible to any evaluator.
- **A2 — the remainder renders:** contract prose not parseable as CHECK/CHECK-EXEMPT is displayed
  under "unevaluated — needs you" (t-2857's unknown-routing rule at wave level). Research waves
  (wave-11) are the norm, not the edge: their whole substance lives in that band.

Deferred to a v2 (do not build now): beat-record count predicates (wave-4's proof-of-life
clause), doc/file-existence predicates (wave-11's "ADR written") — both need a home-of-record
convention before they can be checked honestly.

## Consequences (executed per AC)

1. **GO recorded on T4 (t-3162)**: blocked_by t-3159 cleared; context appended with the verdict,
   vocabulary v1 + A1/A2, and the division-of-labor boundary (display-only, never a defect gate,
   never auto-ship — ADR-079/080 §7 reservations restated).
2. **wave-4 drift filed to the operator surface**: its selector still contradicts its shipped
   status; fix is either narrowing the selector or the first live `CHECK-EXEMPT: t-2846` once T4
   lands — left to T4's build as its first real fixture.
