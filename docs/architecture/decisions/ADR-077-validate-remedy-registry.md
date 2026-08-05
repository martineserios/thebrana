---
status: accepted
---
# ADR-077: Remedy Registry for `validate.sh` — Bound Fixes, Not Just Findings

**Status:** Accepted (2026-08-05)
**Date:** 2026-08-05
**Deciders:** Martín Rios
**Tags:** validate-sh, remedy-binding, harness, dx-tooling, ruvnet-brain-comparison
**Tasks:** t-2630
**Relates:** [ADR-062](ADR-062-runner-executor-sandbox.md) (another "the gate inspects less than you think" class fix) · `project_gentle-ai-ruflo-comparison-adoption-candidates` (auto-memory; item 3, ruvnet-brain's remedy-factory pattern) · `pattern_task-notes-are-not-work-state`

---

## Context

`validate.sh` has ~68 numbered checks (plus 4 semantic checks) and ~166 `fail()`/`warn()`
call sites. Every one of them only echoes a message and increments a counter — there is no
mechanism anywhere in the file that can act on a finding. "Detected" and "fixed" have no
relationship; a check that has printed the same warning for months looks identical to one
that was just introduced.

ruvnet-brain (a comparator studied 2026-08-01/05, see auto-memory
`project_gentle-ai-ruflo-comparison-adoption-candidates` item 3) encodes a stronger
invariant: **"detection without a remedy is structurally impossible."** A remedy registry
binds `id -> executor -> inverse` as a single value; a factory throws if any detected
problem is offered without a runnable, tested undo. Their own audit found a case where a
headline recommendation had literally no executor — a dead button. thebrana's advisory
findings (validate.sh, `/brana:reconcile` drift reports) are all in that same "dead button"
shape today.

### What research found once we tried to apply this literally

t-2630's original scope, drafted before investigation, named three example checks as the
pilot: skill frontmatter errors, duplicate skill names, JSON validity. A full catalog of all
68+4 checks (Explore agent survey, 2026-08-05) found **all three are judgment-required, not
mechanical** — fixing "invalid YAML frontmatter" or "duplicate skill name" means guessing
which value is correct, which risks silently masking a real error under a wrong auto-fix.
That is a worse failure mode than the one this ADR is trying to close.

The checks that *are* genuinely mechanical, low-risk, single-target-state fixes turned out
to be a different, smaller set — three of them (checks 62/63/64) already have purpose-built
migration scripts with `--write` flags sitting unused in `system/scripts/migrate/`, and one
(check 42) is a single ADR-backed frontmatter field. See the catalog reference in t-2630's
task context for the full per-check fixability/risk breakdown.

## Decision

1. **Every check gets a registry entry — `HAS_REMEDY` or `NO_REMEDY:<reason>` — no third
   state.** A check with no entry at all is a **test failure**, not a silent gap. This is
   the literal translation of "detection without a remedy is structurally impossible": it
   doesn't run at `validate.sh` runtime (that would make an advisory tool crash on
   unrelated, pre-existing gaps), it runs as a **completeness test**
   (`tests/procedures/test-validate-remedy-registry-completeness.sh`) that extracts every
   `# Check N` id from `validate.sh` and asserts the registry accounts for all of them.
   Adding a new check without a registry entry fails CI, not just this test file locally.

   **Extraction must not reuse Check 13's raw `^# Check [0-9]` regex as-is, and switching
   to a leading-whitespace-tolerant regex alone is not sufficient.** Verified against the
   live file: the anchored regex is column-0-only and misses at least one real check (51,
   indented 4 spaces inside a conditional block). Widening to `grep -oP '^\s*# Check
   \K[0-9]+[a-z]?'` fixes that, but by itself *also still matches* two fake ids ("1"/"2")
   from Python-heredoc comments nested inside Check 18's embedded script
   (`validate.sh:1125-1205`, between the `<<'PYEOF'` open and the `PYEOF` close) — widening
   the whitespace tolerance does nothing to exclude heredoc-embedded text, since those
   comments are themselves at column 0. Currently harmless only because ids 1/2 happen to
   already be real, registered checks; not a structural guarantee.

   **Extraction must therefore explicitly skip heredoc regions — and the two blocks do NOT
   share identical delimiter syntax, a distinction the first implementation attempt missed
   (caught by the Challenger gate during BUILD, not SPECIFY).** validate.sh has two PYEOF
   heredocs: Check 18's embedded script opens with `<<'PYEOF'` (no space, nothing trailing)
   while a second block (an AskUserQuestion-description-field checker) opens with
   `<< 'PYEOF' 2>/dev/null` (space before the quote, a redirect after) — a detection regex
   anchored to the first block's exact shape silently fails to blank the second. Line numbers
   are not cited here by design (the whole point of catching this class of bug is that they
   drift — see the dynamic-detection requirement below). Implementation: pre-filter the file
   to blank out (not delete — line numbers must stay stable for error messages) every line
   between a heredoc open — matching `<<`, optional whitespace, optional quote, `PYEOF`,
   optional quote, ANYTHING after (not anchored to end-of-line) — and its matching `PYEOF`
   close, THEN run the `# Check N` regex against the filtered text. Do not rely on a
   "cross-validate against `should_run()` gate points" heuristic as the primary defense —
   checks 1-22 have zero individual `should_run N` call sites (they're gated only by
   block-level flags), so that cross-check structurally cannot catch a fake id in that range;
   it may still be added as a secondary sanity check but is not sufficient alone. The
   completeness test's own independent cross-check must use a **genuinely different
   detection method** than `extract_check_ids()` itself — reusing the identical regex in two
   places tests self-agreement, not correctness — exactly how the second heredoc's syntax
   variant shipped undetected in the first BUILD implementation attempt, caught only by the
   BUILD-phase Challenger gate reviewing the actual code (the two SPECIFY-phase rounds
   reviewed this ADR's design text, before either heredoc-detection regex existed). Add fixture
   regression tests for the indented-real-check case (51) AND heredoc-fake-id exclusion
   against BOTH real syntax variants (Check 18's embedded "# Check 1"/"# Check 2" comments must
   NOT appear in the extracted id set).

2. **`NO_REMEDY` is a first-class, visible state — not absence.** Every `NO_REMEDY` entry
   carries a one-line reason, one of four: `judgment-required` (fixing it means guessing
   content/policy), `not-fixable` (no deterministic target state exists), `excluded-high-risk`
   (a fix could exist but is deliberately not automated — see Decision #4), or
   `deferred-wave2` (the SPECIFY-phase catalog found this check genuinely mechanical and
   low-risk, but it isn't wired in this v1 pilot — a real gap, not a judgment call; labeling
   it `judgment-required` would itself be exactly the kind of misleading state this registry
   exists to prevent). `deferred-wave2` entries are the seed list for the Wave 2 follow-up.
   This mirrors ruvnet-brain's "UNKNOWN as a first-class state, visually separate from OFF"
   finding — the failure class it caught (a renderer reading a table column that doesn't
   exist, misread as real "disabled" state) is the same shape as validate.sh silently
   having no remedy where an author might assume one exists, or mislabeling why.

3. **v1 binds remedies for 5 checks: 62, 63, 64** (tasks.json migrations — script and
   `--write` flag already exist; inverse is `git restore .claude/tasks.json`), **42** (single
   frontmatter field, ADR-backed, one-file blast radius), and **29** (`brana reference
   generate` — the generator's own designed purpose; inverse is `git restore
   docs/reference/`). Check 29 was conditional at spec time — its fixture (a copied minimal
   skills/hooks/agents tree) was untested — but proved practical during BUILD (t-2645):
   `find_project_root()` only needs a `.git` directory to resolve, and each generator either
   `.exists()`-guards its input or just needs the target subdirectory to exist, even empty.
   Check 29 is the *only* check delivered from AC2's named candidate list
   (9/28/29/30/36/45/60) — the other six are Wave 2. This is a deliberately narrow pilot —
   not the full mechanical set found in research — see Non-Actions.

4. **Explicitly excluded from any future wave without a separate ADR:** checks that mutate
   state *outside the repo* (34, 58: live scheduler at `~/.claude/scheduler/`; 59: moves git
   worktrees, which can disrupt another in-progress session) and check 47 (wrong JSON shape
   in the fix would reintroduce the exact silent-hook-failure class the check exists to
   guard against — the fix is strictly higher-risk than the finding). These get
   `NO_REMEDY:excluded-high-risk` entries with the reason inline, not `judgment-required` —
   the distinction matters because "excluded" means "a fix could exist but we're choosing
   not to automate it," not "no fix is conceivable."

5. **Executor contract:** each remedy is a pair of bash functions,
   `remedy_<id>_apply()` / `remedy_<id>_undo()`, in `system/scripts/validate-remedies.sh`
   (sourced by `validate.sh`). `apply()` must be idempotent (safe to run twice — tested
   explicitly, not assumed) and must leave the repo in a state where re-running the check
   passes. `undo()` must restore the pre-apply state exactly (verified by `git diff --quiet`
   in the test, not by trusting the function's own claim).

   **Every remedy that invokes a script resolving its target via `git rev-parse
   --show-toplevel` or any other CWD-relative lookup must `cd` into `$SCRIPT_DIR` (or
   `$GIT_ROOT`) first: `(cd "$SCRIPT_DIR" && uv run python3 ...)`.** This is not
   discretionary. `validate.sh` itself resolves `TASKS_FILE` via `BASH_SOURCE`-anchored
   `$SCRIPT_DIR`, CWD-immune by construction — but the `system/scripts/migrate/*.py`
   scripts these remedies wrap resolve their own write target by shelling out to `git
   rev-parse --show-toplevel` with no `cwd=` pinning, i.e. against whatever directory the
   *caller* happens to be in. `validate.sh` already has a dedicated check (30, t-1439) that
   exists specifically because "brana subcommands resolve the project from CWD, so bare
   calls silently return empty/wrong-repo results" bit this codebase before. An unguarded
   remedy invocation reintroduces that exact bug class for a file-mutating operation — worse
   than the read-only case Check 30 guards, since a wrong-CWD write can silently mutate the
   wrong repo's `tasks.json` instead of just returning empty. Same rule applies to check 29's
   `brana reference generate` invocation.

6. **CLI surface:** `./validate.sh --fix <N>` runs `remedy_<N>_apply`, then re-runs check
   `N` to confirm it now passes (self-verifying, not just "ran without error" — satisfies
   AC4's "a check cannot ship claiming a fix exists without a test proving the fix runs and
   reverses cleanly" at the tool level, not only in the test suite). `--fix <N>` on a
   `NO_REMEDY` check prints the reason and exits non-zero — it does not silently no-op.
   Dispatch must look up `REMEDY_REGISTRY[$N]` and confirm `HAS_REMEDY` before calling
   `remedy_${N}_apply` — never construct or `eval` the function name from unvalidated
   input. `--check` and `--fix` are mutually exclusive; passing both is a usage error.

## Consequences

- New checks added to `validate.sh` after this ships must add a registry entry (`HAS_REMEDY`
  or `NO_REMEDY:<reason>`) in the same PR, or the completeness test fails. This is a real,
  permanent authoring cost on every future check — accepted because the alternative (silent
  gaps) is the exact problem this ADR closes.
- 5 bound remedies out of 75 registered check ids (~7%) is a small fraction. The registry's
  value is structural (no check can *silently* lack a remedy — the gap is either genuinely
  justified and visible, or it's a completeness-test failure) more than immediate fix
  coverage. Wave 2 (9, 28, 30, 36, 45, 60, plus the other `deferred-wave2`-tagged ids —
  narrower/riskier mechanical candidates from the same catalog) is a follow-up task, not
  blocked by this ADR, but each addition still goes through the same registry contract.
- `--fix` mutates tracked files. It is opt-in (never runs as part of a normal `validate.sh`
  invocation) and every bound remedy has a tested inverse, but it is still a new way for
  `validate.sh` — previously read-only — to write to the repo. Anyone piping `validate.sh`
  output into automation should not assume `--fix` is implied.

## Non-Actions

- **Not** attempting remedies for judgment-required checks (frontmatter content, duplicate
  names, JSON validity, ADR renumbering, etc.) by guessing a default. That was the original
  scope and research showed it was the wrong call — see Context.
- **Not** wiring remedies for 34/58/59/47 in this task or without a separate ADR — the risk
  profile (mutating state outside the repo; reintroducing a guarded-against failure class)
  is qualitatively different from the v1 set and deserves its own decision.
- **Not** making `NO_REMEDY` checks fail `validate.sh` itself — they remain advisory,
  exactly as today. Only the registry *completeness* (every check has an entry) is enforced.
- **Not** a general-purpose "auto-fix everything" framework. The registry only ever grows by
  someone explicitly writing and testing an `apply`/`undo` pair for one specific check.
