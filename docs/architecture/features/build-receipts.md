---
title: Build receipts — mint executes, validate re-derives
status: specified
task: t-2595
created: 2026-08-02
related:
  - docs/architecture/decisions/ADR-076-build-receipts-as-executed-evidence.md
  - docs/architecture/decisions/ADR-060-branch-strategy-autonomous-agents.md
  - docs/architecture/decisions/ADR-075-ship-on-deploy-surface-change.md
  - docs/ideas/build-receipts.md
---

# Feature: Build receipts

Implementation spec for **t-2593** (`brana receipt mint|validate`) and **t-2594**
(promotion gate). Decisions are settled in
[ADR-076](../decisions/ADR-076-build-receipts-as-executed-evidence.md) — this document
specifies the contract, not the rationale. Where the two disagree, the ADR wins.

## Problem

"Done" rests on an LLM's evaluation of acceptance criteria plus notes written by that same
LLM (`pattern_task-notes-are-not-work-state`). A receipt is an artefact where **git and
executed test output are the authority**.

## Scope

**In:** the receipt schema, `mint`, `validate`, storage, and the promotion gate contract.

**Out:** anything that requires a model. `mint` and `validate` are deterministic
subprocesses — **zero LLM tokens on every path**. This is load-bearing: it is why the
Phase-0 kill (t-2591) that ended the delegation layer does not touch this track. Any
proposal that introduces a model call into either command changes the economics the ADR
rests on and needs its own decision.

## Schema — `brana.build-receipt/v1`

```json
{
  "schema": "brana.build-receipt/v1",
  "task_id": "t-2593",
  "minted_at": "2026-08-02T14:03:11Z",
  "repo": {
    "base_commit":      "<sha1>",
    "base_tree":        "<sha1>",
    "candidate_commit": "<sha1>",
    "candidate_tree":   "<sha1>",
    "paths_digest":     "<sha256>"
  },
  "ac_digest": "<sha256>",
  "execution": {
    "argv":          ["./validate.sh"],
    "cwd_rel":       ".",
    "exit_code":     0,
    "duration_ms":   214113,
    "stdout_sha256": "<sha256>",
    "stderr_sha256": "<sha256>",
    "output_bytes":  48213
  },
  "outcome": "passed"
}
```

### Field rules

| Field | Rule |
|---|---|
| `base_commit` / `base_tree` | `git merge-base HEAD <integration-branch>` and its tree. The **merge-base, never the live branch ref** — see [Hazards](#hazards). |
| `candidate_commit` / `candidate_tree` | `HEAD` at mint time and its tree. |
| `paths_digest` | Digest over `git diff --name-only base_commit..candidate_commit`, sorted. |
| `ac_digest` | Digest over the task's `AC:` lines from `context`, verbatim, in file order. |
| `execution.*` | Recorded by `mint` from **its own** subprocess. No input path sets these. |
| `outcome` | **Derived** — `passed` iff `exit_code == 0`, else `failed`. Never an input. |

**`outcome` has no CLI flag, no env var, and no config key.** This is the single property
separating this design from the reference implementation, where the verdict is a flag the
agent supplies. A test asserts that no input reaches `outcome`.

### Hash construction

Every digest is **domain-separated and length-prefixed**:

```
paths_digest = SHA256( "brana.build-receipt/v1:paths\x00"
                       || for p in sorted(paths): varint(len(p)) || p )

ac_digest    = SHA256( "brana.build-receipt/v1:ac\x00"
                       || for l in ac_lines:      varint(len(l)) || l )
```

Domain separation stops a digest from one field being valid in another. Length prefixing
stops `["ab", "c"]` and `["a", "bc"]` from colliding. Both are cheap and neither is
recoverable after v1 ships.

### Parsing

Canonical JSON. **Unknown fields rejected. Trailing values after the top-level object
rejected.** Sorted keys, no insignificant whitespace, so a receipt round-trips byte-stable.

## `brana receipt mint`

```
brana receipt mint <task-id> [--command <argv...>] [--base <ref>]
```

1. **Refuse a dirty worktree.** Tracked modifications or staged changes → hard error. A
   receipt over an unclean tree binds nothing. Gitignored and untracked files are ignored.
2. Resolve `base = git merge-base HEAD <--base | integration branch>`.
3. **Freeze the snapshot:** record `base_*`, `candidate_*`, compute `paths_digest`,
   `ac_digest`.
4. **Execute** `argv` as a subprocess from the repo root. Capture stdout and stderr
   separately; record exit code and duration. No shell — `argv` is a vector, not a string,
   so nothing is word-split or glob-expanded.
5. **Re-derive `candidate_tree`.** If it moved, the command wrote tracked files during its
   own run: **hard error, no receipt.** Recording a tree that did not produce the captured
   output is the mint-side TOCTOU. Gitignored churn (caches, build artefacts) does not
   count — the re-derivation is over tracked files only.
6. Derive `outcome` from the exit code.
7. Write atomically (temp file + rename) to the store.

`mint` **succeeds and records `outcome: "failed"`** when the command fails. A failing
receipt is a valid receipt — it is evidence of a failed run. Only the *gate* cares about
the outcome value.

### Storage

```
$(git rev-parse --git-common-dir)/brana/receipts/<task-id>.json
```

`--git-common-dir`, never `.git`: one authority shared across linked worktrees, invisible
to `git status`, never pushed. This repo runs concurrent sessions in separate worktrees by
hard rule, so a per-worktree store would silently disagree with itself.

### Idempotency — a content-bound journal, not a lock

Digest the mint request (`task_id` + `candidate_commit` + `argv`).

- Identical request, receipt already present → **no-op, exit 0.**
- Same `task_id` and `candidate_commit`, **different `argv`** → **hard error.** Two
  different commands claiming the same candidate is a contradiction, not a retry.
- Same `task_id`, different `candidate_commit` → supersede. The candidate moved; that is
  normal re-minting.

A lock would need a TTL and a reconciliation path, and stale lock state was already
identified as a deadlock class in the design this replaced. Content-binding needs neither.

## `brana receipt validate`

```
brana receipt validate <task-id> [--at <ref>]
```

Split into two pure functions, **both with zero I/O**; all re-derivation lives in the
caller. The comparison function takes no repo handle — by design, so it cannot be tested
against a repo it also mutates.

```
validate_structure(receipt)          -> Result<(), StructureError>   // shape only
compare(receipt, derived_facts)      -> GateResult                   // pure comparison
```

### Gate result — three-valued, never boolean

| Result | Condition | Routes to |
|---|---|---|
| `allow` | `candidate_commit` reachable from `--at`; `paths_digest` still matches; `ac_digest` matches; `outcome == passed` | proceed |
| `scope-changed` | the task's paths differ from `paths_digest` — the candidate moved | **recovery**, not restart |
| `invalidated` | `ac_digest` mismatch (the AC were edited after minting), or `outcome != passed`, or `candidate_commit` unreachable (history rewritten) | restart |

`scope-changed` is the distinction that earns the design its keep. Collapsing it into a
boolean forces a restart where recovery is correct.

**Re-check after deciding.** On the `allow` path, re-derive the snapshot and re-read the
receipt before returning. Without this the gate is a TOCTOU: the tree can move between the
comparison and the merge it authorises.

## Hazards

Both of these are live failures from this repo, not hypotheticals. Each one silently
corrupts the thing the receipt is supposed to bind.

### H1 — `base_commit` is the merge-base, never the live branch ref

Resolving base as `dev` (the ref) rather than `merge-base(HEAD, dev)` makes the receipt's
base move whenever another session merges to `dev` — which, in a repo that runs concurrent
worktrees by hard rule, is the normal case. `paths_digest` then covers *their* changes as
well as yours, and `scope-changed` fires on every promotion for reasons unrelated to the
task.

The same footgun bit outside the receipt code on 2026-08-02: squashing a branch with
`git reset --soft dev` re-parented the commit onto a `dev` that had advanced while the
worktree held the older tree, recording a deletion of six files another task had merged
an hour earlier. Clean merge, no conflict, no warning
(`pattern_soft-reset-onto-moved-ref-clobbers`). **Anything that resolves a base must
resolve it to a commit that cannot move.**

### H2 — the executed subprocess must not inherit git's hook environment

Git sets `GIT_DIR` and `GIT_INDEX_FILE` in a hook's environment, and those **override
path-based repo discovery** — `cd` does not protect you. Any command `mint` executes that
itself runs git (a test suite with fixtures in `mktemp` dirs) will operate on the **real
repository** instead.

Live result on 2026-08-01 (t-2501, `red-verification` pre-commit hook): three fixture
commits hijacked the feature branch, the outer commit died with
`cannot lock ref 'HEAD': is at X but expected Y`, and the working tree was left checked out
against fixture history (`pattern_git-hook-env-leaks-into-executed-tests`).

This is acute for receipts specifically: the promotion gate runs from a hook, and `mint`
step 5 re-derives `candidate_tree` *after* the run. A leaked `GIT_DIR` means the executed
command can move the very tree `mint` is measuring — producing either a spurious hard error
or, worse, a receipt over a tree the command mutated.

**Requirement:** `mint` clears the git environment for its subprocess —

```
env -u GIT_DIR -u GIT_WORK_TREE -u GIT_INDEX_FILE \
    -u GIT_OBJECT_DIRECTORY -u GIT_COMMON_DIR -- <argv>
```

`GIT_COMMON_DIR` matters twice over: it is also what the storage path resolves through, so
a leaked value would relocate the receipt store itself.

This same 5-var denylist is unset independently in `system/hooks/red-verification.sh` (the
root fix for the live incident above, t-2602), `tests/scripts/test-check-oracle-brana-drift.sh`,
and `tests/scripts/test-ship-brana-oracle.sh` — no shared source yet; update all four sites if
the list ever changes.

## Integration points

### Mint — build CLOSE, step 1

`phases/close.md` step 1 currently reads "Tests pass" as a checkbox the model ticks.
`mint` replaces the assertion with the executed artefact. It runs **before** step 10's
merge to `dev`, on the feature branch, while `HEAD` is the candidate.

The command is `./validate.sh` unless the task specifies otherwise. **Reuse the existing
BUILD→CLOSE gate run rather than executing a second time** where the harness can pass its
captured output through — K2 (below) fires at 60s of added wall-clock, and a cold
`validate.sh` run on this repo exceeds that on its own.

### Validate — ship, at `dev` → `main`

The gate anchors to **promotion**, an involuntary event, never to state the committing
party opts into writing (ADR-076 D4). An escape hatch exists and **logs its own use**, so
abandonment is measurable — an unmeasured bypass is indistinguishable from compliance.

### Open design problem: promotion is a batch, not a branch

**t-2594's acceptance criterion says "no valid receipt for the branch's task" — but at
`dev`→`main` there is no single branch and no single task.** A promotion carries every
task merged to `dev` since the last one. The gate must therefore:

1. Enumerate task IDs from merge commits on `main..dev`.
2. Require a receipt per task ID, not per branch.
3. Decide what a **missing** task ID means — a merge commit whose message names no task is
   not the same as a task whose receipt is absent, and conflating them makes the gate fire
   on unrelated commits (`docs/`, `tasks.json`) that ADR-075 measured as carrying no deploy
   footprint.

Additionally, `candidate_tree` **will not equal the promotion tip's tree** — other tasks
merged in between. The gate therefore checks *reachability plus `paths_digest`*, never tree
equality. A design that compares trees directly fails on every real promotion.

This is recorded here rather than left to implementation because it changes t-2594's
acceptance criteria, and discovering it during implementation would produce a gate that
passes its own tests and blocks every real ship.

## Test plan (t-2593 — tests first)

| # | Test | Asserts |
|---|---|---|
| T1 | mint with a command that exits 1 | receipt written, `outcome: "failed"` |
| T2 | **no input reaches `outcome`** — every CLI arg, env var, and config key fuzzed | D1 holds structurally, not by convention |
| T3 | mint on a dirty worktree | hard error, no receipt |
| T4 | mint where the command writes a tracked file | hard error, no receipt (step 5) |
| T5 | mint where the command writes only gitignored files | succeeds |
| T6 | validate after an unrelated commit to the task's paths | `scope-changed` |
| T7 | validate after editing the task's `AC:` lines | `invalidated` |
| T8 | validate after `git rebase` rewrote the candidate | `invalidated` |
| T9 | tampered `stdout_sha256` | rejected |
| T10 | unknown field in the JSON | rejected |
| T11 | trailing value after the top-level object | rejected |
| T12 | `["ab","c"]` vs `["a","bc"]` path sets | distinct `paths_digest` |
| T13 | identical re-mint | no-op, exit 0 |
| T14 | re-mint, same candidate, different `argv` | hard error |
| T15 | `compare()` called with no repo present | still returns a verdict (proves zero I/O) |
| T16 | mint invoked with `GIT_DIR` set to a foreign repo (H2) | the executed subprocess sees no `GIT_*`; the real repo is untouched |
| T17 | base resolved while the integration branch advances mid-mint (H1) | `base_commit` is the merge-base and does not move |

T2, T15, T16 and T17 are the four that would be easiest to skip and the ones that protect the
properties the whole design rests on.

## Compute cost

| Path | Cost |
|---|---|
| `mint` | one subprocess execution + git plumbing. **Zero LLM tokens.** Marginal cost over the existing build is zero when the CLOSE-gate run is reused, one suite run otherwise. |
| `validate` | git reads only. **Zero LLM tokens**, no subprocess but `git`. |
| Promotion gate | `validate` × N tasks in the batch + a tasks.json read. Zero LLM tokens. |

## Kill thresholds

Inherited verbatim from [ADR-076](../decisions/ADR-076-build-receipts-as-executed-evidence.md),
pre-registered before implementation. Evaluated after the first **20 gated merges**.

| # | Falsifier | Threshold | Action |
|---|---|---|---|
| K1 | escape-hatch use / gated merges | > 50% | **retire the gate — do not harden it** |
| K2 | median wall-clock `mint` adds to CLOSE | > 60s | reuse the CLOSE-gate run, else make `mint` opt-in |
| K3 | merges where the receipt surfaced a real disagreement | 0 | downgrade the hook to advisory |

**Do not renegotiate these after measuring.** A threshold moved once the reading is in is
not a threshold.

## What a valid receipt does not prove

- **Not that the tests are adequate.** It proves the named command ran over exactly these
  trees and produced exactly this output.
- **Not that the AC were the right AC** — only that they were not edited after minting.
- **Not that the change is correct.** Nothing here speaks to correctness.
- **Not that the diff was reviewed.** The receipt binds scope; it does not read it.
- **Not that anything outside the tracked tree is unchanged.** `mint` executes a subprocess
  with the caller's ambient permissions. Network egress, `$HOME` writes, and installs are
  invisible to it — the same "the gate inspects less than you think" class ADR-062 sandboxes
  for the autonomous runner. A receipt is not a sandbox and must not be read as one.

## Open questions

1. **Where does the per-task test command live?** A `TEST:` line in `context` mirroring the
   `AC:` convention is the obvious candidate but is not decided.
2. **Does `mint` run at CLOSE, at promotion, or both?** Settled by K2's first reading.
3. **What does the gate do with a merge commit naming no task?** See the batch problem above.
