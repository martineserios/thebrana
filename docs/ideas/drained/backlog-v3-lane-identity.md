---
title: Lane identity and the unbuilt axes of backlog v3
status: idea
created: 2026-07-28
task: t-2488
---

# Lane identity and the unbuilt axes of backlog v3

> **Component of The Brana** · owns: lane identity, unbuilt v3 axes · see [the-brana.md](../../architecture/the-brana.md) §Cycle

> Brainstormed 2026-07-28 from t-2488, seeded by a t-2502 build that halted at DIAGNOSE.
> Status: idea — no ADR written yet, no implementation started.

## Problem

Two findings, arrived at from opposite directions in one session.

### Finding A — v3 has no *lane* identity, and `epic` is being used as one

[ADR-065](../architecture/decisions/ADR-065-epic-as-hierarchy-top.md) defines an epic as
*"what we're building, empty = feature done"* — a **deliverable**. Session handoff state is
keyed by epic. But a lane is an **execution context**: which worktree, which branch, which
session. Keying handoffs by epic uses a *what* as a *where*, so two parallel sessions
building toward one deliverable are the same key **by construction**.

This is a category error in the choice of key, not a bug in the keying logic.

**Evidence (live, thebrana, 2026-07-28):**

- All 24 `session-state*.json` files return `has_session_id: false`. The store carries no
  session identity at all.
- Three files already claim `epic: "harness-core"` (`harness-core`, `async-close`,
  `thinking`) — filename slug and inner `epic` field have drifted apart.
- The default `session-state.json` was written `16:55:03Z`, *after* the `close` epic file at
  `16:02:23` — so the global-max close anchor resolved to a different session's state while
  this very session was running.
- `BRANA_SESSION_ID` **is** present in the environment and is never persisted anywhere.
  There is no SessionStart hook capturing HEAD; the only HEAD pin is `active-goal.json`'s
  `base_ref`, gated on the task having acceptance criteria, so it is not a general anchor.

### Finding B — v3 designs three orthogonal axes; only one was built, and it grew

The [v3 schema spec](../architecture/features/backlog-v3-schema.md) separates three axes:

| Axis | Designed | Built (measured 2026-07-28) |
|---|---|---|
| **WHAT** — epic → [milestone → phase] → task → subtask | ~10 curated epics | **54 epics**, 50 `next` / 4 `active`, 46 created in one batch on 2026-07-23, all P3, no tags, no parent |
| **CROSS-CUTS** — key:value tags (`client:`, `risk:`, `theme:`) | net-new (D8) | **not built** — flat string tags only |
| **HOW** — waves = drainable queues (`{selector · contract · gate · status}`) | the process overlay | **0 instances** — primitive exists, nothing populates it |

The spec's own stated problem was *"43 epics — the human gets lost."* **Today there are 54.**
The migration promoted every flat epic string into a node; wave 1 — the cleanup that was
supposed to collapse 43 → ~10 — never ran.

So the operator navigates a three-axis system with one axis populated and overgrown, no
cross-cutting index to slice it by, and no queue to drain it through. **The felt confusion is
a build gap, not a comprehension gap.**

Compounding measurements:

- Epic nodes are absent from `brana backlog query --json` (2154 rows, 0 epics) and from
  `roadmap --json`. `brana backlog query --type epic` **does** work (returns 54) — the
  backlog skill's claim that it errors is stale and should be corrected.
- MCP `backlog_query`, `backlog_stats`, and `backlog_set` all timed out at >120s while the
  CLI stayed fast. The MCP path is currently unusable for these verbs.
- `in-001`..`in-004` carry sentence subjects, not slugs — the t-2263 failure class, live.
- AC coverage 38/2156 ≈ 1.8% (spec measurement, 2026-07-20).
- WIP is advisory-only (D4). The promotion-to-hard-block review was targeted at
  **2026-07-28 — today** — alongside the spec-gate pilot.

## The symptom cluster, correctly split

An earlier framing in this session claimed "one missing primitive, five symptoms." That was
too neat and is **corrected here**: there are two distinct failure modes requiring two
distinct fixes.

**Cluster 1 — Identity** (*whose state is this?*)

- `t-2502` — close window anchors on another lane's timestamp. Three reproductions. Worst
  case: a **zero-commit window** that gate Step 1 misreads as a read-only session and skips
  the snapshot entirely, losing a whole session to the nightly async extraction.
- `t-2506` — same-day second close cannot update its own `next[]`.
- Sitrep ambiguity — opening a new session, you cannot tell whether the handoff is this
  lane's or a parallel lane's.

Fix shape: key session state by **lane**, captured at session **start**.

**Cluster 2 — Atomicity / isolation** (*did I read a complete version?*)

- `t-2495` — transient invalid JSON from `backlog query --json`. **Mechanism is OPEN.** A
  torn-read hypothesis was raised and then *refuted* for brana's own write path:
  `save_tasks` uses `write_atomic` (same-dir temp + rename) and `lock_tasks` holds an
  exclusive `flock` sidecar across the whole read-modify-write (t-2166). Surviving suspects
  are the non-Rust writers that bypass both — `close-classify.sh` and seven
  `system/scripts/migrate/*.py`.
- Epic auto-detection failing to converge under concurrency (field note, 2026-07-24,
  observed but never root-caused).

Fix shape: audit non-Rust writers for lock + atomic discipline. Independent of Cluster 1.

**Perfect identity still yields torn reads; atomic writes still leave you unable to tell
whose handoff you are reading.** Do not merge these clusters.

## The primitive already exists in the backlog

`task → task.branch → worktree → session` is already 1:1, enforced by git-discipline's
worktree HARD RULE. `backlog start` already writes `task.branch` and already claims the lane
by branch (`claims_claim` claimant `agent:{branch}:session`). **The session store simply does
not reference it.**

Constraint: the key must be captured at session **start**, not read at close — 15 of 24 state
files record `branch: "dev"` because closes happen after merge, so branch collapses at close
time.

## Separate concern — range vs set

A contiguous git range `A..B` cannot express a non-contiguous commit set. Sessions interleave
on `dev`, so even a *correct* lane-scoped anchor leaves a concurrent lane's commits inside the
range — measured: an 11-commit window holding 2 own commits. Eliminating that needs per-commit
recording plus a `--commits LIST` interface into `close-snapshot.sh`, which today accepts only
`--git-range`. **Decide explicitly whether this is in or out of scope.**

## Requirement added by the operator (2026-07-28)

v3's structure must serve four consumers, and stay cheap in context:

1. **the loop** — autonomous drain needs a verifiable contract per task
2. **the graph / workflow layer** — `.claude/workflows/` fan-out, barriers, judges
3. **close** — needs to know what this lane did
4. **sitrep** — needs to say which lane you are in and what it left

A design that fixes close but leaves sitrep ambiguous, or that fixes both but costs context on
every session start, has not solved the problem. **Context economy is a constraint, not a
nice-to-have** (epic `t-2483`).

## Risks

- **Migration risk.** 24 existing state files carry no session identity. Any keying change
  needs a defined read path for legacy entries or handoffs silently vanish.
- **The cleanup is the hard part, not the schema.** ADR-065 shipped a correct data model and
  the felt problem got *worse* (43 → 54) because wave 1 never ran. A second ADR that also
  ships schema without cleanup repeats the failure. **Any decision here must name who drains
  the 54 epics and when.**
- **Scope sprawl.** t-2488 has been deferred three times. Two findings, two clusters, plus the
  loop/graph/context requirements is already large. Splitting into separately shippable
  decisions matters more than completeness.

## Next steps

1. Validate the handoff empirically: close this session, clear context, run `/brana:sitrep`,
   and record whether it can identify which lane the handoff came from. **This is a
   reproduction, not a formality.**
2. Premortem, then ADR — per `pattern_brainstorm-premortem-before-adr`.
3. `/brana:challenge --deep` on the resulting shape.
4. Decompose with all four disciplines (M+ rule): ADR task blocking implementation, test tasks
   before impl tasks, spec-update tasks, docs tasks.
5. Children to re-parent once the ADR lands: `t-2502`, `t-2506`, `t-2495`, plus a new task for
   the epic cleanup that wave 1 never performed.

## Open questions

- Lane key: `BRANA_SESSION_ID`, branch, or task id? Branch is already 1:1 and already claimed;
  session id is stable across branch switches within a session. They differ when one session
  touches several branches.
- Should waves be **populated** or **retired**? A built-and-unused primitive is a liability;
  either it becomes the HOW axis or it should go.
- Is WIP promoted to hard-block today, or is the cap removed? A cap that warns on every add and
  blocks nothing trains the operator to ignore warnings.
