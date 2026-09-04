---
depends_on:
  - docs/architecture/decisions/ADR-050-loop-request-protocol.md
  - docs/architecture/decisions/ADR-059-multi-agent-substrate-selection.md
  - docs/architecture/decisions/ADR-062-runner-executor-sandbox.md
  - docs/architecture/decisions/ADR-079-backlog-drain-loop-handoff.md
informs:
  - docs/architecture/features/loops-library.md
  - docs/guide/workflows/drain-loop.md
status: accepted
---

# ADR-092: Graduated Loop-Autonomy Ladder (L0→L3, Promotion by Evidence)

**Date:** 2026-09-04
**Status:** Accepted
**Tasks:** t-2824 (this ADR), t-2823 (L0 Reporter precedent, shipped), t-2811/t-2813 (drain-loop, shipped at L1), t-2847 (watchdog/reclaimer, names this ADR as a prerequisite for classifying its own autonomy level)
**Source:** docs/ideas/drained/loop-first-redesign.md §Proposed backlog plan; challenger review of t-2823 (2026-08-13, verdict PROCEED WITH CHANGES, finding 4: "this ADR evaporated during plan→backlog translation; it must exist and block any L1+ (mutating) loop sibling")

## Context

The loop-first direction (docs/ideas/drained/loop-first-redesign.md, 2026-08-13) proposed a graduated autonomy ladder — L0 Reporter → L1 Preparer → L2 trivially-safe Merger → L3 — "promoted by evidence (5 clean runs), never assumed." That ladder was named in the brainstorm, penciled as a follow-up ADR in the proposed backlog plan, and then **evaporated during plan→backlog translation**: the L0 loop (t-2823, pipeline-digest) shipped without it, the L1 loop (t-2811/t-2813, drain-loop) shipped without it, and `docs/architecture/features/loops-library.md` now ships an `autonomy: L0-L3` frontmatter field with no ADR defining what the levels mean or how a loop earns promotion between them.

This is not a hypothetical gap. Two loop entries already carry an `autonomy:` value in production:

- `system/loops/pipeline-digest.md` — `autonomy: L0`, `supervised: true`. Read-only digest, zero writes, proven t-2823 (2026-08-13, "zero write operations in the loop path (read-only verified)" AC).
- `system/loops/drain-loop.md` and `system/loops/epic-drain.md` — `autonomy: L1`, `supervised: true`. Both mutate `tasks.json` and merge branches per an explicit denied-verbs list, always under a human watching beats live. Proven: drain-loop's 8-beat supervised session (2026-08-13, t-2813) plus ongoing production use draining tagged waves since.

Neither entry's `autonomy:` value was ever formally defined — it was assigned by convention, matching the vocabulary the brainstorm coined. `docs/architecture/features/loops-library.md`'s own lint requires a denied-verbs table for any entry above L0 but does not say what distinguishes L1 from L2 from L3, or what evidence justifies moving an entry from one to the next. t-2847 (watchdog + lease-reclaimer) names this ADR as a prerequisite for classifying its own autonomy level. Without this ADR, every future loop either invents its own ad-hoc autonomy story or copies drain-loop's by cargo cult, and the challenger's finding 4 stands unaddressed.

Separately, ADR-062 (runner-executor-sandbox) already gates `supervised: false` (unattended execution) — no loop entry may declare it "until ADR-062 lands" (loops-library.md §Design). That gate is about *whether a loop may run with nobody watching at all* — a sandbox/security question. This ADR is a different, complementary question: *given a loop that is running (supervised or not), what is it allowed to DO, and how does it earn permission to do more.* The two compose: a loop's effective ceiling is `min(its autonomy level's permitted actions, ADR-062's supervised gate)`.

## Decision

**Four autonomy levels, each a superset of denied-verbs freedom over the last, each entered only by evidence recorded against the loop entry itself — never assumed at design time.**

| Level | Name | May do | Denied-verbs boundary | Shipped precedent |
|---|---|---|---|---|
| **L0** | Reporter | Read state, compute a digest, write ONLY to its own output artifact (a gauge file, a record). | Everything else — no writes to any durable store the loop doesn't own outright. | `pipeline-digest` |
| **L1** | Preparer / supervised executor | Mutate durable state (`tasks.json`, branches, merges) strictly within an explicit, named denied-verbs list, with a human watching beats live (`supervised: true` mandatory — L1 can never run unsupervised). | Named per-entry (e.g. drain-loop's own §Denied verbs) — every action outside the list is refused, not just discouraged. | `drain-loop`, `epic-drain` |
| **L2** | Trivially-safe Merger | Everything L1 permits, PLUS: autonomously commit a narrow, provably-safe class of actions without a human watching that specific beat — "trivially-safe" meaning the classifier deciding safety is itself deterministic and machine-verifiable (exit codes, diff shape, a closed enumerable set of file globs), never a judgment call. | The safe-class classifier itself becomes the denied-verbs boundary: anything the classifier does not affirmatively recognize is denied, not defaulted to allowed. | None shipped yet — first candidate is expected to be a narrowly-scoped merge class (e.g. lockfile-only diffs, doc-only diffs with a passing structural check). |
| **L3** | Autonomous | Everything L2 permits, PLUS: broader unattended action within its domain, still bounded by an explicit denied-verbs list, still requiring `supervised: false` to have separately cleared ADR-062's sandbox gate. | Per-entry, reviewed at promotion time with the same evidence bar as L1→L2, scaled up. | None shipped; not expected soon — this level exists in the ladder so the destination is named, not to be reached casually. |

**Promotion is evidence-gated, per entry, never per-level-in-the-abstract.** A loop entry is proposed at the lowest level that lets it do its job (default: L0 unless the job requires mutation, per ADR-050's suggest-and-confirm — see Reconciliation below) and promotes ONE level at a time, only when:

1. **N clean runs at the current level**, N = 5 minimum (the number named in the originating brainstorm; drain-loop's own proof-of-life bar — "8-beat session, ongoing production use" — already exceeds this for L1, retroactively validating the threshold rather than inventing a new one). "Clean" = zero denied-verb refusals surfaced as a near-miss requiring a boundary widening, zero STOP-condition triggers that weren't the loop's own designed termination.
2. **The next level's denied-verbs boundary is written down BEFORE the first promoted beat runs**, not discovered live. Same discipline ADR-050 already requires of prompt content: machine-verifiable, never "assess whether this action seems safe."
3. **A human explicitly approves the promotion** — this is itself a suggest-and-confirm moment under ADR-050's protocol, not an automatic transition. The evidence (N clean runs, denied-verbs draft) is presented; the human confirms or the loop stays at its current level.
4. **Demotion is unconditional and immediate** on any denied-verb near-miss or STOP-condition surprise — one incident drops the entry back a level pending re-review. No "we'll tighten the boundary and stay" — the ladder only moves up on affirmative evidence and moves down on any negative signal, asymmetrically.

Record promotion/demotion events in the loop entry's own `records:`-referenced beat log (loops-library.md §Beat record schema) — promotion history is part of an entry's proof-of-life, not a separate bookkeeping system.

### Reconciliation with ADR-050

ADR-050 governs whether a loop may be *suggested and spawned at all*; this ADR governs what a spawned, running loop is permitted to *do* and how that permission grows. Three of ADR-050's clauses apply unchanged at every rung of this ladder — the ladder does not loosen them, and no future loop entry may cite "I'm L2/L3 now" as grounds to relax any of the three:

- **`durable: false` default (ADR-050 §Durability).** Promotion up the autonomy ladder is orthogonal to durability. An L3 loop is still a session-scoped, non-durable loop by default; earning the right to act more broadly within a session is not the same as earning the right to survive past it. `durable: true` still requires the same explicit user request ADR-050 already demands, regardless of level.
- **Kill-sweep ownership (ADR-050 §Lifecycle contract).** The three-part sweep — the suggesting skill's CLOSE/REPORT step running `CronList`/deleting loops it spawned, `/brana:close`'s sweep of remaining session loops, session-end killing non-durable loops by construction — applies identically at L0 and L3. Higher autonomy is not exemption from being killable the same way everything else is.
- **Machine-verifiable prompt content (ADR-050 §Prompt content).** This requirement gets *stricter*, not looser, as autonomy rises: an L0 loop's termination check must be machine-verifiable; an L2 loop's *safe-class classifier itself* must additionally be machine-verifiable — the higher the autonomy, the less room for a judgment call anywhere in the decision path.

## Consequences

- t-2847 (watchdog + lease-reclaimer) can now classify itself against this ADR: the watchdog is a pure gauge (L0 — it never acts, per its own four-primitive design), the reclaimer is a distinct L1 pump (it mutates task state within a named denied-verbs boundary — reset only on lease-expired AND no-commits evidence — under supervision until it accrues its own 5-clean-run record).
- `docs/architecture/features/loops-library.md` should cite this ADR from its `autonomy:` frontmatter field description instead of leaving the levels undefined by name (doc-sync follow-up, not blocking this ADR's acceptance).
- `pipeline-digest`, `drain-loop`, `epic-drain` need no behavior change — their existing `autonomy:` values (L0, L1, L1 respectively) are retroactively validated by this ADR's definitions, not contradicted by them.
- Any future loop entry proposing `autonomy: L2` or above must attach this ADR's evidence bar (§Decision, promotion rules) to its own task before it may ship — the challenger's finding 4 is closed by this document existing and being citable, not by any code change.
- L2/L3 remain theoretical until a first candidate is proposed; this ADR deliberately does not pre-design a specific L2 safe-class classifier — that is scoped to whichever loop first proposes promotion, reviewed against the rules above.

## Non-Actions

- **No new infrastructure.** Same as ADR-050: native `/loop`, `CronCreate`, `Monitor` remain the only mechanisms. This ADR adds a permission model on top, not a new runtime.
- **No retroactive audit of every existing loop entry's denied-verbs list.** `drain-loop`/`epic-drain`'s existing lists stand as their L1 boundary; this ADR does not require re-deriving them.
- **No L2/L3 loop ships as part of this ADR.** This is the permission-model ADR only — t-2847 and any future L1+ proposal implement against it separately.
- **No change to ADR-062's unattended-execution gate.** `supervised: false` remains hard-blocked until ADR-062's executor sandbox lands, independent of what this ADR's ladder permits an entry to attempt while supervised.
