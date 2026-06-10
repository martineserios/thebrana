
# Fix

Structured bug fixing workflow. Five steps: REPRODUCE → DIAGNOSE → FIX → VERIFY → COMMIT → (HARDEN). Enforces test-first debugging — no source changes until a failing test exists. HARDEN is optional: fires when the same errata class has appeared 2+ times — offers to convert the pattern into a PreToolUse gate.

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
TaskCreate: "/brana:fix — HARDEN"     (blocked by COMMIT, optional)
```

Mark each `in_progress` when starting, `completed` when done. Resume after compression by calling `TaskList` and finding the `in_progress` step.

After creating the step registry, call `/goal` and write `active-goal.json` unless `--no-goal` was passed.

If a task_id is known, first extract `AC:` lines from task context:
```bash
brana backlog get {task_id} | python3 -c "
import json, sys
t = json.load(sys.stdin)
lines = [l[3:].strip() for l in (t.get('context') or '').splitlines() if l.startswith('AC:')]
print('\n'.join(lines))
"
```

- **If AC: criteria found:**
  ```
  /goal "fix {task-id} — Done when: {criteria joined with ' AND '}"
  ```
  Write `~/.claude/run-state/active-goal.json`:
  ```json
  {"task_id": "{task_id}", "cwd": "{git_root}", "session_id": "$BRANA_SESSION_ID", "criteria": ["{criterion1}", "{criterion2}"]}
  ```
  The Stop hook (`goal-completion.sh`) will auto-complete the task when criteria pass.

- **If no AC: criteria (or no task_id):**
  ```
  /goal "fix {task-id}: reproduce → diagnose → fix → verify → commit"
  ```
  No `active-goal.json` write — the narrative goal is for session anchoring only.

COMMIT is the natural terminator for single fixes. HARDEN fires only when recurrence is detected — skip it otherwise and self-terminate after COMMIT.

<!-- ruflo preamble -->
ToolSearch("select:mcp__ruflo__autopilot_learn")

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

3. **Feed the autopilot** — after committing, call:
   ```
   mcp__ruflo__autopilot_learn()
   ```
   Seeds pattern registry from completed fix outcome. Skip silently if ruflo unavailable.

4. **Close the session** if this was the only task: invoke `/brana:close`.

---

---

### Step 6: HARDEN (conditional)

Goal: convert a recurring errata class into a structural PreToolUse gate so it cannot recur.

**Trigger check** (run immediately after COMMIT):

```bash
# Extract 2-3 keywords from the current fix subject/tags
KEYWORDS="{keyword1} {keyword2}"
# Count prior field notes matching the same class
grep -c "$KEYWORDS" ~/.claude/CLAUDE.md \
  "$(git rev-parse --show-toplevel)/.claude/CLAUDE.md" 2>/dev/null | \
  awk -F: '{s+=$2} END {print s}'
```

If count ≥ 2: proceed. Otherwise: skip HARDEN entirely — mark the CC Task `completed` and self-terminate.

**Harden flow (only if triggered):**

1. **Identify the invariant.** State in one sentence what structural condition would have prevented every instance:
   > "Every write to `{path}` must have `{field}` absent / `{condition}` true."

2. **Identify the interception point.** Which CC tool event catches the violation before it lands?
   - `Write` / `Edit` to a specific file or path pattern → `PreToolUse` on `Write`/`Edit`
   - `Bash` command matching a pattern (e.g., `git commit`, `cargo build`) → `PreToolUse` on `Bash`
   - MCP tool call → `PreToolUse` on `mcp__*`

3. **Offer via AskUserQuestion — never proceed without explicit yes:**
   ```
   AskUserQuestion(
     question: "This errata class ({class}) has appeared {N} times. Convert to a PreToolUse gate?\n\nProposed invariant: {invariant}\nInterception: PreToolUse on {tool} matching {pattern}",
     options: ["Yes — draft the hook (Recommended)", "No — skip hardening"]
   )
   ```

4. **If yes — draft the hook script:**
   - File: `system/scripts/hooks/{errata-slug}-gate.sh`
   - Pattern: check the invariant, exit 1 with a clear message if violated, exit 0 otherwise
   - Add entry to `system/.claude-plugin/hooks.json` under `PreToolUse`
   - Template:
     ```bash
     #!/usr/bin/env bash
     # Gate: {invariant description}
     # Errata: {errata-id} — fires when {condition}
     INPUT=$(cat)
     # ... extract relevant fields from $INPUT ...
     if {violation_condition}; then
       echo "{errata-id}: {what was wrong} — {how to fix}" >&2
       exit 1
     fi
     exit 0
     ```

5. **Write a test** in `system/scripts/tests/test-{errata-slug}-gate.sh`:
   - One test: input that SHOULD be blocked → assert exit 1
   - One test: valid input → assert exit 0

6. **Present the complete diff** (hook script + hooks.json entry + test) to the user for review before writing any file.

7. **After approval:** write files, run `chmod +x` on the hook script, verify `./validate.sh` passes.

---

## Rules

- **Test before source.** Never touch implementation until a failing test exists. The test is the spec.
- **Hypothesis must be specific.** "Something is wrong with X" is not a hypothesis. "X does Y when Z, causing W" is.
- **3-strike rule.** If 3 attempts have failed, stop and run `/brana:challenge` before continuing.
- **Minimal change.** The smallest fix that makes the test pass is the right fix.
- **No refactor during fix.** File a separate task for cleanup discovered during the fix.
- **HARDEN is offer-only.** Never write hook files without an explicit "yes" from AskUserQuestion. Draft and present first.

## Resume After Compression

1. `TaskList` — find the `in_progress` step
2. Read `~/.claude/run-state/{task_id}.jsonl` for the last checkpoint state
3. Resume from the in-progress step using checkpoint context
