---
status: accepted
---
# ADR-061: `/goal` Integration — Three-Primitive Composition (loop · goal · workflow)

**Status:** Accepted (2026-06-21; after two challenger passes — review + verification, all findings resolved)
**Date:** 2026-06-21
**Deciders:** Martín Rios
**Tags:** loop-native, goal, workflow, autonomy, substrate, security, looptrap
**Tasks:** t-2194 (this ADR) · Stage 2–4 build tasks decompose from it
**Extends:** [loop-native redesign](../../research/2026-06-11-loop-native-redesign.md) (Finding 3) · [substrate-primitives §2b](../substrate-primitives.md) · [ADR-050](ADR-050-loop-request-protocol.md) (autonomy caps)
**Relates:** [t-1992 step-state contract] (gates Stage 4 only) · pattern_looptrap-autonomy-findings (P5/P7) · t-2193 C3 / t-2173 (grader-outside-graded invariant)

---

## Context

The loop-native redesign placed two of Claude Code's three native orchestration
primitives — `/loop` (the foreman heartbeat) and `Workflow` (the per-task crew) — but
left the third, `/goal`, only gestured at ("iterate-until-done lives in `/goal` +
Workflows"). [Finding 3](../../research/2026-06-11-loop-native-redesign.md)'s mapping
table has two rows. The **supervised** autonomy tier in
[substrate-end-state.md#operating-the-orbit](../substrate-end-state.md#operating-the-orbit)
is documented as *design-pending* for exactly this gap.

`/goal` is the CC-native in-session primitive that keeps a session working turn-after-turn
until a CONDITION is met (distinct from `/loop`'s interval polling and `Workflow`'s
one-shot fan-out). This ADR decides **where `/goal` fits, which skills gain a `/goal`
loop, how the three primitives compose, and how `/goal` terminates on machine-verifiable
state rather than self-assessed progress.**

## Decision

### 1. The composition model — primitives split by what they do to a gate

| Primitive | Verb | Level | Relationship to a human gate |
|-----------|------|-------|------------------------------|
| `/loop` | **POLL** across tasks | session / foreman | *Spans* gates — by parking and handing back to the human, never crossing |
| `/goal` | **ITERATE** within one span | per-task / per-phase | *Owns* one **gate-free** span; **stops at** the gate |
| `Workflow` | **FAN-OUT** once | crew / per-attempt | *Inside* a single attempt; no gate interaction |

This is Finding 3's table extended to its missing third row. It falls out of the
eligibility criteria below, not from preference.

### 2. Eligibility criteria — where `/goal` is allowed to live

Three **hard** filters (pass/fail) and three soft:

| # | Criterion | Type | Source |
|---|-----------|------|--------|
| C1 | A **machine-verifiable** stop signal exists at this grain (exit code / `AC:` / validate.sh) | HARD | LoopTrap P5/P7 — never self-assess "done" |
| C2 | The span is **gate-free** (no human gate inside it) | HARD | ADR-050 — `/goal` must never auto-cross a gate |
| C3 | The span is **mutation-bounded** — either (a) the done-signal is external to the codebase (validate.sh), or (b) the set of files the loop may write is declared and constrained to the span's task | HARD | challenger Attack 2 — block unbounded-mutation spans |
| C4 | Iteration is bounded (≤3 auto-advances, cost-capped) | soft | ADR-050 §t-517 |
| C5 | The span survives context (short spans favored) | soft | compaction/rot |
| C6 | Composes with the built `/loop`-foreman + `Workflow`-crew | soft | reuse |

The **session level fails C2** (it crosses N merge gates) → that level is `/loop`'s job,
not `/goal`'s. This is the clean three-way split.

**Why C3 is hard, not soft (challenger Attack 2):** C1+C2 alone wrongly admit a
rename-across-200-files refactor — machine-verifiable (`cargo test`) and gate-free, yet the
loop can make irreversible mutations with no human touchpoint until the signal fires. C3
bounds the blast radius: the three v1 bindings all pass it (the TDD loop is scoped to the
subtask's files, fix to the failing path, reconcile validates against external validate.sh).

### 3. Architecture — one primitive, many declared bindings

`/goal` is **one primitive parameterized by a stop-condition**, plus a grep-able list of
skill spans that each declare `{span, observable-done-signal}`. A skill "gains a `/goal`
loop" by declaring one thing; new bindings are cheap. This is not N features — it is one
engine and N declarations.

**v1 binding list:**

| Binding | Span | Done signal | Needs t-1992? |
|---------|------|-------------|---------------|
| `/brana:build` TDD loop | red → green (refactor **outside** the span) | all `AC:` exit codes == 0 | No |
| `/brana:fix` | reproduce → fix → verify | the failing test now passes | No |
| `/brana:reconcile` | detect → fix → re-validate | validate.sh exit 0 | No |
| per-skill-phase (generalized) | any gate-free phase | the phase's machine-verifiable `done` | **Yes — Stage 4 only** |

The three specific bindings carry **self-contained, already-external** done-signals, so
they need nothing from t-1992. The step-state contract (t-1992) is load-bearing **only**
for the generalized binding, which must know phase order + gate flags (`next_step` /
`gate_pending`).

**Binding-declaration rule (challenger Attack 1 — gate-free is a snapshot, not a structural
property):** a span declared gate-free today can gain a gate later (e.g. `/brana:reconcile`
gaining a mandatory challenger-confirm step). A binding does not self-invalidate when this
happens. Therefore: **any commit that adds a human gate inside a declared `/goal` span MUST,
in the same commit, either re-scope or retire the affected binding.** This is a process rule
(enforced at review), and binding declarations live next to the skill procedure so the gate
author sees them.

### 4. Security invariants — the spine

`/goal` is an **optimizer with the done-signal as its objective function.** Point an
optimizer at a weak proxy and it Goodharts the proxy. "External done-predicate" is
therefore **necessary but not sufficient.** Three hard invariants — written as
**cross-cutting autonomy policy** (the unifying rule below also governs the runner and
sandbox), with the same-class principle named:

| # | Invariant | Defends against | Principle shared with |
|---|-----------|-----------------|------------------------|
| 1 | **Presence interlock** — auto-advance requires a *structurally-verified* interactive session (not a convention) | headless auto-complete / silent gate-bypass | §2b binding A/B split (doc-level today) |
| 2 | **Done-signal immutability** — the loop may not mutate anything the grader reads: `*.test.*`, `tests/` (incl. `fixtures/`, `mocks/`), `__mocks__/`, the `AC:` lines, **and any task-record field a done-heuristic reads** (`tasks.json` `status`/`notes`/`context` — a `brana backlog get` grader can be gamed by editing them). All pinned at iteration start, not read live; grade against a base-ref-pinned copy of those paths | AC-gaming via test, fixture, mock, AC-line, or task-record edits | t-2193 C3, t-2173 (both **pending**) |
| 3 | **Bounded span** — iterate-until = red→green **only**; refactor is capped/optional, outside the predicate | LoopTrap P7 (refactor-forever) | ADR-050 §t-517 caps |

> **The unifying rule (invariant 2 generalized):** *the thing that checks the agent must
> live outside the agent's control.* It governs the autonomous runner's AC-grader (t-2193
> C3), the executor sandbox (t-2173), and now `/goal`'s done-signal — one rule, three sites.

> **⚠ Enforcement reality (challenger Attack 3 — BLOCKER):** invariant 2 is **aspirational,
> not yet enforced.** The live `system/hooks/goal-completion.sh` grades by running the test
> command in the *live* worktree with **no diff-guard, no base-ref pinning, and a live `AC:`
> read** — so a `/goal` loop can today satisfy its AC by editing a fixture, a mock, or the
> AC line itself. The cited sites (t-2193 C3, t-2173) are **pending tasks, not shipped
> features.** Therefore invariant 2 enforcement is **not "open/deferred" — it is a required
> Stage 2 deliverable**: harden `goal-completion.sh` with base-ref pinning of the grader
> paths above + a `tests/` mutation guard, *before* the build TDD binding is trusted. Until
> that lands, the v1 bindings run with invariant 2 unenforced and a human must review every
> green.

> **Invariant 2 refinement (t-2205, 2026-06-21 — deep challenge, 3 lenses converged):**
> base-ref pinning *alone* is incompatible with TDD — the loop's first step writes the test
> file, which the grader reads, so a single pin at goal start trips the gate on every legit
> run. Resolution — distinguish **Modified** from **Added** grader paths:
> - **Modified** (`git diff --diff-filter=M base_ref`) pre-existing grader paths → **always
>   blocked** (editing a test/fixture/AC-line/`tasks.json` that existed at goal start = gaming).
> - **Added** (`--diff-filter=A`) + **untracked** new grader-path files → blocked **unless**
>   registered in `active-goal.json.tests_required[]`. The build procedure declares each test it
>   writes (a path-only filter cannot distinguish a new test from an injected fixture — both are
>   new files matching `tests/`). `tests_required[]` lives on disk → survives compaction.
> base_ref stays a **single pin at goal start** (per-subtask re-pin rejected: clears the window
> retroactively + fragile across resume; also fails build-loop step 3g's post-green boundary tests).
> **Stage-2 gap (accepted, soak):** registration does *not* verify the test was **red** — a
> trivially-green test can be registered. Acceptable for Stage 2 because the presence interlock
> (inv. 1) means a human reviews every green. **Red-verification is a Stage-3 gate:** a pre-commit
> hook that registers a test in `tests_required[]` only if it exits non-zero. Stage-3 bindings
> (t-2206) are `blocked_by` that hook. Missed registration is **fail-closed** (gate blocks, human
> completes manually).
>
> **Update (t-2216, 2026-06-22 — gap CLOSED):** the red-verification hook shipped as
> `system/hooks/red-verification.sh`, wired into the git pre-commit chain
> (`system/scripts/git-hooks/pre-commit`). It grades the **staged blob** (not the working tree, so
> a stage-green/worktree-red swap cannot earn a false exemption) and registers a newly-added test
> only when it runs red; green stubs, injected fixtures, and un-runnable files stay blocked
> (fail-closed). `build-loop.md` step 3d1 now commits the failing test in its own red commit
> instead of hand-appending to `tests_required[]`. t-2206 (Stage 3) is unblocked.

### 5. Sequencing — evidence-gated, t-1992 off the critical path

```
Stage 1  ADR-061 (this) — generalized design + 3 specific bindings   ← needs nothing from t-1992
Stage 2  BUILD build's TDD binding (stops AT the TDD gate)           ← soak, collect evidence
Stage 3  BUILD fix + reconcile bindings                             ← after build earns a track record
   ───── t-1992 step-state contract lands in parallel, off the critical path ─────
Stage 4  BUILD generalized "any gate-free phase declares a /goal"   ← NOW needs t-1992
```

Autonomy is **earned per binding**, mirroring the autonomous runner's staged-trust
backbone (observe → run-one → batch → learned). The widest surface (Stage 4) ships last.

### Relation to ADR-050 §t-517 and t-1992

- **ADR-050 §t-517** is settled advancement *policy* (machine-verifiable checkpoint, never
  cross a human gate, max 3 auto-advances, validate at the gate). `/goal` is an
  *implementation* of that policy for the supervised tier — it does not re-litigate it.
- **t-1992** supplies the `done` predicate for the **generalized** binding only. Its own
  2026-06-12 analysis found `next_step`/`gate_pending` are *derivable* from a step
  registry + the already-shipped `~/.claude/run-state/{task_id}.jsonl` log — so the
  dependency is small and half-built, and it is off the Stage 1–3 critical path.

## Consequences

**Positive**
- The supervised tier moves from "design-pending" to buildable; the Orbit's two tiers
  both have a defined operating model.
- One engine, cheap bindings — new `/goal` loops are declarations, not features.
- Invariant 2 becomes cross-cutting policy, retro-strengthening the runner and sandbox.
- **Self-feeding sequence (sharpened — challenger Attack 5):** Stage 2's autonomous TDD loop
  produces **usage evidence that informs** t-1981 lint heuristics and t-1992's design — it
  does *not* auto-emit their data. Structured audit output ("criterion X satisfied by commit
  Y in file Z") is itself a **Stage 2 build deliverable**, not an automatic emission of the
  current Stop hook (which emits a one-line string). Deferring t-1992 does not *delay* it,
  but Stage 2 does not *bootstrap* it either — it proves the design is worth building.

**Negative / risks**
- **t-1992 derivation may not hold** — if `next_step`/`gate_pending` aren't cleanly
  derivable, t-1992 balloons. *Mitigated:* gates Stage 4 only, off the critical path.
- **Premature abstraction** — the generalized contract is designed before evidence.
  *Mitigated:* Stages 2–3 produce real bindings first; generalize after.
- **Gate complacency** — `/goal` can turn a human gate into a rubber-stamp reflex.
  *Mitigated:* invariant 1 + short spans (few gates per session).

## Alternatives considered

- **Bottom-up (3 hardcoded loops, generalize later)** — rejected: builds termination logic
  three times, then a refactor pass. Throwaway glue; fails the marathon test.
- **Per-session `/goal` (iterate the whole backlog)** — rejected: fails C2 (crosses merge
  gates). That level is `/loop`'s by construction.
- **`/goal` as a new skill or agent** — rejected: the supervised tier reuses existing
  native primitives (`/brana:build` + `/goal` + `/loop`); no new surface is warranted.

## Open (deferred to build)

- Exact mechanism of the presence interlock (how a binding *proves* an interactive session).
- Whether invariant-2 enforcement is a pre-iteration diff-guard or a pinned-grader copy
  (the *requirement* is decided in §4; only the implementation shape is open).
- Stage-2 evidence thresholds that unlock Stage 3.
- **~~`/goal` is a one-shot anchor today, not an iterate loop (challenger Attack 4).~~ RESOLVED 2026-06-21 (t-2205) — option (b): keep `/goal` a one-shot session anchor.**
  The Stage-2 build binding is *not* a hard re-entry loop. It is: (1) the `active-goal.json`
  declaration (span = build's red→green, done-signal = all `AC:` exit codes == 0) plus
  (2) `goal-completion.sh` auto-completion at Stop. Iteration is driven by the session's
  natural Stop → "goal blocked: {criterion}" → continue cycle, **not** by the hook re-injecting
  a continuation. The §1 "ITERATE" verb stays *design intent* until a later stage proves a hard
  loop is needed. **C2 holds by construction:** no auto-iterating span exists to contain the
  per-subtask TDD gate, so the binding never auto-advances *through* the gate — auto-complete
  fires only when **all** AC are green (i.e. every per-subtask TDD gate was already passed by a
  human), and even then only behind the presence + base_ref-immutability interlocks (§4).
  Deferred to Stage 4 (generalized binding): whether to add real hook-driven re-entry.

## Challenger dispositions (2026-06-21, t-2194 AC)

PROCEED WITH CHANGES — 1 BLOCKER, 2 HIGH, 2 MEDIUM, all incorporated:

| Attack | Severity | Disposition |
|--------|----------|-------------|
| 1 — gate-free is a snapshot | HIGH | **Fixed** — binding-declaration rule (§3) |
| 2 — C1+C2 admit unbounded-mutation spans | HIGH | **Fixed** — added hard criterion C3 (§2) |
| 3 — invariant 2 under-specified + live hook doesn't enforce it; "already enforced" cited pending tasks | BLOCKER | **Fixed** — enumerated grader paths + AC pinning (§4); corrected the false enforcement column; made hardening a required Stage 2 deliverable |
| 4 — TDD binding: `/goal` is a one-shot anchor, not a loop | MEDIUM | **Resolved (t-2205, 2026-06-21)** — option (b): keep one-shot anchor; iteration is session-driven, auto-complete only at full-green behind interlocks. See Open §Attack 4 resolution. |
| 5 — self-feeding-sequence overclaim | MEDIUM | **Fixed** — sharpened Consequences language |
