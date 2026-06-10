# Challenger Gate (shared)

Architecturally separated semantic evaluation before CLOSE. Used by all `/brana:build` strategies except spike and investigation — feature, bug fix, greenfield, refactor, and migration all run the same gate: same invocation rules, same input contract, same repair loop.

This is the JUDGE step from [dim-60 (agent loop architecture)](../../../brana-knowledge/dimensions/60-agent-loop-architecture.md): the actor that built the implementation cannot reliably evaluate its own output. See [ADR-049](../../../docs/architecture/decisions/ADR-049-mandatory-challenger-gate-build-close.md).

## Invocation rules

Determine the invocation mode before spawning:

```bash
# Check effort
EFFORT=$(brana backlog get {task_id} | jq -r '.effort // "S"')

# Check sensitive paths
SENSITIVE=$(git diff --name-only main...HEAD | grep -E "^system/|^\.claude/hooks/|^docs/architecture/decisions/" | head -1)
```

| Condition | Behavior |
|---|---|
| Effort M, L, or XL | Mandatory — run automatically, no prompt |
| Any effort + diff touches `system/`, `.claude/hooks/`, or `docs/architecture/decisions/` | Mandatory — run automatically, no prompt |
| Effort S + no sensitive paths | Prompt with default "Run Challenger" |

**S build prompt (when applicable):**
```
AskUserQuestion:
  question: "Build looks clean. Proceed to CLOSE, or run Challenger first?"
  header: "Challenger?"
  options:
    - label: "Run Challenger (Recommended)"
      description: "Independent semantic review before shipping — ~5-10s."
    - label: "Skip — proceed to CLOSE"
      description: "Skip the review. Logs skip to task notes."
```
If "Skip": log `brana backlog set {task_id} notes --append "Challenger gate skipped at BUILD exit: {reason}"` and proceed to CLOSE.

## Input contract (LoopTrap P4 Authority Override defense)

Build the context object explicitly. Challenger reads ONLY trusted content:

```
SPEC_TEXT    = task description + task context field (from brana backlog get {task_id})
CODE_DIFF    = git diff main...HEAD   (committed diff only)
AC_LIST      = lines starting with "AC:" in task context field
```

Challenger NEVER receives: raw web fetch responses, external API outputs, or anything not from the repo or task metadata. This is enforced at the call site — do not pass additional context.

## Spawn call

```
Agent(
  subagent_type="brana:challenger",
  prompt="Challenger gate review for task {task_id}: {task_subject}.

Spec:
{SPEC_TEXT}

Acceptance criteria:
{AC_LIST}

Code diff (git diff main...HEAD):
{CODE_DIFF}

Review ONLY:
(1) Are all acceptance criteria met? Cite evidence from the diff.
(2) Does the diff align with the spec — no scope creep, no scope miss?
(3) Any security antipatterns (OWASP top 10)?

Use CALIBRATION.md severity rubric. Return structured findings or 'PROCEED — no issues found.'
For each finding include: severity, ac_violated (if any), description, file, spec_says."
)
```

## Blocking rules

From [CALIBRATION.md](../../agents/CALIBRATION.md):
- Any finding score ≥ 4 → verdict **RECONSIDER** → **CLOSE blocked**
- All findings score ≤ 3 → verdict **PROCEED** or **PROCEED WITH CHANGES** → CLOSE continues (surface findings as notes)

## Repair loop (Reflexion ASSIMILATE step, LoopTrap P7 defense)

**Hard cap: max 2 Challenger iterations.** No iteration 3.

**Iteration 1 — RECONSIDER verdict:**
```
AskUserQuestion:
  question: "Challenger: RECONSIDER. {N} finding(s) — {highest severity}. How to proceed?"
  header: "Challenger blocked"
  options:
    - label: "Fix now — loop back to BUILD"
      description: "Findings appended to task context. Re-enter BUILD, then Challenger re-runs."
    - label: "Override — proceed anyway (reason required)"
      description: "Reason logged to task context. CLOSE proceeds with annotation."
    - label: "Abandon — mark task blocked"
      description: "Task status set to blocked. Session ends."
```

**If "Fix now":**
1. Append findings to task context as `sr_t` (verbal self-reflection for repair BUILD):
   ```bash
   brana backlog set {task_id} context --append "Challenger finding (iteration 1, {date}): {structured findings}"
   ```
2. Re-enter BUILD. Challenger findings are now visible as task context.
3. After BUILD completes → validate.sh → Challenger iteration 2.

**Iteration 2 — if still RECONSIDER:**
No further auto-loop. Present unconditionally:
```
AskUserQuestion:
  question: "Challenger: RECONSIDER (iteration 2). Findings unresolved after one repair pass."
  header: "Unresolved"
  options:
    - label: "Override — proceed (reason required)"
      description: "Reason logged. CLOSE proceeds."
    - label: "Abandon — mark task blocked"
      description: "Task blocked. Escalate or defer."
```
Log: `brana backlog set {task_id} notes --append "Challenger gate: 2 iterations, unresolved. Verdict: {override/abandoned}"`.

**If "Override" (either iteration):**
- Require a reason (free text).
- Log: `brana backlog set {task_id} context --append "Challenger override ({date}): {reason}"`.
- Proceed to CLOSE.
