---
status: accepted
---
# ADR-060: Branch Strategy for Quality Work at Speed & Scale (universal invariants + per-project policy)

**Status:** Accepted (2026-06-20; amended same day after challenger review — t-2145)
**Date:** 2026-06-20
**Deciders:** Martín Rios
**Tags:** branching, agents, autonomous, worktree, git, architecture, substrate
**Tasks:** t-2145 (this ADR), t-2146 (runner worktree+base), t-2147 (dev branch+protection), t-2150 (invariant tests), t-2144 (run-batch lock), t-2138 (secret gate), t-2148 (reaping), t-2151 (bootstrap guard)
**Extends:** [doc 19 Branch Strategy](../../19-pm-system-design.md) (GitHub Flow) · [ADR-059](ADR-059-multi-agent-substrate-selection.md) · [autonomous-runner feature spec](../features/autonomous-runner.md)
**Amends:** [git-discipline.md](../../../system/rules/git-discipline.md) (scopes the "agents can't write to worktrees" rule — see Consequences)

---

## Context

The multi-agent substrate (ADR-059) — subagents, workflows, loops, the autonomous runner — is **one development system for all work**, run across every repo: `thebrana` itself, `clients/*` (each its own git repo), `ventures/*`, `personal/*`. The goal is **quality work at speed and scale**: the *invariants* below buy quality and scale; worktree parallelism + a fast integration line buys speed.

This ADR is the branch strategy for that system. **brana is the first adopter of its own system** — it dogfoods the model it ships. (This session is the proof: brana's own sweep/hive-mind/challenger found real bugs in brana's own freshly-merged code.)

A first draft of this ADR reasoned entirely from one brana-specific fact ("`main` = what `bootstrap.sh` deploys") and prescribed a single topology. A challenger review (t-2145, 2026-06-20) found that fatal for a portfolio-wide substrate: client repos have no `dev` branch, deploy via Vercel/Cloud Run, and define their own environments; libraries ship via release tags; personal repos have no "production" at all. One hardcoded topology is wrong. The fix is to separate **what is universal** from **what each project declares**.

Two grounding realities the strategy must respect:
- Different repos have different *production* definitions: brana → `main` (bootstrap-deployed); a client web app → a deploy target (Vercel/Cloud Run); a library → a release tag; personal → none.
- The runner today does **not** yet implement worktree isolation — it cuts `runner/auto/<id>` from the ambient `git branch --show-current` in the live tree (`autonomous-runner.sh`). The model below is the **decided target**; implementation is tracked in t-2146 and is a precondition for live autonomy.

## Decision

### Layer 1 — Universal invariants (every repo, non-negotiable, enforced in the substrate)

These hold regardless of a project's topology. They are the runner's contract:

1. **An agent never pushes to the project's production/default branch.** It only ever opens a PR into the configured *integration branch*.
2. **An agent works in an isolated, ephemeral worktree** cut from a stable base (the integration branch), not the live checkout. Removed on every exit path (success/failure/signal).
3. **A human gates promotion to production.** The agent never merges and never marks a task complete.
4. **Every unit is isolated and revertable** — one branch + one worktree per task; failure contained to that worktree.

### Layer 2 — Per-project policy (declared per repo, sane default)

What each repo declares (the substrate reads it; never hardcodes):

- **Integration branch** — where agents/humans branch from and PR into. `RUNNER_BASE_BRANCH`, declared in the repo's `.claude/CLAUDE.md`. **Default: `dev`.**
- **Production/release mechanism** — branch (`main`), deploy target, or release tag. The agent must avoid pushing to it directly.
- **Staging tier?** — add a `stage` branch only if a real hosted environment exists.

Discovery precedence: `RUNNER_BASE_BRANCH` env (set by the repo's scheduler job) → the repo's `.claude/CLAUDE.md` declaration → **default `dev`, and if `dev` doesn't exist, fall back to the repo default branch with a logged warning** (never silently target production).

### brana's own policy (first adopter — two-tier `dev` → `main`)

| Branch | Role | Protection |
|--------|------|-----------|
| **`main`** | Production — what `bootstrap.sh` deploys to live `~/.claude/`. | Hard: no direct push, require `validate`, no force-push/deletion. |
| **`dev`** | Integration line — where humans + agents converge. Nothing here is live. | Light: PR-per-branch, status check; moves fast. |

`main` lagging `dev` **is the safety buffer** (the feature). **Merge `dev`→`main` = ship** (then `bootstrap.sh`). `dev` is the *integration* branch; whether it is the GitHub *default* branch is a separate, optional, per-repo choice — **do not blanket-switch defaults** (it retargets PRs and breaks CI/deploy triggers; for a client whose deploy fires on `main`, keep `main` as default).

### Flow (uniform for humans and agents, every repo)

```
actor → feature branch in its OWN worktree, cut from <integration branch>
      → PR → <integration branch>   (human-reviewed)
human promotes <integration> → <production>   = ship
```

### Team mode (designed now, dormant until a collaborator joins)

When a person joins, **flip settings on — topology unchanged**: require 1 PR approval, CODEOWNERS, branch-up-to-date, merge queue. Because agent PRs are *already* treated as a contributor's PRs, a human teammate is just another actor in the identical flow. **Today these are not configured** — `dev`→`main` currently has no automated gate beyond local pre-commit hooks; enforcement is deferred, not active.

## Consequences

- **Portable by construction.** The runner gains `RUNNER_BASE_BRANCH` (per-project, default `dev`); `gh pr create` hardcodes `--base "$RUNNER_BASE_BRANCH"` with a preflight abort if that branch is absent (fixes the bug where `--base "$BASE"` could target `main` directly). Tracked in **t-2146**.
- **The worktree model is decided, not yet built.** Today the runner cuts from ambient HEAD in the live tree; t-2146 implements `git worktree add … <base>`. Until then, blast-radius containment and the "detached-HEAD resolved by construction" property **do not hold** — the run-batch mode must be triggered manually, never via overlapping scheduler intervals, until t-2146 + **t-2144** (the lock) ship.
- **Amends `git-discipline.md`.** That rule ("agents can't write to worktrees — compose in agent, write in main context") is scoped to **in-session Claude Code agents** (Task tool, CWD-bound). The autonomous runner uses a **`claude -p` subprocess** `cd`'d into its worktree, which *may* write there. The rule is updated to state this scope.
- **`bootstrap.sh` needs a from-`main` guard** (it currently deploys from whatever branch is checked out → could ship staged `dev` work). Tracked in **t-2151**.
- **Migration is a real, risky step, not a toggle.** Creating `dev` + (optionally) changing the GitHub default cascades: PR retargeting, CI triggers, Vercel auto-deploy. Tracked with explicit steps in **t-2147**; the strategy is *accepted* but brana's repo does not yet match it until t-2147 runs.
- **Safety net composes (in dependency order):** worktree isolation (t-2146) → run-batch lock (t-2144) → secret-scan gate (t-2138, **precondition for any autonomous push**) → consecutive-failure kill (t-2140) → invariant tests (t-2150). None is "in force now" beyond the kill; do not enable live autonomy until A-phase lands.

## Non-actions (explicitly out of scope)

- **Does not mandate two-tier for client/venture/personal repos.** Each declares its own integration/production policy. A Vercel client may set integration=`main` and rely on preview URLs; a library may keep trunk + release tags. Only the Layer-1 invariants are mandatory.
- **Does not add `stage`/`prod` environment branches** to any repo lacking the corresponding hosted environment.
- **Does not change any repo's default branch** as a blanket rule — that is a per-repo, opt-in decision.

## Open questions

1. **Where does `validate` run as the required status check** — local pre-merge or GitHub Actions CI? Needed to gate branch protection. Decide in t-2147.
2. **Per-project policy schema** — exact `.claude/CLAUDE.md` declaration format (a `> Branch-policy: integration=dev, production=main` marker vs a config block). Settle when t-2146 implements discovery.

## Alternatives considered

- **One hardcoded topology (the first draft).** Rejected by challenger — not portable; breaks in client/library/personal repos.
- **Stay main-direct (GitHub Flow as-is).** Rejected — no non-production working line for fast solo work + unattended agents.
- **Full `dev/stage/prod` everywhere.** Rejected — maps branches to environments that mostly don't exist; a collaborator is not an environment.
- **Scope this ADR to brana only + a second substrate ADR.** Rejected — one unified system is the point; brana is its first instance, not a separate regime.
