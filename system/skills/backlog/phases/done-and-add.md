<!-- backlog phase: /brana:backlog done, add, replan, archive, migrate — loaded per the PHASES registry in ../SKILL.md (t-1942) -->

<!-- ruflo preamble -->
ToolSearch("select:mcp__ruflo__claims_release")

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
       - label: "Tech doc + user guide"
         description: "Generate both architecture and user-facing docs from templates."
       - label: "Tech doc only"
         description: "Generate architecture/reference docs only."
       - label: "User guide only"
         description: "Generate user-facing guide docs only."
       - label: "Skip docs"
         description: "No documentation needed for this implementation."
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
3a. **Epic assignment** — tasks must always have an epic (no orphans allowed):
   - Read `active_epic` from `~/.claude/tasks-config.json`. If set, **auto-assign silently** and note "(assigned to epic: {active_epic})" — skip the epic question in step 4.
   - Else: infer epic from subject/tags (e.g., "harness" tag → "harness" epic, "backlog" tag → "backlog-git-alignment", "research" tag → most-recent research epic in tasks.json). If confident, set as the default suggestion in step 4.
   - No inference possible → add **Epic** to the first question batch in step 4. Options: distinct epics from tasks.json (sorted by recency) + "Create new…" (user types via Other input). **There is no skip option — every task must have an epic.**
   - "Create new…" → accept slug from free-text input; confirm: "Create epic '{slug}'? It will appear in backlog focus and filters."
4. **First question batch** — use a single AskUserQuestion with up to 4 questions (omit Epic question if active_epic was auto-assigned in step 3a; omit Milestone if URL auto-detected or no active milestones):
   - **Kind** (skip if URL auto-detected): `feature`, `fix`, `refactor`, `research`, `docs`, `design`, `ops`. Header: "Kind"
   - **Tags**: suggest tags from description keywords matched against existing vocabulary. Options: "Accept {suggested}" (recommended), "Edit", "Skip". Header: "Tags"
   - **Effort**: suggest from description complexity (S/M/L/XL). Options: each size with description. Header: "Effort"
   - **Epic** (only if not auto-assigned in step 3a): options = inferred slug (recommended, if any) + top epics from tasks.json + "Create new…". Header: "Epic"
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
9. **Final confirmation** — AskUserQuestion: "Add {id} '{subject}' [{tags}, {effort}] epic:{epic} under {milestone}? blocked_by: [{deps}]" Options: "Confirm" (recommended), "Edit", "Cancel". Header: "Confirm"
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

