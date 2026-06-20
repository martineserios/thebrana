---
status: accepted
---
# ADR-060: Branch Strategy for Autonomous Agents (two-tier dev/main + worktree-per-actor)

**Status:** Accepted (2026-06-20)
**Date:** 2026-06-20
**Deciders:** Martín Rios
**Tags:** branching, agents, autonomous, worktree, git, architecture
**Tasks:** t-2145 (this ADR), t-2140 (autonomous runner), t-2144 (run-batch lock), t-2138 (secret-scan gate)
**Extends:** [doc 19 Branch Strategy](../../19-pm-system-design.md) (GitHub Flow) · [ADR-059](ADR-059-multi-agent-substrate-selection.md) · [autonomous-runner feature spec](../features/autonomous-runner.md)

---

## Context

The autonomous runner (t-2140) commits code **unattended** with write access to the repo. Doc 19 already chose **GitHub Flow** (one `main`, short-lived feature branches, PR-per-branch) — but that was written for *human* commits, with the explicit note "do NOT require PR approvals (you're solo)." Two facts force a refinement:

1. **Agent commits need a stricter gate than human commits.** For unattended work, the human review *is* the safety mechanism. A human can direct-push a typo; a robot must never touch the production line.
2. **The operator works fast and solo and "gets mixed."** Working directly against the branch that is *deployed* feels unsafe. There is a real need for a non-production working line.

A constraint also shapes the choice: the design must **scale to a future collaborator without re-plumbing** — a person may join later.

Two grounding realities:
- **brana's real production boundary is `bootstrap.sh`** — it deploys from `main` into the live `~/.claude/`. So `main` = deployed; anything not yet on `main` = staged. This is a genuine environment distinction, not a metaphor.
- brana has **no separate staging/prod servers**, so a full `dev/stage/prod` environment-branch model would map branches to environments that do not exist (ceremony).

Research (2026) converges with doc 19: trunk-ish topology targeting one mainline, **git worktree per agent** as the load-bearing isolation primitive, a required human merge gate, and automated stale-branch reaping (the repo carries ~15 orphan branches).

## Decision

Adopt a **two-tier `dev` → `main`** model with **worktree-per-actor** isolation and a **human promotion gate**. Treat agent contributions identically to a teammate's.

### The two branches

| Branch | Role | Protection | Who promotes |
|--------|------|-----------|--------------|
| **`main`** | **Production** — what `bootstrap.sh` deploys to live `~/.claude/`. Stable, released. | Hard: no direct push (human or agent), require `validate` status check, no force-push, no deletion. | Human only, deliberately, via PR `dev`→`main` ("ship"). |
| **`dev`** | **Integration line** — default branch. Where humans *and* agents converge. Nothing here is live. | Light: PR-per-branch, status check; meant to move fast. | Anyone via reviewed PR. |

`main` lagging `dev` is **the feature, not the tax** — that lag is the safety buffer. **Merge to `main` = ship** (then run `bootstrap.sh`).

### Flow (uniform for humans and agents)

```
actor (you / teammate / agent) → feature branch in its OWN worktree, cut from dev
                               → PR → dev   (human-reviewed)
when dev is stable:  dev → main   (human promotion = ship → bootstrap)
```

- **Agents:** the runner cuts `runner/auto/<id>` from `dev` in an **ephemeral worktree** (off a stable base, never the live checkout), works/verifies/commits there, opens a PR into `dev`, and **removes the worktree on exit** (success/failure/signal). It never merges, never marks the task complete, never sees `main`.
- **Humans:** same shape — branch off `dev` (worktree encouraged for parallel work), PR into `dev`.
- Naming unchanged: agents `runner/auto/<id>`; humans `{epic}/{type}/t-{NNN}-{slug}` (doc 19).

### Worktree-per-actor (isolation primitive)

Each branch gets its **own worktree** with its own `.git/index`, cut from a stable base:
```bash
git fetch origin
git worktree add /tmp/brana-runner/<id> -b runner/auto/<id> origin/dev
#   edits + validate + commit happen ONLY inside the worktree
git worktree remove --force /tmp/brana-runner/<id>   # always, via trap
```
This contains blast radius (the live tree and `main`/`dev` are never modified in place), removes working-tree/index collisions so multiple actors run in parallel, and makes the base explicit (eliminating the detached-HEAD invariant gap — base is `origin/dev`, never an empty `git branch --show-current`).

### Team mode (designed now, dormant until a collaborator joins)

When a person joins, **flip settings on — do not change topology**:
- Require **1 PR approval** on `dev` and `main`.
- Add **CODEOWNERS**.
- Require **branch up-to-date** before merge.
- Enable **merge queue** on `main` (and `dev` if concurrent PR volume warrants) — batches + re-tests, replacing any urge to add an integration branch.

Because agent PRs are already treated as a contributor's PRs, a human teammate is just *another actor in the identical flow*. Nothing restructures.

## Consequences

- **The detached-HEAD / empty-BASE bug (sweep finding, 2026-06-20) is resolved by construction** — the runner cuts from `origin/dev` in a worktree, so there is no implicit base to lose.
- **Safety net composes here:** worktree isolation (this ADR) + `--run-batch` lock (t-2144) + secret-scan pre-commit gate (t-2138) + consecutive-failure kill (t-2140) together gate autonomy. **t-2138 is a precondition** for ever enabling push: an autonomous commit must be secret-scanned (the 2026-06-20 `xoxb` token incident proved the existing scan misses tokens).
- **One extra step:** the deliberate `dev`→`main` promotion. Accepted — it is the production gate.
- **`bootstrap.sh` semantics sharpen:** dev = staged, main = deployed. Bootstrap runs on promotion to `main`.
- **Stale-branch reaping becomes routine** — a weekly job deletes merged `runner/auto/*` and reaps stale branches; the ~15 existing orphans get a one-time sweep.
- **Doc 19 is amended, not replaced:** GitHub Flow's single-mainline spirit holds; `dev` is the integration tier and the "no required approvals" note now applies only to *human direct pushes on trivial changes*, never to agents.

## Open questions (not decided here)

1. **Where does `validate` run as a required check** — local pre-merge only, or GitHub Actions CI? Branch protection's "require status check" needs a CI run to gate on. Decide when wiring branch protection (may piggyback existing CI).
2. **Merge queue now or on first collaborator?** Lean: enable when concurrent PR volume (overnight agent batches) actually causes "passed alone, broke together." Until then, sequential review suffices.

## Alternatives considered

- **Stay main-direct (GitHub Flow as-is).** Rejected — gives the operator no non-production working line; "merge to main = ship" with no buffer is risky for fast solo work + unattended agents.
- **Full `dev/stage/prod` environment branches.** Rejected — brana has no separate staging/prod environments; two of the three branches would map to nothing. A collaborator is not an environment. Slot `stage` in later *if* a hosted environment appears.
- **Integration via `dev` branch but agents target `main` directly.** Rejected — splits the model (agents on one flow, humans on another); breaks the "uniform contributor" property that makes team-mode a settings flip.
