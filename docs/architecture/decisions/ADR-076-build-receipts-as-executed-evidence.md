---
status: accepted
---
# ADR-076: Build Receipts as Executed Evidence — and Why Enforced Delegation Was Deferred

**Status:** Accepted (2026-08-02)
**Date:** 2026-08-02
**Deciders:** Martín Rios
**Tags:** harness, receipts, verification, delegation, adr-060, adr-062
**Tasks:** t-2592 (this ADR) · gates t-2593 (`brana receipt mint|validate`) · t-2594 (pre-merge hook) · t-2595 (feature spec) · t-2591 (the Phase-0 measurement that killed the delegation half)
**Relates:** [ADR-060](ADR-060-branch-strategy-autonomous-agents.md) (two-tier `dev`→`main`; records that promotion has no automated gate) · [ADR-062](ADR-062-runner-executor-sandbox.md) (a worktree isolates tracked files, not the process — the same "the gate inspects less than you think" class) · [ADR-075](ADR-075-ship-on-deploy-surface-change.md) (advisory signals inside the deploy path) · idea: [build-receipts](../../ideas/drained/build-receipts.md) · idea: [enforced-delegation](../../ideas/drained/enforced-delegation.md)

---

## Context

### The problem this actually solves

Task notes and git routinely disagree about whether work is done
(`pattern_task-notes-are-not-work-state`). "Done" today rests on an LLM's evaluation of
acceptance criteria plus notes written by that same LLM. There is no artefact in which git
and executed test output — rather than assertion — are the authority.

This is our own reason. It does not depend on any external tool being right, and it is why
the receipt track survived a measurement that killed everything around it.

### What the reference implementation actually does

The receipt design was researched against gentle-ai's Receipt-Driven Development by reading
its source rather than its README. The headline finding **inverts what the name suggests**:

> **Their receipts hash a claim. They never execute verification.**

| Component | What it actually is |
|---|---|
| The verdict | a CLI flag the *agent* supplies — `--outcome passed` (`internal/cli/review_artifact.go:44,78`) |
| The "evidence" | caller-supplied bytes, only SHA-256'd (`verification_evidence.go:90`) |
| State transition | reads that supplied enum directly (`compact.go:1512-1516`) |
| Subprocesses the review engine spawns | **`git` only** — no test runner, ever (`snapshot.go:1468`) |

They are explicit and honest about the boundary; it is a documented design decision, not an
oversight:

> "Checksums only where useful for detecting accidental corruption; **they are not
> authentication**" — `docs/review-authority-threat-model.md:29`

No test asserts a truthful-verification property, because the code claims none.

**So their receipt means:** *"an agent asserted outcome X over exactly these git trees, and
the trees are still these."* That is **scope-binding, not truth** — a materially narrower
claim than "structural proof replaces agent self-report." Adopting the artefact without
correcting this would have reproduced `pattern_hashed-claim-is-not-evidence` and called it
verification.

### The enforcement gap

gentle-ai's five gates (`post-apply`, `pre-commit`, `pre-push`, `pre-pr`, `release`) are
**CLI subcommands, not git hooks** — grep for `.git/hooks` across their codebase returns
nothing. Compliance is procedural, carried by agent-facing skill text. **Nothing physically
prevents `git commit`;** an agent that skips `review validate` commits normally.

That is `pattern_gate-armed-by-the-party-it-constrains` sitting in the reference
implementation itself. A mature, carefully built system landing on a voluntary gate by
default is evidence that the failure is **structural rather than careless** — which raises
the priority of the hook (t-2594) from "wiring" to "the part that makes the artefact
non-decorative."

ADR-060 records the matching hole on our side: `dev`→`main` "has no automated gate beyond
local pre-commit hooks; enforcement is deferred, not active."

### Why the delegation layer is not here

The receipt originated inside a larger design — an orchestrator/executor split that would
delegate build phases to subprocess executors, with receipts as its trust boundary. That
design was descoped by adversarial review and then killed by measurement. The receipt half
survives because it never depended on the delegation half.

## Decision

### D1 — `mint` executes the check; it never hashes a claim

`brana receipt mint` runs the task's test command as a subprocess and hashes **its own
captured stdout plus exit code**. A receipt cannot be minted from an unexecuted assertion,
and no flag lets a caller supply an outcome.

This is a **deliberate deviation** from the reference implementation, and it is the only
property that makes the artefact evidence rather than a signed claim. It is recorded as a
deviation rather than an improvement because their threat model declines the claim honestly;
we are choosing a stronger claim and must therefore carry the cost of actually executing.

### D2 — The git binding is the load-bearing half; the evidence hash is only an equality token

Everything that actually catches drift is **re-derivable from the repo at gate time**:
`base_tree` / `candidate_tree` (git tree OIDs from frozen snapshots), `paths_digest`
(domain-separated and length-prefixed, `snapshot.go:1313`), and snapshot identity. The
evidence hash on its own catches nothing — it can only answer "are these the same bytes."

Consequence: a receipt is worth building on the git binding **even without D1**, and D1 is
worth nothing without the binding. Neither half is optional, and their roles must not be
confused in the schema documentation.

### D3 — The gate result is three-valued, never boolean

| Result | Meaning | Routes to |
|---|---|---|
| `allow` | proceed | merge |
| `scope-changed` | your candidate moved | **recovery**, not restart |
| `invalidated` | your approval is void | restart |

Collapsing these into a boolean is what makes verification tools infuriating enough to be
uninstalled. `scope-changed` is the distinction that earns the design its keep.

### D4 — Enforcement anchors to the merge, an involuntary event

The gate hangs on `dev`→`main` promotion (t-2594), never on state the committing party opts
into writing. An escape hatch exists and **logs its own use**, so abandonment is measurable
rather than silent — an unmeasured bypass is indistinguishable from compliance.

### D5 — Storage under `git rev-parse --git-common-dir`

Not `.git`. One authority shared across linked worktrees, invisible to `git status`, never
pushed. This repo runs concurrent sessions in separate worktrees by hard rule; per-worktree
receipt stores would silently disagree.

### D6 — The orchestrator/executor delegation layer is deferred, killed by its own falsifier

Phase 0 (t-2591) pre-registered its decision rule and committed it (`bf2524aa`, 19:51:11Z)
**before any aggregation**. The rule then fired against the design it was written to test:

| Basis | churn share | Verdict |
|---|---|---|
| Pre-registered (all tokens) | 0.342 | KILL (threshold 0.35) |
| Fresh tokens only | 0.285 | KILL |
| Raw turn counts | 0.326 | KILL |

The quota veto did not fire (median cold-load 6.4% against a 0.40 trigger), so the layer
dies on the churn split alone.

**Both sides of the original argument were wrong.** Over N=5 build sessions: orchestration
**59.0%**, churn 34.2%, understanding **6.8%**. The information-conservation objection was
wrong in its specifics — writing a self-contained brief is cheap. The delegation hypothesis
was wrong too — churn is not the majority to be exported. Neither side named the real cost
centre.

**Mechanism:** `cache_read_input_tokens` is **97.0% of all tokens consumed**. Every turn
re-reads the whole accumulated context, so cost scales as *(turns × context size)* almost
independently of what a turn does. Delegation was designed to move *activity*; the cost is
not in the activity.

The delegation design also failed on enforcement, independently of economics. These findings
are recorded because each one invalidates a specific mechanism, and a future revival must
answer them rather than rediscover them:

1. **The gate was not armed at the drift point.** `delegation-write-gate.sh` fires only
   while run-state exists, and run-state is written voluntarily by the same model whose
   drift is the diagnosed problem. Skipping the flow — today's actual failure mode — arms
   nothing.
2. **Bash bypasses the hook.** PreToolUse `Edit`/`Write` matchers do not intercept `cat >`,
   `sed -i`, or a python script — and `context-budget.md` actively *recommends*
   `/tmp/bulk-edit.py` for 5+ edits. The bypass sits on a recommended path. (Verified.)
3. **`disable-model-invocation` blocks only the Skill tool.** Procedure files stay readable
   and followable inline — and the model does not need them to build inline anyway.
4. **Subprocess executors carry no `agent_id`.** Background `claude -p` executors are
   top-level CC subprocesses, not in-session subagents (ADR-060). "Block when run-state
   active AND no agent_id" therefore blocks the executors themselves — deadlock — or needs
   an env-var discriminator the constrained model can set itself, reopening the advisory
   hole.
5. **Quota, not main-session context, was plausibly the binding constraint.** Parallel
   full-model executors partition the same subscription window rather than adding compute —
   the "hollow under subscription" failure ADR-059 documented for ruflo, reappearing in its
   replacement. The original kill criterion measured context %, interventions and
   wall-clock, never quota, so the design could have passed its own falsifier while making
   the system more expensive. Phase 0 was redesigned to measure quota; it came back slack,
   but the criterion was wrong as first written.

Finding 5 is retained even though the measurement exonerated it, because the *defect was in
the falsifier*, not in the answer.

## Rejected alternatives

- **Adopt the reference receipt as-is.** Rejected by D1. It would produce an artefact whose
  name promises verification and whose content is an agent's assertion — worse than no
  artefact, because it reads as stronger than it is.
- **Evidence hash without git binding.** Rejected by D2. An equality token over
  caller-chosen bytes proves only that nobody edited the bytes.
- **Gates as CLI subcommands (their model).** Rejected by D4. Voluntary at exactly the point
  where the constrained party is the one deciding.
- **Boolean gate result.** Rejected by D3 — it forces a restart where recovery is correct.
- **Build receipts as part of the delegation layer.** Rejected by D6: the delegation layer
  is dead and receipts are independently motivated by
  `pattern_task-notes-are-not-work-state`.
- **Rescuing delegation with the post-hoc hypothesis** (that an executor's turns happen in
  its own small context, cutting the *turns × context* product regardless of churn). This is
  post-hoc, carries no evidential weight, and invoking it now is exactly the sunk-cost
  dynamic the adversarial review warned about. If it is to be tested it needs its own
  pre-registration, threshold, and task.

## Compute cost

Stated explicitly because the track this ADR closes died on compute economics.

| Path | Cost |
|---|---|
| `mint` | one test-suite execution + git plumbing. **Zero LLM tokens.** Marginal cost over the existing build is one extra suite run, unless the CLOSE-step run is reused. |
| `validate` | git reads only. **Zero LLM tokens**, no subprocess but `git`. |
| Pre-merge hook | `validate` plus a tasks.json read. Zero LLM tokens. |
| This ADR + spec | authoring only, no fan-out. |

The receipt track is the opposite economic shape from the layer it outlived: deterministic
subprocesses instead of model turns. That is *why* the Phase-0 kill does not touch it.

## Pre-registered kill thresholds

Written **before** t-2593 begins, per the standing constraint that a threshold registered
after the fact is not a threshold. Evaluated after the **first 20 merges** that pass through
the gate; whoever evaluates records the reading with its date.

| # | Falsifier | Threshold | Action if it fires |
|---|---|---|---|
| K1 | **Nobody uses it.** Escape-hatch invocations as a share of gated merges | > 50% | **Retire the gate.** Do not harden it — routing around a gate is the signal in `pattern_enforcement-systems-overbuild-then-revert`. |
| K2 | **It gets in the way.** Median wall-clock added to CLOSE by `mint` | > 60s | Reuse the CLOSE-step suite run instead of re-executing; if that is not possible, downgrade `mint` to opt-in. |
| K3 | **There was nothing to catch.** Merges where the receipt surfaced a real disagreement — absent receipt, `scope-changed`, `invalidated`, or a failing captured exit code — over the 20 | 0 | Downgrade the hook to advisory and keep `mint` for the record. The problem was smaller than `pattern_task-notes-are-not-work-state` suggested. |

K3 is deliberately weak-but-honest: a gate that deters cannot distinguish itself from a gate
with nothing to do. Zero catches is therefore a *downgrade* trigger, not a delete trigger,
and this asymmetry is recorded so a future reader does not read the number as stronger
evidence than it is.

## Consequences

- **t-2594 is load-bearing, not wiring.** Without a hook anchored to the merge, the receipt
  is one more advisory step for the same model — the artefact this system keeps
  rediscovering (ADR-065's unenforced WIP cap, ADR-069's fail-open, ADR-075's deploy path
  that prints a remedy and continues).
- **`mint` gains a subprocess-execution surface** that the reference implementation
  deliberately does not have. It executes a command from task configuration, which is a real
  capability increase in the build path and should be scoped in the feature spec (t-2595).
- **The gate must re-check after deciding** — re-derive the snapshot and re-read authority on
  the `allow` path — or it is a TOCTOU.
- **Delegation is closed, not paused.** Any revival starts from a new pre-registration, not
  from this ADR's context. The five enforcement findings above survive the economic verdict
  and apply to *any* design that constrains a model using state that model writes.
- **Rung 1 of the adoption ladder (`_shared/executor-brief.md`, t-2597) is unaffected** — it
  burns no compute and improves four already-running delegation surfaces regardless of
  whether delegation ever expands.

## Honesty contract — what this ADR does not establish

- **There is no public evidence that receipt-driven development works.** gentle-ai has an
  internal benchmark measuring *friction of its own tool* (36 journeys) and 18+ named
  community testers filing real bugs — but no external adoption metrics, no testimonials,
  **no measured outcomes**. Nobody has reported developing faster or more safely. Adopting
  receipts is adopting a **design hypothesis with a compelling rationale**, not a proven
  practice. Nobody should later cite gentle-ai as validation.
- **The Phase-0 measurement behind D6 is thin.** N=5, not the pre-registered 12; one
  atypical session carries 652M of the 999M pooled tokens; whole build sessions were
  measured rather than the build-loop phase in isolation, because phase boundaries are not
  marked in transcripts. The verdict was robust across three bases, but it is a small sample.
- **Nothing here speaks to correctness, only to cost and to what is provable.** A valid
  receipt says the named tests were executed over exactly these trees and produced exactly
  this output. It does not say the tests are adequate, that the AC were the right AC, or
  that the change is good.
- **Every state an enforcement system can be in is a state it can get stuck in.** The
  reference implementation's users hit a deadlock formed by three individually defensible
  rules (a corrected candidate holds approval; remediation needs a distinct successor;
  creating a successor needs an invalidated predecessor; invalidation is refused for a
  healthy candidate), a forged authorisation accepted and stored as genuine, and an
  `authority_corrupted` state reachable with the kill switch off. Prefer fewer states.

## Deliberately not decided here

- **The receipt schema itself** — field names, canonical-JSON rules, the strict-parsing
  contract. That belongs in the feature spec (t-2595) where it can be versioned against the
  implementation.
- **Whether `mint` runs at CLOSE, at merge, or both.** Determined by K2's cost reading and
  settled in the spec.
- **What the test command is, per task.** Task configuration, not an architectural decision.

The design constraint governing all three, adopted verbatim from the reference
implementation because it is the failure this system is most likely to repeat:

> "It **must not get in the way**. A system that forces ceremony to change a comma gets
> uninstalled in three days."
