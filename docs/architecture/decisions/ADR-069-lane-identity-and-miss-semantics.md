# ADR-069: Lane Identity, Miss Semantics, and the Unbuilt Axes of v3

- **Status:** Proposed
- **Date:** 2026-07-28
- **Evidence:** [backlog-v3-lane-identity.md](../../ideas/backlog-v3-lane-identity.md) (t-2488 brainstorm); live reproductions 2026-07-28 (below); t-2502 diagnosis (3 reproductions); t-2506 mechanism; t-2495 hypothesis + refutation; live store audit (24 session-state files, 54 epic nodes)
- **Related:** [ADR-065](ADR-065-epic-as-hierarchy-top.md) (epic as hierarchy top), [ADR-068](ADR-068-v3-supersession.md) (v3 supersession), [ADR-060](ADR-060-branch-strategy-autonomous-agents.md) (branch strategy), [backlog-v3-schema.md](../features/backlog-v3-schema.md) D4/D8
- **Task:** t-2488

## Context

Two findings, reached from opposite directions in one session, plus two reproductions
observed while drafting this ADR.

### Finding A — v3 has no *lane* identity, and `epic` is being used as one

[ADR-065](ADR-065-epic-as-hierarchy-top.md) defines an epic as *"what we're building, empty
= feature done"* — a **deliverable**. Session handoff state is keyed by epic. A lane is an
**execution context**: which worktree, which branch, which session. Keying handoffs by epic
uses a *what* as a *where*, so two parallel sessions building toward one deliverable are
the same key **by construction**. This is a category error in the choice of key, not a bug
in the keying logic.

### Finding B — v3 designs three orthogonal axes; one was built, and it grew

| Axis | Designed | Built (measured 2026-07-28) |
|---|---|---|
| **WHAT** — epic → [milestone → phase] → task → subtask | ~10 curated epics | **54 epics**, 46 created in one batch 2026-07-23, all P3, no tags, no parent |
| **CROSS-CUTS** — key:value tags (D8) | net-new | **not built** — flat string tags only |
| **HOW** — waves (`{selector · contract · gate · status}`) | the process overlay | **0 instances** |

The spec's stated problem was *"43 epics — the human gets lost."* There are now 54, because
the wave-1 cleanup never ran. The operator navigates a three-axis system with one axis
populated and overgrown, no cross-cutting index, and no queue to drain it through. **The
felt confusion is a build gap, not a comprehension gap.**

### Reproduction 1 — the read fails *open*, and says so

Running `brana session read --json` on `dev` (2026-07-28, the branch 15 of 24 state files
record):

```
brana: branch "dev" does not match epic convention, falling back to session-state.json
{ written_at: "2026-07-28T16:55:03Z", branch: "dev",
  session_label: "auto-captured (session-end hook)", metrics: {...} }
```

Three properties matter, and only the first was previously recorded:

1. It returned a **different lane's** state. The real handoff (`17:34:57Z`, epic
   `brana-v3-redesign`, 8 `accomplished` / 8 `next` entries) was reachable only via
   `--all` plus a filter on an epic slug the caller must already know.
2. **The tool knew it was guessing** — it announced the miss on stderr — and returned a
   success-shaped result anyway. The defect is not that the key was wrong. The defect is
   that a *miss* silently degrades to a *plausible wrong answer*.
3. The fallback target is **structurally emptier** than what it shadows: a session-end hook
   metrics stub with no `accomplished`, no `next`, no `blockers`. A consumer following it
   reports *"nothing to resume"* rather than *"wrong thing to resume"* — failing closed into
   apparent emptiness, which is indistinguishable from a genuinely quiet session.

**`dev` is the pessimal case and it is the default branch.** Handoffs are written after
merge, when branch has collapsed to `dev`. The branch that can never satisfy the epic
convention is exactly the branch most closes happen on: the convention and the workflow are
in direct contradiction.

### Reproduction 2 — a concurrent lane committed into the shared checkout, live

While this ADR was being drafted, `ceec1d26` landed on `dev` in the **main checkout** at
`17:50:25Z`, 32 seconds before it was observed. The session-start snapshot (`7e328ced`, two
dirty files) was already stale, and another lane's uncommitted `.claude/tasks.json` edit was
swept into that commit by a session that did not author it.

This is precisely the residual case the t-2488 evidence note flagged as unsolved — *two
sessions sharing one checkout* — and it is the case all three t-2502 reproductions came
from. It is now observed rather than inferred.

### Mechanism constraints, verified in this session

- **`BRANA_SESSION_ID` is set but never exported.** `export -p | grep -c BRANA_SESSION_ID`
  = 0; a child `bash -c` prints `UNSET` while the model's own shell prints the id. Any lane
  mechanism relying on environment inheritance — child process, git hook, delegated script —
  **silently receives an empty key.** This is a hard constraint on the mechanism.
- **Linked worktrees keep their own HEAD reflog**, with reason strings that already
  distinguish created-here (`commit:`, `commit (merge):`) from arrived-here (`checkout:`,
  `reset:`, `merge X: Fast-forward`). Verified against `thebrana-t-2505`. Lane attribution
  for worktree-separated lanes is therefore **free and retroactive** — it works for sessions
  that started before this ADR ships.
- All 24 `session-state*.json` files carry `has_session_id: false`. The store has no session
  identity at all, so every keying change needs a defined legacy read path.

## Decision

Six decisions, deliberately separable. Each ships independently; none blocks another except
where stated.

### D1 — A miss is an error, never a substitution *(the load-bearing one)*

`brana session read` must never return, with exit 0, a state whose lane differs from the
lane requested.

- No lane pin resolvable → **exit non-zero** with an actionable message. Do not fall back to
  `session-state.json`.
- `--lane <id>` reads exactly that lane, or fails.
- `--all` continues to enumerate every lane (unchanged; this is the enumeration surface, not
  the resolution surface).
- Legacy identity-less files are reachable **only** through `--all` and explicit `--lane
  legacy:<slug>`. They are never a fallback target.

**Rationale:** D1 alone fixes Reproduction 1. A correct key with fallback-on-miss retained
reproduces the bug verbatim, because the observed failure was a fail-open, not a
mis-addressing. Fixing the key without fixing miss semantics fixes nothing.

### D2 — Lane key: session id, with branch and task recorded as metadata

- **Key:** `BRANA_SESSION_ID`, captured at session **start**.
- **Recorded but non-key:** `branch`, `task_id`, `worktree_path`, `head_at_start`.

Session id survives branch switches within one session — last session touched three
branches — and branch demonstrably collapses to `dev` at close. Recording branch and task
as metadata preserves human legibility and debuggability without making either load-bearing.

**Mechanism (constrained by the export gap):** `system/hooks/session-start.sh` already
computes `SESSION_ID`, `CWD`, and `GIT_ROOT`. It writes a **lane pin file**; it must not
rely on exporting the id. Every consumer resolves the lane by reading that file, never from
the environment.

**Legacy read path:** existing files are addressable as `legacy:<slug>`, listed by `--all`,
and never resolved implicitly. No silent disappearance.

### D3 — Commit attribution: reflog, plus three mechanical guards for the shared checkout

Lane commit attribution derives from the **per-worktree HEAD reflog**, filtered on
created-here reason strings. Free, retroactive, no new recording.

**The shared checkout is not solved by restating the worktree rule.** git-discipline already
mandates worktree-per-lane as a HARD RULE, and Reproduction 2 occurred anyway, in the main
checkout, while this ADR was being drafted. A policy that was already in force and was
already violated cannot be the mechanism that prevents its own violation. The main checkout
is *inherently* shared — `dev` lives there, every session starts there, and closes land
there after merge. Treating it as an exception to be disciplined away is the same
fail-open posture D1 rejects.

Three guards, each mechanical, cheap, and derived from what actually failed:

**D3.1 — The main checkout is a shared workspace, never a lane.**
The lane pin records `worktree_path`. When it resolves to the main checkout, the pin is
marked `shared: true`. Any consumer deriving a commit set from a `shared` pin **fails loud**
rather than computing a window — the same rule as D1, applied to commits instead of state.
A session may still *work* in the main checkout; it may not silently claim commits there.

**D3.2 — HEAD staleness is verified, not assumed.**
The pin records `head_at_start`. Before any lane derives a commit set, it compares current
`HEAD` against `head_at_start` and classifies the delta using reflog reason strings:
own `commit:` entries are mine, `checkout:` / `reset:` / `merge …: Fast-forward` and
commits with no matching reflog entry in this worktree are foreign. A foreign move is
reported, never absorbed. This is what would have caught `ceec1d26` at the moment it landed
rather than 32 seconds later by accident.

**D3.3 — Commits may not sweep paths the lane did not author.**
The pin records `dirty_at_start` — one `git status --porcelain` snapshot taken at session
start. A pre-commit guard in the shared checkout rejects a commit whose staged set includes
a path that was **already dirty when this lane started** and that this lane never wrote.
This is exactly the `ceec1d26` failure: `.claude/tasks.json` was dirty at that lane's start
because it belonged to the t-2492 lane, and it was committed by a session that did not
author it. `git commit -a` in the shared checkout is rejected outright, since it cannot
express authorship.

**Out of scope, recorded as known limitations:**

- **Per-commit ledger.** Reflog plus D3.1–D3.3 covers attribution without new recording.
- **`--commits LIST` into `close-snapshot.sh`.** A contiguous range `A..B` cannot express a
  non-contiguous commit set (measured: an 11-commit window holding 2 own commits). Anchor
  correctness and range over-reach are separate problems; no anchor change solves the
  second. D3.2 makes the over-reach *visible* rather than silent, which is the reachable
  win here.

### D3b — Robustness of the lane pin itself

The pin is new shared state, so it must not reintroduce the failures in D4.

| Property | Design |
|---|---|
| **Atomic write** | Same-dir temp + rename. A pin is never observed half-written. Not doing this would rebuild Cluster 2 inside the Cluster 1 fix. |
| **Single writer** | Written once, at session start, by the owning session only. No concurrent writers to one pin ⇒ no lock needed. This is a property to preserve, not an assumption to rely on: any future in-session pin update requires revisiting it. |
| **Liveness** | A pin is *live* if its session has not closed and its mtime is within a bounded window. D3.1's "other live lanes" test depends on this definition, so it is normative, not incidental. |
| **Stale pins** | Crashed sessions leave pins. `brana session lanes --prune` reaps them; a stale pin degrades D3.1 toward *more* fail-loud, never toward silent success. |
| **Missing pin** | Resolution fails loud (D1). Absence is never interpreted as "use the default." |
| **Corrupt pin** | Same as missing. Never partially parsed. |

**Failure direction is uniform:** every degraded state in this table resolves toward
refusing to answer, never toward answering from another lane. That is the invariant the
whole ADR turns on.

### D4 — Atomicity is a separate cluster and stays separate

The symptom cluster splits in two. **Do not merge them.**

| Cluster | Question | Members |
|---|---|---|
| **Identity** | *whose state is this?* | t-2502, t-2506, sitrep ambiguity |
| **Atomicity** | *did I read a whole file?* | t-2495, epic-detection non-convergence |

Perfect identity still yields torn reads; atomic writes still leave you unable to tell whose
handoff you are reading.

**t-2495's mechanism is OPEN.** A torn-read root cause was recorded and then **refuted** in
the same session: `save_tasks` uses `write_atomic` (same-dir temp + rename) and `lock_tasks`
holds an exclusive `flock` across the whole read-modify-write (t-2166). **Do not touch
`save_tasks` or the serializer; both are correct.** The surviving suspects are the non-Rust
writers that bypass both — `close-classify.sh` and seven `system/scripts/migrate/*.py`.
Auditing them is a real defect hunt regardless of whether it caused the observed failure.

### D5 — Waves: deferred, with a deadline and an owner

Waves are **not** decided by this ADR. The deferral itself is the recorded decision, so that
"decide later" cannot quietly become "ratified by omission":

- Waves remain at 0 instances and gain no new consumers.
- A dedicated decision is due **2026-08-28**, with two admissible outcomes: populate as the
  HOW axis, or retire the primitive.
- Until then, no design may take a dependency on waves.

**Standing note:** zero instances means zero migration cost. Retirement is cheapest now and
gets monotonically more expensive with every consumer added.

### D6 — The epic cleanup is named work with an owner, and it blocks the "done" claim

ADR-065 shipped a correct data model and the felt problem got **worse** (43 → 54) because
wave 1 never ran. An ADR that ships schema without cleanup repeats that failure exactly.

- A cleanup task is filed with a **named owner and a date**, not a backlog aspiration.
- Target: collapse 54 → ~10, starting with the 46 created in the 2026-07-23 batch (all P3,
  no tags, no parent).
- **This ADR is not "done" while the count is above ~10.** Schema completion does not count
  as completion.

## Consequences

- **Session-start gains one file write.** Context economy is a constraint, not a
  nice-to-have (epic t-2483): the lane pin is a file write, not a context injection, and must
  add no tokens to session start.
- **Every session-state consumer must handle a non-zero exit** from `session read`. Callers
  that today assume success — `close`, `sitrep`, the session-end hook — need explicit miss
  handling. This is the intended cost of D1.
- **Sitrep gains a lane line.** It must state which lane the handoff came from; ambiguity
  there is the operator-visible symptom, and a fix that leaves it ambiguous has not shipped.
- **The shared checkout gets slower and louder.** D3.3 rejects `git commit -a` there and can
  reject a commit that sweeps a foreign dirty path. This is a deliberate friction cost paid
  in the one place where cross-lane damage is possible, and it is the only guard that would
  have prevented Reproduction 2 rather than merely reported it. Worktree lanes are
  unaffected — the guard is scoped to the shared checkout, so the fast path stays fast.
- **`pattern_worktree-git-is-a-file-hooks-inert` does not block D3.3.** Post-commit and
  pre-commit hooks were probed firing in linked worktrees; that note concerns hard-coded
  `.git/<path>` resolution, not hook dispatch. D3.3's guard must still resolve the git dir
  via `git rev-parse --git-common-dir` rather than assuming `.git/` is a directory.
- **t-2506 is fixed first and independently.** `brana session write` dedups `next[]` by
  `task_id`, keeps the first, and silently drops the rest (exit `ok:true`, no warning) —
  reproduced at the 2026-07-28 close: 10 entries in, 8 out, and the two dropped were this
  ADR's own open decisions. `task_id` is a **reference, not a unique key.** This is live data
  loss in the handoff path, independent of everything above, and it protects this ADR's own
  handoff.
- **t-2502 unparks once D1 + D2 land**, and its previously agreed fix stays dead: deriving
  the range from the closing session's own commits was unbuildable because nothing recorded
  which commits belong to a session. D3 supplies that; the epic-scoped anchor remains the
  same category error in smaller form and must not be built.
- **Reversibility:** the lane pin is one file and one hook line; miss semantics are one exit
  path. Both revert without data migration. Legacy files are never rewritten.

## Non-Actions — explicitly not adopted

- **Per-commit ledger / `--commits LIST`** (D3) — reflog plus the D3.1–D3.3 guards covers
  attribution; range over-reach is recorded as a known limitation instead.
- **Relying on worktree-per-lane as the mechanism.** It is retained as policy, but
  Reproduction 2 proves it cannot carry the guarantee on its own. The guards are mechanical
  precisely because the rule was already in force when it was violated.
- **Epic-scoped close anchor** — the category error in smaller form. t-2502 was parked
  rather than shipping it.
- **Any change to `save_tasks`, `write_atomic`, or `lock_tasks`** (D4) — the torn-read
  hypothesis was refuted; these are correct.
- **A new node level for lanes.** A lane is not a hierarchy node. The key is session state's
  concern; the backlog already carries `task.branch`.
- **Waves populated or retired** (D5) — deferred with a deadline, not silently ratified.
- **Retiring the `epic` field.** Epic remains a correct *deliverable* key. It was only ever
  wrong as a *lane* key.

## Alternatives considered

- **Key by branch.** Rejected: collapses to `dev` at close time, the most common case
  (15/24 files). Zero new mechanism, but it fails exactly where the handoff is written.
- **Key by task id.** Rejected: fails for sessions with no task or several — the
  2026-07-28 close touched three epics, and the epic walk correctly refused to converge.
- **Key by session id, environment-propagated.** Rejected on measurement: the id is set but
  not exported, so children read an empty key silently. The pin must be a file.
- **Keep fallback-on-miss, fix only the key.** Rejected: reproduces Reproduction 1 verbatim.
  This was the premortem's top-rated failure mode — high likelihood, high impact, and
  undetectable because it looks like success.
- **One merged fix for all five symptoms.** Rejected: an earlier framing in the t-2488
  session claimed "one missing primitive, five symptoms." It was too neat. Identity and
  atomicity are independent (D4).
