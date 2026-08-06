---
depends_on:
  - docs/architecture/decisions/ADR-077-validate-remedy-registry.md
---
# Feature: Remedy Binding for validate.sh Findings

**Date:** 2026-08-05
**Status:** shipped
**Task:** t-2630

## Problem

`validate.sh` has ~68 numbered checks (+ 4 semantic checks) and ~166 `fail()`/`warn()` call
sites. Every one only echoes a message and increments a counter — no check can act on what
it finds. A warning that's been printed unchanged for months is indistinguishable from one
that just appeared. ruvnet-brain's comparable audit found "detection without a remedy is
structurally impossible" catches real gaps (their own headline recommendation had no
executor, a dead button). thebrana's advisory findings are all in that same shape today.

## Decision Record

See [ADR-077](../decisions/ADR-077-validate-remedy-registry.md) for the full decision,
including why the task's original example checks (skill frontmatter, duplicate skill names,
JSON validity) were dropped from scope after investigation showed they require human
judgment, not scripting.

## Constraints

- **No silent gaps.** Every check must resolve to `HAS_REMEDY` or `NO_REMEDY:<reason>` in
  the registry — enforced by a completeness test, not a runtime check inside `validate.sh`
  itself (an advisory tool must not crash on unrelated pre-existing gaps).
- **`apply()` must be idempotent; `undo()` must restore exact pre-apply state**, verified by
  `git diff --quiet` in tests — not by trusting the function's own return code.
- **No remedy for judgment-required or high-risk checks.** Guessing at content/policy risks
  masking a real error under a wrong auto-fix — worse than the "dead button" this fixes.
- **Existing `validate.sh` behavior is unchanged** when `--fix` is not passed. This is
  additive, not a rewrite of the check logic itself.

## Scope (v1)

- A `system/scripts/validate-remedies.sh` file, sourced by `validate.sh`, containing:
  - A `REMEDY_REGISTRY` associative array covering every check id extracted from
    `validate.sh` (`HAS_REMEDY` or `NO_REMEDY:<reason>` per id).
  - `remedy_<id>_apply()` / `remedy_<id>_undo()` function pairs for all 5 v1 checks —
    **62, 63, 64** (tasks.json migrations — wraps the existing
    `system/scripts/migrate/{normalize-tags,collapse-level-epic-v3,drop-stream-field-v3}.py --write`;
    inverse is `git restore .claude/tasks.json`), **42** (writes `model: sonnet` into
    `debrief-analyst.md` frontmatter, covering both the absent-field and
    present-but-wrong-value sub-cases; inverse restores the prior value from git), and
    **29** (runs `brana reference generate`; inverse is `git restore docs/reference/`).
    Check 29's fixture proved practical (feasibility confirmed during BUILD — a minimal
    git-inited skills/hooks/agents tree, `find_project_root()` only needs a `.git` dir),
    so it shipped in v1 as planned rather than dropping to Wave 2.
- `./validate.sh --fix <N>`: runs the check's `apply()`, re-runs check `N` to confirm it now
  passes, prints the undo command. On a `NO_REMEDY` check: prints the reason, exits
  non-zero — never a silent no-op.
- `tests/procedures/test-validate-remedy-registry-completeness.sh`: pre-filters `validate.sh`
  to blank out the two `<<'PYEOF'`...`PYEOF` heredoc regions (`validate.sh:1125-1205`,
  `:1818-1836` — Check 18's embedded Python script contains its own `# Check 1`/`# Check 2`
  comments that would otherwise be mistaken for real check ids), then extracts every
  `# Check N` id from the filtered text via `grep -oP '^\s*# Check \K[0-9]+[a-z]?'`
  (leading-whitespace-tolerant — the raw column-0-anchored form Check 13 uses for its own
  doc self-count misses at least one real check, 51, indented inside a conditional block;
  see ADR-077 Decision #1 and Edge Cases) and asserts each has a registry entry. Includes
  fixture regression tests for both the indented-real-check case (51) and the
  heredoc-fake-id exclusion case (Check 18's embedded comments must NOT appear in the
  extracted set).
- `tests/procedures/test-validate-remedies.sh`: for all 5 v1-bound checks, a fixture
  that induces the FAIL/WARN state, applies the remedy, asserts the check now passes, calls
  `apply()` a second time and asserts it's still a no-op error-free pass (idempotency),
  undoes it, asserts `git diff --quiet` (exact restoration).
- `tests/procedures/test-validate-fix-dispatch.sh`: `--check`/`--fix` mutual exclusion, the
  NO_REMEDY path (reason printed, nothing touched), the HAS_REMEDY happy path end-to-end via
  the real `validate.sh --fix N` CLI, an id absent from the registry entirely, and the
  dispatch-safety boundary (a drifted registry entry claiming `HAS_REMEDY` with no matching
  function must refuse cleanly, never surface a raw shell error).

## Deferred (Wave 2 — separate task, not blocked by this one)

Narrower/riskier mechanical candidates from the same catalog: checks 9 (executable bit /
shebang insert), 28 (`python3` → `uv run python3` prefix), 30 (`cd` subshell wrap), 36/45
(append missing tool declarations), 60 (append `allowed-tools` entries), 13/17/44/48b/53/67
(other mechanical checks catalogued during SPECIFY, registered as `NO_REMEDY:deferred-wave2`
— ADR-077 Decision #2). Each still needs its own `apply`/`undo` pair and test under the same
registry contract — this task only establishes the contract and proves it on the 5
lowest-risk cases.

## Assumptions

- **AC2 ("a curated subset of 9/28/29/30/36/45/60") is satisfied by delivering check 29
  alone in v1**, with the other six (9, 28, 30, 36, 45, 60) moved to the unblocked Wave 2
  follow-up task rather than built now. Confirmed with the user 2026-08-05 (AskUserQuestion,
  "Keep v1 at 29 only") after Challenger flagged that the spec's original draft narrowed
  this without surfacing it — this is the task's second AC narrowing (after the original
  frontmatter/duplicate-name/JSON-validity examples were dropped), so it's called out
  explicitly here rather than left implicit.
- **`REMEDY_REGISTRY` keys are the exact check-id strings as they appear in `# Check N`
  comments** (including lettered sub-checks like `2b`), not a separate normalized id space
  — chosen because that's what a human reads when triaging a `validate.sh` run. Needs
  confirmation if DECOMPOSE finds a check whose sub-letters don't map 1:1 to a single
  fixable/unfixable state (e.g. Check 9 mixes several sub-cases under one number — see
  Edge Cases).
- **Checks 62/63/64's migration scripts are safe to invoke via `--fix` as-is** (dry-run
  default already exists; `--fix` explicitly opts into `--write`). Not re-auditing the
  migration scripts' own correctness — only wiring them into the registry, with the CWD
  hazard from ADR-077 Decision #5 explicitly guarded (see Design).
- **Check 42's remedy covers both FAIL sub-cases, not just the absent-field case.** Check
  42's actual condition (`grep -m1 '^model:' | awk '{print $2}'` ≠ `sonnet`) fires both when
  the field is missing and when it's present but wrong (e.g. `model: opus`). `apply()` must
  set the value in both cases, not only when absent.
- **Check 29's fixture strategy differs from 62/63/64/42, and its inclusion in v1 is
  conditional, not settled.** Unlike those four (each trivially fixturable as a single
  copied file), `brana reference generate` reads a whole tree (skills/hooks/agents) and
  writes an un-enumerated set of `docs/reference/*.md` files. The test fixture for 29
  operates on a **copied minimal skills/hooks/agents tree**, not real repo content,
  specifically so the FAIL-state induction and undo don't touch live reference docs.
  **If DECOMPOSE finds that impractical to fixture cheaply, dropping check 29 to Wave 2
  requires re-confirming with the user before DECOMPOSE is finalized — it is not a
  unilateral implementation-time call.** Check 29 is currently v1's *only* delivered
  check from AC2's named candidate list (9/28/29/30/36/45/60, see the AC2 Assumptions entry
  above) — silently dropping it would take that count to zero without the same explicit
  confirmation the AC2 narrowing itself already required. AC4 (a fix needs a test proving it
  runs and reverses cleanly) is a hard requirement regardless of outcome — check 29 never
  ships without one, but which side of the v1/Wave-2 line it lands on is a decision point,
  not an assumption to silently resolve either way.

## Behavior

- Running `./validate.sh` with no flags: byte-identical output to today (registry is loaded
  but never invoked without `--fix`).
- Running `./validate.sh --fix 62` when tasks.json has string-joined tags: the tags are
  normalized in place, check 62 is re-run and reports PASS, and the exact `git restore`
  command to undo is printed.
- Running `./validate.sh --fix 15` (a `NO_REMEDY:not-fixable` check): prints "No remedy for
  check 15: not-fixable — assumption freshness requires human verification, not a script,"
  exits 1. No file is touched.
- Adding a new `# Check 69` to `validate.sh` without a registry entry: the completeness test
  fails with the specific missing id, not a generic assertion count mismatch.

## Edge Cases

- **A check number has both a mechanical and a judgment-required sub-case** (e.g. Check 9:
  executable bit is mechanical, missing shebang content is not) — DECOMPOSE must split these
  at the sub-case level the registry can actually address. For v1's 5 checks this doesn't
  arise (62/63/64/42/29 are each single-state), but the registry schema must support a check
  id resolving to `HAS_REMEDY` for one sub-case and `NO_REMEDY` for another if Wave 2 needs
  it — confirm the array-key granularity (`9` vs `9-executable`/`9-shebang`) before Wave 2
  starts, not required for v1.
- **`--fix` run when the repo has other uncommitted changes**: the remedy still applies (it
  doesn't require a clean tree), but the undo test's `git diff --quiet` check only applies
  inside the isolated test fixture, not to a real invocation — a real `--fix` leaves the
  fix as an uncommitted change like any other edit, same as running the migration script
  directly today.
- **Check 13's self-count** (the check that counts `# Check N` occurrences to catch doc
  drift) is a different mechanism from the registry-completeness test — Check 13 counts
  occurrences in *docs*, the completeness test counts *ids present in validate.sh itself*,
  using the corrected leading-whitespace-tolerant regex above (Check 13's own regex is
  known to miss indented comments like Check 51's — not fixed here, since that's Check 13's
  own doc-drift concern, not this feature's; flagging so a future check addition doesn't
  silently satisfy one and fail the other for different reasons).
- **`--check` and `--fix` passed together** is a usage error (exit 1 with a message), not a
  defined combined behavior — avoids ambiguity about which flag wins.

## Design

**Files:**
- `system/scripts/validate-remedies.sh` (new) — registry + apply/undo functions, sourced
  by `validate.sh` near the top (after `fail()`/`warn()`/`pass()` are defined).
- `validate.sh` (modified) — source the remedies file; add `--fix <N>` flag parsing
  alongside the existing `--check` flag; on `--fix`, run apply → re-check → report, then
  exit (don't run the full suite).
- `tests/procedures/test-validate-remedy-registry-completeness.sh` (new)
- `tests/procedures/test-validate-remedies.sh` (new)
- `docs/architecture/decisions/ADR-077-validate-remedy-registry.md` (new, already written)

**Registry shape** (bash, matching the project's existing associative-array conventions).
`NO_REMEDY` reasons are one of four (ADR-077 Decision #2): `judgment-required`,
`not-fixable`, `excluded-high-risk`, or `deferred-wave2` (genuinely mechanical per the
SPECIFY-phase catalog, just not built in this pilot — distinct from `judgment-required` so
the registry never mislabels a real, known-fixable gap as "can't be automated"):
```bash
declare -A REMEDY_REGISTRY=(
  [62]="HAS_REMEDY"
  [63]="HAS_REMEDY"
  [64]="HAS_REMEDY"
  [42]="HAS_REMEDY"
  [29]="HAS_REMEDY"
  [1]="NO_REMEDY:judgment-required — missing/invalid frontmatter content can't be inferred"
  [34]="NO_REMEDY:excluded-high-risk — mutates live scheduler outside the repo"
  [28]="NO_REMEDY:deferred-wave2 — mechanical (python3 -> uv run prefix), not yet wired"
  # ... one entry per remaining check id
)
```

**Executor pattern** (mirrors the existing `system/scripts/migrate/*.py` dry-run/`--write`
convention already in the repo). **Every invocation of a CWD-sensitive script must `cd`
into `$SCRIPT_DIR` first** (ADR-077 Decision #5) — `normalize-tags.py` resolves its own
write target via `git rev-parse --show-toplevel` against the *caller's* CWD, not
`BASH_SOURCE`, so an unwrapped call from the wrong directory would silently target the
wrong repo's `tasks.json`:
```bash
remedy_62_apply() { ( cd "$SCRIPT_DIR" && uv run python3 system/scripts/migrate/normalize-tags.py --write ); }
remedy_62_undo()  { ( cd "$SCRIPT_DIR" && git restore .claude/tasks.json ); }
```
Dispatch (`--fix <N>`) looks up `REMEDY_REGISTRY[$N]`, confirms it's `HAS_REMEDY`, then calls
`remedy_${N}_apply` — never `eval`s or otherwise constructs the function name from `$N`
directly.

## Boundaries

| Always | Ask First | Never |
|--------|-----------|-------|
| Registry covers every check id (HAS_REMEDY or NO_REMEDY) | Adding a Wave 2 remedy for a check flagged `excluded-high-risk` (needs its own ADR per ADR-077) | Guess a default value for a judgment-required check |
| `--fix <N>` re-verifies the check passes before reporting success | Widening `--fix` to `--fix-all` (not in v1 scope; revisit after Wave 1 proves out) | Run any remedy as part of a normal (non-`--fix`) `validate.sh` invocation |
| Every bound remedy has a tested, exact-restoring `undo()` | | Touch files outside the repo (scheduler live config, worktrees) from a remedy — checks 34/58/59 |
| `cd`/subshell-wrap every CWD-sensitive script invocation | | Wire a remedy for check 47 — the fix's wrong-JSON-shape risk is strictly higher than the finding it guards against |
| | | Dispatch `--fix <N>` via `eval` or unvalidated function-name construction |

## Testing Strategy

- **Unit:** none — this is all shell/integration by nature (file mutation, subprocess
  invocation).
- **Integration (100% of test budget):**
  - Registry completeness: every `# Check N` id in `validate.sh` has a registry entry.
  - Per-remedy apply/undo round-trip on a fixture (not the real repo's own `tasks.json` —
    a copied fixture file, to avoid corrupting live backlog state if a test fails mid-run).
  - Per-remedy idempotency: `apply()` called a second time immediately after the first is a
    safe no-op (no error, check still passes) — ADR-077 Decision #5's idempotency
    requirement, tested explicitly rather than assumed.
  - `--fix` on a `NO_REMEDY` check exits non-zero and prints the reason, touches nothing
    (`git diff --quiet` before/after).
- **Mock policy:** real files (fixtures), real subprocess calls to the actual migration
  scripts — no mocking. The whole point is proving the executor really runs and really
  reverses.

## Documentation Plan

- [x] **Tech doc** — this file (`docs/architecture/features/validate-remedy-binding.md`).
- [x] **Existing docs to update** — none identified via spec-graph routing (no existing node
  has `validate.sh` in `impl_files`); confirmed unchanged through BUILD.
- [x] **User guide** — confirmed not needed during BUILD: `--fix` is a maintainer-facing
  flag on an internal tool, not a user-facing feature, and `validate.sh` has no `--help`/
  usage mechanism to update (verified: no `--help` or `usage()` anywhere in the file).

## Challenger findings

**Iteration 1 (RECONSIDER → fixed):** completeness-test regex missed indented checks and
conflated heredoc-embedded fake ids; remedy executors didn't guard the CWD-resolution hazard
Check 30 exists to prevent; AC2's 7-candidate scope was silently narrowed to 1 without a
flagged assumption. All three fixed — see ADR-077 Decisions #1 and #5, and this spec's
Assumptions section.

**Iteration 2 (RECONSIDER → fixed):** the iteration-1 regex fix only closed the indentation
half, not the heredoc-embedded-fake-id half; the check-29 Wave-2 fallback introduced a new
unguarded path back to zero AC2 coverage plus an ADR/spec count inconsistency. Both fixed —
extraction now pre-filters the two `PYEOF` heredoc regions before matching (with a fixture
test for the exclusion), and check 29 was made explicitly conditional with a required
re-confirmation gate if it dropped.

**BUILD resolution:** check 29's fixture proved practical (t-2645/t-2650) — all 5 checks
(62/63/64/42/29) shipped in v1. A third, unrelated bug surfaced during BUILD itself (not a
Challenger finding): the completeness test's heredoc-exclusion check had hardcoded Check 18's
`PYEOF` span as absolute line numbers, which went stale the moment the `--fix` dispatch
insertion added lines above it. Fixed to locate every `PYEOF` span dynamically instead
(same scan `extract_check_ids()` itself uses) — see commit `e4b9a367`.

Hard 2-iteration Challenger cap reached at that point (per `challenger-gate.md`'s repair
loop). Both iteration-2 fixes are concrete, verifiable textual corrections rather than open
design questions; user reviewed the fix summary and approved proceeding to DECOMPOSE without
a third automated pass (2026-08-05). ADR-077 status: Accepted.
