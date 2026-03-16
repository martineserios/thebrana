---
name: build
description: "Build anything — features, bug fixes, refactors, spikes, migrations, investigations. Auto-detects strategy from description, integrates with /brana:backlog, enforces TDD. The unified development command."
argument-hint: "[decompose] [description or task ID]"
group: execution
depends_on:
  - backlog
  - challenge
  - retrospective
allowed-tools:
  - Bash
  - Read
  - Write
  - Edit
  - Glob
  - Grep
  - Task
  - WebSearch
  - WebFetch
  - AskUserQuestion
---

# Build

The unified development command. One entry point for all work types: features, bug fixes, greenfield projects, refactors, spikes, migrations, and investigations. Auto-detects the right strategy, integrates deeply with `/brana:backlog`, and enforces TDD throughout.

## Invocation

```
/brana:build "description"              — start from a description
/brana:build                            — ask what to build
/brana:build decompose "description"    — decompose work into a task tree (phase/milestone/task/subtask)
/brana:build decompose <id>            — decompose an existing task into subtasks
```

Also entered via `/brana:backlog start <id>` for code tasks — see Task Integration below.

---

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
   brana backlog add --json '{"subject":"...","type":"phase","stream":"roadmap",...}'
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

## CLI Integration — MANDATORY

**NEVER read or write tasks.json directly.** No `cat tasks.json`, no `uv run python` parsing, no `Read` tool on tasks.json. Use `brana backlog` CLI commands via Bash for ALL task operations:

```bash
# ✗ WRONG — reads 435KB into context, wastes tokens
cat .claude/tasks.json | uv run python -c "..."

# ✓ RIGHT — 11ms, 0 context tokens
brana backlog get t-069
brana backlog query --status pending --stream roadmap
brana backlog search "enforcement"
```

Commands:
- **Read:** `brana backlog get <id>`, `brana backlog query --status pending`, `brana backlog search "keyword"`, `brana backlog next`
- **Write:** `brana backlog set <id> <field> <value>`, `brana backlog add --json '{...}'`
- **Browse:** `brana backlog stats`, `brana backlog tags`, `brana backlog roadmap`

This applies to EVERY step — CLASSIFY, SPECIFY, DECOMPOSE, BUILD, CLOSE. No exceptions.

---

## Step 0: CROSS-REFERENCE

Before anything else, check if this work already exists or relates to existing work.

1. **Search for related tasks** via CLI:
   ```bash
   brana backlog search "description keywords"
   brana backlog query --tag "relevant,tags"
   ```
2. **Analyze results** for:
   - Subject fuzzy match (significant words overlap)
   - Tag overlap (2+ shared tags)
   - File path overlap (if description mentions specific files)
   - URL match (if description contains URLs, check research stream)
3. **If matches found**, use AskUserQuestion:
   ```
   question: "Found related tasks. What to do?"
   options:
     - "This IS {id} — start it" (if exact match)
     - "Create new + link as related to {id}"
     - "Merge into {id}"
     - "No relation — create new"
   ```
4. **If no matches**, proceed silently.
5. **If entering via `/brana:backlog start`**, skip cross-reference (task already identified).

---

## Step 0b: STEP REGISTRY

**Size gate:** Skip this for Trivial/Small sizes (see Sizing heuristics below). Only create the registry for Medium and Large builds.

Create a CC Task step registry. Follow the [guided-execution protocol](../_shared/guided-execution.md).

Register these steps as CC Tasks (adapt based on detected strategy after CLASSIFY):

- **Feature/Greenfield/Migration:** CLASSIFY, SPECIFY, DECOMPOSE, BUILD, CLOSE
- **Bug fix:** CLASSIFY, REPRODUCE, DIAGNOSE, FIX, CLOSE
- **Refactor:** CLASSIFY, SPECIFY, VERIFY-COVERAGE, BUILD, CLOSE
- **Investigation:** CLASSIFY, SYMPTOMS, INVESTIGATE, REPORT
- **Spike:** CLASSIFY, QUESTION, EXPERIMENT, ANSWER

Since strategy isn't known yet, create the CLASSIFY task first. After CLASSIFY confirms the strategy, create the remaining steps.

---

## Step 1: CLASSIFY

Mandatory. One interaction. Never skip.

### Detection rules

Analyze the description (and task metadata if from `/brana:backlog start`) to propose a strategy:

| Strategy | Stream signal | Description signal |
|----------|-------------|-------------------|
| **Feature** | `roadmap` | Default — anything that adds capability |
| **Bug fix** | `bugs` | "fix", "broken", "crash", "bug", "error", "wrong", "fails" |
| **Greenfield** | — | "start", "new project", "create project", "from scratch" |
| **Refactor** | `tech-debt` | "refactor", "restructure", "clean up", "simplify", "reorganize" |
| **Spike** | `experiments` | "can we", "test if", "try", "spike", "prototype", "feasibility" |
| **Migration** | — | "migrate", "switch from", "move to", "upgrade", "replace X with Y" |
| **Investigation** | `research` | "why", "investigate", "understand", "debug", "diagnose", "analyze" |

### Confirmation

Use AskUserQuestion:
```
question: "Detected: {strategy}. Correct?"
options:
  - "{detected strategy} (Recommended)"
  - "Feature"
  - "Bug fix"
  - "Refactor"
  - "Spike"
```
Header: "Strategy"

### Mid-stream reclassification

At any point during the build, the user can say "this is actually a {type}" and Claude shifts strategy. When reclassifying:
- If moving TO a strategy with SPECIFY: start SPECIFY from current knowledge (don't lose work)
- If moving FROM spike to feature: the spike findings become SPECIFY context
- If moving FROM investigation to bug fix: the report becomes REPRODUCE evidence

---

## Step 2: APPROVE

**Mandatory for Medium/Large builds.** After CLASSIFY confirms the strategy, present the step sequence and get approval before executing. **Do NOT use CC plan mode (EnterPlanMode) — use AskUserQuestion for approval.**

1. **Present the strategy's step sequence** inline:
   ```
   ## Build Steps: {task subject}
   Strategy: {detected strategy}
   Size: {sizing}

   Steps:
   1. SPECIFY — research loop, draft feature spec
   2. DECOMPOSE — break spec into ordered tasks
   3. BUILD — TDD loop per task
   4. CLOSE — validate, retrospective, docs, merge
   ```
   Adapt the steps to the detected strategy (bug fix uses REPRODUCE → DIAGNOSE → FIX → CLOSE, etc.).
2. **Get approval** via AskUserQuestion:
   ```
   question: "Build steps above. Proceed?"
   options: ["Approve", "Adjust", "Cancel"]
   ```
3. **If the user adjusts**, incorporate changes and re-present.
4. **Proceed to the first step** of the approved strategy.

For **Trivial/Small** builds: skip the approval gate, proceed directly. State the steps inline: "This is small — I'll SPECIFY (light) → BUILD → CLOSE."

---

## Strategy: FEATURE

```
SPECIFY → DECOMPOSE → BUILD → CLOSE
```

### SPECIFY (interactive, open-ended)

The user controls the pace. Stay in the research→discuss loop until the user says to move on.

#### Research loop

**Seed from task metadata:** If attached to a task, extract research keywords from the task's `tags`, `description`, and `context` fields. These are the initial search vectors for all research tracks below.

Run research in this order — each layer adds context for the next:

1. **Knowledge base** — search ruflo memory + dimension docs using task tags and description keywords
   ```bash
   source "$HOME/.claude/scripts/cf-env.sh"
   cd "$HOME" && $CF memory search --query "{task tags + description keywords}" --namespace knowledge --format json
   ```
2. **Project docs** — grep/read the project's own documentation, existing implementations, CLAUDE.md. Search for task tags and related concepts.
3. **Cross-project patterns** — search claude-flow for patterns from other clients matching task tags
4. **Web research** — spawn scout agents for external research using task description + tags as search terms (parallel with discussion)

#### Present and discuss

- Present findings organized by relevance
- Discuss with the user naturally — goals, constraints, scope, edge cases
- Ask follow-up questions, challenge assumptions gently
- **While the user reads/thinks**, spawn scouts for the next research angle (parallel)

#### Auto-store findings

Every research finding gets stored immediately in ruflo:
```bash
cd "$HOME" && $CF memory store \
  -k "research:{project}:{topic}:{finding-slug}" \
  -v '{"finding": "...", "source": "...", "confidence": 0.3, "ttl_days": 30}' \
  --namespace knowledge \
  --tags "type:research,client:{project},topic:{topic}" \
  --upsert
```
Confidence 0.3 + 30-day TTL: intermediate findings age out if not promoted.

#### Draft signal

When the user says "draft it", "ready", "let's spec this", "move on", or similar:

1. **Auto-suggest dimension doc updates** — check which brana-knowledge dimension docs overlap with the research topics. Use AskUserQuestion:
   ```
   question: "Research touched topics X, Y. Update dimension docs?"
   options: ["Yes — update dim {N}, {M}", "Skip"]
   ```
   If approved, write the updates.

2. **Write feature spec** at `docs/features/{slug}.md` (or `docs/architecture/features/{slug}.md` if the project has the restructured layout):
   ```markdown
   # Feature: {title}

   **Date:** YYYY-MM-DD
   **Status:** specifying
   **Task:** t-NNN

   ## Problem
   {from discussion}

   ## Decision Record (frozen YYYY-MM-DD)
   > Do not modify after acceptance.
   **Context:** ...
   **Decision:** ...
   **Consequences:** ...

   ## Constraints
   - {from discussion}

   ## Scope (v1)
   - {from discussion}

   ## Research
   {key findings that informed the decision — auto-populated}

   ## Design
   {technical approach — components, files, patterns}

   ## Documentation Plan
   - [ ] **User guide** — `docs/guide/features/{slug}.md`: {what users need — behavior, commands, config, examples}
   - [ ] **Tech doc** — `docs/architecture/features/{slug}.md`: {what contributors need — design rationale, extending, key files}
   - [ ] **Existing docs to update** — {list any affected workflow/command/feature docs}

   ## Challenger findings
   {auto-populated after challenger review}
   ```

3. **Challenger review** — spawn a separate challenger agent (context isolation):
   ```
   Agent(subagent_type="challenger", prompt="Review this feature spec: {spec content}")
   ```
   Incorporate findings into the spec's Challenger findings section.

4. **Promote research** — findings that survived into the final spec get upgraded:
   ```bash
   cd "$HOME" && $CF memory store \
     -k "research:{project}:{topic}:{finding-slug}" \
     -v '{"finding": "...", "confidence": 0.6}' \
     --namespace knowledge --upsert
   ```

5. **Present spec to user** for approval. Wait for confirmation before proceeding.

6. Update spec status to `decomposing`.

### DECOMPOSE

0. **Assumption check** (after strategy confirmed, before decomposing):
   Scan docs related to the task's tags and description for tracked assumptions. Read frontmatter `assumptions:` sections from relevant docs (dimension docs, ADRs, reasoning docs).

   ```bash
   # Search ruflo for assumptions related to task tags
   source /home/martineserios/.claude/scripts/cf-env.sh
   cd "$HOME" && $CF memory search --query "{task tags + description keywords}" --namespace assumptions --format json 2>/dev/null || true
   ```

   Also grep project docs for `assumptions:` YAML blocks in files matching the task's topic area.

   **If any assumption has `last_verified` older than its confidence tier threshold** (tech: 6 months, architecture: 18 months, methodology: 36 months), warn:
   ```
   ⚠ Stale assumption in [doc path]: "[claim]". Last verified: YYYY-MM-DD. Verify before proceeding.
   ```

   If no assumptions are stale or no tracked assumptions exist for this area, proceed silently.

1. **Impact analysis** (if `docs/spec-graph.json` exists):
   From the feature description, identify `system/` files likely to be modified. Read `docs/spec-graph.json` and find all nodes whose `impl_files` contain those paths. Display a blast radius table:

   | Doc | Type | Relevant because |
   |-----|------|-----------------|
   | docs/reflections/14-... | impl_files match | Contains system/skills/build references |

   Use this to inform the task breakdown — each affected doc area may need its own task.

   **Fallback:** If `docs/spec-graph.json` doesn't exist, skip impact analysis and proceed directly to task breakdown.

2. **Break spec into ordered tasks** with acceptance criteria.
   - Each task is small enough for one commit
   - Titles are imperative: "Implement X", "Add Y"
   - Dependencies are explicit
   - **Include documentation tasks** — for feature/greenfield/migration strategies, the task breakdown MUST include:
     - A user guide task (`docs/guide/features/{slug}.md`)
     - A tech doc task (`docs/architecture/features/{slug}.md`)
     - Tasks to update any existing docs affected by the feature
   - Doc tasks should depend on the implementation tasks they document

3. **Persist tasks** (size-gated):

   **Medium/Large builds:** Persist subtasks via CLI — same mechanism as `/brana:build decompose` mode.
   The spec from SPECIFY provides the decomposition context (no interactive prompts needed).
   ```bash
   # Create subtasks under the current task
   brana backlog add --json '{"subject":"...","type":"subtask","parent":"{task-id}","blocked_by":[...]}'
   ```
   Each subtask gets an ID, deps, and survives across sessions.

   **Trivial/Small builds:** Keep tasks inline in the conversation. No backlog persistence — the build completes in one session anyway.

4. **Present the plan** for approval. Use AskUserQuestion:
   ```
   question: "Task breakdown ready. Approve?"
   options: ["Approve", "Adjust", "Cancel"]
   ```

5. Update spec status to `building`.

### BUILD

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

3. **For each task** (in dependency order):
   a. **Mark CC Task in_progress** (if created): `TaskUpdate: status → in_progress`
   b. **State what you'll change** — which files, why, how it maps to acceptance criteria
   c. **Write failing test** — the acceptance criteria become test assertions
   d. **Implement** — make the test pass
   e. **Verify** — run tests, lint, compare before/after
   f. **Commit** — `feat(scope): description`
   g. **Mark CC Task completed** + update tasks.json: `brana backlog set {subtask-id} status completed`
   h. **Mini-debrief:**
      - What surprised?
      - Spec mismatch? (feature spec says X, reality requires Y)
      - Reusable pattern?
      - Store significant findings in ruflo

4. **At natural breakpoints** (every 2-3 tasks), ask:
   ```
   question: "Continue to next task, or review/adjust?"
   options: ["Continue", "Review", "Adjust tasks"]
   ```

### CLOSE

See CLOSE section below (shared across strategies).

---

## Strategy: BUG FIX

```
REPRODUCE → DIAGNOSE → FIX → CLOSE
```

### REPRODUCE

1. **User describes the symptom** — what's broken, when it happens, expected vs actual.
2. **Find the failing case** — read relevant code, check logs, identify the conditions.
3. **Write a failing test** that reproduces the bug:
   - The test IS the spec — it documents what "fixed" looks like
   - Test must fail with the current code
   - Confirm: "Test fails as expected. The bug is reproducible."
4. **If no test framework exists**: document the reproduction steps, note "no test framework — manual verification."

### DIAGNOSE

1. **Read the code path** — trace from symptom to root cause.
2. **Identify root cause** — not just the symptom, the underlying reason.
3. **Present diagnosis** to user:
   ```
   "The bug is: {root cause}
    It happens because: {explanation}
    The fix should: {proposed approach}"
   ```
4. **Wait for user confirmation** or redirection.

### FIX

1. **Create branch** (if not already on one):
   ```bash
   git checkout -b fix/{task-id}-{slug}
   ```
2. **Implement the fix** — make the failing test pass.
3. **Run full test suite** — no regressions.
4. **Commit:** `fix(scope): description`

### CLOSE

See CLOSE section below. Bug fixes skip the feature spec update (no spec was created).

---

## Strategy: GREENFIELD

```
ONBOARD → SPECIFY → DECOMPOSE → BUILD → CLOSE
```

### ONBOARD

1. **Detect what exists** — scan for package.json, pyproject.toml, .git, .claude/, docs/.
2. **If nothing exists**, ask the user:
   ```
   question: "What kind of project?"
   options: ["Code project", "Venture/business", "Hybrid"]
   ```
3. **Set up project structure** based on type:
   - Code: `.claude/CLAUDE.md`, `docs/decisions/`, test directory
   - Venture: add `docs/sops/`, `docs/okrs/`, `docs/metrics/`
   - Hybrid: both
4. **Write project CLAUDE.md** — name, stack, conventions.
5. **First commit:** `chore: project scaffold`
6. **Register in portfolio** if not already in `tasks-portfolio.json`.

Then proceed to SPECIFY → DECOMPOSE → BUILD → CLOSE for the first feature/MVP.

---

## Strategy: REFACTOR

```
SPECIFY (light) → VERIFY COVERAGE → BUILD → CLOSE
```

### SPECIFY (light)

1. **What's wrong** with the current structure? (Ask the user or infer from description)
2. **What should it look like after?**
3. **What must NOT change?** — the behavior contract.
4. No feature spec needed for refactors — the tests are the spec.

### VERIFY COVERAGE

1. **Run existing tests** — all must pass. Record baseline: "N tests pass."
2. **Identify coverage gaps** — if the area being refactored lacks tests:
   - Write tests for current behavior FIRST
   - These tests anchor the refactor — behavior must not change
3. **Confirm baseline:** "N tests pass before refactor. Behavior contract is locked."

### BUILD

Same as feature BUILD, except:
- After each change: run tests, must still pass
- No new behavior — same tests, same results
- Commits: `refactor(scope): description`

### CLOSE

See CLOSE section below. Refactors skip feature spec and user guide updates (no new behavior).

---

## Strategy: SPIKE

```
QUESTION → EXPERIMENT → ANSWER
```

No branch. No spec. No tasks.json entry. No docs. Just learn.

### QUESTION

1. **What are we trying to learn?** (From description or ask)
2. **What would "yes" look like? What would "no"?**
3. **Timebox:** "Spend max {N} minutes on this." (Ask user or default to 30)

### EXPERIMENT

1. Work in `/tmp/spike-{slug}/` or a scratch directory.
2. Quick prototype — throwaway code.
3. No tests, no commits, no branch.
4. Focus entirely on answering the question.

### ANSWER

1. **Result:** yes / no / partially. Present findings.
2. **Store finding** via retrospective pattern:
   ```bash
   cd "$HOME" && $CF memory store \
     -k "spike:{project}:{slug}" \
     -v '{"question": "...", "answer": "...", "conclusion": "yes|no|partial"}' \
     --namespace patterns \
     --tags "type:spike,project:{project}" \
     --upsert
   ```
3. **If yes** — offer to create a feature task:
   ```
   question: "Spike succeeded. Create a feature task to build this?"
   options: ["Yes — create task", "No — just log the finding"]
   ```
   If yes: `/brana:backlog add` with context from the spike.
4. **If no** — documented dead end. Move on.
5. **Clean up:** `rm -rf /tmp/spike-{slug}/` (ask first).

---

## Strategy: MIGRATION

```
SPECIFY → DECOMPOSE → BUILD (careful) → CLOSE
```

Same as Feature strategy, with these differences:

### SPECIFY additions

- **Current state:** what system/version/approach exists now?
- **Target state:** what are we moving to?
- **Rollback plan:** how do we revert if it fails?
- **Coexistence:** old and new must coexist during transition.

### BUILD differences

- **Incremental:** build the new system alongside the old one first.
- **Switchover:** the cutover is its own task — not buried in another commit.
- **Verify:** run tests against BOTH old and new during transition.
- **Remove old:** separate commit after the new system is verified.

---

## Strategy: INVESTIGATION

```
SYMPTOMS → INVESTIGATE → REPORT
```

No branch. No commits. Read-only. May lead to a build.

### SYMPTOMS

1. **User describes** what's happening — errors, unexpected behavior, performance issue.
2. **Gather evidence:** read logs, check error messages, identify reproduction steps.
3. **Form hypotheses** — list possible causes, ordered by likelihood.

### INVESTIGATE

1. **Test hypotheses one by one:**
   - Read code paths
   - Run diagnostic commands
   - Check data/state
   - Compare expected vs actual behavior
2. **Document findings as you go** — each hypothesis tested, result, next step.
3. **No code changes** — this is read-only analysis.

### REPORT

1. **Present findings:**
   ```
   Root cause: {explanation}
   Evidence: {what confirmed it}
   Recommended action: fix | refactor | accept | defer
   ```
2. **Store findings:**
   ```bash
   cd "$HOME" && $CF memory store \
     -k "investigation:{project}:{slug}" \
     -v '{"symptoms": "...", "root_cause": "...", "recommendation": "..."}' \
     --namespace patterns \
     --tags "type:investigation,project:{project}" \
     --upsert
   ```
3. **If fix needed** — offer to start a bug fix:
   ```
   question: "Investigation found a bug. Start a fix?"
   options: ["Yes — start /brana:build fix", "No — just log"]
   ```
   If yes: enter BUG FIX strategy with investigation findings as context.

---

## CLOSE (shared step)

Runs at the end of: feature, bug fix, greenfield, refactor, migration. NOT spike or investigation.

### Steps

1. **Validate acceptance criteria:**
   - All tasks/acceptance criteria met
   - Tests pass
   - No regressions
   ```markdown
   ### Validation
   - [x] Task 1: {title} — {how verified}
   - [x] All tests pass
   ```

2. **Log build outcome to decision log:**
   ```bash
   uv run python3 system/scripts/decisions.py log main decision \
     "Built {task-id} ({strategy}): {one-line summary of what was built}" \
     --refs "{task-id}" 2>/dev/null || true
   ```

3. **Retrospective** — look back on the build process:
   - What errors or re-approaches happened?
   - What surprised us?
   - What patterns should we store for next time?
   - Store learnings in ruflo:
     ```bash
     cd "$HOME" && $CF memory store \
       -k "pattern:{project}:{slug}" \
       -v '{"problem": "...", "solution": "...", "confidence": 0.5}' \
       --namespace patterns \
       --tags "client:{project},type:build-learning" \
       --upsert
     ```
   If ruflo unavailable, append to project's auto memory MEMORY.md.

4. **Knowledge maintenance** (after tests pass, before docs/merge):

   a. **Field notes**: Review session learnings from the build. If any practical discoveries emerged (unexpected behavior, workarounds, integration gotchas, performance findings), prompt the user:
      ```
      question: "Capture any of these as field notes?"
      options: ["Yes — I'll specify which", "No learnings worth capturing", "Auto-capture all"]
      ```
      Only flag obvious, reusable learnings — don't prompt for every mini-debrief. Store approved field notes:
      ```bash
      source /home/martineserios/.claude/scripts/cf-env.sh
      cd "$HOME" && $CF memory store \
        -k "field-note:{project}:{slug}" \
        -v '{"observation": "...", "context": "{task-id}", "date": "YYYY-MM-DD"}' \
        --namespace field-notes \
        --tags "client:{project},source:build" \
        --upsert 2>/dev/null || true
      ```
      If ruflo unavailable, append to the relevant doc's Field Notes section (if it has one) or to project auto memory.

   b. **Assumption verification**: If the build touched code related to tracked assumptions (check docs with `assumptions:` frontmatter whose `claim` overlaps with modified files/topics), update `last_verified` date to today in the relevant doc's frontmatter. Only update assumptions the build actually exercised — don't blanket-refresh.

   c. **Changelog update**: If the build changed behavior documented in a reasoning doc (reflections, ADRs, architecture docs), append a changelog entry to that doc:
      ```markdown
      ## Changelog
      - YYYY-MM-DD: {what changed} ({task-id}, {commit hash})
      ```
      If the doc has no Changelog section, add one at the end.

   d. **Reindex**: After any doc updates (field notes, assumption verification, changelog), trigger ruflo reindex for affected files:
      ```bash
      source /home/martineserios/.claude/scripts/cf-env.sh
      cd "$HOME" && $CF memory store \
        -k "reindex:{project}:{doc-slug}" \
        -v '{"updated": "YYYY-MM-DD", "reason": "build-close", "task": "{task-id}"}' \
        --namespace knowledge \
        --upsert 2>/dev/null || true
      ```
      If no docs were updated, skip reindex silently.

5. **Update feature spec** (feature, greenfield, migration only):
   - Set status to `shipped`
   - Add learnings from retrospective

6. **Generate feature documentation** via `/brana:docs`:

   Invoke the living documentation skill:
   ```
   Skill(skill="brana:docs", args="all {task-id}")
   ```

   `/brana:docs all` handles strategy-aware generation (tech doc, user guide, shared doc updates, philosophy overview) and spec-graph routing. See the [docs skill](../docs/SKILL.md) for full details.

   **Shipped without docs means not shipped.**

7. **Update task** (if entered via `/brana:backlog start`):
   - Set status → `completed`
   - Set completed date
   - Add notes from retrospective

8. **GitHub sync** (if `github_sync.enabled` in `~/.claude/tasks-config.json`):
   - If task has `github_issue`: run `system/scripts/gh-sync.sh close {issue-number}`.
   - If sync fails: warn "GitHub issue not closed. Close manually: gh issue close #{issue-number}" — do NOT block CLOSE.

9. **Pre-merge doc check** (feature, greenfield, migration only):
   - Run: `git diff --name-only main...HEAD | grep -E '(docs/architecture/features/|docs/guide/features/)'`
   - **If no doc files in diff:** warn clearly:
     ```
     ⚠ No feature docs found in this branch.
     "Shipped without docs means not shipped."
     Generate docs now? (yes / skip — I'll add them later)
     ```
     If user says yes: invoke `Skill(skill="brana:docs", args="all {task-id}")`.
     If user says skip: proceed to merge (soft enforcement, not a hard block).
   - **If doc files present:** proceed silently.
   - **Bug fix / refactor branches:** skip this check entirely.

10. **Merge** — present the command, do NOT auto-execute:
   ```bash
   git checkout main
   git merge --no-ff feat/{branch-name} -m "{type}: {description}"
   git branch -d feat/{branch-name}
   ```

11. **Update living docs** (post-merge, on main):
   Invoke `/brana:docs all` to update system-level documentation:
   - `reference` — regenerate catalogs from frontmatter (deterministic)
   - `marketplace` — sync plugin marketplace metadata (counts, version)
   - `guide` — update affected user guide docs (from spec-graph `guide_files`)
   - `tech` — update affected architecture docs (from spec-graph `arch_files`)
   - `overview` — refresh philosophy.md (only if core behavior changed)

   For **existing shared docs**: show a diff preview before committing.
   For **new per-feature docs**: auto-commit (already handled in step 6).
   Commit on main: `docs: update living docs after {task-id}`

   Skip silently if no spec-graph hits (not every build touches documented systems).

12. **Report:**
   ```markdown
   ## Build Complete: {title}

   **Strategy:** {type}
   **Branch:** {branch}

   ### What was built
   | # | Task | Commit | Verified |
   |---|------|--------|----------|
   | 1 | {description} | {hash} | {how} |

   ### What was learned
   - {key learnings stored}

   ### Docs updated
   - {list of doc changes}

   ### Knowledge maintained
   - {field notes captured, assumptions verified, changelogs updated}
   ```

---

## Task Integration

### Entry via /brana:backlog start

When `/brana:backlog start <id>` invokes this skill:

1. **Task metadata is pre-loaded:**
   - `subject` → seeds the description
   - `stream` → informs strategy detection
   - `tags` → inform research scope
   - `description` → additional context
   - `context` → prior research, notes, links
   - `blocked_by` → verified all resolved

2. **Skip cross-reference** (task already identified).

3. **CLASSIFY uses stream as primary signal:**
   - `roadmap` → feature
   - `bugs` → bug fix
   - `tech-debt` → refactor
   - `experiments` → spike
   - `research` → investigation
   - Description signals override if clearer.

4. **Branch created from task convention:**
   - `roadmap` → `feat/{id}-{slug}`
   - `bugs` → `fix/{id}-{slug}`
   - `tech-debt` → `refactor/{id}-{slug}`

5. **CLOSE auto-completes the task.**

### Task fields updated during build (via CLI)

The build loop updates fields via `brana backlog set`:

```bash
# CLASSIFY
brana backlog set <id> status in_progress
brana backlog set <id> started 2026-03-14
brana backlog set <id> strategy feature
brana backlog set <id> build_step classify

# SPECIFY → DECOMPOSE → BUILD (update build_step as loop progresses)
brana backlog set <id> build_step specify
brana backlog set <id> build_step decompose
brana backlog set <id> build_step build
brana backlog set <id> branch "feat/t-123-slug"

# CLOSE
brana backlog set <id> status completed
brana backlog set <id> completed 2026-03-14
brana backlog set <id> build_step null
brana backlog set <id> notes --append "Retrospective findings here"
```

### Creating tasks automatically

When `/brana:build` is invoked WITHOUT `/brana:backlog start`:

1. After CLASSIFY, create via CLI:
   ```bash
   brana backlog add --json '{"subject":"{description}","stream":"{from strategy}","type":"task","strategy":"{detected}","execution":"code"}'
   # Then set status + dates:
   brana backlog set t-{N} status in_progress
   brana backlog set t-{N} started YYYY-MM-DD
   brana backlog set t-{N} build_step specify
   ```
2. Confirm with user: "Created t-{N} for this work. Proceeding."
3. CLOSE updates this task to completed.

### Strategy transitions create linked tasks

- **Spike → Feature:** spike ANSWER creates a feature task with context: "Validated in spike t-{N}"
- **Investigation → Bug fix:** investigation REPORT creates a bug fix task with context: "Root cause from investigation t-{N}"
- Linked via `context` field, not `blocked_by` (the predecessor is already complete).

---

## Sizing heuristics

The strategy adapts not just by type but by size. These heuristics determine how much of each step to do:

| Size | Signal | SPECIFY depth | DECOMPOSE detail |
|------|--------|--------------|-------------------|
| **Trivial** | 1 file, obvious fix | Skip SPECIFY | No decomposition |
| **Small** | 1-3 files, scope clear | Light (no research) | Inline — no separate step |
| **Medium** | 4+ files, design needed | Full research loop | Full task breakdown |
| **Large** | New skill/system, unknown scope | Deep research + challenger | Full + dependencies |

Claude proposes the size. User can override: "this is bigger than it looks" or "just do it, it's simple."

---

## Rules

1. **CLASSIFY is mandatory.** Never skip the confirmation step. Never silently apply a strategy.
2. **TDD always** (except spike). Write the test before the code. The PreToolUse hook enforces this on feat/* branches.
3. **User controls pace in SPECIFY.** Never auto-advance from research to draft. Wait for the signal.
4. **Challenger is context-isolated.** Always spawn a separate agent for the challenger review. Never self-review.
5. **Shipped without docs means not shipped.** CLOSE generates tech doc + user guide from templates (feature/greenfield/migration). Refactors get tech doc only if architecture changed. Bug fixes skip docs.
6. **Don't auto-merge.** Present the merge command. Let the user decide.
7. **Mid-stream reclassification is allowed.** The user can change strategy at any point. Carry forward what's been learned.
8. **Mini-debrief after every task in BUILD.** 30 seconds. What surprised? Pattern? Don't skip.
9. **Cross-reference before creating work.** Always check for related tasks first (unless entering via /brana:backlog start).
10. **Graceful degradation.** If ruflo is unavailable, use auto memory. If no test framework, note it and proceed. If no GitHub Issues, use tasks.json.
11. **Step registry for Medium/Large builds.** Follow the [guided-execution protocol](../_shared/guided-execution.md). Skip for Trivial/Small.

---

## Resume After Compression

If context was compressed and you've lost track of progress:

1. Call `TaskList` — find all CC Tasks matching `/brana:build`
2. **Filter by level:**
   - **Step-level** tasks match `/brana:build -- {STEP}` (CLASSIFY, SPECIFY, DECOMPOSE, BUILD, CLOSE)
   - **Subtask-level** tasks match `/brana:build -- BUILD/subtask: {name}`
3. Find the `in_progress` step-level task — that's your current build step
4. If in BUILD step: find the `in_progress` subtask — that's your current subtask
5. If no `in_progress` at either level, find the first `pending` with all blockers `completed`
6. Use the task description and `build_step` field in tasks.json for additional context
