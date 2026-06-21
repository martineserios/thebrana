# Branching — dev-first integration model

> thebrana uses a **dev-first (dev-is-live)** branch model. `dev` is where you work and
> what is deployed; `main` is a blessed release snapshot. Established 2026-06-21 (t-2188)
> after `dev` silently drifted 10 commits behind `main` because the skills only ever
> targeted `main`.

## The three roles

| Branch | Role | How it advances |
|--------|------|-----------------|
| feature (`{epic}/{type}/t-NNN-slug`) | one unit of work | branched **off `dev`** |
| **`dev`** | integration **+ live** branch — what you work on and what `./bootstrap.sh` deploys | feature branches merge in (`--no-ff`); auto-deploys on merge so changes go live immediately |
| **`main`** | blessed **release** snapshot | advances **only** via a deliberate `dev→main` fast-forward release (periodic, not per-feature) |

## Rules

- **Never commit to `main` directly, and never merge a feature branch into `main`.**
  Feature branches integrate to `dev` only.
- `main` advances solely by a release:
  ```bash
  git checkout main
  git merge --ff-only dev          # dev-first keeps this a clean fast-forward
  git push origin main dev         # publish the snapshot + back up dev
  git checkout dev                 # return to the live/integration branch
  ```
  If `--ff-only` is rejected, `main` was touched directly (a convention violation) —
  **stop and investigate, do not force.**
- **Session state** (`.claude/tasks.json`, `docs/spec-graph.json`) commits on the current
  branch — i.e. `dev` — never on `main`. This was the original drift source.
- **"Deploy"** = `./bootstrap.sh` run from `dev` (dev-is-live). A *release* is the snapshot
  to `main`, not the deploy. (Supersedes the old "deploy = merge to main" rule.)

## Where it's enforced

- `/brana:build` CLOSE phase (`system/skills/build/phases/close.md`) integrates the feature
  branch to `dev`, auto-deploys, and offers the `dev→main` release as its final step.
- `/brana:close` (`system/skills/close/phases/`) reaps worktrees merged into `dev` and
  reconciles tasks against `dev` commits (`dev ⊇ main`).

## Release cadence

Cut a `dev→main` release when `dev` is stable — end of a work batch, or before stepping
away. Not per-feature. `main` should always be a coherent, deployable snapshot.

## Cross-repo

This model is **thebrana-only** for now. proyecto-anita, `clients/*`, and `ventures/*`
keep their own workflows (client repos often follow the client's process). A uniform
dev-first rollout across repos is deferred — see t-2188 scope.
