---
title: Enforced Delegation — orchestrator/executor split for build phases
status: draft
created: 2026-08-01
---
# Enforced Delegation — orchestrator/executor split for build phases

> Brainstormed 2026-08-01. Status: draft — shaped, challenged (2 rounds + pre-mortem),
> capabilities verified against CC docs, then **descoped by adversarial review**.
>
> **Superseded as a plan by [gentle-ai-adoption-ladder.md](gentle-ai-adoption-ladder.md)** —
> the review killed the enforcement layer, not orchestration; the ladder is the corrected,
> incremental approach. This doc remains the full record of the design and why it failed.

## Problem

thebrana defines 13 agents and 19 skills mention delegation, but no skill enforces it.
Delegation is advisory (work-preferences, context-budget ">85% → delegate"), so skill
phases run inline in the main context; context-budget rules then manage the pollution as
a symptom. gentle-ai proves the structural alternative: orchestrator gates on every SDD
phase skill (`delegate_only: true`, "you are the ORCHESTRATOR — STOP"), content-bound
reviewer briefs, authority in git rather than in the agent.

Source study: gentle-ai vs ruflo comparison, 2026-08-01
(memory: project_gentle-ai-ruflo-comparison-adoption-candidates; artifact 7195f454).

## Direction decided so far

- **Scope:** pilot on `/brana:build` phases only (specify, build-loop, verify-gates).
- **Enforcement:** hard — `role: executor` / `delegate_only` frontmatter + a PreToolUse
  hook that blocks implementation-tool calls when an executor skill runs in the main context.
- **Executor compute:** all-background within the pilot — `claude -p` in its own worktree
  (ADR-060 runner model). Build-phase work is substantive by definition; in-session agents
  keep their existing read-only roles (review/research/challenge). Mixed routing deferred
  until gates extend beyond build.
- **Authority:** git + receipts, never a runtime of our own (gentle-ai's philosophy on
  native Claude Code compute). Pairs with the RDD-style build receipt adoption candidate.
- **Success metrics:** context health (main stays out of orange zone through a build),
  scope correctness (content-bound briefs + receipts), throughput (parallel phases),
  simplicity guard (no orchestration theater — the ruflo lesson).

## ruflo compatibility check

ruflo has analogous pieces (claims board, worker-dispatch hooks, loop-workers, swarm) —
independent evidence the orchestrator/executor split is a real need — but they are the
execution layer verified hollow under subscription (ADR-059). Zero runtime dependency;
ruflo stays at the memory layer. Claims-style collision semantics can be reimplemented
over tasks.json in ~50 lines if concurrent executors ever collide.

## Gate mechanism (decided, round 1)

The naive design ("hook detects executor skill running in main context") is unenforceable —
hooks fire identically for main and subagent tool calls; CC has no role concept. Dissolution,
using only individually-enforceable native pieces:

1. Executor procedures carry `disable-model-invocation: true` → the Skill tool cannot load
   them in ANY context. The door only opens from outside.
2. Background executors receive the procedure as a **file path in the brief** and Read it —
   no Skill invocation needed.
3. The orchestrator writes run-state ("phase X delegated, awaiting receipt"); a PreToolUse
   hook blocks Edit/Write to implementation paths in the main context while that state holds.
4. Frontmatter `role: executor` is the classification marker; the binding brief
   (task ID + tree OID + phase + AC digest) pins executor scope.

## Verified capabilities (CC docs, 2026-08-01)

1. `disable-model-invocation: true` — real; blocks model invocation in all contexts and
   subagent preloading; user /slash still works (acceptable operator override); description
   excluded from context. Source: code.claude.com/docs/en/skills.md.
2. Headless relay — `claude -p` cannot pause mid-run (no awaiting-input event). **Redesign:**
   executor ends its run with a structured `blocked:{question}` JSON result → orchestrator
   relays → `claude -p --resume <session-id>` with the answer, run from the same worktree
   (session lookup is directory-scoped). Terminate-and-resume beats pausing: no zombie
   processes. Source: code.claude.com/docs/en/headless.md.
3. Hooks — fire for subagent calls too; input carries `agent_id` ONLY on subagent calls
   (native main-vs-subagent discriminator); `if` supports path matching (`Write(src/**)`).
   delegation-write-gate = block impl writes when run-state active AND no agent_id.
   Source: code.claude.com/docs/en/hooks.md.

## Risks

Top pre-mortem risks (both flagged by user):

1. **Friction → abandonment.** Spawn latency + receipt ceremony make gated builds feel heavy;
   "skip the workflow" becomes habit; the layer dies by disuse. Mitigations: async handoff
   (orchestrator returns immediately, executor works in background); an `--inline` escape
   hatch that logs its own use (abandonment becomes measurable); receipts make the known
   subagent silent-finish failure loud instead of invisible.
2. **Wrong diagnosis.** Context pollution may come mostly from research/MCP/web noise, not
   inline phase execution. Mitigation: step zero of the pilot = instrument one week of builds
   via transcript cost data (pattern_cc-transcript-has-cost-data) before building anything;
   re-scope if inline execution isn't a top-2 consumer.
3. **Kill criterion (falsifier):** context %% at build CLOSE, budget interventions per build,
   wall-clock on multi-phase tasks. If unchanged after N pilot builds, the layer is removed —
   receipts stay regardless (independently valuable).

## Challenge outcomes

- Round 1: naive hook-based role detection unenforceable → dissolved into
  disable-model-invocation + file-path procedure delivery + run-state write-block (see Gate mechanism).
- Round 2 (devil's advocate, receipt-only-first): defended — the drift is model drift, not
  operator indiscipline; rules are advisory to the model; receipts don't parallelize.
  Falsifiability requirement added.

## Async-build UX (decided)

Key discovery: `claude -p` executors are non-interactive — an executor cannot ask the user
anything mid-phase. This forces (and improves) the design:

- **Questions — hybrid model:** SPECIFY becomes a front-loaded interview: orchestrator +
  user settle every ambiguity before dispatch (mechanizes the spec-assumptions rule).
  Fallback: executor hits the unforeseen → writes `needs-input` run-state + pauses →
  orchestrator relays the question → resumes with the answer.
- **Visibility — both:** silent event notifications (phase-complete / receipt / needs-input /
  failure) + on-demand status via `brana ops status` executor rows.
- **Merge — ask during pilot, auto later:** orchestrator presents receipt summary + diff stat
  for approval; flips to auto-merge-on-valid-receipt after N clean receipts.
- **Control-tower effect:** main session stays free; 2–3 executors in parallel worktrees is
  where the throughput metric materializes.

## Shape — proposed architecture

**New structures**
- `system/skills/_shared/orchestrator-gate.md` — shared procedure: role check, brief
  composition, run-state write, dispatch.
- **Binding brief** `BRANA_EXEC_BINDING {json}`: task_id, base_tree OID, phase, ac_digest,
  procedure_path, worktree path. Executor prompt MUST begin with it (gentle-ai's
  reviewer-binding pattern).
- **Build receipt** `brana.build-receipt/v1` (JSON): task_id, phase, base_tree,
  candidate_tree, test_evidence_hash, ac_digest, terminal_state. Minted by executor at
  phase end; validated by orchestrator against git before merge. Pilot storage:
  `~/.claude/run-state/receipts/`.
- **Frontmatter convention:** `role: orchestrator|executor`; executor procedures carry
  `disable-model-invocation: true` (unloadable via Skill in any context; delivered to
  executors as file paths).
- **Run-state** `~/.claude/run-state/delegation/{task}.json`: phase, status
  (running|needs-input|receipt-ready|failed), question payload for relay.

**New/changed components**
- `/brana:build`: specify/build-loop/verify-gates become orchestrator-side routers; executor
  procedures split into `system/skills/build/executors/*.md` (delegate-only).
- `brana receipt mint|validate` CLI subcommand (Rust — testable, fast, and the validation
  logic lives outside the model).
- Hook `delegation-write-gate.sh` (PreToolUse): blocks Edit/Write to implementation paths in
  the main context while a delegation run-state is active.
- `brana ops status`: executor state rows (embed in existing command per
  automation-through-usage rule — no new standalone command).
- No new agent file needed for the pilot: the executor is `claude -p` + brief template
  (`_shared/executor-brief.md`). In-session agents keep existing read-only roles.

**Flow:** INTERVIEW (orchestrator+user → ambiguity-free brief) → DISPATCH (worktree +
`claude -p`) → MONITOR (events + status) → RECEIPT-VALIDATE → MERGE (ask → auto) → CLOSE
(evaluator grades quality; receipt archived; task completed).

**Phased rollout**
- **Phase 0 — measure:** 1 week of transcript cost data → where does context actually go.
  Falsifier baseline. (pattern_cc-transcript-has-cost-data)
- **Phase 1 — receipt primitive:** `brana receipt` + mint/validate in build CLOSE, still
  inline. Independent value regardless of delegation's fate.
- **Phase 2 — one gate:** build-loop phase delegated to background executor; hybrid
  questions; both visibility modes; ask-to-merge.
- **Phase 3 — full pilot:** specify + verify-gates gated; kill-criterion review; auto-merge
  flip decision.

## Second-order effects

- Gating build-loop → main context free → 2–3 executors run in parallel → **the bottleneck
  moves to merge/tasks.json contention on dev** — the documented concurrent-session race
  (t-2216/t-2206) returns at higher frequency. Mitigation: orchestrator serializes merges;
  the ~50-line claims-lite over tasks.json likely lands sooner than expected. (Risk, planned for.)
- Receipts gate merges → build-evaluator's role shifts from gatekeeper to quality
  commentary → **asymmetric value: receipts survive even if delegation is killed by the
  falsifier** — Phase 1 is a no-regret move. (Opportunity.)

## Adversarial review outcome (2026-08-01) — design descoped

3-lens hive-mind challenge; 2 of 3 workers completed before a spend-limit abort (verify pass
never ran — findings are worker-level, but the checkable ones were verified by hand against
the repo). Both workers converged independently on the same structural verdict.

**HIGH (both workers, verified):**

1. **The gate is not armed at the drift point.** `delegation-write-gate.sh` fires only while
   run-state exists, and run-state is written voluntarily by the same model whose drift is the
   diagnosed problem. Skipping the flow entirely — today's actual failure mode — arms nothing.
   Enforcement is hard only *inside* a flow whose entry is exactly as advisory as the rules it
   replaces (`always-use-build-framework` already exists and is already skipped).
2. **Bash bypasses the hook.** PreToolUse Edit/Write matchers don't intercept `cat >`, `sed -i`,
   or a python script — and `context-budget.md:18` actively recommends `/tmp/bulk-edit.py` for
   5+ edits. The bypass sits on a recommended path. VERIFIED.
3. **`disable-model-invocation` blocks only the Skill tool.** Procedure files stay Readable and
   followable inline — and the model doesn't need them to build inline anyway; it does that
   today with no procedure at all.
4. **The receipt is self-attestation, not evidence.** `test_evidence_hash` is minted by the
   executor model; `validate` can only confirm git-derivable facts (tree OIDs, digests) unless
   `brana receipt mint` *executes the test command itself*. As specified it is a signed claim.
5. **Quota is the scarce resource, not main-session context.** 2–3 parallel full-model
   `claude -p` executors each cold-load repo context and consume the same subscription window
   (delegation-routing exempts only haiku), so parallelism partitions quota rather than adding
   compute — the exact "hollow under subscription" failure ADR-059 documented for ruflo,
   reappearing in its replacement. The kill criterion measures context %, interventions, and
   wall-clock — never quota — so the design could pass its own falsifier while making the
   system more expensive.

**Design bug (single worker, verified — I got this wrong):** background `claude -p` executors
are top-level CC subprocesses, *not* in-session subagents (ADR-060:74 confirms the runner is a
`claude -p` subprocess). Their tool calls carry **no `agent_id`**. So "block when run-state
active AND no agent_id" blocks the executors themselves — deadlock — or needs an env-var
discriminator that the constrained model can set itself, reopening the advisory hole.

**Also raised (single worker, plausible):**
- *Information conservation:* an ambiguity-free brief costs roughly the understanding-half of
  the work; delegation exports only iteration churn. Phase 0 as specified measures cost
  per phase and cannot detect this — it must split understanding-tokens vs churn-tokens
  *within* build-loop or the falsifier fires on the wrong variable.
- *Stale run-state is a new deadlock class:* crashed executor or laptop sleep leaves status
  `running` with no TTL or reconciliation, locking main-session writes; the path is user-global
  so it can false-block unrelated projects.
- *No merge gate exists to hang receipts on:* ADR-060:68 — `dev`→`main` has "no automated gate
  beyond local pre-commit hooks; enforcement is deferred, not active." VERIFIED.
- *The falsifier is anchored:* Phase 0 was sequenced after a fully shaped four-phase
  architecture; N unspecified; sunk cost makes an honest kill implausible.
- *Relay needs an attended session:* main sessions compact and close, leaving a stranded
  executor's `blocked:{question}` with no delivery path — reintroducing the resource the
  design exists to free.

### Revised position

**Descope to Phase 0 + Phase 1. Do not build the delegation layer yet.** Both workers reached
this independently, and the verified findings support it: the enforcement story doesn't survive
contact (gate unarmed at the drift point, Bash bypass, no agent_id for subprocesses), and the
economic premise is unproven (quota, not context, may be the binding constraint).

What survives and is worth building now:
- **Phase 0 — measurement, redesigned:** split understanding-tokens vs churn-tokens *within*
  build-loop, and measure **quota burn** alongside context %. Both were missing.
- **Phase 1 — receipts, redesigned:** `brana receipt mint` must **run the test command and hash
  its real output**, not hash a model's claim. That makes it evidence. Independent value
  regardless of delegation's fate — and per ADR-060 it needs a real pre-merge hook to hang on,
  which is its own small task.

Delegation returns only if Phase 0 shows churn-tokens dominate *and* quota is slack — with an
honest, pre-registered N and kill criterion written before any further code.

## Engineering disciplines

- **DDD:** ADR "Enforced delegation — orchestrator/executor split" + receipt-format decision.
  M+ effort → feature spec required at `docs/architecture/features/enforced-delegation.md`
  before system/ writes (spec-gate).
- **TDD:** Rust tests for `brana receipt mint|validate`; hook tests for
  delegation-write-gate.sh; brief-composer golden tests.
- **SDD:** update build skill docs, delegation-routing.md, branching doc, ADR-060 addendum.
- **Docs:** tech doc (features/enforced-delegation.md), guide updates for build flow.

## Next steps (post-review, descoped)

1. **Phase 0 — instrument builds** (no code): churn-vs-understanding token split within
   build-loop + quota burn. Pre-register N and the kill criterion before anything else.
2. **ADR** — "Build receipts as evidence" (narrow), recording the descope and why the
   delegation layer was deferred.
3. **Phase 1 — `brana receipt mint|validate`** (TDD, Rust): mint EXECUTES the test command and
   hashes real output; validate checks tree OIDs + digests + evidence.
4. **Pre-merge hook** to hang receipt validation on (ADR-060: no gate exists today).
5. Delegation layer: **deferred** pending Phase 0 evidence.

## Backlog

- `t-2591` — Phase 0 instrumentation (churn-vs-understanding split + quota burn)
- `t-2592` — ADR: receipts as evidence + delegation deferral (DDD)
- `t-2595` — feature spec + docs (SDD, gates implementation)
- `t-2593` — `brana receipt mint|validate` (TDD, blocked by t-2592 + t-2595)
- `t-2594` — pre-merge hook enforcing receipt validation (blocked by t-2593)
