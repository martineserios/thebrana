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

## Mechanical pre-check: exit-contract lint (t-2888)

Before spawning the challenger, run the deterministic lint over the same diff range:

```bash
system/scripts/exit-contract-lint.sh main...HEAD
```

Registry: helpers marked `# Exit contract` in `system/skills/_shared/*.md` — the class
that was dropped three times against `resolve_epic_ancestor` (t-2263, t-2843, t-2845)
despite documentation at the source.

| Exit | Meaning | Action |
|---|---|---|
| 0 | clean | proceed to spawn |
| 1 | added call site doesn't branch on the helper's exit status | fix the call site(s) in BUILD, re-run the lint, then spawn |
| 2 | registry empty/unreadable | the **lint** is broken, not the diff — fix it; never skip silently |

Semantics (kept distinct from the LLM gate):
- Mechanical violations do **not** consume the max-2 Challenger iteration cap — the cap
  counts LLM challenger runs only. The challenger still runs after the lint is clean: it
  judges whether a *branched* call distinguishes every documented outcome; the lint owns
  only the mechanical class (no branch at all).
- Intentionally ignoring a helper's failure requires an explicit `|| true` at the call
  site — that is the opt-out, not an override.
- Disputed violation: require a reason and log it with the mechanical prefix so
  CALIBRATION.md's monthly finding review can filter non-LLM findings:
  ```bash
  brana backlog set {task_id} notes --append "Challenger gate (mechanical exit-contract-lint): overridden ({date}) — {reason}"
  ```

## Sizing valve (ADR-082 rungs 0–2)

After the mechanical lint and before spawning, compute the beat's rung. The ladder,
signals table, briefs, and helpers are single-sourced in
[`judge-sizing.md`](judge-sizing.md) — **do not restate any mapping here** (the
t-2494 drift class). Sequence:

```bash
# Inputs — all machine-readable (ADR-082 §1):
EFFORT=$(brana backlog get {task_id} --field effort 2>/dev/null | tr -d '"')
KIND=$(brana backlog get {task_id} --field kind 2>/dev/null | tr -d '"')
FILES=$(git diff --name-only main...HEAD | tr '\n' ' ')
NATURE=$(nature_class "$KIND" "$FILES")
CRIT=$(criticality_hit "$FILES")
# Fired signals this beat (comma-separated, from recorded events only):
#   RECONSIDER_SEV4      — prior challenger iteration verdict RECONSIDER with sev >= 4
#   PASS_WITH_GAPS       — evaluator verdict PASS-WITH-GAPS
#   CRITICAL_PATH        — CRIT=1 doubles as this signal when the diff lands in a critical section
#   SIBLING_VERDICT      — parse_sibling_verdict on the prior verdict printed "yes"
#   ESCAPED_DEFECT_AREA  — judge_area_weight "{task area}" >= 1
RUNG=$(resolve_judge_rung "$EFFORT" "$NATURE" "$CRIT" "$SIGNALS_CSV") || {
    echo "⚠ judge-sizing valve broken (exit $?) — fix the valve; never skip silently" >&2; exit 2; }
```

**Beat report line (always, every beat):** `judge rung: {N} — {shape}` plus, for any
mechanism whose precondition failed, an explicit unarmed line, e.g.
`blind test-author did not arm: AC unapproved` (`blind_author_arms` prints the
verdict; an unarmed mechanism must be observable, never silent — ADR-082 §2).

| Rung | What this gate does differently |
|---|---|
| 0 | Nothing — the flow below runs exactly as written (single challenger) |
| 1 | Spawn the **second-variant finder** (brief from judge-sizing.md §Briefs) in the same message as the challenger — parallel, blind (diff-only). Its findings merge into the same blocking rules |
| 2 | Run the funnel per judge-sizing.md §Spawn contracts: 2 nature-routed finders → haiku filter → strongest-model default-refute verify. `SPLIT` verdicts surface to the human as their own class — never suppressed |

**Signal timing:** a signal fired by this beat's own judge pass arms the raised rung
for the *re-judgment* (repair-loop iteration 2 runs at the raised rung); the
delivered verdict stands (ADR-082 §2 Timing).

**Control arm (first 6 rung-2 firings):** run the rung-1 shape (lone second-variant
finder) alongside the full funnel on the same beat; record both counts in the
escaped-defect log's `control_arm: {rung1_findings, panel_findings}` field
(`append_escaped_defect` 7th arg). This is the data ADR-082 §6's rung-2-collapse
decision reads. Every rung ≥ 1 firing appends a log record regardless
(`append_escaped_defect docs/ops/escaped-defects.jsonl ...`).

Panel-role allowlists are subset-only (`judge_allowlist_violations` must print
nothing — ADR-082 §4e); panel spawns never consume the max-2 challenger iteration
cap (same rule as the mechanical lint).

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
(4) Does this fix have structural siblings outside the diff — the same pattern in a
    parallel path, second variant, or sibling consumer the diff does not touch?
    End your verdict with the recorded field, exactly one of:
    'SIBLINGS: yes — {paths}' or 'SIBLINGS: no'.

Use CALIBRATION.md severity rubric. Return structured findings or 'PROCEED — no issues found.'
For each finding include: severity, ac_violated (if any), description, file, spec_says."
)
```

The `SIBLINGS:` line is signal 4's source (ADR-082 §3): `parse_sibling_verdict` reads
it — a recorded `yes` arms rung 2 for the re-judgment pass. A missing field means
prompt drift: treat as NOT fired and state the omission in the beat report.

## Blocking rules

From [CALIBRATION.md](../../agents/CALIBRATION.md):
- Any finding score ≥ 4 → verdict **RECONSIDER** → **CLOSE blocked**
- All findings score ≤ 3 → verdict **PROCEED** or **PROCEED WITH CHANGES** → CLOSE continues

**Always log** (t-2857 — this line is machine-read, not just a human record; matches the
`Evaluator:` convention in [verify-gates.md](../build/phases/verify-gates.md)):
```bash
brana backlog set {task_id} notes --append "Challenger: {verdict} ({date}), {N} finding(s), max severity {score}"
```
`{verdict}` is exactly `PROCEED`, `PROCEED WITH CHANGES`, or `RECONSIDER` — no other
wording. Findings themselves (the numbered list) may still be surfaced as additional
notes text alongside this line; the verdict line's exact wording is the contract.

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
