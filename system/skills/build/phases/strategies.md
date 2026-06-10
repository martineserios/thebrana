<!-- build phase: Strategy variants: bug fix, greenfield, refactor, spike, migration, investigation — loaded per the PHASES registry in ../SKILL.md (t-1942) -->

## Strategy: BUG FIX

```
REPRODUCE → DIAGNOSE → FIX → CLOSE
```

### REPRODUCE

1. **User describes the symptom** — what's broken, when it happens, expected vs actual.
2. **Find the failing case** — read relevant code, check logs, identify the conditions.
3. **Write a failing test** that reproduces the bug:
   - The test IS the spec — it documents what "fixed" looks like
   - Test must fail with the current code
   - Confirm: "Test fails as expected. The bug is reproducible."
4. **If no test framework exists**: document the reproduction steps, note "no test framework — manual verification."

> **☑ Checkpoint — REPRODUCE** (M+ builds with task_id):
> ```bash
> printf '{"step":"REPRODUCE","completed":"%s","task_id":"%s"}\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "{task_id}" >> ~/.claude/run-state/{task_id}.jsonl
> ```

### DIAGNOSE

1. **Read the code path** — trace from symptom to root cause.
2. **Identify root cause** — not just the symptom, the underlying reason.
3. **Present diagnosis** to user:
   ```
   "The bug is: {root cause}
    It happens because: {explanation}
    The fix should: {proposed approach}"
   ```
4. **Wait for user confirmation** or redirection.

> **☑ Checkpoint — DIAGNOSE** (M+ builds with task_id):
> ```bash
> printf '{"step":"DIAGNOSE","completed":"%s","task_id":"%s"}\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "{task_id}" >> ~/.claude/run-state/{task_id}.jsonl
> ```

### Gate: REPRODUCE → FIX

Before implementing the fix, verify a failing test was written in REPRODUCE:
- Check `git diff --name-only` and `git diff --cached --name-only` for test file patterns.
- **If test files found:** proceed to FIX.
- **If no test files found:** hard block.
  ```
  AskUserQuestion:
    question: "No failing test written yet. The test IS the spec — write it before fixing. What to do?"
    header: "TDD gate"
    options:
      - label: "Write test now (Recommended)"
        description: "Add a failing test before implementing the fix."
      - label: "Skip — no test framework available"
        description: "No testing infrastructure available for this target."
  ```
  If "Write test now": loop back to REPRODUCE step 3.
  If "Skip": log reason and proceed.

### FIX

1. **Create branch** (if not already on one):
   ```bash
   git checkout -b fix/{task-id}-{slug}
   ```
2. **Implement the fix** — make the failing test pass.
3. **Run full test suite** — no regressions.
4. **Commit:** `fix(scope): description`

> **☑ Checkpoint — FIX** (M+ builds with task_id):
> ```bash
> printf '{"step":"FIX","completed":"%s","task_id":"%s"}\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "{task_id}" >> ~/.claude/run-state/{task_id}.jsonl
> ```

### Challenger Gate

Run the Challenger Gate before CLOSE. Read and follow [`../../_shared/challenger-gate.md`](../../_shared/challenger-gate.md) — bug fixes use the same invocation rules, input contract, and repair loop.

### CLOSE

Read `phases/close.md` — shared CLOSE. Bug fixes skip the feature spec update (no spec was created).

---

## Strategy: GREENFIELD

```
ONBOARD → SPECIFY → DECOMPOSE → BUILD → CLOSE
```

### ONBOARD

1. **Detect what exists** — scan for package.json, pyproject.toml, .git, .claude/, docs/.
2. **If nothing exists**, ask the user:
   ```
   question: "What kind of project?"
   options: ["Code project", "Venture/business", "Hybrid"]
   ```
3. **Set up project structure** based on type:
   - Code: `.claude/CLAUDE.md`, `docs/decisions/`, test directory
   - Venture: add `docs/sops/`, `docs/okrs/`, `docs/metrics/`
   - Hybrid: both
4. **Write project CLAUDE.md** — name, stack, conventions.
5. **First commit:** `chore: project scaffold`
6. **Register in portfolio** if not already in `tasks-portfolio.json`.

Then proceed to SPECIFY → DECOMPOSE → BUILD → CLOSE for the first feature/MVP.

---

## Strategy: REFACTOR

```
SPECIFY (light) → VERIFY COVERAGE → BUILD → CLOSE
```

### SPECIFY (light)

1. **What's wrong** with the current structure? (Ask the user or infer from description)
2. **What should it look like after?**
3. **What must NOT change?** — the behavior contract.
4. No feature spec needed for refactors — the tests are the spec.

> **☑ Checkpoint — SPECIFY** (M+ builds with task_id):
> ```bash
> printf '{"step":"SPECIFY","completed":"%s","task_id":"%s"}\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "{task_id}" >> ~/.claude/run-state/{task_id}.jsonl
> ```

### VERIFY COVERAGE

1. **Run existing tests** — all must pass. Record baseline: "N tests pass."
2. **Identify coverage gaps** — if the area being refactored lacks tests:
   - Write tests for current behavior FIRST
   - These tests anchor the refactor — behavior must not change
3. **Confirm baseline:** "N tests pass before refactor. Behavior contract is locked."

> **☑ Checkpoint — VERIFY-COVERAGE** (M+ builds with task_id):
> ```bash
> printf '{"step":"VERIFY-COVERAGE","completed":"%s","task_id":"%s"}\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "{task_id}" >> ~/.claude/run-state/{task_id}.jsonl
> ```

### BUILD

Same as feature BUILD (`phases/build-loop.md`), except:
- After each change: run tests, must still pass
- No new behavior — same tests, same results
- Commits: `refactor(scope): description`

### Challenger Gate

Run the Challenger Gate before CLOSE. Read and follow [`../../_shared/challenger-gate.md`](../../_shared/challenger-gate.md) — refactors use the same invocation rules, input contract, and repair loop.

### CLOSE

Read `phases/close.md` — shared CLOSE. Refactors skip feature spec and user guide updates (no new behavior).

---

## Strategy: SPIKE

```
QUESTION → EXPERIMENT → ANSWER
```

No branch. No spec. No tasks.json entry. No docs. Just learn.

### QUESTION

1. **What are we trying to learn?** (From description or ask)
2. **What would "yes" look like? What would "no"?**
3. **Timebox:** "Spend max {N} minutes on this." (Ask user or default to 30)

> **☑ Checkpoint — QUESTION** (M+ builds with task_id):
> ```bash
> printf '{"step":"QUESTION","completed":"%s","task_id":"%s"}\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "{task_id}" >> ~/.claude/run-state/{task_id}.jsonl
> ```

### EXPERIMENT

1. Work in `/tmp/spike-{slug}/` or a scratch directory.
2. Quick prototype — throwaway code.
3. No tests, no commits, no branch.
4. Focus entirely on answering the question.

> **☑ Checkpoint — EXPERIMENT** (M+ builds with task_id):
> ```bash
> printf '{"step":"EXPERIMENT","completed":"%s","task_id":"%s"}\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "{task_id}" >> ~/.claude/run-state/{task_id}.jsonl
> ```

### ANSWER

1. **Result:** yes / no / partially. Present findings.
2. **Store finding** via retrospective pattern:
   ```bash
   cd "$HOME" && $CF memory store \
     -k "spike:{project}:{slug}" \
     -v '{"question": "...", "answer": "...", "conclusion": "yes|no|partial"}' \
     --namespace pattern \
     --tags "type:spike,project:{project}" \
     --upsert
   ```
3. **If yes** — offer to create a feature task:
   ```
   question: "Spike succeeded. Create a feature task to build this?"
   options: ["Yes — create task", "No — just log the finding"]
   ```
   If yes: `/brana:backlog add` with context from the spike.
4. **If no** — documented dead end. Move on.
5. **Clean up:** `rm -rf /tmp/spike-{slug}/` (ask first).

---

## Strategy: MIGRATION

```
SPECIFY → DECOMPOSE → BUILD (careful) → CLOSE
```

Same as Feature strategy (`phases/specify.md` → `decompose.md` → `build-loop.md` → `close.md`), with these differences:

### SPECIFY additions

- **Current state:** what system/version/approach exists now?
- **Target state:** what are we moving to?
- **Rollback plan:** how do we revert if it fails?
- **Coexistence:** old and new must coexist during transition.

### BUILD differences

- **Incremental:** build the new system alongside the old one first.
- **Switchover:** the cutover is its own task — not buried in another commit.
- **Verify:** run tests against BOTH old and new during transition.
- **Remove old:** separate commit after the new system is verified.

---

## Strategy: INVESTIGATION

```
SYMPTOMS → INVESTIGATE → REPORT
```

No branch. No commits. Read-only. May lead to a build.

### SYMPTOMS

1. **User describes** what's happening — errors, unexpected behavior, performance issue.
2. **Gather evidence:** read logs, check error messages, identify reproduction steps.
3. **Form hypotheses** — list possible causes, ordered by likelihood.

> **☑ Checkpoint — SYMPTOMS** (M+ builds with task_id):
> ```bash
> printf '{"step":"SYMPTOMS","completed":"%s","task_id":"%s"}\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "{task_id}" >> ~/.claude/run-state/{task_id}.jsonl
> ```

### INVESTIGATE

1. **Test hypotheses one by one:**
   - Read code paths
   - Run diagnostic commands
   - Check data/state
   - Compare expected vs actual behavior
2. **Document findings as you go** — each hypothesis tested, result, next step.
3. **No code changes** — this is read-only analysis.

> **☑ Checkpoint — INVESTIGATE** (M+ builds with task_id):
> ```bash
> printf '{"step":"INVESTIGATE","completed":"%s","task_id":"%s"}\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "{task_id}" >> ~/.claude/run-state/{task_id}.jsonl
> ```

### REPORT

1. **Present findings:**
   ```
   Root cause: {explanation}
   Evidence: {what confirmed it}
   Recommended action: fix | refactor | accept | defer
   ```
2. **Store findings:**
   ```bash
   cd "$HOME" && $CF memory store \
     -k "investigation:{project}:{slug}" \
     -v '{"symptoms": "...", "root_cause": "...", "recommendation": "..."}' \
     --namespace pattern \
     --tags "type:investigation,project:{project}" \
     --upsert
   ```
3. **If fix needed** — offer to start a bug fix:
   ```
   question: "Investigation found a bug. Start a fix?"
   options: ["Yes — start /brana:build fix", "No — just log"]
   ```
   If yes: enter BUG FIX strategy with investigation findings as context.

---

