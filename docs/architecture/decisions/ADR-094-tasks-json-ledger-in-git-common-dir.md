---
status: proposed
amends: docs/architecture/decisions/ADR-091-tasks-json-untracked-canonical-snapshot.md
extends: docs/architecture/decisions/ADR-060-branch-strategy-autonomous-agents.md
informs: docs/domain/MODEL-001-brana-core.md
---

# ADR-094: Move the live `tasks.json` ledger out of the working tree into `$GIT_COMMON_DIR/brana/`

**Status:** Proposed (2026-09-07) — pending review by the decider; recommend `/brana:challenge` before acceptance
**Date:** 2026-09-07
**Deciders:** Martín Rios
**Tags:** tasks-json, worktree, git, incident, harness, ship
**Tasks:** t-3322 (this ADR) · t-3323 (tests) · t-3324 (move + migration) · t-3325 (fail loud) · t-3326 (backups) · t-3327 (ship procedure) · t-3328 (post-checkout backstop) · t-3329 (Gate 3 rule) · t-3287 (git snapshot, re-scoped) · t-3288/t-3289 (docs sync) — all under umbrella t-3282
**Amends:** [ADR-091](ADR-091-tasks-json-untracked-canonical-snapshot.md) — supersedes its decision 1 (*where* the untracked ledger lives); decisions 2–5 (locking, merge driver on the snapshot, snapshot ownership, event-triggered flush) stand unchanged
**Extends:** [ADR-060](ADR-060-branch-strategy-autonomous-agents.md) (two-tier branch model — constrains how the ship touches the shared checkout)

---

## Context

### The incident (2026-09-07, ~19:41 -03)

Three days after ADR-091 untracked `.claude/tasks.json`, the first `dev → main` ship that carried
that change (PR #1075) **wiped the live backlog ledger** — 3199 tasks — on the shared main
checkout, with no error and no warning. The ship followed the documented Tier-2 procedure
(`system/skills/ship/SKILL.md` §Step 2) to the letter:

```
 dev (post-ADR-091)                  main (pre-ship, @9b8bba5e)
 .claude/tasks.json IGNORED    →     .claude/tasks.json TRACKED (stale blob from PR #1072)
 live, 3199 tasks, uncommitted
        │
        │  git checkout main            git treats IGNORED files as expendable: it overwrote
        ├─────────────────────────────► the live file with main's stale blob. No warning.
        │                               (an untracked-but-NOT-ignored file WOULD have been
        │                               protected — "would be overwritten by checkout")
        │  git merge --ff-only origin/main
        ├─────────────────────────────► new main (e2f7f36e) untracks the path → git DELETED it.
        │
        │  next brana call → find_tasks_file_from() (util.rs:195): file missing →
        └─────────────────────────────► silently wrote {"tasks":[]}. Every tool kept "working".
```

Detection was accidental: a `backlog_batch` returned `task t-3285 not found`. Reproduced
deterministically in a scratch repo (git 2.53.0): track a file → branch untracks it via
`rm --cached` + `.gitignore` → write live content → `git checkout` the old branch → live content
replaced; → fast-forward past the untracking commit → file gone. Two lines, no output.

**Recovery.** Restored the last git-tracked blob (`76c83d1e`, 15:46:44 -03, 3199 tasks) and
replayed this session's own edits from its transcript. Mining the JSONL transcripts of all 45
sessions active in the window showed **zero** backlog writes to thebrana's ledger from any
other session (the 83 other hits were proyecto_anita / bemol sessions writing to their own
ledgers — the CLI resolves by cwd), the ID counter (`next_id` = max+1) corroborated it, and no
scheduler job that ran in the window writes tasks. Net loss: none. Net exposure: ~7 hours of
edits that survived only because nothing else happened to write in that window.

### Why ADR-091 did not close this

ADR-091 §Context named the hazard precisely — "ordinary git operations in the main checkout
(`checkout`, `merge`, `stash pop`, `reset`) can silently clobber the live, actively-flock-written
file" — and concluded that untracking the file takes it out of git's reach. It does not, for
two reasons the ADR did not model:

1. **Git protects untracked files but clobbers ignored ones.** Checkout refuses to overwrite
   an untracked file that a target commit tracks (`error: The following untracked working tree
   files would be overwritten by checkout`). The moment the path is listed in `.gitignore` —
   which ADR-091 decision 1 requires — that protection is withdrawn: ignored files are, by
   git's definition, safe to destroy. There is no "precious" attribute in mainline git.
2. **This is not a transition window. It is permanent.** 145 of this repo's 156 refs still
   track `.claude/tasks.json`: every release tag `v1.0.0`…`v1.80.1` and ~25 older branches.
   Any `git checkout v1.79.0` for archaeology, any old branch, any `git bisect` across the
   untracking commit, in the main checkout, wipes the live ledger again. History is immutable
   (tags are published releases), so the set of dangerous refs never shrinks.

Three further causes compounded it:

3. **Silent failure.** `find_tasks_file_from()` auto-creates `{"tasks":[]}` at every resolution
   tier when the file is missing. A recoverable deletion became an invisible empty backlog
   that every CLI/MCP call happily read and wrote.
4. **The ship procedure contradicts git discipline.** `git-discipline.md` bans branch
   switching in the shared checkout for feature work (worktrees only), but the ship skill's
   Tier-2 sequence does `git checkout main … git checkout dev` in exactly that checkout — the
   one directory where the live ledger, and every concurrent session's untracked state, lives.
5. **The safety half shipped after the dangerous half, and the gate was overridden.** ADR-091
   sequenced t-3287 (snapshot + restore) after t-3285 (untrack). Gate 3 flagged the missing
   half at HIGH confidence (2/3 reviewers); the override was granted as an "accepted ADR-091
   trade-off". ADR-091's trade-off text analysed *fresh clones* and *machine loss* — never the
   routine ship path. A documented risk is still a live risk; "tracked follow-up" is not a
   mitigation.

### The property that matters

The file's *location*, not its tracking status, is the safety property. A file inside the
working tree at a path git has ever tracked in any reachable ref can never be made safe from
checkout. A file under `$GIT_DIR` can: git never reads, writes, deletes or cleans unknown
content inside its own directory during `checkout`, `switch`, `merge`, `reset`, `stash`,
`clean -xdf`, `gc` or `worktree` operations. And `git rev-parse --git-common-dir` — already
ADR-091's cross-worktree sharing mechanism — resolves to the same directory from every
worktree of a repo.

## Decision

1. **The canonical ledger lives at `$(git rev-parse --git-common-dir)/brana/tasks.json`**
   (i.e. `.git/brana/tasks.json` in the main checkout), together with its `tasks.json.lock`
   sidecar. `find_tasks_file_from()` resolves there first for any git repo. The worktree-
   toplevel tier is **removed** for git repos — it is the stale-copy shadowing path that
   t-3286 and t-3305 keep fixing, and a git repo always has a common dir. The cwd tier
   (`<cwd>/.claude/tasks.json`) survives only for non-git projects, where no checkout hazard
   exists. Cross-project access via the portfolio slug (`project:` param) resolves through the
   same function and follows automatically. — *t-3324*

   **Scope (portfolio):** `find_tasks_file_from()` is one shared binary used by every repo in
   the portfolio (clients, ventures, personal), most of which still *git-track*
   `.claude/tasks.json` and never had this hazard. The relocation applies **only where the
   ledger is untracked** — the resolver checks `git ls-files --error-unmatch .claude/tasks.json`
   in the common root: tracked → keep using it, no migration, no hazard; untracked/ignored (or
   absent) → `.git/brana/tasks.json`. A repo adopts ADR-091 + ADR-094 as one explicit,
   per-repo step (`git rm --cached` + `.gitignore` + migration in the same commit), never as a
   side effect of upgrading the binary. — *t-3324*

2. **Migration is explicit, idempotent and refuses ambiguity.** `bootstrap.sh` and the CLI's
   first use in a repo: if `.git/brana/tasks.json` is absent and `<common-root>/.claude/tasks.json`
   holds >0 tasks, *move* it (rename, with the lock sidecar) and say so; if both exist and
   differ, stop and print both paths and counts — never choose silently. The
   `.claude/tasks.json` `.gitignore` line stays one release as a net for stragglers. — *t-3324*

   **Rollout (split-brain guard):** `brana-mcp` servers already running in other sessions
   keep the *old* binary after a ship. Left alone, they would find `.claude/tasks.json` gone,
   auto-create an empty ledger there and write to it while new binaries write to
   `.git/brana/` — two diverging ledgers, silently. So the migration (a) leaves a **marker**
   at the old path that is deliberately *not* valid ledger JSON
   (`MOVED — see .git/brana/tasks.json (ADR-094); restart this Claude Code session`), which
   old binaries fail to parse loudly instead of resurrecting an empty ledger, and which new
   binaries recognise as "already migrated"; (b) runs from `bootstrap.sh` at ship time, which
   prints "restart every Claude Code session" in red; and (c) `brana doctor` and the
   session-start gauge (t-3332) warn while any `brana-mcp` process older than the installed
   binary is alive. — *t-3324, t-3332*

3. **Fail loud; never fabricate a ledger.** `find_tasks_file_from()` no longer creates
   `{"tasks":[]}` anywhere. A missing ledger in a git repo is an error naming the path and the
   two legitimate ways out (`brana backlog init` for a genuinely new project; restore a backup
   or the git snapshot). `save_tasks()` refuses a write that drops the task count to 0 or by
   more than 50% unless explicitly forced (`--force` / `force: true`, denied to the runner
   manifest and absent from every scheduler command). — *t-3325*

4. **Every write leaves a backup.** Before each successful save, the previous ledger is copied
   to `.git/brana/backups/tasks.json.<UTC-ts>.json`; the newest N (default 20, ~100 MB cap) are
   kept. `brana backlog backups list|restore`. This bounds any future loss — whatever destroys
   the file — to one write. It complements, not replaces, t-3287's git snapshot, which owns
   history/blame and off-machine recovery. — *t-3326, t-3287*

5. **The shared main checkout stays on `dev`, forever.** The ship fast-forwards `main` by ref
   only (`git fetch origin main:main`), runs `bootstrap.sh` from a persistent `../thebrana-main`
   worktree, and fast-forwards `dev` in place. No `git checkout <branch|tag>` in the main
   checkout, by anyone, for any reason — a `validate.sh` check greps the ship/build/close skills
   for it, and `git-discipline.md` states the rule. This is defense in depth: even with the
   ledger safe under `.git/`, the main checkout holds every concurrent session's other
   untracked state. — *t-3327*

6. **`post-checkout` backstop.** Git has no pre-checkout hook, so prevention at the git layer is
   impossible; detection + restore is the strongest backstop available. After any HEAD change,
   if the canonical ledger is missing or its count collapsed versus the newest backup, restore
   that backup, print a banner naming the ref transition, exit non-zero. — *t-3328*

7. **Gate 3: a "removes a safety mechanism before its replacement lands" finding is not
   overridable.** The only paths are *fix before deploy* or *abort*. Any accepted trade-off in
   a Gate 3 synthesis must name the concrete operational paths (ship, close, runner, scheduler,
   fresh clone) that were checked against it. — *t-3329*

Decision order (TDD/M+ discipline): this ADR → t-3323 failing tests → t-3324/3325/3326/3328
implementation → t-3287 snapshot on the new path → t-3288/t-3289 docs. t-3327 and t-3329 are
independent of the Rust changes and can land first.

## Consequences

**Easier:**
- The 145 refs that track `.claude/tasks.json` become permanently harmless; tags and old
  branches can be checked out (in a worktree) without thought.
- Worktree sharing needs no resolution heuristics at all: one path, derived from the common
  dir, no fallback tier that can shadow it. t-3305's four sibling hooks become a one-line fix.
- A wipe becomes impossible to miss (decision 3) and cheap to undo (decision 4).
- The ship no longer touches the shared checkout's working tree (decision 5).

**Harder:**
- Every literal `.claude/tasks.json` path in hooks, scripts, tests and docs must move
  (t-3324 lists them). The `brana-cli.md` rule "never Read/Write tasks.json directly" keeps its
  intent with a new path; the `post-tasks-validate.sh` PostToolUse matcher follows.
- `.git/` is not a place people look. `brana doctor` and `brana backlog status` must print the
  resolved path, and `bootstrap.sh --check` must report ledger health, so the location is
  discoverable.
- Deleting `.git/` (re-clone) deletes the ledger with it — the same as deleting the repo
  directory today. Decision 4 plus t-3287's snapshot are the recovery path; `bootstrap.sh`
  restores from the newest available source and never proceeds silently on an empty ledger.
- Until t-3324 lands, the interim rule is manual: nobody checks out a branch or tag in the main
  checkout. The recovered ledger is backed up at `~/.claude/tasks-json-backups/`.

## Non-actions (explicitly out of scope)

- **Rewriting history** to remove `.claude/tasks.json` from the 145 refs. Tags are published
  releases; the hazard is closed by relocation, not by mutating history.
- **Moving the ledger outside the repo** (`~/.local/state/brana/<repo-id>/`). Rejected: loses
  "travels with the directory", needs a repo-identity mapping, and gains nothing over
  `.git/brana/` for the checkout hazard.
- **Changing the locking / atomic-write machinery** (ADR-091 decision 2). Untouched.
- **Changing the snapshot file's location** (`system/state/tasks-snapshot.json`, ADR-091
  decision 3–5). The merge driver keeps pointing there; only the *source* it snapshots moves.

## Open questions

1. Should `brana backlog init` require an interactive confirmation when *any* backup or
   snapshot exists for the repo (to make "I meant a fresh ledger" impossible to do by
   accident)? Leaning yes.
2. Backup rotation count and cap: 20 × ~5 MB is the proposal; a busy day of runner beats may
   want time-bucketed retention (hourly for a day, daily for a week) instead of a flat N.
3. Whether the post-checkout hook should also guard other live state in the main checkout
   (`.claude/sessions/`, `inbox/`) — same failure class, different files. Probably a
   follow-up, not this ADR.

## Alternatives considered

| Alternative | Why not |
|---|---|
| Keep `.claude/tasks.json`, add only fail-loud + backups + procedure + hook | Mitigates but does not close the class: 145 refs remain a permanent trigger; a single forgotten `git checkout` still destroys live state (now recoverable, still disruptive to every concurrent session). |
| `.git/info/exclude` instead of `.gitignore` | Identical semantics — excluded files are still "ignored" and clobbered on checkout. |
| Git `precious` attribute | Proposed upstream for years; not in mainline git as of 2.53. |
| Symlink `.claude/tasks.json → ../.git/brana/tasks.json` | Checkout to a tracking ref replaces the symlink with a regular file; the data survives but the CLI would start writing to the wrong file until noticed. Adds a second thing that can be wrong. |
| Procedure only ("never checkout in the main checkout") | Adopted as decision 5, but as defense in depth — procedures are the weakest layer (see `enforcement-systems-overbuild-then-revert` and the fact that the ship skill itself was the violator). |
| Block the ship until t-3287 landed (what Gate 3 asked for) | Would have prevented *this* incident but not the class — t-3287's snapshot does not stop a checkout from wiping the live file; it only shortens the recovery. Adopted as decision 7 for the process gap it exposed. |

## Review record

- 2026-09-07: drafted by the session that caused and recovered the incident; audit evidence
  (scratch-repo reproduction, transcript mining of the lost window, ref census) is in t-3322's
  context and this session's close. Not yet challenged. Recommended before acceptance:
  `/brana:challenge --deep` with the systems lens on decision 1's migration edge cases
  (two ledgers present; worktrees created before migration; non-git projects) and on decision
  3's collapse threshold (legitimate bulk archives).
- 2026-09-07 (later), Gate 3 completeness review of the first ship after the incident:
  **decisions 5 and 7 were implemented and enforced (validate.sh Check 74, the bootstrap
  guard, the rewritten ship/close/branching/git-discipline text, the Gate 3 rule) while this
  ADR was still `proposed`** — enforcement ran ahead of acceptance, under incident pressure.
  Named here rather than hidden: both are narrow, incident-driven hardenings independent of
  the contestable decisions (1–4), each shipped its replacement in the same commit, and the
  reviewer judged them a strict improvement. If the decider amends or rejects 5 or 7, Check 74
  and the guard must be revised in the same change — they are not free to drift from the ADR.
  Also recorded from that review: the interim hourly backup job and the by-ref ship were
  themselves put through the new non-overridable-class test (3/3 reviewers: none).
