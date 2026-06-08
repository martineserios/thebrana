# Skill Validation Checklist

Every brana skill should pass this checklist before being considered complete. Derived from the [12-Factor Agents manifesto](https://github.com/humanlayer/12-factor-agents) (humanlayer, 2025), adapted to CC skill architecture.

---

## The Checklist

### 1. Trigger description routes correctly

The `Use when:` line unambiguously activates this skill and does not conflict with other skills. A reader unfamiliar with the system can predict which skill fires for a given user phrase.

- [ ] Trigger is specific (not "use this for coding tasks")
- [ ] Trigger does not overlap with an adjacent skill's trigger
- [ ] Skill routes to `Not for:` list avoids false matches

### 2. Prompts are explicit and self-contained

The skill does not rely on ambient session context to behave correctly. All inputs and preconditions are stated inside the skill file.

- [ ] Required task ID, branch, or file paths are stated or fetched at skill start
- [ ] No implicit assumption about what the user typed before invoking
- [ ] Preflight step verifies preconditions before doing work

### 3. Context loading is bounded

The skill does not load more than it needs into context. Large files, full git logs, and entire directories are loaded only when the skill explicitly requires them.

- [ ] Skill reads only the files its workflow references
- [ ] No unconditional `cat` of large files at startup
- [ ] Subagents are used when a step would otherwise consume significant context

### 4. Control flow is explicit

The skill's steps are listed and sequential. There are no implicit loops, no "continue as appropriate" instructions, and no steps that depend on the model remembering earlier context.

- [ ] Workflow steps are numbered and complete
- [ ] Early-exit conditions are stated (e.g., "if no tasks are pending, report and stop")
- [ ] Resume behavior after context compaction is defined or not required

### 5. Errors become context, not stops

When a step fails (CLI error, missing file, empty result), the skill produces context for the next step rather than aborting silently or crashing the session.

- [ ] CLI failures surface a human-readable message
- [ ] Empty results are handled explicitly ("nothing found" is a valid output)
- [ ] Partial results proceed to the next step with a note, not a hard stop

### 6. Task state is updated

If the skill performs work covered by a backlog task, it updates the task status at completion. Skills do not leave tasks in `in_progress` after the session ends.

- [ ] Marks task `in_progress` at start if applicable
- [ ] Marks task `completed` (or notes blockers) at end
- [ ] Does not create new tasks without also assigning them a status and effort

### 7. Outputs are user-facing, not internal

The skill's final output is addressed to the user, not to itself. Status lines, summaries, and next actions are phrased as human-readable communication.

- [ ] Final message answers "what happened and what's next"
- [ ] No raw JSON or debug output left in the final response unless explicitly requested
- [ ] Next step is actionable (a command, a decision, or explicit "nothing to do")

### 8. Skill is single-responsibility

The skill does one job. If it is doing two independent jobs, those are two skills.

- [ ] Skill name unambiguously describes one action
- [ ] Can be invoked without side-effecting an unrelated system
- [ ] "Also does X" is a smell — X belongs in its own skill or a subskill

### 9. Tool calls are typed and constrained

The skill does not use Bash as a universal escape hatch. Structured tools (Read, Edit, Write, Grep, Glob) are preferred; Bash is used only for shell operations with no dedicated tool equivalent.

- [ ] File reads use the Read tool, not `cat` via Bash
- [ ] File edits use the Edit tool, not `sed` via Bash
- [ ] Bash is used for: git commands, CLI invocations, process control

### 10. Human contact is explicit

When the skill needs a decision from the user, it asks once with a clear question. It does not loop, guess, or proceed on an assumption.

- [ ] Decision points use `AskUserQuestion` or a clearly phrased question in output
- [ ] Skill does not proceed on ambiguous input
- [ ] If the user can provide feedback that changes behavior, that feedback path is documented

### 11. Skill is idempotent (where applicable)

Running the skill twice on the same state produces the same outcome. Side effects are guarded against double-application.

- [ ] Re-running a completed skill does not create duplicate tasks, commits, or files
- [ ] Idempotency exceptions are documented (e.g., "always appends a new log entry")

### 12. Skill can be audited

A reviewer reading the skill file can understand what it does, why, and when to use it — without running it.

- [ ] `Use when:` and `Not for:` are accurate and specific
- [ ] `## Input` section lists all required context (if applicable)
- [ ] `## Steps` or equivalent workflow section is complete and current

---

## How to Use This Checklist

**New skill:** Run through all 12 items before marking the skill ready.

**Existing skill audit:** Start with items 1, 4, and 8 — these are the most common failure modes (trigger overlap, implicit control flow, and scope creep).

**When a skill keeps misfiring:** Check item 1 (trigger specificity) and item 10 (human contact — does the skill ask when it should, or proceed when it should ask?).

---

## Origin

Derived from the [12-Factor Agents manifesto](https://github.com/humanlayer/12-factor-agents) by humanlayer (2025). The twelve factors (stateless reducer, own your prompts, own your context window, tools as structured outputs, unify execution and business state, launch/pause/resume, contact humans with tool calls, own your control flow, compact errors into context, small focused agents, trigger from events, stateless reducer) are mapped here to the CC skill primitive rather than to general agentic systems.

See also: [docs/reference/skills.md](skills.md) for skill authoring conventions.
