<!-- build phase: Verification gates: ISC, BUILD→CLOSE, Four Questions, Docs, Evaluator, Challenger — loaded per the PHASES registry in ../SKILL.md (t-1942) -->

### ISC Verify (all strategies with task_id, when isc field is set)

Before the BUILD→CLOSE gate, check whether the active task has ISC (Ideal State Criteria):

```bash
brana backlog get {task_id} | jq -r '.isc[]?' 2>/dev/null
```

If the `isc` array is non-empty, verify each item as a binary pass/fail with evidence:

For each criterion:
1. State the criterion explicitly
2. Gather evidence (run a command, read a file, check git status — whatever proves the state)
3. Judge: **PASS** or **FAIL** with one-line evidence summary

Collect results. If any criterion **FAIL**:
```
question: "ISC VERIFY: {N} of {total} criteria failed — {list of failed criteria}. Fix before closing?"
options: ["Fix now", "Skip — reason required"]
```
If "Skip": require reason, log: `brana backlog set {id} notes --append "ISC skipped: {reason}"`.

If all pass (or no isc field): proceed silently.

### Gate: BUILD → CLOSE (Medium/Large feature/greenfield/migration only)

Before entering CLOSE, verify all mandatory artifacts exist on the branch:
1. **Tests:** `git diff --name-only main...HEAD` must include test files (`*test*`, `*spec*`, `tests/`, `__tests__/`)
2. **Docs:** at least one doc file in the diff (`docs/`)
3. **All subtasks completed:** no `in_progress` or `pending` subtasks remain
4. **validate.sh passes (MEASURE gate):** run `./validate.sh` from repo root; require exit 0.
   ```bash
   ./validate.sh
   ```
   This is the objective, manipulation-resistant MEASURE signal — the loop only advances to CLOSE when the external validator agrees. If non-zero: display the failing check output, fix before proceeding. Opt-out requires written justification.

Check each, collect failures, then gate:
```
question: "BUILD→CLOSE gate. Missing or failing: {list of failures}. Fix before closing?"
options: ["Fix now", "Skip gate — reason required"]
```
If all pass (including validate.sh exit 0), proceed silently. If "Skip gate": require reason. Log: `brana backlog set {id} notes --append "BUILD→CLOSE gate skipped: {reason}"`.

Bug fix and refactor strategies: skip doc check (require tests + validate.sh).
Spike and investigation: skip this gate entirely.

### Four Questions Gate (all strategies except spike/investigation)

Before declaring BUILD done, answer all four — out loud, in the response:

1. **Tests pass with actual output?** — run the suite, state the pass count (e.g. "535/535 pass").
2. **All requirements addressed?** — re-read the spec or task description; confirm every criterion is covered.
3. **Assumptions documented?** — every assumption made during BUILD is recorded under `## Assumptions` in the spec.
4. **Evidence provided?** — a test run result, screenshot, or log excerpt proves the behavior works as specified.

If any answer is No, continue working. This gate is blocking, not advisory. Spike and investigation strategies skip it.

### Docs — generate here, not in CLOSE

Run `/brana:docs` immediately after BUILD passes, before CLOSE. CLOSE step 6 is the fallback safety net only.

```
Skill(skill="brana:docs", args="{strategy-appropriate args}")
```

| Strategy | Args |
|----------|------|
| Feature / Greenfield / Migration | `all {task-id}` |
| Bug fix | `update {task-id}` |
| Refactor | `update {task-id}` |

Skip for spike and investigation strategies.

### Evaluator Gate

**Applies to:** all strategies except spike and investigation. **Requires** `AC:` lines in task context — skipped silently otherwise.

#### Check for AC lines

```bash
AC_LINES=$(brana backlog get {task_id} | jq -r '.context // ""' | grep '^AC:' | sed 's/^AC: //')
```

If `AC_LINES` is empty: log inline "Evaluator gate: no AC: lines — skipped" and proceed to Challenger Gate.

#### Spawn call

```
Agent(
  subagent_type="brana:build-evaluator",
  prompt="Evaluate t-{task_id}: {task_subject}.

Acceptance criteria:
{AC_LINES}

Modified files (git diff --name-only main...HEAD):
{MODIFIED_FILES}

Grade each criterion MET / PARTIAL / MISSED with file:line evidence.
Return structured verdict: PASS, PASS WITH GAPS, or FAIL."
)
```

Where `MODIFIED_FILES` = output of `git diff --name-only main...HEAD` (from the worktree).

#### Verdict handling

| Verdict | Action |
|---------|--------|
| **PASS** | Log to task notes; proceed to Challenger Gate |
| **PASS WITH GAPS** | Surface gaps inline; log to task notes; proceed to Challenger Gate |
| **FAIL** | Block CLOSE — trigger repair loop below |

Always log: `brana backlog set {task_id} notes --append "Evaluator: {verdict} ({date}), {N} criteria checked"`

#### Repair loop (max 2 iterations)

**Iteration 1 — FAIL verdict:**
```
AskUserQuestion:
  question: "Evaluator: FAIL. {N} criteria MISSED: {list}. How to proceed?"
  header: "Evaluator blocked"
  options:
    - label: "Fix now — loop back to BUILD (Recommended)"
      description: "Missed criteria appended to task context. Re-enter BUILD, then Evaluator re-runs."
    - label: "Override — proceed anyway (reason required)"
      description: "Reason logged to task context. CLOSE proceeds with annotation."
    - label: "Abandon — mark task blocked"
      description: "Task status set to blocked."
```

If "Fix now":
1. Append missed criteria to task context: `brana backlog set {task_id} context --append "Evaluator FAIL (iteration 1, {date}): MISSED — {criteria list}"`
2. Re-enter BUILD. Missed criteria visible as task context.
3. After BUILD completes → validate.sh → Evaluator iteration 2.

**Iteration 2 — if still FAIL:** No further auto-loop. Present unconditionally:
```
AskUserQuestion:
  question: "Evaluator: FAIL (iteration 2). Criteria still missing after one repair pass."
  header: "Unresolved"
  options:
    - label: "Override — proceed (reason required)"
      description: "Reason logged. CLOSE proceeds."
    - label: "Abandon — mark task blocked"
      description: "Task blocked."
```
Log: `brana backlog set {task_id} notes --append "Evaluator gate: 2 iterations, unresolved. Outcome: {override/abandoned}"`

If "Override" (either iteration): require reason, log: `brana backlog set {task_id} context --append "Evaluator override ({date}): {reason}"`.

---

### Challenger Gate

**Applies to:** all strategies except spike and investigation.

Read and follow [`../../_shared/challenger-gate.md`](../../_shared/challenger-gate.md) — the full shared gate: invocation rules, input contract, spawn call, blocking rules, and repair loop (max 2 iterations).

### CLOSE

Read `phases/close.md` (relative to the build skill directory) — the shared CLOSE procedure.

---
