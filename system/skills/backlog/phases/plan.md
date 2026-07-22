<!-- backlog phase: /brana:backlog plan — interactive phase planning, TDD + challenge gates — loaded per the PHASES registry in ../SKILL.md (t-1942) -->

## /brana:backlog plan

Interactive phase planning. Builds the hierarchy conversationally.

### Steps

1. **Detect project** from CWD (git root -> basename) or argument
2. **Read tasks.json** — if it doesn't exist, create with empty tasks array
3. **If phase title provided**, use it. Otherwise ask: "What phase are you planning?"
3a. **Epic** — resolve `active_epic` via `mcp__brana__backlog_focus(top: 0)` (its `active_epic` field is project-scoped — never a raw read of `~/.claude/tasks-config.json`, which can hold a foreign project's value at the global scope, ADR-066). If MCP unavailable, fall back to `brana backlog focus --json`'s first element's `active_epic` field. If set, assign it to the phase (and all tasks will inherit via `inherit_initiative()`). If unset, ask via AskUserQuestion:
    ```
    question: "Assign this phase to an epic?"
    header: "Epic"
    options:
      - label: "Use active: {active_epic}" (if one is set)
        description: "Assign the currently active epic to this task."
      - label: "Enter slug manually"
        description: "Type the epic slug directly."
      - label: "Skip — no epic"
        description: "Leave this task without an epic assignment."
    ```
    Assign the epic to the phase task; child milestones and tasks inherit automatically at write-time.
4. **Create the phase task** (type: phase) with next available ph-N id; include `epic` if set in step 3a
5. **Ask for milestones:** "What are the key milestones in this phase?"
6. **For each milestone**, ask: "Break down {milestone} into tasks?"
   - If yes: ask for tasks and their `work_type` (implement / research / design — infer from description if obvious, confirm with user), create with parent → milestone id
   - If no: create milestone only, tasks deferred
7. **Ask about dependencies:** "Any tasks that block others?"
8. **Propose the full tree** formatted as a roadmap view
9. **Cross-reference scan** — before finalizing, check the broader backlog for overlap:
   - Collect all subjects and tags from the proposed new tasks in this phase
   - Search existing pending tasks via CLI:
     ```bash
     brana backlog search "{subject keywords}"    # per proposed task
     brana backlog query --tag "{tag1},{tag2}"     # for each unique tag in the phase
     ```
   - Match by **subject keyword overlap** (significant words from proposed task subjects appear in existing task subjects)
   - Match by **tag overlap** (2+ shared tags between a proposed task and an existing task)
   - **If overlaps found**, present via AskUserQuestion (multiSelect: true):
     ```
     question: "Found existing tasks that overlap with proposed phase tasks:"
     options:
       - label: "Link {new-subject} → blocked_by {existing-id} {existing-subject} (tag overlap: {shared})"
         description: "Create the task and mark it blocked by the overlapping existing task."
       - label: "Merge {new-subject} into {existing-id} (duplicate)"
         description: "Don't create a new task; add this scope to the existing task instead."
       - label: "No relation — keep all as-is"
         description: "Create the task independently with no relation."
     ```
   - **If no overlaps found**, skip silently
   - **Never auto-link or auto-merge** — always ask the user
10. **Offer bulk tags:** "Tag all tasks in this phase? (comma-separated, or skip)" — applies tags to every task in the phase

> ⛔ **REQUIRED GATE — do not proceed to step 12 without completing step 11.**

11. **Gate: plan completeness** — Before approval, verify the plan includes test artifacts. Writing tests and ADRs IS planning — not a separate step after implementation. **This gate fires for every plan that contains code tasks. There is no exception for S-sized builds at the plan stage.**

   **How to check:** Scan ALL proposed tasks (subjects + descriptions + tags) for test-related work: keywords "test", "spec", "TDD", "coverage", or tasks in a `tests/` path. Count separately: (a) code tasks (work_type: implement/design), (b) test tasks.

   - **If code tasks exist but NO test tasks are found:** hard block. Use AskUserQuestion — do NOT proceed to step 12 without user input:
     ```
     AskUserQuestion:
       question: "Plan has code tasks but no test tasks. Tests are part of planning (DDD→SDD→TDD). Add test tasks?"
       header: "TDD gate"
       options:
         - label: "Add test tasks now (Recommended)"
           description: "Create separate test tasks linked to implementation tasks."
         - label: "Skip — tests are inline with implementation (Small tasks)"
           description: "Tests will be written alongside code in a single task."
         - label: "Skip — not testable (scripts, config, docs only)"
           description: "This work type doesn't require separate test tasks."
     ```
     If "Add test tasks now": loop back to step 6 to add test tasks before code tasks (with `blocked_by` linking code → tests).
     If "Skip — inline": proceed (Small tasks write tests inline per BUILD step 3d).
     If "Skip — not testable": proceed.
   - **If test tasks found:** proceed to step 12.
   - **If all tasks are docs/config/spec only:** gate passes automatically — no code, no test required.

11b. **Acceptance-criteria generation** (ADR-047 §5; implements loop+goal-native planning) — for each **leaf** task with `work_type` `implement` or `design`, generate machine-checkable `acceptance_criteria` so the task can auto-complete under `/goal` (see [`docs/architecture/ac-grammar.md`](../../../../docs/architecture/ac-grammar.md) for the 8 heuristics). Skip phases, milestones, and `research`/`docs`-only tasks.

   **a. Generate (template + LLM-fill by `work_type`):** scaffold 1–3 criteria, then fill specifics from the task subject/description:
   - `implement` → `"<project test cmd>" passes` (infer: `cargo test` / `pytest` / `bun test` / `bash tests/<file>.sh` from project manifest) **plus** one observable: `file <impl path> contains "<symbol>"` or `validate.sh Check <N> passes`.
   - `design` → `file docs/architecture/decisions/<adr-slug>.md exists` (or the doc the task produces).

   **b. Lint each (warn, don't block)** — classify every generated criterion:
   ```bash
   bash system/scripts/ac-lint.sh "<criterion>"   # exit 0 "checkable" | exit 1 "prose"
   ```
   For any that returns `prose`, warn inline — never silently drop or auto-rewrite:
   ```
   ⚠ {task_id}: criterion "<text>" won't auto-complete (prose) — loop will need manual sign-off. Keep, or rephrase to a heuristic in ac-grammar.md?
   ```
   Keep prose criteria the user confirms (genuine human-judgment checks are allowed).

   **c. Atomicity signal** — if a leaf task would carry **>10 criteria** (ADR-047 §1) or is **effort M+**, flag it:
   ```
   ⚠ {task_id} ({effort}, {N} criteria) looks too large for one goal cycle — consider splitting into atomic leaf tasks.
   ```
   Suggest a split (loop back to step 6); never force.

   **d. Write at step 14** via the structured field (canonical — not `AC:` lines):
   ```bash
   brana backlog set {task_id} acceptance_criteria '["<c1>", "<c2>"]'   # or backlog_add --acceptance-criteria (repeatable)
   ```

   Skip silently if the phase has no implement/design leaf tasks.

12. **Challenge gate (M+ tasks)** — If any task in the phase has effort M, L, or XL:
    ```
    AskUserQuestion:
      question: "Phase has M+ effort tasks. Run /brana:challenge before writing?"
      header: "Challenge gate"
      options:
        - label: "Yes — challenge the plan now (Recommended)"
          description: "Run /brana:challenge on this plan before writing tasks."
        - label: "Skip — already challenged or S-only work"
          description: "Proceed without a challenge pass."
    ```
    - If "Yes": invoke `/brana:challenge` on the current plan. Address all HIGH findings before proceeding. MEDIUM findings may be noted as risks in task context fields.
    - If "Skip": proceed.
    - **If the phase is an investigation/spike** (strategy: investigation or all tasks tagged `investigation`): recommend the **double-challenge pattern** — challenge once before planning, once after reshaping. Suggest running `/brana:challenge` again after step 8 (PROPOSE).

13. **Wait for approval** — user can adjust before writing
14. **Write tasks.json** — one Write for the entire batch
15. **Report:** show the tree with IDs and tags for reference

### Defaults
- `work_type`: inferred from task kind (implement → feature/fix/refactor, research → research/docs, design → design); ask if ambiguous
- `acceptance_criteria`: auto-generated for leaf implement/design tasks (step 11b) — template+LLM-fill, linted against [`ac-grammar.md`](../../../../docs/architecture/ac-grammar.md), written to the canonical field
- `epic`: inherited from phase (set in step 3a); null if skipped
- Execution: code (if project has .git), manual (otherwise)
- Priority/effort: null (user provides later if needed)
- Status: pending for all new tasks

---

