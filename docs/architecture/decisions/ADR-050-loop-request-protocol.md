---
depends_on:
  - docs/architecture/decisions/ADR-027-auto-learning-loop.md
  - docs/ideas/cc-feature-adoption-v2.1.76-81.md
informs:
  - docs/ideas/session-aware-loop-integration.md
status: accepted
---

# ADR-050: Loop-Request Protocol — Suggest-and-Confirm, No Auto-Spawn

**Date:** 2026-06-10
**Status:** Accepted (2026-06-11)
**Tasks:** t-730 (design), t-731 (implementation — re-scoped by this ADR), t-1930 (tests), t-517 (non-advancement conditions)
**Source:** Revival review of cancelled initiative t-719; challenger review 2026-06-09 (verdict: RECONSIDER → design-first)

## Context

Initiative t-719 ("Session-Aware Loop Integration", 2026-03-30) proposed three layers: session-persistent loop config, a `/brana:watch` skill, and skill-embedded watchers (`/brana:build` auto-starts a test watcher, review auto-starts a drift watcher). It was cancelled 2026-04-04 as "superseded by ADR-027/028" — but ADR-027 covers only the knowledge-capture loop. The runtime-watcher scope was dropped, not absorbed. Its child tasks survived as pending zombies until 2026-06-09.

Phase 3 was deferred on a platform constraint: "CronCreate is main-context only — skills can't invoke it" (CC v2.1.87). **That constraint is now empirically dissolved:** skill procedures execute in main context, where CronCreate is available. Verified 2026-06-09 — cron job `20a4a021` created and deleted from within a `brana:backlog` skill flow. CronCreate has also gained `durable: true` (survives session restarts), and a native `/loop` skill with `ScheduleWakeup` self-pacing now exists.

So the question is no longer *can* skills spawn loops — they can — but *should* they do so automatically.

## Decision

**NO-GO on auto-spawned watchers. GO on a minimal suggest-and-confirm protocol.**

Skills never spawn loops silently. At defined moments, a skill procedure MAY suggest a loop; the user confirms via one question or the suggestion is dropped. No new infrastructure — the native `/loop`, `CronCreate`, and `Monitor` primitives are the only mechanisms.

### Evidence for NO-GO on auto-spawn

1. **Cache economics.** The prompt cache TTL is 5 minutes. Any watcher interval >5 min forces a full-context cache miss per fire. A 15-minute test watcher across a 3-hour build session = 12 uncached full-context reads — paying repeatedly for signal the build loop already produces.
2. **Redundancy with the TDD loop.** `/brana:build` BUILD step 3f runs tests per subtask; the BUILD→CLOSE gate runs `validate.sh`. An interval test-poller adds no information between those points.
3. **Prior deliberate decision.** `docs/ideas/cc-feature-adoption-v2.1.76-81.md` already ruled: "Session cron forgotten mid-session → Don't automate — user-initiated only." This ADR upholds that ruling and gives it an ADR home.
4. **ADR-027 ratchet.** "No evidence = no expansion." The Phase A gate metric (doc-update rate >50%) has no recorded measurement. Adding a new automation tier before the existing one is measured inverts the priority stack.
5. **Wrong tool shape.** CronCreate's own guidance: live watching belongs to `Monitor` (event-streamed), not cron (wall-clock polling). Test-watching is event-shaped.
6. **LoopTrap surface.** Recurring self-prompts widen the loop-termination-poisoning surface (arxiv 2605.05846: P5 sunk-cost, P7 recursive decomposition). Fewer autonomous loops = smaller attack surface.

### The protocol (what t-731 implements)

A skill procedure may include a **loop suggestion** step, constrained as follows:

| Rule | Specification |
|---|---|
| **Suggestion moments** | Only at strategy-defined points: BUILD start (long builds, effort L/XL only), CLOSE of a multi-session task. Max one suggestion per skill invocation. |
| **Form** | One AskUserQuestion or inline mention. Decline = drop silently, never re-ask in the same session. |
| **Mechanism choice** | Event-shaped need (watch file/process/output) → `Monitor` or background Bash. Time-shaped hygiene (uncommitted-changes nag) → `CronCreate`, interval ≥20 min (past cache TTL, amortized) or ≤4 min (within TTL) — never 5–19 min (worst-of-both per ScheduleWakeup economics). |
| **Durability** | `durable: false` always. Session-scoped loops die with the session — no cross-session zombies. `durable: true` requires explicit user request, never a skill suggestion. The factory foreman ([loop-native redesign](../../research/2026-06-11-loop-native-redesign.md)) falls under this rule: per-session, with cross-session continuity via a SessionStart suggestion when agent-ready tasks exist — not via `durable: true`. A durable foreman remains possible later through the explicit-request exception; nothing is built for it until supervised runs produce evidence. |
| **Lifecycle contract** | Spawn: only post-confirmation. Kill: (a) the suggesting skill's CLOSE/REPORT step runs `CronList` and deletes loops it spawned; (b) `/brana:close` sweeps any remaining session loops (one procedure line); (c) session end kills non-durable loops by construction. Branch switch: loops are not branch-aware in v1 — the close-step sweep is the backstop. |
| **Prompt content** | Loop prompts must be self-contained and reference machine-verifiable checks (`validate.sh`, `git status --porcelain`, test exit codes) — never "assess whether progress is being made" (LoopTrap defense). |

### t-517 non-advancement conditions (designed here, as required by its deferral)

Auto-advance of the step registry (TaskCompleted → start next step) may fire ONLY when all hold:

1. The completed step wrote its run-state checkpoint (machine-verifiable, not self-asserted).
2. The next step is **not** a gate step — CLASSIFY, APPROVE, any step containing an AskUserQuestion gate, and all SKIP-with-reason gates always require main-context initiation. Auto-advance never crosses a human gate.
3. A hard cap: max 3 consecutive auto-advances without a human touchpoint; the 4th transition requires user confirmation.
4. `validate.sh` (or the strategy's equivalent machine signal) passed at the most recent gate.

t-517 remains deferred until someone wants to implement it; these conditions remove the challenger's stated blocker.

## Consequences

- t-731 re-scopes from "wire auto-spawn" to "add suggest-and-confirm lines to build/close procedures + the close-step loop sweep." Effort drops M → S.
- t-1930 (tests) scopes to: validate the procedure lines exist, the close sweep runs `CronList`/`CronDelete`, and suggestion constraints (one per invocation) are stated in procedures.
- `docs/ideas/cc-feature-adoption-v2.1.76-81.md` needs an errata line: the "skills can't invoke CronCreate" claim is obsolete (constraint dissolved, verified 2026-06-09); its "don't automate" ruling is superseded by this ADR's protocol.
- t-705 (loop provider): no dependency taken. Disposition deferred to t-703 (provider abstraction, P2) — not obsoleted, not required.

## Non-Actions

- **No watch dashboard** (was t-729). `CronList` suffices for v1; revisit only if loop volume grows.
- **No session-persistent loop config** (was t-724–726, `session-loops.json`). Native `/loop` + durable CronCreate cover the rare cross-session case on explicit user request.
- **No `/brana:watch` skill** (was t-727–728). The native `/loop` skill is the user-facing entry point.
- **No auto-spawned test watcher during BUILD.** Redundant with the TDD loop (evidence point 2).
- **No drift watcher in `/brana:review`.** Drift detection is `/brana:reconcile`'s job in the current taxonomy; the original idea predates that split. A reconcile suggestion at CLOSE of long sessions is the surviving form.

## Surfaces (for t-731)

- `system/procedures/build.md` — BUILD-start suggestion point (L/XL only), step registry non-advancement conditions reference
- `system/procedures/close.md` — session loop sweep line
- `docs/ideas/cc-feature-adoption-v2.1.76-81.md` — errata line
- `docs/ideas/session-aware-loop-integration.md` — supersession pointer update (→ this ADR for the watcher scope)
