---
status: accepted
---
# ADR-068: v3 Supersession — Retiring the Orbit/Substrate Doc Cluster into the v3 Design

- **Status:** Accepted (2026-08-19 — accepted as lived reality: three docs already treated it as superseded-by; see [the-brana-guide.md](../../ideas/the-brana-guide.md) L0.3 / D1)
- **Date:** 2026-07-24
- **Evidence:** [brana-v3-redesign.md](../../ideas/drained/brana-v3-redesign.md) §"Lessons encoded" (the fold-in list) · wave-1 ground-truth diagnoses t-2395 (scheduler timeout + one dead close-queue entry) and t-2396 (challenger prompt ambiguity, 48 recurring read-fails) · challenge finding "unreconciled prior architecture" ([2026-07-19](../../reviews/brana-v3-challenge-2026-07-19.md) §1)
- **Related:** t-2397 (this ADR) · ADR-059 (substrate selection — retained) · [ADR-060](ADR-060-branch-strategy-autonomous-agents.md) (branch strategy — retained, amendment scoped below) · [ADR-050](ADR-050-loop-request-protocol.md) (blast-radius constants — retained) · ADR-065 / [backlog-v3-schema](../features/backlog-v3-schema.md) (the task contract) · t-2439, t-2444 (wave-1 diagnosis follow-ups)

## Context

The 2026-06 autonomous-runner work produced a three-doc spine — an index and two
capstones — describing brana's autonomous-agent system:

| Doc | Role |
|---|---|
| [the-orbit.md](../the-orbit.md) | Index & reading map; the Substrate / Orbit / ground-control vocabulary |
| [substrate-end-state.md](../substrate-end-state.md) | Orbit capstone — autonomy tiers, staged rollout, safety net, operating surface |
| [substrate-primitives.md](../substrate-primitives.md) | Substrate capstone — primitive set, composed blocks, composition grammar, durability/trust, §2b two-architectures |

[brana-v3-redesign.md](../../ideas/drained/brana-v3-redesign.md) (draft v3.3, adversarially
challenged twice) is now the governing design for the same subject matter. Its wave-1
scope explicitly includes retiring this cluster. The 2026-07-19 challenge named the
unreconciled prior architecture as its first finding: v3 was re-deriving a shipped
sibling design instead of reconciling with it. Leaving both live is the drift.

**The cluster is not being retired for being wrong.** Its engineering rigor — locked
decision tables, tested invariants, explicit interfaces — is the bar v3 adopted after
its own challenge. What failed was the *integration model*, in five specific ways
(v3-redesign §"Lessons encoded"): it was a **sidecar** daily work never fed; its
**learning gate was circular** (graduation needed outcomes that manual whitelisting
never produced); its **autonomy was binary** with no fast-supervised middle; it made
**full worker isolation a precondition**; and its **compute assumptions about agy quota
were naive**.

### What the wave-1 diagnoses actually found

v3's motivation cited two live failures. Both were diagnosed before this ADR was
written (t-2395, t-2396, both completed 2026-07-24), and **neither is what it was
framed as**:

- **The "stalled extraction queue" is two unrelated mundane bugs, not a quota
  deadlock** (t-2395). `knowledge-pipeline-tier1` failed on a **timeout
  misconfiguration** — `scheduler.json` allows 300s for a chained
  `--tier1 && --tier2` command whose two tiers share that one budget; a full pass
  measures ~585s. Zero quota/429/RESOURCE_EXHAUSTED hits. The fix (t-2441) also
  found a second layer t-2395 could not see: the generated systemd unit's
  `TimeoutStartSec` is `(timeoutSeconds+60)*(maxRetries+1)` = 360s, an *outer* kill
  above the runner's own `timeout` — which is what the 360s wall-clock in the logs
  actually was. *(That formula was itself a defect, corrected by t-2611: it omitted
  the `lockWaitSeconds` flock wait, which the runner spends before the job's own
  `timeout` starts. See docs/guide/scheduler.md §Concurrency and locking for the
  current derivation. The t-2441 diagnosis above is unaffected — the 360s reading
  was correct for the formula then in force.)* Separately, the close queue held **one** dead entry at
  `retry_count:3`, labelled `schema-invalid`. That label turned out to be a
  **misclassification** (t-2442): the raw agy output was a Google OAuth
  re-authentication prompt, and on retry `Error: timed out waiting for response` —
  the validator JSON-parses any output and buckets every parse failure as a contract
  violation, so the category cannot distinguish a data error from an infrastructure
  one. The conclusion "not quota" still holds; the category was never evidence for
  it. (The quota category is `quota-exhausted:`; `agy-empty-output` was retired in
  t-2085 per ADR-052.) The other 16 "unprocessed" entries were same-day backlog
  awaiting the nightly run. agy was healthy when tested.
- **The recurring CALIBRATION.md read-fail (×48) is prompt ambiguity, not a stale
  path** (t-2396). Both files exist exactly where they belong: the static severity
  rubric at `system/agents/CALIBRATION.md`, and the CC-native per-run agent memory at
  `~/.claude/agent-memory/brana-challenger/` (sharded index + `calibration_*.md`, by
  design). `challenger.md` describes both concepts adjacently without stating where
  each lives, so the agent conflates them and reads the rubric's name from the memory
  directory — fresh every run.

Four follow-ups from that pass have since landed and sharpen the picture: **t-2439**
(a `--json` ingestion path that bypassed the shared validator), **t-2444** (the
challenger prompt disambiguation that ends the 48 repeated tool-fails), **t-2441**
(the timeout fix, which found the systemd layer above it), and **t-2442** (the queue
reset, which found the error category itself was lying).

**Two of them sharpen the thesis rather than just closing tickets.** t-2442's
miscategorisation and t-2439's validator bypass are the same shape as the integration
failure this ADR describes: a mechanism that *reports* correctness while not actually
checking it. t-2442's entry sat dead for 25 days behind a label that named the wrong
cause, and would have become permanently unrecoverable on 2026-07-29 when a
status-blind 30-day reaper deleted its snapshot (t-2463). Machinery that is never
exercised does not merely stay unproven — it degrades silently, and its own error
surfaces mislead whoever finally looks. That is the strongest available evidence for
v3's principle that verification must live outside the thing it verifies.

**This changes the ADR's framing of the retirement.** The correct claim is *not* "the
prior system failed in production." It is narrower and more damning of the integration
model: **the cluster's machinery was never exercised enough for anyone to know.** The
symptoms that motivated a redesign came from adjacent operational plumbing, and both
sat unnoticed until a task was created specifically to look for them. The
agy-quota-deferral deadlock remains a real **design** concern for wave 2 — agy's quota
is small and does exhaust — but it caused neither observed symptom, and no claim in
this ADR or in v3 should rest on it as evidence.

## Decision

**1. The three docs above are superseded by [brana-v3-redesign.md](../../ideas/drained/brana-v3-redesign.md)** as the
governing design for autonomous operation, its ladder, and its safety model. They are
**retained** as dated design records carrying `Superseded by:` pointers — not deleted,
not rewritten. Where they conflict with v3, v3 wins.

**2. The Substrate / Orbit / ground-control vocabulary is retired from active use.**
v3's vocabulary is the ladder (**L1 report-only → L2 cockpit → L3 unattended**) plus
the cockpit, the outcome ledger, and shapes. Docs still using the old three words are
historical by that fact.

**3. Eight mechanics are carried forward, not discarded.** This is the substance of the
supersession — the cluster's parts that v3 absorbs natively:

| Mechanic | Where it lived | How v3 absorbs it (and what changed) |
|---|---|---|
| **Task contract** | substrate-primitives §2b — "one definition of done (the task's `AC:` lines), two bindings"; default-deny: no `AC:` → not autonomous-eligible | v3 **principle 2**: the task *is* the machine-readable interface — `execution:` marker (default-deny eligibility), `AC:` lines (mechanical verification), `blocked_by`/priority/effort as sequencing *and* shape features. Backbone: [backlog-v3-schema](../features/backlog-v3-schema.md) + ADR-065. **Changed:** the cluster assumed the contract was authored; measurement found 38/2,156 tasks (≈1.8%) carry non-empty `acceptance_criteria`. AC authoring becomes tracked work with cockpit assistance (waves 3–4). |
| **Staged observe→act rollout with a tested observe invariant** | substrate-end-state §"staged trust" — Stage 1 OBSERVE (zero writes) → run-one → run-batch; invariant test suite (t-2150) | v3 **principle 6** + the ladder. **Changed:** split into two tiers, because one zero-write invariant could not express LEARN's actual job. **Tier A (pure observe)** — read + ledger-write only, test proves zero task/git/reminder/memory mutation. **Tier B (scoped mutation)** — writes permitted at L1 only if a test proves them *inert* (gate nothing, no ranking, no auto-apply, until explicit human promotion), generalizing the `ac_state: proposed` real-but-inert pattern (t-2283). |
| **Shape-based rule-table graduation with auto-demotion** | [features/learned-eligibility.md](../features/learned-eligibility.md) — Stage 4, design-only, gated on soak | v3 **principle 5**: graduation applies to **shapes** — (kind, effort, tags, file-surface, AC-presence) — never to individual tasks or whole processes. A transparent, auditable rule table (≥K live runs ∧ ≥95% merged-clean ∧ 0 rejected-as-harmful ∧ never P0), continuously evaluated, **auto-demoting** shapes that start failing. **Changed:** the circular gate is broken — outcomes now fall out of ordinary L2 cockpit review, not from manual whitelisting nobody performed. |
| **Ledger + soak gate** | the runner's `would-run` / `would-park` / `excluded` ledger; Stage 4 "built after soak" | v3 **outcome ledger**: every L2 review writes an explicit verdict row — merged-clean / merged-with-edits / rejected — never a raw approve click. Soak gate: no learning before ≥50 real outcomes / ≥2 weeks. **Changed:** the cluster never checked the gate against real throughput. At solo throughput (≥1 task/day floor) two weeks yields ~14 outcomes *across all shapes*, so shape coarsening (provisional ≤10 shapes) is a precondition for any shape being reachable at all, and wave 5 ships graduation **machinery**, not a graduation date (challenge finding #1, t-2285). |
| **Defer, don't halt** | substrate-end-state §"Completion" — a task hitting a human-only decision is **parked**: high-priority `needs-human` reminder + `PARKED` note, batch moves on | v3 **principle 4**, unchanged in substance and promoted to a design principle: a loop hitting a human-only decision parks a NEEDSHUMAN question (via `brana remind`) and continues with other work. Escalation is a **lane**, not a stop. Wave 4 makes the park lane a first-class cockpit surface; the durable store is ADR-063. |
| **Verification gate stack** | substrate-primitives §2b binding B (`AC:` → validate + build-evaluator) and its security invariant: *the thing that checks the agent must live outside the agent's control* — grader runs from a pinned base-ref copy, never the agent-writable worktree | v3 **wave 3**: an ordered, worker-independent stack — NEEDSHUMAN check → **non-empty diff** → `validate.sh` → AC check (build-evaluator vs the task's `AC:` lines). **Changed:** the empty-diff step is new; a silent no-op passes an AC check and the cluster had no guard for it. **Retained verbatim:** the pinned-base-ref security invariant, and default-deny (no `AC:` lines → routes to a human). `goal-completion.sh`'s guards migrate guard-by-guard (presence interlock, base_ref pin, Modified/Added split, allowlist, audit trail), not by atomic deletion. |
| **Ephemeral-worktree isolation** | ADR-060 invariant #2 + safety-net layer 1 (t-2146); substrate-primitives §3 worktree-persistence gotcha | v3 **principle 3** — *the worktree is the sandbox*: isolation is git-topological (ephemeral worktree per task, explicit base resolution, PR-only output, human merge gate, hooks on every commit). **Changed:** syscall-level sandboxing (t-2173, bwrap capability isolation) is **demoted from HARD precondition to conditional** — it fought the OS (PID-namespace hangs, executor kills, AppArmor blocks) while the git layers did the real protecting. It returns only if v3 ever runs genuinely untrusted code. **Retained gotcha:** a worktree where an agent committed survives the run holding its branch checked out — release explicitly or sweep before re-dispatch. |
| **ADR-050 blast-radius constants** | [ADR-050](ADR-050-loop-request-protocol.md) (consecutive-failure kill, auto-advance cap, self-contained machine-verifiable loop prompts) + substrate-end-state §"Bounds & stop" (`RUNNER_MAX_TASKS` 5, `RUNNER_MAX_FAILS` 3, 600s per-task timeout, kill-switch) | v3 **wave 3**: "blast-radius constants encoded **per loop**" — consecutive-failure kill at 3 · per-task timeout · batch cap · per-loop cost ceiling. **Changed:** generalized from one runner's env-vars to a per-loop property, and extended by principle 7's **hard per-run token ceiling with checkpoint/resume** (replacing skip-and-defer-until-quota-reset). Wave contract: a stop-condition ceiling exists from wave 2's first unattended run. ADR-050 itself is **not** superseded. |

**4. The ADR-060 amendment is scoped here, not written here.** See the next section.

## Scope of the ADR-060 amendment (wave 4/5 deliverable)

ADR-060 Layer-1 invariant #3 reads: *"A human gates promotion to production. The agent
never merges and never marks a task complete."* v3's **L3** rung admits merge without a
human for graduated shapes. v3 states this must be a **formal amendment, not a silent
violation**. This ADR fixes what the amendment must settle; it deliberately settles
none of it, because the rule table's thresholds cannot be authored credibly until
wave 4 produces a real ledger.

The amendment must decide:

1. **Blast radius of the edit.** Only invariant #3 changes. Invariants #1 (never push
   production), #2 (isolated ephemeral worktree off a stable base), and #4 (one branch +
   one worktree per task, failure contained) are untouched and remain unconditional.
   #3 becomes *conditional*: human gate is the default; a narrow per-shape exception
   exists.
2. **The exception's precondition set, and whether it is conjunctive.** Candidates from
   v3's L3 definition: (a) the shape has cleared the rule table on real ledger evidence,
   (b) an objective verifier exists for it, (c) stop conditions are encoded, (d) the
   full verification gate stack is green on the run. Proposed: all four, conjunctive.
3. **Merge target.** The exception should admit an agent merge into the **integration**
   branch only (`dev` for brana) — never production, never a deploy-triggering branch.
   This keeps invariant #1 and the `dev`→`main` ship gate intact, so "L3" still cannot
   deploy. The amendment must say this explicitly rather than leaving "merge" unqualified.
4. **Task completion is a separate lift.** Invariant #3 bans two things. Lifting "never
   merges" without lifting "never marks a task complete" leaves the outcome ledger
   unwritable by the loop that produced the outcome. The amendment must rule on the
   second clause explicitly rather than letting it ride on the first.
5. **Revocation semantics.** Auto-demotion (principle 5) must be able to withdraw a
   shape's exception. The amendment must state what happens to in-flight L3 runs when
   their shape demotes mid-run, and whether demotion is immediate or takes effect at the
   next dispatch.
6. **Portability.** ADR-060's Layer 1 is *universal* — it binds clients/, ventures/, and
   personal/ repos too, most of which will never have a ledger. The amendment must state
   whether the L3 exception is brana-only or per-project opt-in. Proposed default:
   brana-only, until a second repo has its own ledger and rule table.
7. **Recording form.** Repo precedent exists both ways — ADR-060 was itself amended in
   place (2026-06-20, after challenger review), while [32-lifecycle.md](../../reflections/32-lifecycle.md)
   holds that a choice which must be cited or superseded on its own belongs in its own
   ADR. Reversing a universal invariant is the second kind. Proposed: a new ADR that
   supersedes ADR-060 §Layer 1 item 3, with a pointer added to ADR-060.
8. **Timing.** The amendment gates the *first L3 run*, not wave 1. It must be Accepted
   before that run and cannot be written honestly before wave 4's ledger exists.
   It is therefore a wave-4/5 deliverable, tracked as its own task.

## Consequences

- **No link rot.** The three docs stay at their paths; all 26 inbound references across
  11 files (ADR-061, `features/consensus-primitive.md`, `features/learned-eligibility.md`,
  `docs/ideas/drained/orbit-evidence-first.md`, `docs/README.md`, and the cluster's own
  cross-links) continue to resolve. Readers arriving via those links hit the
  `Superseded by:` pointer first.
- **`docs/README.md` marks all three rows superseded** and indexes this ADR.
- **The cluster's peripheral docs are not retired by this ADR** and remain live design
  records: `features/autonomous-runner.md`, `features/learned-eligibility.md`,
  `features/consensus-primitive.md`, `workflow-primitive.md`,
  `research/substrate-leverage-audit.md`. Several of them describe machinery v3 absorbs
  (notably learned-eligibility → principle 5) and will need their own reconciliation
  when their waves come up — v3's own second-order note says every idea doc gets re-read
  against the spec. That is not this ADR's job.
- **`autonomous-runner.sh` and the `brana orbit` CLI surface are unaffected.** This ADR
  retires documents, not code. What happens to the runner is decided by waves 2–4 as
  they build the ladder's rungs.
- **The wave-1 diagnoses are now the citable ground truth** for what did and did not
  fail. Any future doc repeating "the extraction queue stalled on agy quota" is drift
  against t-2395.
- **Wave 1's remaining items are separate tasks** and are untouched here:
  re-parenting/cancelling t-1994/t-1995, and the native `memory:` frontmatter
  migration for challenger/build-evaluator/debrief-analyst. (The ADR-062 filename
  collision — t-2398 — was resolved out of band on 2026-07-28 under t-2507, which
  cleared all four duplicate ADR numbers at once; the step-state contract is now
  ADR-074 and ADR-062 unambiguously means the runner/executor sandbox.)

## Non-actions (explicitly out of scope)

- **Does not delete or rewrite any doc.** Supersession pointers only.
- **Does not supersede ADR-059, ADR-060, or ADR-050.** All three are retained; ADR-060
  gets a scoped future amendment, which is not the same as retirement.
- **Does not amend ADR-060.** It scopes the amendment; the amendment is a later ADR.
- **Does not fix anything the wave-1 diagnoses found.** The scheduler timeout (t-2441),
  the dead close-queue entry (t-2442), and the challenger prompt ambiguity (t-2444) are
  their own tasks, all completed 2026-07-24, alongside t-2439 and the follow-ups
  t-2462/t-2463 that the close-queue dig surfaced.
- **Does not decide the fate of the runner implementation** or of Stage 4 learned
  eligibility as code.

## Open questions

1. **Is `the-orbit.md`'s index role replaced, or just vacated?** It was the front door
   for the cluster. v3 has no equivalent index doc yet; `brana-v3-redesign.md` is a
   design, not a reading map. Whether v3 needs a front door is a wave-5 (core/packs cut)
   question.
   **Resolved 2026-08-19:** replaced by [`docs/architecture/the-brana.md`](../the-brana.md)
   (front door; `the-orbit.md` stays as a superseded pointer-only index, the model for
   the-brana.md's own reading map).
2. **Do the retired capstones' *unabsorbed* parts survive anywhere?** substrate-primitives
   §1–§3 (the primitive set, the composed-block library, the Workflow durability/trust
   notes, the cost gate) are reference material that v3 uses but does not restate. If
   they matter operationally, they should be extracted into a live reference doc rather
   than read out of a superseded one.
   **Routed 2026-08-19, not yet closed:** lands as the-brana.md's Space-chapter primitive
   table — tracked as [the-brana-guide.md](../../ideas/the-brana-guide.md) L2.1.
3. **What ends "v3 is draft"?** `brana-v3-redesign.md` is still `status: draft` while
   this ADR treats it as governing. Challenge finding #5 ("what does v3-done mean")
   remains open at the epic level.

## Alternatives considered

- **Delete the three docs.** Rejected — 26 inbound references, and the repo's
  convention throughout `docs/` is pointer-not-delete (`memory-taxonomy-sdd.md`,
  `08-diagnosis.md`, ADR-022). The failure record is also the evidence base for v3's
  own principles; deleting it would leave "Lessons encoded" citing nothing.
- **Rewrite the three docs into v3 vocabulary in place.** Rejected — they are dated
  design records. Rewriting destroys the before/after that makes the five failure modes
  legible.
- **Write the ADR-060 amendment inside this ADR.** Rejected — the rule table's
  thresholds (K, the shape set, the merged-clean rate) do not exist until wave 4 ships a
  ledger. An amendment authored now would encode guesses into a universal invariant.
- **Fold the mechanics into a new spec doc instead of an ADR.** Rejected — supersession
  is a decision that must be citable and itself supersedable; per 32-lifecycle.md that
  is an ADR, not a spec.
- **Retire the whole cluster including the feature specs.** Rejected as
  over-reach for wave 1 — the feature specs describe machinery waves 2–4 still have to
  reconcile against, and retiring them now would remove the specs before their
  replacements exist.
