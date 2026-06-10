<!-- build phase: BUILD loop (all strategies) — loaded per the PHASES registry in ../SKILL.md (t-1942) -->

<!-- ruflo preamble -->
ToolSearch("select:mcp__ruflo__agent_spawn,mcp__ruflo__hive-mind_memory")

### BUILD

**Hive-mind announce (best-effort):**
At build start, announce what you're working on:
```
mcp__ruflo__hive-mind_memory(
  action: "set",
  key: "client:{PROJECT}:build:{TASK_ID}",
  value: {"status": "in-progress", "branch": "{BRANCH}", "task": "{SUBJECT}", "started": "{ISO_TIMESTAMP}"}
)
```
At build end (success or failure), update status:
```
mcp__ruflo__hive-mind_memory(
  action: "set",
  key: "client:{PROJECT}:build:{TASK_ID}",
  value: {"status": "done|failed", "branch": "{BRANCH}", "task": "{SUBJECT}", "completed": "{ISO_TIMESTAMP}"}
)
```
If MCP unavailable, skip silently. Hive-mind is transient awareness, not critical path.

**Loop suggestion (L/XL builds only — one per invocation, ADR-050):**
For effort L or XL tasks only, once per build invocation, optionally suggest a session loop:
```
AskUserQuestion:
  question: "Long build detected. Start a session loop to nag about uncommitted changes every 20 min?"
  header: "Loop?"
  options:
    - label: "Yes — start loop"
      description: "Runs: git status --porcelain (exits 0 if clean). durable:false — dies with session."
    - label: "No thanks"
      description: "Skip. Will not ask again this session."
```
If "Yes": invoke `CronCreate` with `durable: false`, interval ≥20 min (past cache TTL) or ≤4 min (within TTL) — never 5–19 min (ScheduleWakeup worst-of-both). Prompt must reference a machine-verifiable check (`git status --porcelain`, `validate.sh`, test exit code) — never open-ended assessment. If user declines, drop silently; never re-ask in the same session.

Skip this step for: S/XS builds, spike/investigation strategies, and any invocation where the loop was already offered this session (check `~/.claude/run-state/loop-offered-{task_id}` sentinel).

1. **Create branch** (if not already on one):
   ```bash
   git checkout -b feat/{task-id}-{slug}
   ```

2. **Create CC Tasks for subtask tracking** (Medium/Large builds only):
   For each subtask from DECOMPOSE, create a CC Task for compression resilience:
   ```
   TaskCreate:
     subject: "/brana:build -- BUILD/subtask: {subtask subject}"
     description: "{acceptance criteria}"
     addBlockedBy: [previous subtask CC Task ID]
   ```
   **Naming convention:** Always prefix with `/brana:build -- BUILD/subtask:` so the
   resume-after-compression protocol can distinguish these from build step-level CC Tasks
   (`/brana:build -- DECOMPOSE`, `-- BUILD`, etc.).

   **Authority split:**
   - **CC Tasks** = session-scoped progress. Survives context compression within a session.
   - **tasks.json** (via CLI) = persistent state. Survives across sessions.
   - On subtask completion: update BOTH (CC Task → completed, `brana backlog set {id} status completed`).
   - On conflict: tasks.json wins (it's the durable record).

   **Trivial/Small builds:** Skip CC Tasks. Progress tracked inline in conversation.

   **Agent delegation rule:** When spawning an agent for any subtask implementation, use model routing (Router-as-Haiku pattern — see `system/skills/_shared/model-routing.md`) to pick the cheapest sufficient model:
   ```
   score = complexity_score(subtask)   # see model-routing.md formula
   model = score < 0.3 ? "haiku" : score < 0.7 ? "sonnet" : "opus"
   mcp__ruflo__agent_spawn(agentType: "claude", domain: "{project_slug}", model: model, task: "{subtask description + TDD checklist}")
   ```
   Fall back to native `Agent(subagent_type: "claude", prompt: "...")` if ruflo is unavailable — use the same model selection.

   Always include the delegation TDD checklist — append it verbatim from `system/skills/_shared/delegation-tdd-checklist.md` to the task/prompt:
   > Include the acceptance criteria from `system/skills/_shared/delegation-tdd-checklist.md` verbatim at the end of this prompt. Do not mark the subtask done until all criteria are met.

   Never delegate implementation without explicit TDD acceptance criteria — agents that receive "implement X" without a checklist produce code without tests.

   **Scope drift prevention:** Agents drift into adjacent artifacts at task boundary seams — they fill gaps they perceive, not gaps they were given. Before delegating any M+ task, add an explicit "Out of scope" callout naming specific files or dirs the agent must not touch. Example: `"Do NOT create backlog-reconcile.sh — that is tracked separately under t-1765."` (promoted 2026-05-30 from session debrief)

3. **For each task** (in dependency order):
   a. **Mark CC Task in_progress** (if created): `TaskUpdate: status → in_progress`
   b. **Skill check** (Medium/Large builds only): run `brana skills suggest --query "<subtask subject and key terms>"`. If a match scores > 0.3, mention it: "Skill available: /brana:{name} ({reason}). Use it?" If the user says yes, invoke the skill for this subtask. If no match, proceed without mentioning.
   b2. **Pre-edit challenger: procedure and skill files** — Before the first Edit to any `system/procedures/*.md`, `system/skills/*/SKILL.md`, or `system/skills/*/phases/*.md` file in this build (any effort, any strategy), run challenger on the spec:
      ```
      Agent(
        subagent_type="brana:challenger",
        prompt="Pre-edit challenger review for {task_id}: {task_subject}.

      Spec: {task description + context field}
      Planned change: {what you're about to edit and why}
      Target file(s): {matching paths}

      Review: (1) Is this the right change for the stated problem? (2) Any unintended side-effects on model behavior? (3) Does this conflict with existing patterns or adjacent procedures?
      Return numbered findings or 'Proceed — no issues found.'"
      )
      ```
      Present findings inline. If any finding is RECONSIDER-severity, ask:
      ```
      AskUserQuestion:
        question: "Pre-edit challenger raised concern(s) about {file}. How to proceed?"
        header: "Challenger"
        options:
          - label: "Adjust the plan first (Recommended)"
            description: "Revise the spec or scope, then re-enter BUILD."
          - label: "Proceed anyway"
            description: "Proceed with the original plan; findings noted."
      ```
      This gate fires once per build (not per subtask). The post-build Challenger Gate (before CLOSE) is separate — both gates run for procedure/skill edits; this pre-edit gate is advisory, the post-build gate has blocking rules. (t-1431)
   c. **State what you'll change** — which files, why, how it maps to acceptance criteria
   d. **Write failing test** — the acceptance criteria become test assertions
   d2. **Gate: TEST → IMPLEMENT** — Before writing any implementation code, verify test files were created or modified in this subtask. Check `git diff --name-only` and `git diff --cached --name-only` for test file patterns (`*test*`, `*spec*`, `tests/`, `__tests__/`).
      - **If test files found:** proceed to implementation.
      - **If no test files found:** hard block.
        ```
        AskUserQuestion:
          question: "No test files written yet for this subtask. Tests are part of the plan — write them before implementing. What to do?"
          header: "TDD gate"
          options:
            - label: "Write tests now (Recommended)"
              description: "Add tests before proceeding to implementation."
            - label: "Skip — not a testable change (config, docs, markup)"
              description: "This change type doesn't warrant tests."
            - label: "Skip — reason required"
              description: "Skip tests but provide justification for the task log."
        ```
        If "Write tests now": loop back to step 3d.
        If "Skip — not testable": proceed (no log needed for config/docs/markup).
        If "Skip — reason required": require free text, log: `brana backlog set {id} notes --append "TDD gate skipped: {reason}"`.
      - **Skip this gate for:** spike strategy, investigation strategy, and subtasks tagged `docs` or `config`.
   e. **Implement** — make the test pass
   f. **Verify** — run tests, lint, compare before/after
   g. **Probe boundaries** (after green tests) — explicitly test what should NOT work:
      - Invalid inputs: nulls, empty strings, out-of-range values, wrong types
      - Edge cases: zero, max int, empty collections, concurrent access
      - Error paths: missing files, network failures, permission denied
      - Spec negatives: behaviors the spec says must be rejected
      Write at least 2 boundary tests per subtask. If any reveal a bug, fix before committing.
      Skip for trivial changes (config, docs, markup).
   h. **Commit** — `feat(scope): description`
   i. **Mark CC Task completed** + update tasks.json: `brana backlog set {subtask-id} status completed`
   j. **Mini-debrief:**
      - What surprised?
      - Spec mismatch? (feature spec says X, reality requires Y)
      - Reusable pattern?
      - Store significant findings in ruflo

4. **At natural breakpoints** (every 2-3 tasks), ask:
   ```
   question: "Continue to next task, or review/adjust?"
   options: ["Continue", "Review", "Adjust tasks"]
   ```

> **☑ Checkpoint — BUILD** (M+ builds with task_id; write after all subtasks complete):
> ```bash
> printf '{"step":"BUILD","completed":"%s","task_id":"%s"}\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "{task_id}" >> ~/.claude/run-state/{task_id}.jsonl
> ```

