<!-- build phase: Decompose mode — /brana:build decompose — loaded per the PHASES registry in ../SKILL.md (t-1942) -->

## Decompose Mode (`/brana:build decompose`)

When invoked with `decompose` as the first argument, `/brana:build` skips the normal CLASSIFY → BUILD loop and instead **decomposes work into a persisted task tree**. This gives you control and visibility over long or multi-session work.

### What it does

1. **Identify the scope** — from description or existing task ID
2. **Decompose** into the task hierarchy: phase → milestone → task → subtask (use whatever levels fit the scope)
3. **Persist** via `brana backlog add` CLI — every node in the tree becomes a real task with dependencies
4. **Present** the tree for approval before persisting

### Hierarchy rules

| Type | Prefix | When to use |
|------|--------|-------------|
| `phase` | `ph-` | Large initiatives spanning weeks (e.g., "Phase 3: Hook system") |
| `milestone` | `ms-` | Checkpoints within a phase, deliverable in days |
| `task` | `t-` | Atomic work units, one branch each |
| `subtask` | `st-` | Steps within a task, too small for their own branch |

**Right-size the decomposition:** A 3-file bug fix doesn't need phases. A new subsystem does. Use the minimum hierarchy depth that gives useful visibility.

### Flow

1. **Analyze scope** — read task metadata (if ID given) or parse description
2. **Research if needed** — quick codebase scan to understand what's involved (files, dependencies, blast radius)
3. **Draft tree** — present as a table:
   ```
   ## Task Tree: {title}

   | ID | Type | Subject | Parent | Blocked by | Effort |
   |----|------|---------|--------|------------|--------|
   | ph-N | phase | Phase name | — | — | L |
   | ms-N | milestone | Milestone name | ph-N | — | M |
   | t-N | task | Task name | ms-N | — | S |
   | t-N+1 | task | Next task | ms-N | t-N | S |
   ```
4. **Get approval** via AskUserQuestion:
   ```
   question: "Task tree ready. Persist it?"
   options: ["Approve", "Adjust", "Cancel"]
   ```
5. **Persist** — create all tasks via CLI in dependency order:
   ```bash
   brana backlog add --json '{"subject":"...","type":"phase","work_type":"implement",...}'
   brana backlog add --json '{"subject":"...","type":"milestone","parent":"ph-N",...}'
   brana backlog add --json '{"subject":"...","type":"task","parent":"ms-N","blocked_by":["t-N"],...}'
   ```
6. **Report** — show the persisted tree with assigned IDs

### Decomposing an existing task

When given a task ID (`/brana:build decompose t-123`):
- Read the task via `brana backlog get t-123`
- The existing task becomes the parent (or is promoted to milestone/phase if appropriate)
- Subtasks inherit the parent's stream and tags
- Set the parent's `build_step` to `decompose`

### Integration with normal build

After planning, the user can start any task with `/brana:backlog start <id>` which enters the normal build loop (CLASSIFY → SPECIFY → BUILD → CLOSE). The plan provides the roadmap; the build loop executes each piece.

---

