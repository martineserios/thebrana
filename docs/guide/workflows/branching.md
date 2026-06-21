# Branching — two-tier dev → main (ADR-060)

> thebrana uses the two-tier model from [ADR-060](../../architecture/decisions/ADR-060-branch-strategy-autonomous-agents.md):
> `dev` is the integration buffer, `main` is production (what `bootstrap.sh` deploys).
> The skills were wired to actually follow it on 2026-06-21 (t-2188) after `dev` had
> silently drifted 10 commits behind `main` because the build/close skills only ever
> targeted `main` directly.

## The two tiers

| Branch | Role | How it advances |
|--------|------|-----------------|
| feature (`{epic}/{type}/t-NNN-slug`) | one unit of work | branched **off `dev`** |
| **`dev`** | integration buffer — where humans + agents converge. **Nothing here is live.** | feature branches merge in (`--no-ff`); no deploy |
| **`main`** | **production** — what `bootstrap.sh` deploys to live `~/.claude/`. | advances **only** at ship: `dev→main` fast-forward, then `bootstrap.sh` |

**`main` lagging `dev` is the safety buffer** — that gap is the feature, not a problem to
close eagerly. Work accumulates and is validated on `dev`; production only moves when you
deliberately ship.

## Rules

- **Never commit to `main` directly, and never merge a feature branch into `main`.**
  Feature branches integrate to `dev` only.
- **Integration (per feature)** lands on `dev` — no deploy. `dev` is not live.
- **Ship (periodic, human-gated)** promotes `dev` to production *and* deploys:
  ```bash
  git checkout main
  git merge --ff-only dev          # dev→main stays a clean fast-forward
  ./bootstrap.sh                   # deploy production → live ~/.claude (from-main guard passes here)
  git push origin main dev         # publish the release + back up dev
  git checkout dev                 # return to the integration branch
  ```
  If `--ff-only` is rejected, `main` was touched directly (a convention violation) —
  **stop and investigate, do not force.**
- **`bootstrap.sh` deploys from `main` only** — the from-main guard (ADR-060 / t-2151)
  refuses any other branch, so you cannot accidentally ship staged `dev` work. Deploy is
  a ship-time action, never an integration-time one.
- **Session state** (`.claude/tasks.json`, `docs/spec-graph.json`) commits on the current
  branch — i.e. `dev` — never on `main`. (This was the original drift source.)
- Restart in-flight sessions after a ship — they still hold pre-deploy skill/hook state.

## Where it's enforced

- `/brana:build` CLOSE phase (`system/skills/build/phases/close.md`) integrates the feature
  branch to `dev` (no deploy), and offers the `dev→main` **ship** (merge + bootstrap) as its
  final, human-gated step.
- `/brana:close` (`system/skills/close/phases/`) reaps worktrees merged into `dev` and
  reconciles tasks against `dev` commits (`dev ⊇ main`).
- `bootstrap.sh` from-main guard (t-2151) blocks deploying from anything but `main`.

## Ship cadence

Ship `dev→main` when `dev` is stable — end of a work batch, or before stepping away. Not
per-feature. `main` should always be a coherent, deployed-and-known-good snapshot.

## Cross-repo

This two-tier model is brana's own per-project policy. ADR-060's **Layer-1 invariants**
(agents never push to production; isolated worktrees; human-gated promotion) are universal,
but the `dev`/`main` topology is **not** mandated for other repos — proyecto-anita,
`clients/*`, and `ventures/*` declare their own integration/production policy (client repos
often follow the client's process, deploy via Vercel/Cloud Run, etc.). A per-repo audit is
deferred — see t-2189.
