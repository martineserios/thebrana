
# Fix

Structured bug fixing workflow. Five steps: REPRODUCE → DIAGNOSE → FIX → VERIFY → COMMIT. Enforces test-first debugging — no source changes until a failing test exists.

## Usage

`/brana:fix [task-id or bug description]`

If a task ID is provided, load it via `brana backlog get <id>` and use the description as the bug statement.

## Step Registry

On entry, create CC Tasks for each step (for compression resilience):

```
TaskCreate: "/brana:fix — REPRODUCE"
TaskCreate: "/brana:fix — DIAGNOSE"   (blocked by REPRODUCE)
TaskCreate: "/brana:fix — FIX"        (blocked by DIAGNOSE)
TaskCreate: "/brana:fix — VERIFY"     (blocked by FIX)
TaskCreate: "/brana:fix — COMMIT"     (blocked by VERIFY)
```

Mark each `in_progress` when starting, `completed` when done. Resume after compression by calling `TaskList` and finding the `in_progress` step.

## Procedure

### Step 1: REPRODUCE

Goal: prove the bug is real with a failing test before touching any source.

1. **Understand the symptom.** Read the task description or ask: "What's broken, when does it happen, what's the expected vs actual behavior?"
2. **Find the failing case.** Read relevant code, check recent commits, identify the conditions that trigger the bug.
3. **Write a failing test** that captures the bug:
   - The test IS the spec — it documents what "fixed" looks like
   - Run it: confirm it fails with current code
   - State: "Test fails as expected: `{test name}` — `{actual output}`"
4. **If no test framework exists:** document reproduction steps as a numbered list. State "No test framework — manual verification required." Note this in the task.

> If 3 or more previous fix attempts have already failed for this bug, pause and run `/brana:challenge` on your diagnosis before continuing to Step 2.

**Checkpoint:**
```bash
printf '{"step":"REPRODUCE","completed":"%s","task":"%s"}\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "{task_id}" >> ~/.claude/run-state/{task_id}.jsonl
```

---

### Step 2: DIAGNOSE

Goal: state a specific hypothesis about root cause — not a symptom.

1. **Read the failing test output carefully.** Note the exact error message, line, and stack.
2. **Trace the call path.** Follow the code from the failing assertion back to where the bad value or wrong path originates.
3. **State the hypothesis:**
   > "This bug fails because `{component}` does `{wrong thing}` when `{condition}`, producing `{bad result}` instead of `{expected result}`."
4. **Distinguish root cause from symptom.** A symptom is "the test fails on line 42." A root cause is "the nil check is missing at the call site in `parse_config()`."
5. **If the hypothesis is uncertain:** run one targeted experiment (add a log, write a second test, read adjacent code). Revise the hypothesis once.

**Checkpoint:**
```bash
printf '{"step":"DIAGNOSE","completed":"%s","hypothesis":"%s"}\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "{hypothesis}" >> ~/.claude/run-state/{task_id}.jsonl
```

---

### Step 3: FIX

Goal: make the minimal change that satisfies the hypothesis.

1. **Write only what the hypothesis requires.** No scope creep — do not refactor adjacent code while fixing.
2. **Change the minimum number of files.** If the fix touches more than 3 files, re-examine the hypothesis — it may be too broad.
3. **Do not add features while fixing.** If a fix reveals a missing feature, file a separate task.
4. Run the failing test after each edit. Stop when it goes green.

---

### Step 4: VERIFY

Goal: confirm the fix works and introduced no regressions.

1. **Run the full test suite.** State the result: "N/N tests pass."
2. **Confirm the original symptom is gone.** Re-state the expected vs actual: "Expected `{X}`, now getting `{X}` — fixed."
3. **Boundary check:** think of 1-2 adjacent cases that could have been affected. If they're not covered by existing tests, add them now.
4. **If any tests fail that were passing before:** the fix introduced a regression. Go back to Step 2 with the new failure.

---

### Step 5: COMMIT

1. **Commit message format:**
   ```
   fix({scope}): {what was wrong and what changed}
   ```
   Examples:
   - `fix(parse-config): nil check missing when optional key absent`
   - `fix(session-end): cd /tmp invalidates git root for subsequent brana calls`

2. **If a task ID exists:** add it to notes and set status:
   ```bash
   brana backlog set {task_id} status completed
   brana backlog set {task_id} notes --append "Fixed {date}: {one-line summary}"
   ```

3. **Close the session** if this was the only task: invoke `/brana:close`.

---

## Rules

- **Test before source.** Never touch implementation until a failing test exists. The test is the spec.
- **Hypothesis must be specific.** "Something is wrong with X" is not a hypothesis. "X does Y when Z, causing W" is.
- **3-strike rule.** If 3 attempts have failed, stop and run `/brana:challenge` before continuing.
- **Minimal change.** The smallest fix that makes the test pass is the right fix.
- **No refactor during fix.** File a separate task for cleanup discovered during the fix.

## Resume After Compression

1. `TaskList` — find the `in_progress` step
2. Read `~/.claude/run-state/{task_id}.jsonl` for the last checkpoint state
3. Resume from the in-progress step using checkpoint context
