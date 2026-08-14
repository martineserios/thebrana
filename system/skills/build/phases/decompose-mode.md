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
3a. **WAVES** (ADR-080 §2) — only when decomposing under an epic: resolve the
   tree root's epic ancestor via [`../../_shared/epic-ancestor-walk.md`](../../_shared/epic-ancestor-walk.md)
   (`resolve_epic_ancestor`). **Check the exit status, not just the string**
   (t-2487 contract, t-2263 failure class) — three distinguishable outcomes:
   - **Non-zero exit:** the lookup itself broke (task missing, binary error).
     This is *unknown*, not "no epic" — surface "⚠ epic lookup failed for
     {root-id} (backlog read error) — not skipping WAVES on an unknown epic,
     stopping instead" and stop 3a; do not fall through to the empty-result
     case below. A transient failure silently treated as "no epic" would drop
     the wave graph for a genuinely epic-scoped decompose with no visible
     signal — the same class of loss named in t-2263.
   - **Exit 0, empty result:** a real negative — no epic ancestor. Skip 3a
     silently, same as "fewer than 2 milestones" below.
   - **Exit 0, non-empty result:** the epic slug. Proceed.
   If the draft tree has fewer than 2 milestones with tasks under them, skip 3a
   silently (same as the real-negative case). Otherwise, using the shared
   primitives in [`../../_shared/wave-graph-emit.md`](../../_shared/wave-graph-emit.md):
   - **One wave per milestone**, selector `parent:<ms-id>` — the ids are not
     assigned until step 5 persists the tree, so draft the graph against the
     table's placeholder milestone rows and resolve real `ms-N` ids at persist
     time.
   - **Gate chain (cross-milestone only)** from the `Blocked by` column: if any
     task under milestone B is blocked by a task under a *different* milestone
     A, wave-B's gate is `wave_name_for_milestone(epic_slug, A's milestone-slug)`.
     A `blocked_by` edge between two tasks in the *same* milestone is not a
     gate edge — it stays inside that milestone's wave.
   - **Contract** seeded from the milestone's stated definition-of-done (prose).
     Quote it as a single shell argument when interpolating into a `wave add`
     call (below) — free prose can contain `"`, backticks, or `$(...)`, and an
     unescaped double-quoted interpolation can break argument parsing or
     execute a substitution. Pass it as one already-quoted string, never build
     the command by concatenating unescaped prose into a larger quoted string.
   - **Wave naming**: `wave_name_for_milestone(epic_slug, ms_slug)`.
   - **Cycle check before persist**: pipe the full `id<TAB>gate` set through
     `wave_gate_chain_has_cycle`. A cycle is a hard stop — fix the milestone
     dependency edges before proceeding; never persist a cyclic graph. Plan-time
     defense in depth alongside the epic runner's PREFLIGHT cycle-STOP
     (ADR-080 §3.1).
   - Show the wave graph alongside the draft tree table (one line per wave:
     `<name>`: selector, gate, contract) so step 4's approval covers both.
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
   **If step 3a produced a wave graph**, create the wave objects too, only now
   (on approval), each `status: queued`, using the real `ms-N` ids just
   assigned (gate before selector so an upstream wave name resolves for
   `--gate`):
   ```bash
   brana backlog wave add --name "<wave-name>" --selector "parent:<ms-N>" \
     --contract "<milestone definition-of-done>" [--gate <upstream-wave-name>]
   ```
6. **Report** — show the persisted tree with assigned IDs, plus the wave graph if one was written

### Decomposing an existing task

When given a task ID (`/brana:build decompose t-123`):
- Read the task via `brana backlog get t-123`
- The existing task becomes the parent (or is promoted to milestone/phase if appropriate)
- Subtasks inherit the parent's stream and tags
- Set the parent's `build_step` to `decompose`

### Integration with normal build

After planning, the user can start any task with `/brana:backlog start <id>` which enters the normal build loop (CLASSIFY → SPECIFY → BUILD → CLOSE). The plan provides the roadmap; the build loop executes each piece.

---

