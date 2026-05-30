
# Backlog

Manage the project backlog — plan, track, and navigate work across phases,
milestones, and streams. Natural language is the primary interface;
these commands are shortcuts for complex operations.

## When to use

When explicitly managing the backlog: planning phases, viewing roadmaps,
restructuring work. Daily task interaction happens through natural
language guided by the task-convention rule — no skill invocation needed.

## CLI Integration — MANDATORY

**NEVER read or write tasks.json directly.**

**Prefer MCP tools** (brana server) when available — structured JSON, 65% fewer tokens:

### Initiative Model (v3)

Tasks have two new optional fields:

| Field | Values | Purpose |
|-------|--------|---------|
| `epic` | slug string (e.g. `"cc-alignment"`) | Groups tasks under a named epic |
| `work_type` | `implement` / `research` / `design` / `ops` / `review` | Cognitive mode — what kind of work this is |

**Active epic** is set in `~/.claude/tasks-config.json` → `active_epic`. When set, `backlog_focus` / `brana backlog focus` shows ★-marked tasks from that epic first, then P0/P1 overflow from others.

**Stream taxonomy** (v3 — 3 values):

| Value | Covers |
|-------|--------|
| `dev` | code, features, bugs, tech-debt, architecture |
| `ops` | maintenance, docs, config, deploy |
| `research` | spikes, evaluations, knowledge, experiments |

### MCP tools (preferred)

| Operation | MCP tool |
|-----------|---------|
| Get task | `backlog_get(task_id: "t-123")` |
| Get field | `backlog_get(task_id: "t-123", field: "status")` |
| Query tasks | `backlog_query(status: "pending", stream: "dev")` or `backlog_query(kind: "fix")` |
| Filter by epic | `backlog_query(epic: "cc-alignment")` |
| Filter by work type | `backlog_query(work_type: "implement", status: "pending")` |
| Multi-tag AND | `backlog_query(tag: "dx,cli")` |
| Filter by parent | `backlog_query(parent: "ph-001", task_type: "task")` |
| Search | `backlog_search(query: "enforcement")` |
| Aggregate stats | `backlog_stats()` |
| Set field | `backlog_set(task_id: "t-123", field: "status", value: "in_progress")` |
| Set epic | `backlog_set(task_id: "t-123", field: "epic", value: "cc-alignment")` |
| Add/remove tag | `backlog_set(task_id: "t-123", field: "tags", value: "+newtag")` |
| Append text | `backlog_set(task_id: "t-123", field: "context", value: "note", append: true)` |
| Create task | `backlog_add(subject: "...", kind: "feature", task_type: "task")` |
| Create with epic | `backlog_add(subject: "...", epic: "cc-alignment", work_type: "implement")` |
| Focus (top tasks) | `backlog_focus(top: 5)` or `backlog_focus(work_type: "research")` |

### CLI fallback (when MCP unavailable)

| Operation | CLI command |
|-----------|------------|
| Project status | `brana backlog status` |
| Cross-client status | `brana backlog status --all --json` |
| Full roadmap tree | `brana backlog roadmap --json` |
| Subtree of phase | `brana backlog tree <id> --json` |
| Aggregate stats | `brana backlog stats` |
| Tag inventory | `brana backlog tags --output json` |
| Tag filter (AND) | `brana backlog tags --filter "a,b" --output json` |
| Next unblocked task | `brana backlog next --kind feature --tag Y` |
| Next by stream | `brana backlog next --stream dev` |
| Query tasks | `brana backlog query --status pending --kind fix --output json` |
| Filter by epic | `brana backlog query --epic cc-alignment` |
| Filter by work type | `brana backlog query --work-type implement --status pending` |
| Multi-tag AND query | `brana backlog query --tag "dx,cli" --count` |
| Filter by parent | `brana backlog query --parent ph-001 --type task` |
| Get full task | `brana backlog get <id>` |
| Get single field | `brana backlog get <id> --field status` |
| Focus (active epic) | `brana backlog focus` |
| Focus by work type | `brana backlog focus --work-type research` |
| Focus override epic | `brana backlog focus --epic cc-alignment` |

### Write operations

| Operation | CLI command |
|-----------|------------|
| Set any field | `brana backlog set <id> <field> <value>` |
| Set epic | `brana backlog set <id> epic cc-alignment` |
| Set work type | `brana backlog set <id> work_type implement` |
| **Set active epic** | `brana backlog set-active <slug>` |
| Set to null | `brana backlog set <id> priority null` |
| Append to text | `brana backlog set <id> context --append "note"` |
| Add/remove tag | `brana backlog set <id> tags +newtag` / `tags -oldtag` |
| Add blocked_by | `brana backlog set <id> blocked_by +t-100` |
| Create task (JSON) | `brana backlog add --json '{"subject":"...","kind":"feature","type":"task"}'` |
| Create task (shorthand) | `brana backlog add --subject "..." --kind feature --type task --tags "a,b" --effort S` |
| Create with epic | `brana backlog add --subject "..." --epic cc-alignment --work-type implement` |
| Create initiative | `brana backlog add --subject "..." --kind feature --type initiative` |
| Create task (from file) | `brana backlog add --json @/tmp/task.json` |
| Create task (stdin) | `echo '{"subject":"..."}' \| brana backlog add --json -` |
| Rollup parents | `brana backlog rollup` |

### Rules

1. **Prefer MCP tools** (`backlog_query`, `backlog_get`, `backlog_set`, `backlog_add`, `backlog_search`, `backlog_stats`) when available. Fall back to CLI if MCP server is not running.
2. **Every "Read tasks.json" instruction below → call MCP tool or CLI command.**
3. **Every "Write tasks.json" instruction below → call `backlog_set`/`backlog_add` (MCP) or `brana backlog set`/`brana backlog add` (CLI).**
4. For batch creates (plan command), call `backlog_add` once per task.
5. All operations return JSON. MCP returns structured data natively; CLI returns JSON on stdout.
6. All writes are atomic — no need to read-modify-write.
7. Both MCP and CLI auto-detect tasks.json from git root.

## Display Themes

All rendering sections below use the **task-line template** to determine icons,
progress bars, and decorations. Resolve the active theme before rendering:

1. If `--theme <name>` flag is on the command, use it
2. Else read `~/.claude/tasks-config.json` → `{"theme": "<name>"}`
3. Else default to `classic`

### Task-line template

```
classic:   {icon} {id}  {subject}  {detail}
           ✓ done  ← active  → pending  · blocked  · parked
           bars: ████░░░░  {done}/{total}

emoji:     {icon} {id}  {subject}  {detail}
           ✅ done  🔨 active  🔲 pending  🔒 blocked  💤 parked
           bars: ████░░░░  {done}/{total}
           project header: 📋 {name}
           status --all header: boxed ╭╮╰╯ with 📊
           priority high: ⚡high
           blocked ref: ⛓ {id}
           health dots: 🟢 done  🟡 active  🔴 blocked

minimal:   {icon} {id}  {subject}  {detail}
           ● done  ◐ active  ○ pending  ⊘ blocked  ◌ parked
           bars: ━━━━╍╍╍╍  {done}/{total}
           blocked ref: ← {id}
```

### Wide mode (`--wide`)

Any view command (`status`, `roadmap`, `next`, `tags --filter`) accepts `--wide`.
Wide mode renders tasks as **tabular rows** with all metadata visible on one line — like `kubectl get pods -o wide`.
Wide mode composes with any theme (icons come from the active theme).

**Wide-mode template:**

```
Columns:  {icon} {id}  {subject}  {status}  {tags}  {pri}  {eff}  {stream}  {project}  {blocked_by}  {started}  {completed}

Header row (always shown):
  ID       Subject                         Status    Tags              Pri  Eff  Stream   Project      Blocked     Started     Done

Task rows (classic icons):
  ✓ t-007  Design auth flow                done      auth              P1   S    roadmap  —           2026-02-10  2026-02-12
  → t-008  Implement JWT middleware         pending   auth, quick-win   P1   S    roadmap  —           —           —
  · t-009  Write auth tests                blocked   auth              P1   M    roadmap  t-008       —           —

Task rows (emoji icons):
  ✅ t-007  Design auth flow                done      auth              P1   S    roadmap  —           2026-02-10  2026-02-12
  🔲 t-008  Implement JWT middleware         pending   auth, quick-win   P1   S    roadmap  —           —           —
  🔒 t-009  Write auth tests                blocked   auth              ⛓ t-008

Task rows (minimal icons):
  ● t-007  Design auth flow                done      auth              P1   S    roadmap  —           2026-02-10  2026-02-12
  ○ t-008  Implement JWT middleware         pending   auth, quick-win   P1   S    roadmap  —           —           —
  ⊘ t-009  Write auth tests                blocked   auth              P1   M    roadmap  ← t-008     —           —
```

**Rules:**
- `subject` gets remaining width after fixed columns; truncate with `…` if too long
- `tags` shows first 3 comma-separated, then `+N` if more
- Null fields render as `—` (em-dash), never blank
- `project` column: in cross-client views (`--all`), shows `client/project` for multi-project clients, client slug for single-project. In single-project views, shows project slug from tasks.json root or `—`
- Phases/milestones render as **section headers** (bold subject + progress bar, no per-column detail):
  ```
  ph-002  Phase 2: API Foundation                                        ████░░░░ 3/8
    ✓ t-007  Design auth flow              done      auth              P1   S    roadmap  —           2026-02-10  2026-02-12
    → t-008  Implement JWT middleware       pending   auth, quick-win   P1   S    roadmap  —           —           —
  ```
- Without `--wide`, all views use the compact tree layout (unchanged default behavior)

### Tree connectors (all themes)

Hierarchy views (status, roadmap) use box-drawing characters when not in `--wide` mode:

```
├── child (has siblings after)
└── child (last sibling)
│   continuation line
```

---

## Commands

- `/brana:backlog plan [project] "[phase-title]"` — plan a phase interactively
- `/brana:backlog status [project] [--all] [--unified] [--wide]` — progress overview (`--all` = cross-client task drill-down, `--unified` = priority-sorted flat list)
- `/brana:backlog roadmap [project] [--wide]` — full tree view with all levels
- `/brana:backlog next [project] [--stream X] [--wide]` — next unblocked task by priority
- `/brana:backlog start <id>` — begin work on a task
- `/brana:backlog done [id]` — complete current task
- `/brana:backlog add "[description]"` — quick-add a task
- `/brana:backlog replan [project] [phase-id]` — restructure a phase
- `/brana:backlog archive [project]` — move completed phases to archive
- `/brana:backlog migrate <file>` — import tasks from a markdown backlog
- `/brana:backlog execute [scope] [--dry-run] [--max-parallel N] [--retry]` — execute tasks via subagents
- `/brana:backlog tags [project]` — tag inventory, filtering, and bulk tag management
- `/brana:backlog context <id> [text]` — view or set rich context on a task
- `/brana:backlog theme [name]` — view or set display theme (classic, emoji, minimal)
- `/brana:backlog triage [project] [--reresearch] [--scope P2+]` — research-informed priority reassessment
- `/brana:backlog sync [--dry-run] [--force]` — sync tasks.json with GitHub Issues

---

## Step Registry (plan and execute subcommands)

For the `plan` and `execute` subcommands, create a CC Task step registry on entry. Follow the [guided-execution protocol](../_shared/guided-execution.md). Other subcommands (status, roadmap, next, add, etc.) are single-step and don't need a registry.

**plan steps:** DETECT, READ, MILESTONES, TASKS, DEPS, PROPOSE, CHALLENGE, WRITE
**execute steps:** READ, FILTER, WAVES, CONFIRM, EXECUTE, WRITEBACK, REPORT

### Resume After Compression

If context was compressed during a plan or execute flow:

1. Call `TaskList` — find CC Tasks matching `/brana:backlog — {STEP}`
2. The `in_progress` task is your current step — resume from there

---

## /brana:backlog plan

Interactive phase planning. Builds the hierarchy conversationally.

### Steps

1. **Detect project** from CWD (git root -> basename) or argument
2. **Read tasks.json** — if it doesn't exist, create with empty tasks array
3. **If phase title provided**, use it. Otherwise ask: "What phase are you planning?"
3a. **Epic** — read `active_epic` from `~/.claude/tasks-config.json`. If set, assign it to the phase (and all tasks will inherit via `inherit_initiative()`). If unset, ask via AskUserQuestion:
    ```
    question: "Assign this phase to an epic?"
    header: "Epic"
    options:
      - "Use active: {active_epic}" (if one is set)
      - "Enter slug manually"
      - "Skip — no epic"
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
       - "Link {new-subject} → blocked_by {existing-id} {existing-subject} (tag overlap: {shared})"
       - "Merge {new-subject} into {existing-id} (duplicate)"
       - "No relation — keep all as-is"
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
         - "Add test tasks now (Recommended)"
         - "Skip — tests are inline with implementation (Small tasks)"
         - "Skip — not testable (scripts, config, docs only)"
     ```
     If "Add test tasks now": loop back to step 6 to add test tasks before code tasks (with `blocked_by` linking code → tests).
     If "Skip — inline": proceed (Small tasks write tests inline per BUILD step 3d).
     If "Skip — not testable": proceed.
   - **If test tasks found:** proceed to step 12.
   - **If all tasks are docs/config/spec only:** gate passes automatically — no code, no test required.

12. **Challenge gate (M+ tasks)** — If any task in the phase has effort M, L, or XL:
    ```
    AskUserQuestion:
      question: "Phase has M+ effort tasks. Run /brana:challenge before writing?"
      header: "Challenge gate"
      options:
        - "Yes — challenge the plan now (Recommended)"
        - "Skip — already challenged or S-only work"
    ```
    - If "Yes": invoke `/brana:challenge` on the current plan. Address all HIGH findings before proceeding. MEDIUM findings may be noted as risks in task context fields.
    - If "Skip": proceed.
    - **If the phase is an investigation/spike** (strategy: investigation or all tasks tagged `investigation`): recommend the **double-challenge pattern** — challenge once before planning, once after reshaping. Suggest running `/brana:challenge` again after step 8 (PROPOSE).

13. **Wait for approval** — user can adjust before writing
14. **Write tasks.json** — one Write for the entire batch
15. **Report:** show the tree with IDs and tags for reference

### Defaults
- `work_type`: inferred from task kind (implement → feature/fix/refactor, research → research/docs, design → design); ask if ambiguous
- `epic`: inherited from phase (set in step 3a); null if skipped
- Execution: code (if project has .git), manual (otherwise)
- Priority/effort: null (user provides later if needed)
- Status: pending for all new tasks

---

## /brana:backlog status

High-level progress view with aggregation. Use `--all` for cross-client task-level drill-down.

**Delegate entirely to CLI. Do not read tasks.json or compute anything manually.**

### Steps

1. Run `brana backlog status` — outputs themed project status (progress bar, counts)
2. Run `brana backlog stats` — outputs JSON aggregate stats (by_status, by_state, by_stream, by_priority, by_type). `by_status` keys are raw `task.status` values (queryable via `--status`); `by_state` keys are synthetic display values (`done`, `active`, `blocked`, `parked`, `pending`).
3. Run `brana backlog next` — outputs themed next-up list (top 5 by priority)
4. Present the CLI output directly to the user. Do not reformat or recompute.

### Cross-client view (`--all`)

Run `brana backlog status --all` — CLI handles portfolio aggregation, theming, and rendering.

For JSON output (when you need to process data): `brana backlog status --all --json`

### Additional detail (optional, only if user asks)

- Blocked chains: `brana backlog blocked`
- Stream breakdown: already in `brana backlog stats` output
- Phase tree: `brana backlog roadmap`
- Specific phase subtree: `brana backlog tree <phase-id>`

---

## /brana:backlog roadmap

Full tree view — every level expanded.

**Delegate entirely to CLI. Do not read tasks.json or build trees manually.**

### Steps

1. Run `brana backlog roadmap` — outputs themed full tree (phases -> milestones -> tasks with icons, progress bars, blocked indicators)
2. Present the CLI output directly to the user. Do not reformat.

For JSON output: `brana backlog roadmap --json`
For a subtree: `brana backlog tree <phase-or-milestone-id>`

---

## /brana:backlog next

Find the highest-priority unblocked task.

**Delegate entirely to CLI.**

### Steps

1. Run `brana backlog next` — outputs themed top-5 list sorted by priority
2. Present the CLI output directly.

Optional filters (pass through to CLI):
- By tag: `brana backlog next --tag scheduler`
- By stream: `brana backlog next --stream dev` or `--stream research`

---

## /brana:backlog start

Begin work on a task or freeform description. Accepts task IDs, phase IDs, or natural language. For code tasks, enters the `/brana:build` loop. This is the unified entry point — `/brana:do` is an alias for `start` with freeform text.

### Steps

1. **Parse argument** — detect input type:
   - **Task/subtask ID** (matches `^(t|st)-\d+$`): look up the task directly → step 2
   - **Phase/milestone ID** (matches `^(ph|ms)-\d+$`): look up the phase → step 1b (batch detection)
   - **Freeform text** (anything else, or `/brana:do` invocation): → step 1a (skill routing)
   - **No argument**: offer candidates from `/brana:backlog next`

1a. **Freeform text routing** (absorbs `/brana:do` logic):
   Search for matching skills via ruflo:
   ```
   mcp__ruflo__memory_search(
     query: "{freeform text}",
     namespace: "skills",
     limit: 5,
     threshold: 0.3
   )
   ```
   If MCP unavailable, fall back to CLI: `brana skills suggest --query "{text}"`

   Present results using the same threshold logic as step 5 (skill suggestion):
   - Above suggest_threshold (0.5): suggest via AskUserQuestion
   - Between thresholds (0.3–0.5): mention inline
   - Below mention_threshold (0.3): offer marketplace search

   Always include a "Create task first" option. If the user selects it:
   - Create a task via `brana backlog add --json '{"subject": "{text}", ...}'`
   - Continue to step 2 with the new task ID

   If the user selects a skill instead:
   - Invoke it: `Skill(skill="brana:{name}", args="{text}")`
   - Stop here — no task flow needed

1b. **Batch detection** (phase/milestone ID):
   Query children: `brana backlog query --parent {id} --status pending`
   Evaluate batch eligibility:
   - **3+ unblocked tasks** AND
   - **Average effort ≤ M** (S=1, M=2, L=3, XL=4; avg ≤ 2) AND
   - **Dependency density < 0.3** (blocked_by edges / total tasks < 0.3)

   If batch-eligible, propose:
   ```
   AskUserQuestion:
     question: "Phase has {N} parallelizable tasks (avg effort: {avg}). Run as batch or interactive?"
     header: "Mode"
     options:
       - "Batch — /brana:backlog execute {id} (Recommended)"
       - "Interactive — pick one task to start"
   ```
   - If batch: invoke `Skill(skill="brana:backlog", args="execute {id}")` — stop here
   - If interactive: present unblocked children for selection → continue to step 2 with chosen task

   If NOT batch-eligible (fewer tasks, high deps, large effort):
   - Present unblocked children for selection → continue to step 2

2. **Read tasks.json**, find the task
3. **Check blocked_by** — if any blocker not completed, warn and abort
4. **Auto-classify strategy** (if not already set on the task):
   - Infer from task kind, tags, and description:
     - `kind: fix` or `stream: dev` or tag `bug` → strategy: `bug-fix`
     - `kind: research` or `stream: research` → strategy: `spike`
     - `kind: refactor` or tag `refactor` → strategy: `refactor`
     - `kind: docs` or `stream: ops` → strategy: `feature` (light)
     - Tag `migration` → strategy: `migration`
     - Tag `investigation` → strategy: `investigation`
     - Default → strategy: `feature`
   - **Confirm with user:** "Start t-008 as **feature**? [feature / bug-fix / refactor / spike / other]"
   - Write the confirmed `strategy` field to the task
   - **If strategy is `investigation`:** surface the double-challenge pattern:
     > "Investigation tasks benefit from two challenge rounds: challenge the design after shaping, then challenge the reshaped plan before writing tasks. `/brana:challenge` can be invoked at any point — recommended after step 8 (PROPOSE) and again after addressing findings."
5. **Skill suggestion** (after strategy confirmed):

   Read `skill_routing` from `~/.claude/tasks-config.json` (defaults: `suggest_threshold: 0.5`, `mention_threshold: 0.3`, `enabled: true`). If `enabled: false`, skip step 5.

   **5a.** Build query from task metadata: `"{subject} {tags joined} {strategy}"`

   **5b.** Try MCP (primary — semantic matching via HNSW, namespace "skills"):
   ```
   mcp__ruflo__memory_search(
     query: "{query from 5a}",
     namespace: "skills",
     limit: 5,
     threshold: 0.3
   )
   ```

   **5c.** If MCP unavailable, fall back to CLI:
   ```bash
   brana skills suggest --task <id>
   ```

   **5d.** Present results based on confidence:

   - **Top result > suggest_threshold (default 0.5):**
     ```
     AskUserQuestion:
       question: "Suggested skill for this task:"
       header: "Skill"
       options:
         - "/brana:{top_name} (score: {score})" (Recommended)
         - "/brana:{second_name} (score: {score})" (if available)
         - "Skip — none needed"
     ```

   - **Top result between mention_threshold and suggest_threshold (0.3–0.5):**
     Mention inline: "Possible match: /brana:{name} ({score})" — no AskUserQuestion, no blocking.

   - **All results < mention_threshold (0.3) — MANDATORY acquisition offer:**
     Do NOT skip this. Low scores mean a potential skill gap — the user must be given the choice.
     Only if task execution is `code` (skip for external/manual tasks), offer marketplace search:
     ```
     AskUserQuestion:
       question: "No local skill matches this task. Search externally?"
       header: "Gap"
       options:
         - "Search externally"
         - "Skip"
     ```
     If user selects "Search externally":
     ```
     Skill(skill="brana:acquire-skills", args="{subject keywords}")
     ```
     The acquire-skills skill handles marketplace search, evaluation, and installation.

     **After either choice**, write breadcrumb to task context:
     ```
     backlog_set(task_id: "<id>", field: "context", value: "skill_gap_checked: true (score < 0.3, user chose: {choice})", append: true)
     ```

   - **No results (ruflo down + CLI fails):**
     Skip silently. Don't block task start.

   **5e.** If user selects a skill, note it in the task's `context` field for the build loop.

   **5f. Agent pool check** (code tasks, effort M+ only — skip for S/XL and non-code):
   Check if warm pool agents are available for background delegation:
   ```
   mcp__ruflo__agent_pool(action: "status", agentType: "claude")
   ```
   If pool has idle agents (`idle > 0`):
   ```
   AskUserQuestion:
     question: "Pool has {idle} warm agent(s). Run in-session or delegate to background pool?"
     header: "Execution mode"
     options:
       - "In-session (default — interactive, you see progress)"
       - "Background pool (fire and forget — check results later)"
   ```
   If user selects **background**: spawn with `mcp__ruflo__agent_spawn(agentType: "claude", domain: "{project}", model: "sonnet", task: "{task subject + strategy}")` and stop — do NOT enter `/brana:build`.
   If user selects **in-session**, pool is empty, or ruflo unavailable: proceed to step 6.

6. **Determine execution mode:**
   - `code`: check git status clean → create branch `{prefix}{id}-{slug}` → set status + started date + branch field → **enter `/brana:build` with the task's strategy** (build_step: classify)
   - `external`: set status + started date, show task description
   - `manual`: set status + started date, show checklist from description
7. **Write tasks.json** (status: in_progress, started: today, strategy: confirmed)
7b. **Task claim (best-effort):**
   ```
   # SESSION_ID = current branch name (git branch --show-current)
   mcp__ruflo__claims_claim(
     issueId: "task:{id}",
     claimant: "agent:{SESSION_ID}:session"
   )
   ```
   If MCP unavailable or claim fails, continue — claims are advisory, not blocking.
8. **GitHub sync** (if `github_sync.enabled` in `~/.claude/tasks-config.json`):
   - If task has no `github_issue`: run `system/scripts/gh-sync.sh create {task-id} {tasks-json-path}`. Read issue number from stdout, write to task's `github_issue` field.
   - If task has `github_issue`: run `system/scripts/gh-sync.sh pull-context {issue-number}`. If comments returned, replace `## GitHub Comments` section in task's `context` field.
   - If sync fails (exit code 1 or 2): warn "GitHub sync failed. Task started locally." — do NOT block start.
9. **Report:** "Started t-008 'Implement JWT middleware' as **feature**. Branch: feat/t-008-jwt-middleware."
10. **For code tasks:** invoke `/brana:build` immediately using the Skill tool:
   ```
   Skill(skill="brana:build", args="{task-id}")
   ```
   This is mandatory — do NOT stop after the report. The build loop takes over from CLASSIFY onward.

### Branch creation

```bash
# Check for existing branch
git branch --list "feat/t-008-*" 2>/dev/null
# If exists: "Branch already exists. Resume?" -> checkout
# If not: create new
git checkout -b feat/t-008-jwt-middleware
```

Integrate with worktree pattern if on a different branch:
```bash
git worktree add ../project-feat-t-008 -b feat/t-008-jwt-middleware
```

---

## /brana:backlog done

Complete the current task. For code tasks that went through `/brana:build`, the CLOSE step already handles completion — use `/brana:backlog done` only for manual and external tasks.

### Steps

1. **Identify task:**
   - If id provided, use it
   - If on a task branch (feat/t-NNN-*), extract id from branch name
   - Otherwise: show in_progress tasks, ask which one
2. **Read tasks.json**, find the task
3. **Check if build-managed:** if the task has a `build_step` field set, warn: "This task is in the /brana:build loop (step: {build_step}). Use /brana:build CLOSE to complete it, or force-complete here?"
4. **For execution: code** (non-build-managed):
   - Stage changes: `git add -A` (or ask user what to stage)
   - Commit with conventional type from stream mapping
   - Create PR: `gh pr create --title "{type}: {subject}" --body "Closes #{github_issue}"`
   - Offer to merge: "Merge to main? (PR #{N})"
   - **Worktree cleanup:** if task was started in a worktree (`git worktree list` shows `../project-{prefix}{id}`), offer to remove it after merge: `git worktree remove ../project-{prefix}{id} && git branch -d {branch}`
5. **For execution: external/manual:**
   - Ask: "Any notes on the outcome?"
   - Record in task.notes
   - **Doc prompt:** if the task produced user-visible deliverables (check: tags contain `docs`, `feature`, `workflow`, `skill`, or description mentions "build", "create", "launch", "design"), ask via AskUserQuestion:
     ```
     question: "This task produced deliverables. Generate documentation?"
     options:
       - "Tech doc + user guide" (writes both from templates)
       - "Tech doc only"
       - "User guide only"
       - "Skip docs"
     ```
     If user selects any doc option, generate using templates at `system/skills/build/templates/tech-doc.md` and/or `system/skills/build/templates/user-guide.md`. Output to `docs/architecture/features/{task-slug}.md` and/or `docs/guide/features/{task-slug}.md`.
6. **Update task:** status → completed, completed → today's date, clear build_step
6b. **Release task claim (best-effort):**
   ```
   # SESSION_ID = current branch name (git branch --show-current)
   mcp__ruflo__claims_release(
     issueId: "task:{id}",
     claimant: "agent:{SESSION_ID}:session",
     reason: "task completed"
   )
   ```
   If MCP unavailable, skip silently.
7. **Write tasks.json** — hook handles rollup + validation
8. **GitHub sync** (if `github_sync.enabled` in `~/.claude/tasks-config.json`):
   - If task has `github_issue`: run `system/scripts/gh-sync.sh close {issue-number}`.
   - If sync fails: warn "GitHub issue not closed. Close manually: gh issue close #{issue-number}" — do NOT block done.
9. **Report:** "Completed t-008. Milestone 'Auth System': 2/3 done."

---

## /brana:backlog add

Quick-add a single task with intelligent suggestions.

### Steps

All interactive confirmations use the **AskUserQuestion** tool for a selectable UI experience. Batch independent questions into a single AskUserQuestion call (up to 4 questions per call).

1. **Parse description** from argument. If no description provided: scan recent conversation turns for actionable items — problems discussed, ideas proposed, improvements suggested, or work identified. Draft a subject + description from the strongest candidate and present it: "Add task: '{subject}'? [Confirm / Edit / Cancel]". If no actionable item found in conversation, ask for a description.
2. Read tasks.json (all pending tasks, active milestones, tag vocabulary)
3. **URL auto-detection:** if the description contains `https://`, suggest `kind: research`, auto-extract the URL to the `context` field (format: `URL: {url}`), and skip the kind/milestone prompt.
4. **First question batch** — use a single AskUserQuestion with up to 4 questions:
   - **Kind** (skip if URL auto-detected): `feature`, `fix`, `refactor`, `research`, `docs`, `design`, `ops`. Header: "Kind"
   - **Tags**: suggest tags from description keywords matched against existing vocabulary. Options: "Accept {suggested}" (recommended), "Edit", "Skip". Header: "Tags"
   - **Effort**: suggest from description complexity (S/M/L/XL). Options: each size with description. Header: "Effort"
   - **Milestone** (skip if URL auto-detected or no active milestones): options from active milestones + "None". Header: "Milestone"
5. Auto-assign next id, set defaults. Auto-classify `strategy` from description/kind/tags (same heuristic as `/brana:backlog start`). Leave `build_step` null.
6. **Dependency scan** — cross-reference all pending tasks:
   - Match by **tag overlap** (2+ shared tags with the new task)
   - Match by **subject keyword** overlap (significant words from description appear in existing task subjects)
   - If candidates found, present via AskUserQuestion (multiSelect: true):
     ```
     question: "Link any as blocked_by?"
     options: one per candidate task ("{id} {subject} (reason)")
     ```
   - If no candidates found, skip silently
   - **Never auto-commit dependencies** — always ask
   - **Research cross-reference** (runs alongside dependency scan):
     - Adding a **non-research** task → scan `stream: research` or `work_type: research` tasks for tag overlap → include in dependency question or separate AskUserQuestion
     - Adding a **research** task → scan non-research tasks for tag overlap → surface as informational note
7. **Build-trap check** — if the description contains solution verbs ("build", "implement", "create", "add", "setup") without outcome/problem context:
   - AskUserQuestion: "This looks like a solution. What problem does it solve?" Options: user provides context via "Other" free text, or "Skip". Header: "Problem"
   - If the user provides text, store it in the `context` field
   - If skipped, proceed without context
8. Priority: **leave null** (user sets manually via `/brana:backlog triage` or direct edit)
9. **Final confirmation** — AskUserQuestion: "Add {id} '{subject}' [{tags}, {effort}] under {milestone}? blocked_by: [{deps}]" Options: "Confirm" (recommended), "Edit", "Cancel". Header: "Confirm"
10. Write tasks.json
11. **GitHub sync** (if `github_sync.enabled` in `~/.claude/tasks-config.json`):
    - Run `system/scripts/gh-sync.sh create {task-id} {tasks-json-path}`. Read issue number from stdout, write to task's `github_issue` field.
    - If sync fails: warn "GitHub issue not created. Run `/brana:backlog sync` later." — do NOT block add.

---

## /brana:backlog replan

Restructure an existing phase.

### Steps

1. Read tasks.json, show current tree for the phase
2. Interactive: "What changes? (add tasks, reorder, move, remove)"
3. Propose updated structure
4. Confirm before writing
5. Handle orphan prevention: if removing a milestone, reassign or remove its children

---

## /brana:backlog archive

Move completed phases to archive.

### Steps

1. Read tasks.json
2. Find phases with status: completed
3. Show: "Archive these completed phases? [list]"
4. Move subtrees to tasks-archive.json (create if doesn't exist)
5. Remove from tasks.json
6. Update next_id counters (don't reset — IDs are never reused)
7. Report: "Archived {N} phases ({M} tasks). Active file: {remaining} tasks."

---

## /brana:backlog migrate

Import tasks from an existing markdown backlog.

### Steps

1. Read the markdown file
2. Parse structure: headings -> phases/milestones, checkboxes -> tasks
3. Propose tasks.json structure with assigned IDs
4. Wait for approval — user adjusts mapping
5. Write tasks.json
6. Report: "Imported {N} tasks from {file}."

---

## /brana:backlog tags

Tag inventory, filtering, and bulk tag management.

### Usage

```
/brana:backlog tags [project]                    — tag inventory (all tags + task counts)
/brana:backlog tags --filter "tag1,tag2"         — AND filter (tasks with ALL listed tags)
/brana:backlog tags --any "tag1,tag2"            — OR filter (tasks with ANY listed tag)
/brana:backlog tags add <id|ids> "tag1,tag2"     — add tags to one or more tasks
/brana:backlog tags remove <id|ids> "tag1"       — remove a tag from one or more tasks
```

### Steps

**Inventory (no subcommand):**
1. **Resolve active theme** (see Display Themes)
2. Read tasks.json
3. Collect all unique tags across all tasks
4. Count tasks per tag (include status breakdown)
5. Render:

```
Tags in {project}:

  scheduler     4 tasks  (2 pending, 1 in_progress, 1 completed)
  quick-win     3 tasks  (3 pending)
  research      2 tasks  (1 in_progress, 1 completed)
  auth          2 tasks  (2 pending)
```

**Filter (`--filter` or `--any`):**
1. Read tasks.json
2. `--filter`: keep tasks where tags array contains ALL specified tags (AND)
3. `--any`: keep tasks where tags array contains ANY specified tag (OR)
4. **If `--wide`**, render using **wide-mode template** (all columns). Otherwise render using task-line template — flat list with status and tags:

```
Tasks tagged [scheduler]:
  → t-008 Implement JWT middleware [scheduler, auth]     pending
  · t-012 Seed dev data [scheduler]                      blocked
  ← t-018 Deploy scheduler config [scheduler, quick-win] in_progress
  ✓ t-021 Scheduler v2 research [scheduler, research]    completed
```

Icons come from active theme (example above uses classic).

**Add tags:**
1. Parse task id(s) — comma-separated or space-separated
2. Parse tags — comma-separated quoted string
3. Read tasks.json, find tasks
4. Append new tags (deduplicate, preserve existing)
5. Confirm: "Add tags [scheduler, auth] to t-008, t-009?"
6. Write tasks.json

**Remove tags:**
1. Parse task id(s) and tag to remove
2. Read tasks.json, filter out the tag from each task's tags array
3. Confirm: "Remove tag 'scheduler' from t-008, t-009?"
4. Write tasks.json

---

## /brana:backlog context

View or set rich context on a task — rationale, links, notes, decisions.

### Usage

```
/brana:backlog context <id>                     — show context for a task
/brana:backlog context <id> "context text"      — set context (replaces existing)
/brana:backlog context <id> --append "note"     — append to existing context
```

### Steps

**View (no text):**
1. Read tasks.json, find task by id
2. If context is null/empty: "No context set for {id}. Add some?"
3. If context exists: display it with task subject as header

```
t-008 Implement JWT middleware

Context:
  Rationale: chose JWT over session cookies for stateless API. See ADR-005.
  Key constraint: tokens must expire in 15min, refresh tokens in 7d.
  Related: t-009 (tests), ms-003 (parent milestone).
```

**Set (with text):**
1. Read tasks.json, find task
2. Replace context field with provided text
3. Confirm: "Set context on t-008?"
4. Write tasks.json

**Append (`--append`):**
1. Read tasks.json, find task
2. If context is null, set to the appended text
3. If context exists, append with newline separator
4. Confirm: "Append to t-008 context?"
5. Write tasks.json

---

## /brana:backlog theme

View or set the display theme.

### Usage

```
/brana:backlog theme              — show current theme
/brana:backlog theme emoji        — set theme to emoji
/brana:backlog theme classic      — set theme to classic
/brana:backlog theme minimal      — set theme to minimal
```

### Steps

**View (no argument):**
1. Read `~/.claude/tasks-config.json`
2. If file exists and has `theme` field, show: "Current theme: **{name}**"
3. If no file: "Current theme: **classic** (default). Set with `/brana:backlog theme <name>`."

**Set (with name):**
1. Validate name is one of: `classic`, `emoji`, `minimal`
2. Read `~/.claude/tasks-config.json` (create if missing)
3. Set `theme` field to the given name, preserve other fields
4. Write the file
5. Report: "Theme set to **{name}**. All `/brana:backlog` output will use {name} icons."

### Config format

```json
{
  "theme": "emoji"
}
```

Stored at `~/.claude/tasks-config.json` (global, not per-project).

---

## /brana:backlog execute

Execute tasks via subagents — DAG-aware parallel execution with automatic wave scheduling.

```
/brana:backlog execute [scope] [--dry-run] [--max-parallel N] [--retry]
```

**Arguments:**
- `scope`: task/milestone/phase ID, or `"next"` for the next unblocked wave. Default: next
- `--dry-run`: show execution plan without running agents
- `--max-parallel N`: max concurrent subagents per wave (default: 3)
- `--retry`: re-run failed/partial tasks, skip completed

### Prerequisites

Tasks must have `spawn` field set (see ADR-003 for schema). Tasks without `spawn` are skipped with a message: "no tasks configured for agent execution."

### Steps

1. **Read tasks.json**, identify scope
2. **Filter executable tasks** — only tasks with `spawn: "subagent"` and status `pending` (or `in_progress`/failed for `--retry`)
3. **Build execution waves** from `blocked_by` DAG (topological sort):
   - Wave 1: tasks with no unmet dependencies
   - Wave 2: tasks whose blockers are all in wave 1
   - Wave N: tasks whose blockers are all in earlier waves
4. **Check parent `spawn_strategy`** — if set, override wave ordering:
   - `"parallel"`: all children in one wave (ignore inter-child deps)
   - `"sequential"`: one task per wave, in order
   - `"auto"`: use DAG (default behavior)
5. **Present execution plan:**
   ```
   Execution plan for ph-002 (3 waves, 8 tasks):

     Wave 1 (parallel):
       t-007 Design auth flow          haiku   research
       t-010 Design schema             haiku   research

     Wave 2 (parallel):
       t-008 Implement JWT middleware   sonnet  code
       t-011 Write migrations           sonnet  code

     Wave 3 (parallel):
       t-009 Write auth tests           sonnet  code
       t-012 Seed dev data              sonnet  code

   Estimated: 3 waves, max 2 parallel agents per wave.
   Proceed? (yes / dry-run was requested)
   ```
6. **User confirms**
7. **Execute wave-by-wave:**

   **7a. Swarm init** (once per execute run, before first wave):
   ```
   mcp__ruflo__swarm_init(topology: "mesh", maxAgents: {max_parallel}, strategy: "adaptive")
   ```
   Captures the swarmId for use in agent_spawn calls below.
   **Fallback:** If ruflo unavailable, skip swarm init — use native Task tool per task as before.

   - **Knowledge injection (per task, before spawning):**
     Query ruflo for domain context related to the task:
     ```
     mcp__ruflo__memory_search(
       query: "{task.subject} {task.tags joined by space}",
       namespace: "knowledge",
       limit: 3,
       threshold: 0.4
     )
     ```
     - If results found (score >= 0.4): format as a `## Knowledge context` section with one bullet per result (`- {key}: {value preview}`). Prepend to the agent prompt.
     - If no results or ruflo unavailable: skip silently. Knowledge injection is best-effort — never blocks spawning.

   **7b. Per-task claim** (before spawning each agent):
   ```
   mcp__ruflo__claims_claim(
     issueId: "task:{task.id}",
     claimant: "agent:{swarmId}:{task.id}",
     context: "{task.subject}"
   )
   ```
   If claim fails (another agent holds it), skip this task in the wave — it may be running in a parallel session.

   - For each task in the wave, spawn a subagent via ruflo (preferred) or Task tool (fallback):
     ```
     mcp__ruflo__agent_spawn(
       agentType: "{agent_config.type or 'claude'}",
       model: "{computed model from routing table}",
       domain: "{project_slug}",
       task: "{task subject + description + knowledge context}",
       swarmId: "{swarmId from 7a}"
     )
     mcp__ruflo__coordination_orchestrate(
       task: "{task.subject}",
       agents: ["{agentId}"],
       strategy: "parallel"
     )
     ```
     **Fallback (ruflo unavailable):** use native Task tool:
     - `subagent_type`: from `agent_config.type` (default: `"general-purpose"`)
     - `model`: from `agent_config.model`
     - `prompt`: task subject + description + relevant context + knowledge context

   - **Non-code tasks** (research, analysis, manual):
     - Agent produces a summary/deliverable
     - Write `agent_result` to tasks.json: `{status: "completed", summary: "...", completed_at: "..."}`
     - Mark task status: completed
   - **Code tasks** (execution: code):
     - Agent reads code, composes changes, writes output to `/tmp/task-{id}-output.json`
     - Agent does NOT write to project files — compose only
     - Queue task for write-back phase
   - **Failed tasks:**
     - Write `agent_result`: `{status: "failed", error: "...", completed_at: "..."}`
     - Task stays `in_progress`. Dependents remain blocked.
     - Log error and continue with remaining tasks in wave

   **7c. Per-task release or mark-stealable** (after each task completes or fails):
   - On completion:
     ```
     mcp__ruflo__claims_release(issueId: "task:{task.id}", claimant: "agent:{swarmId}:{task.id}", reason: "completed")
     ```
   - On failure (agent timed out or errored):
     ```
     mcp__ruflo__claims_mark-stealable(issueId: "task:{task.id}", reason: "stale", context: "{error summary}")
     ```
   Skip silently if ruflo unavailable — claims are advisory, never blocking.
8. **Write-back phase** (code tasks, sequential):
   - For each completed code task:
     - Read `/tmp/task-{id}-output.json`
     - Create worktree: `git worktree add ../project-{prefix}{id} -b {prefix}{id}-{slug}`
     - Apply changes in worktree
     - Run tests (if applicable)
     - If tests pass: commit, mark completed
     - If tests fail: mark `agent_result.status: "partial"`, leave for user
     - Clean up: remove worktree
9. **Report summary** (render using task-line template icons for completed):
   ```
   Execution complete:
     ✓ 6 tasks completed
     ◐ 1 task partial (t-009: tests failed)
     ✗ 1 task failed (t-012: agent timeout)

   Milestone 'Auth System': 3/4 done
   Next: /brana:backlog execute --retry ph-002
   ```
   Icons come from active theme (✓/✅/● for completed).

### Model routing

See `system/skills/_shared/model-routing.md` for the canonical Router-as-Haiku pattern. Summary below.

Before spawning an agent for a task, compute a complexity score (0.0–1.0):

| Input | Score contribution | Max |
|-------|-------------------|-----|
| `min(word_count(description) / 100, 0.3)` | Description length | 0.3 |
| `min(len(blocked_by) * 0.1, 0.2)` | Dependency count | 0.2 |
| `0.2` if stream is `dev` | Stream type | 0.2 |
| `0.1` if `architecture` in tags | Architecture tag | 0.1 |
| `0.1` if effort is `L` or `XL` | Effort estimate | 0.1 |

Score → model mapping:
- **< 0.3** → haiku (simple tasks)
- **0.3–0.7** → sonnet (standard tasks)
- **> 0.7** → opus (complex tasks)

**Override:** If the task or `agent_config.model` specifies a model explicitly, that wins over the computed score.

**Logging:** Log each routing decision to the decision log as a `cost` entry: `brana decisions log --agent backlog --entry-type cost --content "t-NNN routed to MODEL (score: X.XX)"`

**User override tracking:** If the user explicitly requests a different model than the computed score suggests (e.g., "use opus for this"), log the override: `brana decisions log --agent backlog --entry-type cost --content "t-NNN override: computed=MODEL1 (score: X.XX), user chose MODEL2"`. After 10+ overrides in the same direction (e.g., user keeps upgrading haiku→sonnet), `/brana:review routing` will flag this as a threshold adjustment signal.

**Fallback:** If no task metadata is available (e.g., ad-hoc agent spawn), use the agent's default model from its frontmatter.

### Failure recovery

- `--retry` re-runs tasks with `agent_result.status` of `"failed"` or `"partial"`
- Completed tasks are skipped
- User can also fall back to manual: `/brana:backlog start <id>` on any failed task

### Schema fields (on task objects)

```json
{
  "spawn": "subagent",
  "agent_config": {"type": "general-purpose", "model": "sonnet"},
  "agent_result": null
}
```

After execution:
```json
{
  "agent_result": {
    "status": "completed",
    "summary": "Implemented JWT middleware with refresh token rotation",
    "error": null,
    "completed_at": "2026-02-18T14:30:00Z"
  }
}
```

On parent tasks, `spawn_strategy` controls child batching:
```json
{
  "type": "milestone",
  "spawn_strategy": "auto"
}
```

---

## /brana:backlog triage

Research-informed priority reassessment across project backlogs.

### Usage

```
/brana:backlog triage [project] [--reresearch] [--scope P2+]
```

### Default behavior (no flags)

1. Read tasks.json for the project (or portfolio if omitted)
2. For each pending task without a priority, analyze: revenue impact, urgency, dependencies, effort
3. Propose priority assignments (P0-P3 tiers: P0 = this week, P1 = next, P2 = queue, P3 = backlog)
4. Wait for approval before writing

### With `--reresearch`

1. Read tasks.json
2. Identify tasks with external context: URLs in description/context/notes, tool/platform names in tags (e.g., "kapso", "respond-io", "meta")
3. For each, spawn a scout agent for brief web research (latest docs, changelog, API status)
4. Compare findings against current task description — flag if scope changed, tool matured, or blocker resolved
5. Propose priority adjustments with research summary
6. Wait for approval before writing

### With `--scope P2+`

Only re-evaluate tasks at P2 or lower (skip P0/P1 which were recently triaged).

### Priority tiers

| Tier | Meaning | Review cadence |
|------|---------|----------------|
| P0 | This week — active work | Daily |
| P1 | Next up — queue | Weekly |
| P2 | Backlog — when bandwidth allows | Monthly |
| P3 | Icebox — someday/maybe | Quarterly |

### Sort order

P0 > P1 > P2 > P3 > null. Ties broken by: in_progress first, then pending, then `order` field.

---

## /brana:backlog sync

Sync tasks.json with GitHub Issues. Creates missing issues, closes completed ones, updates stale labels.

### Usage

```
/brana:backlog sync [--dry-run] [--force]
```

### Steps

1. **Check config** — read `github_sync.enabled` from `~/.claude/tasks-config.json`. If not enabled, report: "GitHub sync not configured. Add `github_sync` to `~/.claude/tasks-config.json`."
2. **Read tasks.json** — find tasks needing sync:
   - Non-completed tasks without `github_issue` → need creation
   - Completed tasks with `github_issue` + open issue → need closing
   - Tasks with label drift (compare current task fields against live GitHub labels via `gh issue view --json labels`)
3. **Report plan:** "Sync plan: ~N to create, ~M to close, ~K to update."
4. **If `--dry-run`:** show the plan (task IDs + subjects) and exit without executing.
5. **If not dry-run:** confirm with user before executing.
6. **Execute:** run `system/scripts/gh-sync.sh sync-all {tasks-json-path}`. Script handles progress output.
7. **If `--force`:** run `system/scripts/gh-sync.sh sync-all {tasks-json-path}` without filtering — re-sync all tasks.
8. **Report summary:** "Sync complete: N created, M closed, K errors."
