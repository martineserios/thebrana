# Executor Brief (shared)

The envelope for any delegation prompt. Give a subagent a **bounded assignment** it cannot
drift out of: what it may touch, what counts as done, and exactly what shape to return.

Induced from three delegations already running in production — not drafted from scratch. Each
field below cites the live pattern it generalizes:

| Field | Induced from |
|---|---|
| Identity line | `challenger-gate.md` §Spawn call · `verify-gates.md:93` (build-evaluator) |
| Inputs (labelled, delimited) | `challenger-gate.md` §Input contract |
| Scope boundary | `challenger-gate.md` §Input contract (read-trust boundary) + `agents/scout.md` frontmatter `tools:` allowlist |
| Acceptance criteria | `verify-gates.md:95-96` (`AC_LINES`) |
| Return contract | `challenger-gate.md` ("severity, ac_violated, description, file, spec_says") · `verify-gates.md:102` ("PASS, PASS WITH GAPS, or FAIL") |
| TDD criteria | [`delegation-tdd-checklist.md`](delegation-tdd-checklist.md), included by reference |

## Why this exists

Three gaps recur in ad-hoc delegation prompts:

1. **No scope boundary.** The agent infers which files are fair game and drifts. `challenger-gate.md`
   solved this for *reads* ("Challenger reads ONLY trusted content… NEVER receives raw web fetch
   responses"). Nothing generalized it to *writes*.
2. **No return contract.** The caller gets prose and re-derives structure by hand — paying again for
   context it already had.
3. **No stated done-condition.** The agent decides when it is finished.

## The six fields

Compose these into the delegation prompt. Omit a field only when it genuinely does not apply,
and say so inline rather than dropping it silently.

**Field order is not part of the contract** — only presence and explicit labelling are. Live
call sites legitimately differ: `challenger-gate.md` leads with `Spec:` then `Acceptance
criteria:`, while the build-evaluator spawn leads with `Acceptance criteria:`. Both are
conformant. The numbering below is for reference, not a required sequence.

### 1. Identity — task, subject, and role in one line
```
{Purpose} for task {task_id}: {task_subject}.
```

### 2. Inputs — labelled and delimited
Every input gets a heading. Never inline a diff or file body without one; unlabelled blobs are
where scope drift starts.
```
Acceptance criteria:
{AC_LINES}

Spec:
{task description + context field}

Changed files (git diff --name-only {base}...HEAD):
{MODIFIED_FILES}
```

### 3. Scope boundary — what may be touched, what is off-limits
```
Scope: you may read anywhere under {repo_root}. You may WRITE only to:
  - {path glob 1}
  - {path glob 2}
Do not modify: .claude/tasks.json, system/hooks/, docs/architecture/decisions/,
  or any path outside the list above.
Do not run: git commit, git merge, git push.
```
**Constraint that must be stated, not assumed** — in-session Task agents cannot write to a
worktree (ADR-060). For in-session delegation, the brief says *compose and return; the caller
writes*:
```
You cannot write to this worktree. Return the full intended file content in your response;
the orchestrator applies it.
```

### 4. Acceptance criteria — the done-condition, verbatim
Copy the task's `AC:` lines verbatim. Do not paraphrase — paraphrase is where a criterion
quietly softens.

### 5. Return contract — the exact shape expected
State a closed verdict vocabulary and the per-item fields. This is what lets the caller consume
the result without re-reading the work.
```
Return exactly:
  VERDICT: {one of: PASS | PASS WITH GAPS | FAIL}
  Then, for each {finding|criterion}: {field1}, {field2}, {field3} — with file:line evidence.
Report what you could NOT determine as well as what you could.
```
That last line is from `agents/scout.md` ("Report what you found AND what you didn't find") — an
agent that omits its gaps produces confident, incomplete work.

### 6. TDD criteria — for code output only
Append [`delegation-tdd-checklist.md`](delegation-tdd-checklist.md) verbatim. Skip for
read-only delegations (review, research, evaluation).

## Worked example

A populated brief for a real pending task (t-2593, `brana receipt mint|validate`):

```
Agent(
  subagent_type="general-purpose",
  prompt="Implement the receipt schema module for task t-2593: brana receipt mint|validate.

Acceptance criteria:
AC: failing tests written before implementation
AC: mint executes the test command itself and hashes real output — a receipt cannot be
    minted from an unexecuted claim
AC: validate detects a mismatched candidate tree, a mismatched AC digest, and tampered evidence
AC: strict parsing — unknown fields and trailing JSON rejected

Spec:
Rust CLI subcommand implementing gentle-ai-style receipts. Schema brana.build-receipt/v1.
Reference to study: gentle-ai internal/reviewtransaction/receipt.go.

Scope: you may read anywhere under the repo. You may WRITE only to:
  - src/receipt/**
  - tests/receipt/**
Do not modify: .claude/tasks.json, system/hooks/, docs/architecture/decisions/.
Do not run: git commit, git merge, git push.

Return exactly:
  VERDICT: PASS | PASS WITH GAPS | FAIL
  Files written: path — one-line purpose, per file
  Tests: name — PASSING|FAILING, and the command that proves it
  Unresolved: anything you could not determine, or 'none'

Include the acceptance criteria from system/skills/_shared/delegation-tdd-checklist.md
verbatim at the end of this prompt. Do not mark the subtask done until all criteria are met."
)
```

## Validation — regenerated against a live call site

The template was checked by regenerating `challenger-gate.md`'s existing spawn call from the six
fields and diffing against the real one. Result: **4 of 6 fields reproduce verbatim**, and the two
differences are gaps in the original, not defects in the template.

| Field | Regenerated vs live |
|---|---|
| 1 Identity | ✅ exact — `"Challenger gate review for task {task_id}: {task_subject}."` |
| 2 Inputs | ✅ all present and labelled — `Spec:` / `Acceptance criteria:` / `Code diff (…):`. Order differs from the reference numbering above, which is why order is explicitly not part of the contract. |
| 3 Scope boundary | ⚠️ partial — the live prompt scopes the *review* (`Review ONLY: (1)(2)(3)`), but the **trust boundary is never told to the agent**. `challenger-gate.md` §Input contract documents it for the caller ("enforced at the call site") and the challenger itself is never informed what it must not accept. |
| 4 Acceptance criteria | ✅ exact — `AC_LIST` passed verbatim |
| 5 Return contract | ✅ shape matches — closed vocabulary + per-item fields (`severity, ac_violated, description, file, spec_says`) |
| 6 TDD criteria | ✅ correctly absent — read-only delegation, template says skip |

**Two findings for `challenger-gate.md`** (not fixed here — out of scope for this task):
1. The input trust boundary is caller-side only; the agent is never told what it must refuse.
2. No "report what you could not determine" instruction, so an under-informed review is
   indistinguishable from a clean one.

## Relationship to `delegation-tdd-checklist.md`

The checklist is **retained, not absorbed** — it has a live call site at
`build/phases/build-loop.md:78` and is documented at
`docs/architecture/extending-agents.md:110`, and it is correct as-is. The split:

| File | Owns |
|---|---|
| `executor-brief.md` (this file) | The envelope — identity, inputs, scope boundary, AC, return contract |
| `delegation-tdd-checklist.md` | The done-criteria block for delegations producing **code** |

A code delegation uses both: brief as envelope, checklist appended at the end. A review or
research delegation uses the brief alone.

## What this does not do (honesty contract)

- **It is a convention, not an enforcement mechanism.** Nothing prevents a caller from writing
  a prompt without it, and nothing prevents an agent from ignoring the scope boundary — the
  boundary is instruction text, not a sandbox. Treating it as a guarantee is the mistake
  documented in `pattern_gate-armed-by-the-party-it-constrains`.
- It does not verify the returned work. That is the challenger gate and the evaluator.
- It does not reduce token cost. Measured 2026-08-01 (t-2591): `cache_read` is ~97% of session
  tokens, so cost tracks turns × context size, not prompt quality. This file buys **scope
  correctness**, not efficiency — do not justify it on cost.
