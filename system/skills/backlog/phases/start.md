<!-- backlog phase: /brana:backlog start — task start, strategy, skill suggestion, branch creation — loaded per the PHASES registry in ../SKILL.md (t-1942) -->

## /brana:backlog start

Begin work on a task or freeform description. Accepts task IDs, phase IDs, or natural language. For code tasks, enters the `/brana:build` loop. This is the unified entry point — `/brana:do` is an alias for `start` with freeform text.

<!-- ruflo preamble -->
ToolSearch("select:mcp__ruflo__memory_search,mcp__ruflo__agent_spawn,mcp__ruflo__swarm_init,mcp__ruflo__claims_claim,mcp__ruflo__claims_release,mcp__ruflo__claims_mark-stealable,mcp__ruflo__coordination_orchestrate,mcp__ruflo__agent_pool,mcp__brana__backlog_query")

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
       - label: "Batch — /brana:backlog execute {id} (Recommended)"
         description: "Execute all tasks in the plan sequentially via backlog execute."
       - label: "Interactive — pick one task to start"
         description: "Choose one task to start now and defer the rest."
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
         - label: "/brana:{top_name} (score: {score})" (Recommended)
           description: "Use the top-matching skill for this task type."
         - label: "/brana:{second_name} (score: {score})" (if available)
           description: "Use the second-best matching skill instead."
         - label: "Skip — none needed"
           description: "No skill acquisition needed; proceed without one."
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
         - label: "Search externally"
           description: "Search skills.sh or marketplace for a matching skill."
         - label: "Skip"
           description: "Proceed without installing a skill."
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
       - label: "In-session (default — interactive, you see progress)"
         description: "Run agents inline — visible progress, blocks until done."
       - label: "Background pool (fire and forget — check results later)"
         description: "Dispatch to background workers; results available later."
   ```
   If user selects **background**: spawn with `mcp__ruflo__agent_spawn(agentType: "claude", domain: "{project}", model: "sonnet", task: "{task subject + strategy}")` and stop — do NOT enter `/brana:build`.
   If user selects **in-session**, pool is empty, or ruflo unavailable: proceed to step 6.

6. **Determine execution mode:**
   - `code`: check git status clean → compute and display branch name (see Branch creation below) → create branch → set status + started date + branch field → **enter `/brana:build` with the task's strategy** (build_step: classify)
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
9. **Report:** "Started t-008 'Implement JWT middleware' as **feature**. Branch: harness-core/feat/t-008-implement-jwt-middleware."
10. **For code tasks:** invoke `/brana:build` immediately using the Skill tool:
   ```
   Skill(skill="brana:build", args="{task-id}")
   ```
   This is mandatory — do NOT stop after the report. The build loop takes over from CLASSIFY onward.

### Branch creation

Branch name follows the project convention (CLAUDE.md §Branch naming):
```
{epic-slug}/{work-type}/t-{NNN}-{subject-slug}
```

**Computing the branch name:**
1. `epic-slug` — the flat `epic` field is retired (backlog-v3 migration, ADR-065, t-2284)
   and its write path is sealed (t-2310) — do not read or set `task.epic`. Instead resolve
   the epic-node ancestor via the task's `parent` chain. Read and follow
   [`../../_shared/epic-ancestor-walk.md`](../../_shared/epic-ancestor-walk.md) — call
   `resolve_epic_ancestor(task_id)`.

   **Check the exit status first (t-2487).** A non-zero exit means the lookup broke, not
   that the task lacks an epic — the two used to be indistinguishable. On non-zero: emit
   "⚠ epic lookup failed for t-NNN (backlog read error) — not naming a branch on an
   unknown epic" and stop. Do not fall through to the no-epic message below, which would
   send the user to set a parent that may already be correct.

   If it returns empty *at exit 0* (no epic ancestor found, or none of the ancestors are a
   valid slug): emit warning and stop: "⚠ Task t-NNN has no epic ancestor. Set one first:
   `brana backlog set t-NNN parent <epic-task-id>` (list candidates via
   `mcp__brana__backlog_query(task_type: \"epic\")` — the CLI's `brana backlog query
   --type epic` currently errors, since backlog-v3's epic-as-top nodes were never added
   to its `--type` enum; use the MCP tool or `brana backlog query --json | jq -r '.[] |
   select(.type=="epic") | .id+" "+.subject'` instead), then re-run start." Do not create
   a branch with a placeholder epic.
2. `work-type` — resolve via the shared authority. Read and follow
   [`../../_shared/branch-prefix.md`](../../_shared/branch-prefix.md) — call
   `resolve_branch_prefix(task.kind, task.work_type)`.

   **Do not restate the mapping here (t-2494).** This step used to carry its own
   `work_type` → prefix table while `task-convention.md` carried a `kind`-keyed one, so
   every `kind:fix` task with `work_type:implement` resolved to `feat/` here and `fix/`
   there. Three defect branches were mislabelled `feat/` and the conflict was resolved by
   hand twice before it was traced. `kind` is authoritative; `work_type` is the fallback
   for the 22% of tasks that carry no `kind`.

   The function always returns a bare prefix and exits 0 — unknown input degrades to
   `feat`, never to empty, so a malformed branch name cannot be produced here.
3. `subject-slug` — first 3–4 words of `task.subject`, lowercased, non-alphanumeric replaced with `-`, consecutive dashes collapsed. Strip leading articles ("a", "an", "the"). Strip leading/trailing dashes. Aim for ≤4 words (CLAUDE.md convention).

**Display the suggestion before creating:**
```
Suggested branch: {epic-slug}/{work-type}/t-{NNN}-{subject-slug}
# Example: harness-core/feat/t-1621-backlog-start-branch-suggest
```

**Always create the branch as a worktree — never `git checkout -b`** (git-discipline.md
"Worktrees, not checkout — HARD RULE"; concurrent sessions share the main checkout's HEAD and
working tree, so a checkout-cut branch races other sessions). `cd` to the repo root first so `../`
resolves correctly, then spot-check the path before working there:
```bash
BR={epic-slug}/{work-type}/t-{NNN}-{subject-slug}
# Resume if the branch already exists, else create a fresh worktree:
if git branch --list "*t-{NNN}-*" | grep -q .; then
  git worktree add ../<repo>-t-{NNN} "$BR"      # existing branch → attach worktree
else
  git worktree add ../<repo>-t-{NNN} -b "$BR"   # new branch
fi
ls ../<repo>-t-{NNN}/README.md   # verify the path resolved before any edits
```
After merge, clean up: `git worktree remove ../<repo>-t-{NNN} && git branch -d "$BR"`.

---

