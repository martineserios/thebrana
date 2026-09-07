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
| **`main`** | **production** — what `bootstrap.sh` deploys to live `~/.claude/`. | advances **only** at ship: PR `dev→main` with required CI (branch-protected, t-3023), then `bootstrap.sh` |

**`main` lagging `dev` is the safety buffer** — that gap is the feature, not a problem to
close eagerly. Work accumulates and is validated on `dev`; production only moves when you
deliberately ship.

## Rules

- **Never commit to `main` directly, and never merge a feature branch into `main`.**
  Feature branches integrate to `dev` only.
- **Integration (per feature)** lands on `dev` — no deploy. `dev` is not live.
- **Ship (periodic, human-gated, tier-2 valve — t-3023)** promotes `dev` to production
  *and* deploys. `main` is branch-protected on GitHub: a pull request is required, the CI
  workflow's `validate` and `rust` checks must pass on the PR head (strict: the PR must be
  current with `main`), and `enforce_admins` is on — so a direct `git push origin main` is
  rejected for everyone, including the repo owner. No review approval is required (solo
  operator; the gate is the checks, not a rubber stamp). The procedure is `/brana:ship`:
  ```bash
  git push origin dev
  gh pr create --base main --head dev --title "ship: dev→main $(date +%F)" --body "..."
  gh pr checks --watch             # required: validate, rust, tests
  gh pr merge --merge              # merge commit onto main; refused until checks are green
  git branch --show-current        # must print: dev — the shared checkout never switches (ADR-094)
  git fetch origin main:main       # fast-forward local main BY REF; no working tree is touched
  git merge --ff-only main         # on dev, in place: fold the merge commit back, dev == main
  ./bootstrap.sh                   # deploy production → live ~/.claude (guard: HEAD == main's tip)
  git push origin dev
  ```
  Every ship therefore leaves a PR record (`gh pr list --base main --state merged`): what
  shipped, when, which sha, which checks. If the `--ff-only` is rejected, `main` diverged
  from `dev` outside this procedure — **stop and investigate, do not force.**
- **The shared main checkout stays on `dev` forever** ([ADR-094](../../architecture/decisions/ADR-094-tasks-json-ledger-in-git-common-dir.md)
  decision 5). Never `git checkout` / `git switch` a branch or tag in it — not for a ship,
  not for archaeology. It holds every concurrent session's untracked/ignored live state, and
  git overwrites *ignored* files without warning when checking out any ref that still tracks
  the same path (145 tags and old branches track `.claude/tasks.json`): that sequence wiped the
  backlog ledger on 2026-09-07. Need another ref materialised? `git worktree add ../thebrana-<ref> <ref>`.
  `validate.sh` Check 74 fails on any `git checkout main|dev` command line in skills/rules/guide/bootstrap.
- **`bootstrap.sh` deploys `main`'s content only** — the guard (ADR-060 / t-2151, widened by
  ADR-094) accepts being on `main` *or* HEAD == `main`'s tip (which is what `dev` is right
  after the ship's fast-forward), and refuses anything else, so you cannot accidentally ship
  staged `dev` work. Deploy is a ship-time action, never an integration-time one.
- **Session state** (`docs/spec-graph.json`, `system/state/`) commits on the current
  branch — i.e. `dev` — never on `main`. (This was the original drift source.) The backlog
  ledger itself is no longer git-tracked (ADR-091) and is moving under `.git/brana/` (ADR-094);
  its history is the periodic snapshot (t-3287), not per-session commits.
- Restart in-flight sessions after a ship — they still hold pre-deploy skill/hook state.

## Where it's enforced

- `/brana:build` CLOSE phase (`system/skills/build/phases/close.md`) integrates the feature
  branch to `dev` (no deploy), and offers the `dev→main` **ship** (merge + bootstrap) as its
  final, human-gated step.
- `/brana:close` (`system/skills/close/phases/`) reaps worktrees merged into `dev` and
  reconciles tasks against `dev` commits (`dev ⊇ main`).
- `bootstrap.sh` guard (t-2151, ADR-094) blocks deploying anything that is not `main`'s tip.
- `validate.sh` Check 74 (`system/scripts/check-no-checkout-in-main.sh`, t-3327) fails on any
  `git checkout main|dev` / `git switch main|dev` command line in `system/skills`, `system/rules`,
  `system/procedures`, this guide, `.claude/CLAUDE.md`, `bootstrap.sh`, or the `brana deploy` hint.
- GitHub branch protection on `main` (t-3023, t-3319): required pull request (0 approvals), required
  status checks `validate` + `rust` + `tests` (strict), `enforce_admins` — verifiable with
  `gh api repos/{owner}/{repo}/branches/main/protection`.

## Ship cadence

Ship `dev→main` when `dev` is stable — end of a work batch, or before stepping away. Not
per-feature. `main` should always be a coherent, deployed-and-known-good snapshot.

## Fast-track exception: schema-sealing / retired-field commits

A narrow exception to the ship cadence above, for one specific class of commit.

- **What qualifies:** a commit that adds or enforces a retired-field / schema-write
  guard — e.g. adding an entry to a `RETIRED_FIELDS` constant, or hardening a write
  path's field whitelist. [ADR-067](../../architecture/decisions/ADR-067-retired-fields-write-guard.md)
  is the origin case.
- **Why it's an exception:** ordinary feature lag between `dev` and `main` is harmless
  — a stale binary just lacks new behavior. Schema-sealing lag is not: a `brana` /
  `brana-mcp` binary built *before* the sealing commit landed on `dev` doesn't know a
  field is retired, and can actively write corrupted data into the one shared,
  unversioned `tasks.json` for as long as it stays live and un-shipped. That's a
  corruption hazard, not a missing-behavior hazard — see
  [ADR-067](../../architecture/decisions/ADR-067-retired-fields-write-guard.md)'s
  Consequences section.
- **What "fast-track" means concretely:** don't wait for the normal "end of a work
  batch" trigger from Ship cadence above. As soon as a schema-sealing commit lands on
  `dev`, run the same [ADR-060](../../architecture/decisions/ADR-060-branch-strategy-autonomous-agents.md)
  ship sequence promptly — through the PR valve, exactly as above (`/brana:ship`): push `dev`,
  open/merge the CI-gated PR, then in place on `dev`:
  ```bash
  git fetch origin main:main       # by ref — never checkout
  git merge --ff-only main
  ./bootstrap.sh
  git push origin dev
  ```
  Then restart any in-flight sessions holding an old MCP/CLI process — shipping alone
  doesn't reload a binary a session is already running.
- **Scope:** this exception is narrow — it applies only to commits that add or enforce
  a retired-field or schema-write guard. It does **not** relax the normal batch cadence
  in "Ship cadence" above for anything else; ordinary features, fixes, and docs still
  wait for a normal ship batch.

## Cross-repo

This two-tier model is brana's own per-project policy. ADR-060's **Layer-1 invariants**
(agents never push to production; isolated worktrees; human-gated promotion) are universal,
but the `dev`/`main` topology is **not** mandated for other repos — proyecto-anita,
`clients/*`, and `ventures/*` declare their own integration/production policy (client repos
often follow the client's process, deploy via Vercel/Cloud Run, etc.). A per-repo audit is
deferred — see t-2189.
