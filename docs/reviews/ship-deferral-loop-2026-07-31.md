# Ship deferral loop — investigated and falsified

**Date:** 2026-07-31
**Task:** t-2547
**Verdict:** the premise is false. There is no deferral loop.

## What the task claimed

> "Ship is deferred because the batch is large, and the batch is large because ship is
> deferred — t-2214 has failed this way once already."

The claim is a self-reinforcing loop: each deferral grows the batch, and the grown batch
justifies the next deferral. It rested on two observations — t-2214 was filed and deferred
on 2026-06-21 and is still open, and `dev` was 55 commits ahead when the task was filed.

## AC1 — the loop, characterised with dates and counts

**It is not real.** Shipping is one of the most frequent operations in this repo.

Ship events are invisible in `git log main` because promotion is `--ff-only`: main's
first-parent history *is* dev's history, and no merge commit is created. The record lives in
the reflog.

| Measure | Value |
|---|---|
| `dev`→`main` ship events in reflog | **23** |
| Ships in the 12 days 2026-07-17 → 07-28 | **~21** |
| Days with multiple ships | 07-21 (2), 07-22 (3), 07-23 (3), 07-27 (4), 07-28 (2) |
| Commits landing on main, 07-22 | **71** |
| Commits landing on main, 07-24 | **68** |
| Commits landing on main, 07-27 | **53** |
| Commits landing on main, 07-28 | **37** |

**Ship is not deferred.** It ran roughly twice a day through late July.

### CORRECTION (2026-07-31, same session)

An earlier draft of this section also concluded *"a large batch is not exceptional — 67
commits is a normal day's volume."* **That was wrong**, and it was the strongest claim in the
document. It read per-*day* commit totals as if they were per-*ship* batch sizes, but several
of those days carried multiple ships (07-22 had 3, 07-27 had 4). Disaggregating gives the
opposite answer.

Per-ship batch size, measured across all 79 ship events in the reflog:

| Statistic | Commits |
|---|---|
| Minimum | 1 |
| **Median** | **2** |
| Mean | 7 |
| Maximum | 121 |
| Batches ≥ 50 commits | **2 of 79** |
| Batches ≥ 67 (today's gap) | **1 of 79** |

**This repo ships small and often — a median of two commits per promotion.** The current
67-commit gap is roughly 30× the median and sits in the top ~1% of all batches ever shipped.
It is a genuine anomaly, not business as usual.

### What survives, and what this changes

- **Still falsified:** the *mechanism*. Batch size does not cause deferral. Ship ran ~21 times
  in 12 days, and the single largest batch on record (121) shipped rather than stalling.
  Nothing supports "the batch is large *because* ship is deferred."
- **No longer dismissed:** the *symptom*. An abnormally large undeployed batch is real and
  rare. The original concern was pointing at something true; only its explanation was wrong.

### A causal story that fits both facts

Frequent shipping and a rare enormous batch are only paradoxical if ship is assumed to be a
deliberate periodic decision. It isn't — it is a **step inside build's CLOSE** (close.md:227),
so it is offered exactly when a build finishes and never otherwise.

That predicts precisely this distribution: most sessions run a build, hit CLOSE, and ship
their two commits — hence the median of 2. A run of sessions that end *without* a build
(research, planning, task triage, or a session ending by compaction or interruption) never
sees the offer at all, and the batch accumulates untouched until the next build happens to
close.

Stated as a hypothesis rather than a finding: it fits the observed distribution and the
located defect, but confirming it requires reconstructing whether the sessions in the 3-day
window ended without a build.

### TESTED AND REFUTED (2026-07-31, same session)

That reconstruction was done. **The hypothesis is false.**

The 68 commits accumulated between 2026-07-28 and 07-31 contain **9+ build merges**
(t-2506, t-2544, t-2542, t-1781, t-2516, t-2535, t-2515, t-2507, t-2539) and **22
session-close commits** (`chore(tasks)` / `chore(state)`). Builds completed and sessions
closed repeatedly across the window. Build's CLOSE therefore ran many times, and step 14's
ship offer should have fired on each occasion. No ship happened.

So the batch did not grow because the offer was never reached *by virtue of no build
closing*. Builds closed plenty.

**What remains as candidate explanations**, neither yet tested:

1. **Step 14 is the fourteenth step of a long procedure.** CLOSE runs 1→14 with docs
   generation, reconcile checks and living-doc updates in between. A CLOSE that is truncated
   by context compression, interrupted, or simply not run to completion never reaches the
   ship offer. This predicts the offer is *skipped*, not *declined*.
2. **It is reached and declined.** One instance is directly documented: on 2026-07-31 the
   offer fired at the end of the t-2545 build, was presented, and was declined in favour of
   continuing to accumulate — a decision made partly on the mistaken belief (corrected above)
   that 67 commits was an ordinary batch.

Distinguishing these needs data neither the git history nor the reflog holds: whether CLOSE
reached step 14. That is a question about session transcripts, not the repository.

**Consequence for the remedy.** t-2567's first defect — close.md:227 is a bare `{N}` with no
derivation anywhere in `system/` — stands unaffected and is independently evidenced. Its
second defect ("wrong host") is **weakened**: sessions ending without a build genuinely never
see the offer, so putting the check in `/brana:close` is still right, but that is *not* what
caused this particular batch. The fix should be pursued on its own merits, not as the
explanation for the 68-commit gap.

**Two of this investigation's causal stories have now failed under test** — first "large
batches are routine" (falsified by disaggregating per-ship), then this one. Both were
plausible, both fitted the data available at the time, and both were wrong. The pattern worth
carrying forward is that a causal story which merely *fits* is not evidence; it has to be
given a chance to fail.

### What t-2214 actually is

Not a blocked deploy — a **stale task**. Shipping has happened ~21 times since it was filed.
It is `status:in_progress`, `started:null`, `effort:S`, `branch:null`: declared started five
weeks ago and never begun, while the thing it describes went on happening without it.

This is bookkeeping drift, the same class validate.sh Check 68 (t-2545) was built to detect,
and t-2541 measured across worktrees. The task tracked a *specific* ship that dozens of
actual ships superseded.

**The original diagnosis inverted cause and effect.** t-2214's staleness was read as evidence
that shipping had stalled. It was evidence that the *task* had been abandoned — because
shipping no longer needed it.

## AC2 — the real risk of a large promotion, and rollback cost

The deferral instinct rests on rollback being expensive. **It is not.** Measured 2026-07-31:

**Rollback is `git revert` + one `./bootstrap.sh` run.**

- `main` and `origin/main` are the same commit (`bef34d56`) — main is **pushed**, so rollback
  must be `revert`, not `reset`. `git-discipline.md` forbids force-pushing main.
- **Every deploy path deletes files absent from source**, so a reverted file is genuinely
  removed from `~/.claude/` rather than left behind:
  - `sync_dir()` (bootstrap.sh:292-309) removes dest files with no source counterpart —
    covers `rules/` and `scripts/`.
  - hooks: `rsync -a --delete` (bootstrap.sh:395-417).
  - plugin cache: `rsync -av --delete` (bootstrap.sh:150, 901).

So there is no residue problem, which is the failure mode that would have made rollback
genuinely costly. **The named risks, ranked:**

1. **In-flight session breakage** — the only real one. Sessions hold pre-deploy hook and skill
   state; after a deploy they must be restarted. This is t-2214's own note ("Reiniciar
   sesiones en vuelo tras el deploy") and it is a function of *deploying at all*, not of
   batch size. It argues for shipping when no session is mid-flight — not for shipping less.
2. **Rollback granularity** — a 67-commit batch reverts as a unit unless you identify the
   specific bad commit. Real but modest: commits are atomic and conventionally named.
3. **Review burden** — nobody reviews the batch at promotion time today, so this is a
   hypothetical cost, not an incurred one.
4. **Bootstrap blast radius** — mitigated by the delete semantics above and `--check`.

**One caveat this investigation did not measure:** no rollback has actually been performed.
The mechanism is verified by reading the deploy paths, not by executing a revert. The claim
is "the machinery supports clean rollback," not "rollback has been rehearsed."

## AC3 — trigger rule

A draft rule ("ship whenever `dev` contains a change under `system/hooks|rules|skills`, plus a
48-hour backstop") was **rejected by pre-mortem before adoption**. It would have failed for
five reasons, three of them high/high:

- It fixes a non-problem — ship already ran twice a day.
- It over-triggers: nearly every commit touches `system/`, so it fires on almost every merge,
  becomes noise, and gets ignored.
- It has no enforcement surface — a doc rule nothing evaluates, which is precisely the WIP
  cap's fate (t-2531/t-2565).
- Its condition is invisible without AC4.
- Its 48-hour backstop has no clock; nothing wakes to evaluate it.

**Decided rule: embed the check in `/brana:close`, do not create a new rule.**

`work-preferences.md` already names the anti-pattern being avoided: *"New capabilities should
embed as steps in existing frequently-used commands, not standalone commands the user must
remember. Anti-pattern: creating useful capabilities as standalone commands nobody remembers
to run."*

`/brana:close` runs at the end of every session — the single most reliable recurring ritual in
this workflow, and the natural moment to ship, because it is exactly when no work is in
flight (neutralising risk #1 above). CLOSE step 14 **already offers this**. So the remedy is
not a new rule at all; it is making step 14's condition **derived and honest** (AC4) instead
of dependent on someone remembering the number.

**Trigger:** at CLOSE, compute the count at read time; if `dev` is ahead of `main`, offer the
ship. Time- and size-based triggers are both rejected — the evidence shows neither latency
nor batch size is the operative variable.

## AC4 — the deploy-pending indicator must be derived

The task records a stale handoff claiming *"DEPLOY PENDING — dev is 12 commits ahead of main"*
which "was wrong when written (dev was 1 ahead) and wrong later (10, then 16, then 55)."

Confirmed again this session, from the other direction: I stated "72 commits ahead" from a
remembered number when the true figure was 67, minutes after reading it. **A written-down
count is wrong the moment the next commit lands**, and a deploy-pending signal nobody can
trust is worse than none, because it is indistinguishable from a verified one.

**Rule: never write the count down. Compute it at the point of display.**

```bash
git rev-list --count main..dev
```

Cost is negligible and it cannot go stale. This is the same principle t-2541 settled for
worktrees and t-2545 implemented: **derive from the repo, never trust a cached field.** The
deploy-pending indicator is that identical pattern applied to the branch gap.

### The exact defect, located

`system/skills/build/phases/close.md:227` is the **only** place the indicator exists:

```
question: "dev is ahead of main by {N} commits. Ship dev→main and deploy?"
```

`{N}` is a bare placeholder. **Nothing in `system/` computes `main..dev`** — a grep for
`rev-list --count` across the tree returns worktree-reaping logic and runner tests, and no
deploy-gap derivation at all. The template therefore invites filling the number from memory
or from a handoff note, which is precisely how the stale "12 commits ahead" was produced.

Two concrete gaps follow:

1. **No derivation.** close.md:227 should carry the command inline so the number cannot be
   supplied from recall:
   ```bash
   AHEAD=$(git rev-list --count main..dev)
   ```
   and skip the offer entirely when `AHEAD` is 0.
2. **Wrong host.** This lives in *build's* CLOSE, so it only fires after a build completes.
   `system/skills/close/` — `/brana:close`, the session-end ritual that runs every session —
   has **no ship check at all**. A session that ends without a build never sees the offer.
   Since AC3 concludes the trigger belongs in the recurring ritual, the check needs to exist
   there, not only on the build path.

Neither is implemented by this investigation — see "Follow-up" below.

## Follow-up

This is an investigation; it diagnoses and decides, it does not implement. The two gaps above
are a small, well-specified change to `system/skills/build/phases/close.md` and
`system/skills/close/`, and should be a separate task so the edit gets the pre-edit challenger
review that procedure-file changes require.

## AC5 — disposition of t-2214

**Close as superseded.** It describes a specific ship that ~21 later ships made moot. Keeping
it open asserts that a deploy is pending when the deploy in question happened many times
over. Its only durable content — "restart in-flight sessions after deploy" — is preserved in
AC2 above as risk #1.

## Incidental finding — convention violations on `main`

Not in scope, recorded because the reflog made them visible. All cluster in 2026-06-20…06-25:

- **5+ direct commits to `main`** (`chore(state)`, `chore(tasks)`, `chore(gitignore)`)
- **4 non-fast-forward merges** (`Merge made by the 'ort' strategy`)
- **3 feature branches merged straight into `main`** — `system/ops/t-1816-learning-sweep-cursor`,
  `docs/close/worktree-reap-active-lane`, `backlog-git-alignment/fix/t-2166-lock-tasks-json-writes`

CLAUDE.md forbids all three. **They stop after ~2026-06-25** — every promotion since
2026-07-17 is a clean `merge dev: Fast-forward`. The two-tier model appears to have been
genuinely adopted. Archaeology, not an active problem; no task filed.

## What would change this verdict

Stated so the finding can be falsified in turn:

- If ship events drop below roughly one a week while `dev` keeps growing, the loop hypothesis
  becomes live again and this document is wrong.
- If a promotion is ever rolled back and proves costly in practice, AC2's "rollback is cheap"
  needs revisiting — it currently rests on reading the deploy paths, not on a rehearsal.
