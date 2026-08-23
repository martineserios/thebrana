---
status: proposed
---
# ADR-069: Lane Identity, Miss Semantics, and the Unbuilt Axes of v3

- **Status:** Proposed, **partially superseded** (2026-08-23, t-3030 — see §Amendment): D3.2 and D3b are retracted per t-2516; the remaining decisions stand as Proposed. Original line (its "six" count is stale — the Decision section itself lists D0, D0b, D1–D6 with sub-items; retraction is by label, not by count): **two of six decisions require redesign before Accepted** (t-2516
  verification, 2026-07-28). The *diagnosis* is unchanged and holds; **D3.2** (reflog
  attribution) and **D3b** (missing pin ⇒ fail loud) rest on mechanisms that verification
  contradicted. See the inline VERIFIED blocks in D3.2, D3b and D1's consequences.
- **Date:** 2026-07-28
- **Evidence:** [backlog-v3-lane-identity.md](../../ideas/drained/backlog-v3-lane-identity.md) (t-2488 brainstorm); live reproductions 2026-07-28 (below); t-2502 diagnosis (3 reproductions); t-2506 mechanism; t-2495 hypothesis + refutation; live store audit (24 session-state files, 54 epic nodes)
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

**Correction to an earlier draft.** It claimed "six decisions, each ships independently."
That was a comforting fiction, and the challenge gate refuted it. The real graph:

```
D0b (store scoping)  ──precondition for──▶  everything (D1's escape hatches are void without it)
D0  (key unification) ──┐
D2  (resume query)    ──┼──▶ ship together as ONE change; D1 alone is unusable
D1  (miss semantics)  ──┘
D3.1/3.2/3.3 ──depends on── D2 (every guard reads a pin field)
D3b          ── is D2's spec, not a separate decision
D4           ── produces no diff: two Non-Actions + an audit that needs an owner
D5           ── produces no diff: a deferral
D6           ── files a task
```

**Three decisions carry a diff — D0b, and D0+D1+D2 as one unit, and D3.** D4/D5/D6 are
governance. Since full scope was chosen partly on the strength of separability, that
justification does not hold; scope is retained on the operator's explicit call, with the
dependency graph stated honestly instead.

### D0 — Reads and writes must resolve through one key function *(root cause)*

Reproduction 1 is not a fail-open layered on a correct key. It is a **write-key/read-key
asymmetry**, verified in source:

| Path | Function | Key |
|---|---|---|
| Write | `write_state` → `unit_scoped_state_path(root, state.epic, branch)` — `brana-core/src/session.rs:342` | **epic-first**, branch fallback |
| Read | `read_state` → `epic_scoped_state_path(root, branch)` — `brana-core/src/session.rs:332` | **branch-only** |
| Consume | `mark_consumed` → `epic_scoped_state_path(root, branch)` — `brana-core/src/session.rs:649` | **branch-only** (and it *writes*) |

The 17:34:57Z handoff was written under the epic key; the read on `dev` looked under the
branch key, missed, and fell through. **Read must resolve by the same key the write used.**
Since a reader holds no state to read `epic` from, that key must come from the lane pin
(D2) — which is why D0/D1/D2 ship as one change, not three.

`mark_consumed` resolving by the broken key is worse than a bad read: on `dev` it stamps
`consumed_at` onto another lane's file. A cross-lane **write**.

### D0b — Session state must be worktree-shared, like `tasks.json` *(precondition)*

The store is **worktree-scoped today, and it should not be.** Verified empirically from the
t-2488 worktree: `brana session read --all --json` returns **0 lanes**, while the main
checkout returns 24.

| Resolver | Function | Effect |
|---|---|---|
| Session state | `find_project_root()` → `git_toplevel()` — `brana-core/src/util.rs:124-130` | **per-worktree** store |
| `tasks.json` | `find_tasks_config()` → `git_common_root()` first — `brana-core/src/util.rs:158-165` | **shared** across worktrees |

`find_tasks_config` already does the right thing, with a comment at `util.rs:153-157`
explaining that common-dir resolution is exactly what makes state shared. Session state was
never given the same treatment. The split is not theoretical: a real orphaned store exists
at `~/.claude/projects/-home-martineserios-enter-thebrana-thebrana-feat-t-798/`.

**Decision:** session state resolves via `git_common_root()`. Existing per-worktree stores
are migrated or explicitly adopted as `legacy:` lanes.

**Why this is a precondition and not a nicety:** without it, D1's fail-loud fires on every
worktree lane on day 1, and D1's own escape hatches (`--all`, `--lane legacy:<slug>`) point
at a directory that does not contain the handoff. **Reproduction 1 was measured on `dev` in
the main checkout — the one environment where this defect is invisible.** Any keying
decision taken before D0b is taken in the wrong coordinate system.

### D1 — A miss is an error, never a substitution

`brana session read` must never return, with exit 0, a state whose lane differs from the
lane requested.

- No lane resolvable → **exit non-zero** with an actionable message.
- `--lane <id>` reads exactly that lane, or fails.
- `--all` continues to enumerate every lane (the enumeration surface, not the resolution
  surface).
- Legacy identity-less files are reachable **only** through `--all` and explicit
  `--lane legacy:<slug>`. Never a fallback target. The current `(orphan)` display label is
  not an identifier; each legacy file needs a real addressable slug.

**Every fallback surface must be closed, not just the first.** Naming one and fixing one is
how the sibling survives:

| Surface | Location | Current miss behaviour |
|---|---|---|
| `session-state.json` fallthrough | `brana-core/src/session.rs:56-64` | returns another lane's state |
| **`handoff last` fallback** | `brana-cli/src/commands/session.rs:96-100` | prints legacy markdown, returns `Ok(())` — **exit 0** |
| **MCP `session_read`** | `brana-mcp/src/tools/session_read.rs:25` | `{"found": false}` — no exit code exists |
| **`mark_consumed`** | `brana-core/src/session.rs:649` | writes to the mis-resolved file |
| **Shell caller idiom** | `system/hooks/session-start.sh:514`, `session-end.sh:109` | `2>/dev/null \|\| VAR=""` converts loud failure back into silence |

The last row is the one that decides whether D1 is real. **Making `read` fail loudly does
not make the system fail loudly** — the dominant caller idiom in this codebase swallows the
exit code and, at `session-start.sh:575`, an empty result activates yet another legacy
scan. D1 is not shipped until those call sites are changed in the same change-set.

**Rationale, corrected:** D1 alone converts *wrong answer, exit 0* into *no answer, exit
non-zero*. That removes silent cross-lane contamination and is worth shipping for that
reason alone — but it does **not** make the real handoff reachable on `dev`. Only D0+D2
does. An earlier draft of this ADR claimed D1 was sufficient for Reproduction 1; that claim
was refuted against the source and is retracted here.

### D2 — Write key is the lane id; **resume is a query, not a key lookup**

The distinction an earlier draft collapsed, and the one that makes D1 safe:

| Operation | Mechanism |
|---|---|
| **Write** | Key by `BRANA_SESSION_ID`, captured at session start. One session ⇒ one file ⇒ no cross-lane clobber. |
| **Resume** | **Query** the lane store: most recently closed lane whose `worktree_path` matches mine, else whose `branch` matches, else whose `task_id` matches. Ranked, and it reports *which* rule matched. |

**Why this is not optional.** A fresh session has no state under its own id, so under
key-lookup resolution **a miss is the universal case at session start**, and D1 would make
every session start fatal. Key choice therefore *determines the base rate of misses* — the
opposite of this ADR's earlier claim that miss semantics are independent of key choice.

Resume returns **at most one** lane and always states the matching rule and the candidate
count. Ambiguity (two equally-ranked candidates) is a **miss** under D1, not a coin flip.
This is what makes "which lane am I resuming?" answerable — the operator-visible symptom.

- **Recorded but non-key:** `branch`, `task_id`, `worktree_path`, `head_at_start`,
  `dirty_at_start`.
- **Legacy:** existing files are addressable as `legacy:<slug>`, enumerated by `--all`, and
  never resolved implicitly. Filename-derived slugs collide with inner `epic` fields today
  (three files claim `harness-core`), so legacy slugs must be disambiguated at migration,
  not at read time.

**Pin discovery — the circularity, resolved.** A consumer cannot read the pin keyed by an id
it cannot see (`BRANA_SESSION_ID` is not exported). But **cwd *is* inherited**. So the pin is
discovered by `worktree_path`, and carries `session_id` inside it. In the shared main
checkout two live pins may match one cwd — that is detected and, per D1, is a miss rather
than a guess.

**Autonomous bootstrap.** `claude -p` runners and cron fire no interactive SessionStart hook,
so they would have no pin — and under D3b "missing pin → fail loud" that converts the whole
autonomous surface from working-but-mis-attributed to **not working**. Therefore: a pin is
creatable explicitly (`brana session lane init --session-id <id>`), the autonomous runner
calls it, and a run without a pin degrades to a named `autonomous:<run-id>` lane rather than
a hard failure. Not verified: whether `autonomous-runner.sh` fires SessionStart inside its
sandbox. **This must be checked before Accepted.**

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

**D3.2 — HEAD staleness is *detected*; attribution works only in worktree lanes.**
The pin records `head_at_start`. A lane compares current `HEAD` against it and classifies
the delta by reflog reason string — `commit:` created here, `checkout:` / `reset:` /
`merge …: Fast-forward` arrived here.

**Scope correction.** This works in linked worktrees, which keep their own HEAD reflog. It
does **not** work in the shared main checkout, which has exactly **one** reflog shared by
every lane: another lane's `commit:` entry is indistinguishable from mine. An earlier draft
claimed D3.2 "would have caught `ceec1d26`" — false. It would have classified `ceec1d26` as
**mine**. In the shared checkout D3.2 can detect only that HEAD *moved*, never by whom; that
detection feeds D3.1, which refuses rather than attributes.

Known limits, none of which the reflog survives: **rebase/amend/squash** rewrite SHAs so a
lane's own work classifies foreign; **cherry-pick** is indistinguishable from authorship;
**reflog expiry** (default 90d / 30d unreachable) bounds the "free and retroactive" claim;
**detached HEAD** yields no branch metadata; and **`git worktree remove` deletes the
worktree's reflog** — which git-discipline mandates after merge.

> **VERIFIED 2026-07-28 (t-2516 G1) — empirically, and the framing above needed correcting.**
> `git worktree remove` deletes `.git/worktrees/<name>/` in full, `logs/HEAD` included.
> Measured on the t-2506 lane: 5 reflog entries present before removal, admin directory and
> reflog file both absent after. Merged commits survive; only the per-lane attribution
> evidence dies.
>
> **The "at exactly the moment close needs it" claim was wrong**, because it assumed an
> ordering this ADR never stated:
>
> | ordering | reflog at close | D3.2 |
> |---|---|---|
> | close → merge → remove | live | works |
> | merge → remove → close | gone | cannot attribute |
>
> Both orderings occur in practice, and the second one occurred in the very session that
> verified this: t-2506 was merged to `dev` and its worktree removed before close, leaving its
> three commits with no worktree reflog and only the shared checkout's single reflog — which
> D3.2 above already says cannot attribute. So D3.2 is **not unconditionally self-defeating.
> It is unavailable to any lane that merges before it closes**, which is a normal way to work
> and not an edge case.
>
> **Consequence for the mechanism, not just its caveats.** Reflog-as-source is
> retroactive-by-luck: it reads evidence that a mandated cleanup step is entitled to delete.
> Attribution must instead be **recorded when the commit happens**, while the evidence
> certainly exists, rather than **reconstructed at close**, when it may not. D3.3 already
> installs a commit-time guard, so the recording point exists; D3.2 should append there
> instead of mining the reflog afterwards. **Do not implement D3.2 as specified.**

**D3.3 — Commits may not sweep paths that were dirty at lane start.**
The pin records `dirty_at_start` — one `git status --porcelain` snapshot at session start. A
pre-commit guard in the shared checkout rejects a commit whose staged set includes a path
that was dirty at this lane's start, unless the path is explicitly acknowledged
(`--adopt-path`). `git commit -a` in the shared checkout is rejected outright, since it
cannot express authorship.

**Predicate correction.** An earlier draft also required "and this lane never wrote it."
That is **not knowable** — no per-lane write ledger exists, and D3's own Out-of-scope
section declines to build one, making the guard circular. The predicate is therefore
`dirty_at_start` **alone**, which is recordable, plus an explicit opt-in for the legitimate
case (a lane resuming its own uncommitted work). This is more conservative — it will stop
some valid commits — and that is the correct failure direction. It is also the only guard
here that would have *prevented* `ceec1d26` rather than merely reported it, and only if that
lane staged `.claude/tasks.json` rather than adopting it deliberately.

**Host surfaces, named:** `system/scripts/git-hooks/pre-commit` (already worktree-safe via
`git rev-parse --git-path`), its sibling `commit-msg`, and the bootstrap step that resolves
the effective `core.hooksPath`. The guard must compose with `no-attribution-commit.sh`
rather than replace it.

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

> **VERIFIED 2026-07-28 (t-2516 G2) — the autonomous surface has no pin at all, and
> "missing pin ⇒ fail loud" is therefore not a degradation but an outage.**
>
> `system/scripts/autonomous-runner.sh:80–103` (`sandbox_claude`) runs `claude -p` under
> bubblewrap with `--tmpfs /home`, bind-mounting exactly three things beneath it: `~/.cargo`,
> `~/.gitconfig`, `~/.claude/.credentials.json`. **`~/.claude/settings.json` is not mounted and
> `~/.claude/hooks/` is not mounted**, the process is launched under `env -i`, and no
> `CLAUDE_CONFIG_DIR` or `--settings` appears anywhere in the script. SessionStart has no
> configuration and no script to run, so it cannot fire. `~/.claude/projects/` is likewise
> unmounted, so session state can be neither read nor written from inside the jail — the store
> would resolve onto the tmpfs and evaporate with the sandbox.
>
> **This inverts the incentive the ADR is built on.** Lines 83–86 fall back to *unsandboxed*
> execution when `bwrap` is absent or `RUNNER_SANDBOX=0`, and that path has a full `HOME`, so
> hooks do fire and a pin would exist. Under "missing pin ⇒ fail loud" the **sandboxed
> default fails and the degraded unsandboxed fallback works** — the rule would reward turning
> the sandbox off. A failure direction that is uniform for interactive sessions is not uniform
> once the autonomous surface is included.
>
> D3b needs a lane-pin source for non-interactive runs that does not depend on SessionStart —
> established by the runner as it constructs the jail, not discovered by the session inside it.
> Note also that `BRANA_SESSION_ID` cannot serve here: it is set but never exported, so even
> without `env -i` a child process sees it unset.

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
- Until then, no design may take a dependency on the wave **primitive**.
- **The deadline is a `brana remind` row linked to the task, not a sentence in this ADR.**
  A prose date is what ADR-065's cleanup had, and it never ran. Past-due reminders are
  surfaced at session start with a start prompt; a date without a reminder row is theatre.

**Terminology hazard, flagged:** "wave" names two different things — the stored primitive
(0 instances) and the v3 *program phase* (wave 1, wave 2…, used throughout ADR-068). This
decision governs the **primitive only**. D6's epic cleanup *is* program wave 1, so the two
decisions collide on the word without colliding on substance.

**Standing note:** zero instances means zero migration cost. Retirement is cheapest now and
gets monotonically more expensive with every consumer added.

### D6 — The epic cleanup is named work with an owner, and it blocks the "done" claim

ADR-065 shipped a correct data model and the felt problem got **worse** (43 → 54) because
wave 1 never ran. An ADR that ships schema without cleanup repeats that failure exactly.

- A cleanup task is filed with an owner and a **`brana remind` row**, not a prose date.
  Live measurement 2026-07-28: 54 epics — 4 `active`, 50 `next`, **46** from the 2026-07-23
  batch (all P3, no tags, no parent). The batch *is* the work.
- **Correction to an earlier draft:** it stated "this ADR is not done while the count is
  above ~10." That is withdrawn. It coupled six separable decisions to one unrelated data
  chore, made ADR status a function of mutable data with nothing reading it, and reproduced
  ADR-065's failure mode — a prose gate — while citing that same failure as its reason. The
  accountability is kept; the coupling is dropped.
- What ADR-065 actually contained, checked: **no cleanup clause at all**. The "43 → ~10"
  cleanup was assigned in `docs/architecture/features/backlog-v3-schema.md:267` as "v3 wave
  1" — a prose assignment to a program phase. Nothing enforced it and 43 became 54. That is
  the precedent D5 and D6 must not repeat.

## Consequences

- **Session-start gains one file write.** Context economy is a constraint, not a
  nice-to-have (epic t-2483): the lane pin is a file write, not a context injection, and must
  add no tokens to session start.
- **Every session-state consumer must handle a non-zero exit** from `session read`. Callers
  that today assume success — `close`, `sitrep`, the session-end hook — need explicit miss
  handling. This is the intended cost of D1.
  > **VERIFIED 2026-07-28 (t-2516 G3):** `system/scripts/statusline-slow-cache.sh` is **not** a
  > session-state consumer — no read of `session-state*.json`, `brana session read`, or any
  > equivalent. It is ruled out of D1's blast radius. The consumer list above is unchanged by
  > this check; the suspected fourth consumer does not exist.
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
- **Reversibility is asymmetric.** An earlier draft claimed it was symmetric; that is
  withdrawn. **Revert-safe:** D1 in isolation, D3.1–D3.3, D5. **Not revert-safe:** D2 after
  any close has run under it — handoffs written to session-id-keyed filenames survive on
  disk but become unreadable by the reverted reader, which derives `session-state-{epic}.json`
  from a branch regex and will never produce a uuid-keyed name. Recovery is a rename
  migration, which is exactly what "no data migration" denied. Worse, the reverted reader
  lands on `session-state.json` — the metrics stub from Reproduction 1. **A rollback script
  is a required deliverable of D2, not a contingency.**
- **`brana session path` is a third resolution surface** (`brana-cli/src/commands/session.rs:242-247`),
  resolving branch-first while `session write` resolves epic-first. The session-end hook
  probes with `path` and writes with `write` — reading a different file than the writer
  writes. This is the mechanism that produced Reproduction 1's orphan stub. It is in scope
  for D0.
- **t-2506 has a sibling.** `dedup_next_items` (`brana-core/src/session.rs:123-134`) is the
  known dropper, but `merge_states` (`session.rs:491-495`) implements the same `task_id`
  drop independently, on the same-day merge path — i.e. the second close of any day, when
  handoff volume is highest. Both are in scope; fixing one leaves the other.
- **D2 silently retires two live behaviours.** Per-session filenames mean the same-day merge
  branch stops firing, and the `branch_has_active_worktree` clobber guard (`session.rs:377-388`,
  added for t-2263) becomes dead code because it only triggers against an existing file at
  the same path. Both must be explicitly re-provided or explicitly dropped.
- **Session state is not single-writer today.** `system/hooks/session-end-persist.sh:240-242`
  performs an unlocked read-modify-write (`jq … > tmp && mv`) on a session-state file after
  `session write`. D3b's single-writer premise holds for the pin, not for the store — and
  this writer is missing from D4's suspect list, which names only `tasks.json` writers.

## Non-Actions — explicitly not adopted

- **Per-commit ledger / `--commits LIST`** (D3) — reflog plus the D3.1–D3.3 guards covers
  attribution; range over-reach is recorded as a known limitation instead.
- **Relying on worktree-per-lane as the mechanism.** It is retained as policy, but
  Reproduction 2 proves it cannot carry the guarantee on its own. The guards are mechanical
  precisely because the rule was already in force when it was violated.
- **Epic-scoped close anchor** — the category error in smaller form. t-2502 was parked
  rather than shipping it. (2026-08-17: t-2502 shipped only the D3 "visible, not silent"
  slice — an empty-window flag `ANCHOR_ZERO_WINDOW` and a multi-epic over-reach warning in
  `close/phases/gate-and-evidence.md`'s CLOSE-ANCHOR-BLOCK; no anchor change. Truncation
  itself still waits on the lane pin, t-2521.)
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

## Amendment (2026-08-23, t-3030): partial supersession after t-2516

t-2516 (2026-07-28, merged 7a7638a9) verified this ADR's three open mechanism questions and left the status deliberately Proposed. The-brana consolidation (board §3, guide L6 task E) resolves that hanging state explicitly rather than leaving the reader to infer it from inline VERIFIED blocks:

- **Retracted:** **D3.2** (reflog attribution — the reflog is destroyed by the mandated worktree cleanup; attribution must be recorded at commit time, not reconstructed at close) and **D3b** (missing pin ⇒ fail loud — the autonomous sandbox cannot fire SessionStart, so fail-loud would break the secure default and reward disabling the sandbox). Neither is to be implemented as written; any redesign is a new ADR, not an edit here.
- **Stand as Proposed:** D0, D0b, D1, D2, D3 (items other than 3.2), D4, D5, D6, and the Context diagnosis (Findings A/B, both reproductions).
- **Frontmatter** stays `status: proposed` — the repo has no partial-supersession enum and this ADR is not superseded as a whole. The header line carries the qualifier.

Refs: t-2516 notes · guide L6/E · board §3 ("amend or mark partially superseded").
