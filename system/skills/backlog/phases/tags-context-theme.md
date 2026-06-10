<!-- backlog phase: /brana:backlog tags, context, theme — loaded per the PHASES registry in ../SKILL.md (t-1942) -->

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

