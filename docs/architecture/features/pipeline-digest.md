# Feature: pipeline-digest (L0 Reporter gauge)

**Date:** 2026-08-13
**Status:** shipped
**Task:** t-2823 (epic t-2820 loop-first)
**Branch:** loop-first/feat/t-2823-l0-reporter-digest

## Goal

First loop of the loop-first direction: a read-only gauge of pipeline state,
run on a `/loop` beat (30–60m). Each beat reports unmerged branches with
merge-readiness signals, stale merged branches, inbox queue (names only), and
backlog signals — then stops. No writes, no rebases, no processing. The point
is evidence: what the digest teaches drives L1 (preparer) and everything after,
per the graduated-autonomy ladder in
[loop-first-redesign.md](../../ideas/loop-first-redesign.md).

## Design Decisions

- **L0 read-only is the sanctioned start** — the idea doc's challenger review
  returned 3× RECONSIDER on any L0+ write path (unattended runs, inbox drain,
  auto-rebase). The gauge therefore mutates nothing it observes.
- **"Zero writes" scope** — zero mutations of *observed* pipeline state (git
  refs/worktrees, backlog, inbox contents). The digest artifact itself is the
  required output and lands outside the repo. `git merge-tree --write-tree`
  creates only unreferenced loose objects (pruned by auto-gc); no refs move.
- **Digest home: `~/.claude/run-state/pipeline-digest/`** (user-confirmed) —
  durable, no git churn, readable by SessionStart/ops hooks later.
  `latest.md` is the current gauge; `history.jsonl` appends one summary line
  per beat (the cheap no-op preflight reads only this).
- **Prompt packaging: committed prompt file** (user-confirmed) —
  `system/loops/pipeline-digest.md`, first file of the `system/loops/`
  convention. No new skill surface for an MVP.
- **Merge oracle is a signal, not a verdict** — `merge-tree` conflict state is
  reported but never acted on (the probe showed it under-reports risk; day 2 it
  flipped t-2622 from clean to CONFLICTS).

## Code Flow

1. `system/loops/pipeline-digest.md` — the `/loop` beat prompt: preflight
   (read last history line) → run script → report deltas only.
2. `system/scripts/pipeline-digest.sh [repo-path]` — the collector:
   - branch sweep: `for-each-ref` → merged into base (`merge-base
     --is-ancestor`) goes to stale-merged; otherwise ahead/behind
     (`rev-list --left-right --count`), conflict probe (`merge-tree
     --write-tree`), last activity, dirty-worktree flag via `worktree list
     --porcelain` + per-worktree `status --porcelain`.
   - inbox: `ls -1 inbox/` names only — contents never read.
   - backlog: `brana backlog query --count` (pending, in_progress, P0, P1) +
     ANSI-stripped `brana backlog stale` excerpt; degrades to a skip line when
     the CLI is absent.
   - output: markdown to stdout + `$BRANA_DIGEST_DIR/latest.md`, one JSON line
     appended to `history.jsonl`.
   - env: `BRANA_DIGEST_DIR` (default `~/.claude/run-state/pipeline-digest`),
     `BRANA_DIGEST_BASE` (default `dev`).

## Testing

`tests/scripts/test-pipeline-digest.sh` — 17 checks against a fixture repo:
section presence, artifact production, inbox names-only (a planted
content marker must not leak), read-only verification both dynamic (byte-equal
`for-each-ref` + `status --porcelain` before/after) and static (grep guard
against mutating git subcommands), history append semantics, and boundary
cases (missing inbox, no `brana` on PATH). Run:

```bash
./tests/scripts/test-pipeline-digest.sh
```

## Known Limitations

- "Ready-to-drain" backlog signal is approximated by pending/P0/P1 counts —
  wave-aware drain readiness belongs to the t-2811 pipeline front half.
- Loop cadence/no-op behavior lives in the prompt, not the script — the script
  always writes a beat when invoked.
- Single-repo: observes the repo it is pointed at; no portfolio sweep.
