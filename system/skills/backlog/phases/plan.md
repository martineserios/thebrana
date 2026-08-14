<!-- backlog phase: /brana:backlog plan — interactive phase planning, TDD + challenge gates — loaded per the PHASES registry in ../SKILL.md (t-1942) -->

## /brana:backlog plan

<!-- ruflo preamble -->
ToolSearch("select:mcp__brana__backlog_focus,mcp__brana__backlog_query")

Interactive phase planning. Builds the hierarchy conversationally.

### Steps

1. **Detect project** from CWD (git root -> basename) or argument
2. **Read tasks.json** — if it doesn't exist, create with empty tasks array
3. **If phase title provided**, use it. Otherwise ask: "What phase are you planning?"
3a. **Epic** — epic membership is the `parent` chain to a `type: "epic"` node (ADR-065); the flat `epic` field is retired and write-sealed (t-2310) — never set it. Resolve `active_epic` via `mcp__brana__backlog_focus(top: 0)` (its `active_epic` field is project-scoped — never a raw read of `~/.claude/tasks-config.json`, which can hold a foreign project's value at the global scope, ADR-066). If MCP unavailable, fall back to `brana backlog focus --json`'s first element's `active_epic` field. If set, map the slug to its epic node (`mcp__brana__backlog_query(task_type: "epic")`, match `subject == slug`; CLI: `brana backlog query --type epic` — works since t-2377) and set it as the **phase task's** `parent` in step 4 — the phase task is the ONLY node parented to the epic; child milestones and tasks inherit membership through the parent chain automatically, never re-parent them to the epic node directly. If unset, ask via AskUserQuestion:
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
    Membership lands on the phase task's `parent`; child milestones and tasks inherit automatically through the chain.
4. **Create the phase task** (type: phase) with next available ph-N id; set its `parent` to the epic node id resolved in step 3a (if any)
5. **Ask for milestones:** "What are the key milestones in this phase?"
6. **For each milestone**, ask: "Break down {milestone} into tasks?"
   - If yes: ask for tasks and their `work_type` (implement / research / design — infer from description if obvious, confirm with user), create with parent → milestone id
   - If no: create milestone only, tasks deferred
7. **Ask about dependencies:** "Any tasks that block others?"
7a. **WAVES** (ADR-080 §2) — if the phase has 2+ milestones with tasks under them,
   emit a wave graph from the plan structure using the shared primitives in
   [`../../_shared/wave-graph-emit.md`](../../_shared/wave-graph-emit.md):
   - **One wave per milestone**, selector `parent:<ms-id>` — no tags written.
   - **Gate chain (cross-milestone only)** from the dependency edges gathered
     in step 7: if any task under milestone B is `blocked_by` a task under a
     *different* milestone A, wave-B's gate is
     `wave_name_for_milestone(epic_slug, A's milestone-slug)`. A `blocked_by`
     edge between two tasks in the *same* milestone is not a gate edge — it
     stays inside that milestone's wave. Independent milestones share a gate
     or have none.
   - **Contract** seeded from the milestone's stated definition-of-done (prose).
     Quote it as a single shell argument when interpolating into a `wave add`
     call (step 14) — free prose can contain `"`, backticks, or `$(...)`, and
     an unescaped double-quoted interpolation can break argument parsing or
     execute a substitution. Pass it as one already-quoted string, never build
     the command by concatenating unescaped prose into a larger quoted string.
   - **Wave naming**: `wave_name_for_milestone(epic_slug, ms_slug)` →
     `<epic-slug>-<ms-slug>`.
   - **Cycle check before WRITE**: pipe the full `id<TAB>gate` set through
     `wave_gate_chain_has_cycle` (from the shared file). A cycle is a hard stop —
     surface the diagnostic and fix the milestone dependency edges before
     proceeding; never display or write a cyclic graph. This plan-time check is
     the first line of defense — the epic runner's PREFLIGHT cycle-STOP
     (ADR-080 §3.1) is the last, not the only one.
   - If the phase has 0 or 1 milestones, skip 7a silently — nothing to group.
8. **Propose the full tree** formatted as a roadmap view, and — if step 7a
   produced a wave graph — display it alongside the task tree in the same
   PROPOSE gesture (ADR-080 §2.4): one line per wave (`<name>`: selector, gate,
   contract). The human approves the graph and the tree together.
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

11b. **Acceptance-criteria generation** (ADR-047 §5; implements loop+goal-native planning) — for each **leaf** task with `work_type` `implement` or `design`, generate machine-checkable `acceptance_criteria` so the task can auto-complete under `/goal` (see [`docs/architecture/ac-grammar.md`](../../../../docs/architecture/ac-grammar.md) for the 10 heuristics). Skip phases, milestones, and `research`/`docs`-only tasks.

   **a. Generate (template + LLM-fill by `work_type`):** author **grammar-matching shapes FIRST** (ac-grammar.md heuristics 1–10) — freeform prose only as fallback when no shape fits — and check demand, not just clarity (ac-grammar.md §Authoring rules: would the minimal under-delivering implementation still pass? If yes, raise demand — quantify over the full set, or add a `demoable: <command>`). Scaffold 1–3 criteria, then fill specifics from the task subject/description:
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
14. **Write tasks.json** — one Write for the entire batch. **If step 7a produced a
   wave graph**, create the wave objects too, only now (on approval), each
   `status: queued` (per-wave, gate before selector so an upstream wave name
   resolves for `--gate`):
   ```bash
   brana backlog wave add --name "<wave-name>" --selector "parent:<ms-id>" \
     --contract "<milestone definition-of-done>" [--gate <upstream-wave-name>]
   ```
15. **Report:** show the tree with IDs and tags for reference, plus the wave graph if one was written

### Defaults
- `work_type`: inferred from task kind (implement → feature/fix/refactor, research → research/docs, design → design); ask if ambiguous
- `acceptance_criteria`: auto-generated for leaf implement/design tasks (step 11b) — template+LLM-fill, linted against [`ac-grammar.md`](../../../../docs/architecture/ac-grammar.md), written to the canonical field
- epic membership: phase task's `parent` → epic node (step 3a); children inherit through the parent chain — there is no per-task epic field (retired, ADR-065)
- Execution: code (if project has .git), manual (otherwise)
- Priority/effort: null (user provides later if needed)
- Status: pending for all new tasks

---

