
# Build

The unified development command. One entry point for all work types: features, bug fixes, greenfield projects, refactors, spikes, migrations, and investigations. Auto-detects the right strategy, integrates deeply with `/brana:backlog`, and enforces TDD throughout.

## Lifecycle context

Build implements the brana development workflow defined in [docs/reflections/32-lifecycle.md](../../docs/reflections/32-lifecycle.md): **DDD → SDD → TDD → Code**.

| Build step | Lifecycle phase | What it produces |
|---|---|---|
| SPECIFY | DDD (when `docs/domain/` exists) + SDD | Domain glossary updates, ADR(s), feature spec |
| DECOMPOSE | SDD continuation | Ordered task tree with acceptance criteria |
| BUILD | TDD | Failing test → implementation → refactor, per subtask |
| EXTRACT/EVALUATE/PERSIST | Continuous learning | Patterns, ADRs, field notes |

DDD is strategic (judgment), SDD is tactical (decisions), TDD is mechanical (red-green-refactor). DDD enforcement activates when `docs/domain/` exists in the project (same opt-in pattern as SDD's `docs/decisions/`).

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

## Task Operations — MANDATORY

**NEVER read or write tasks.json directly.** No `cat tasks.json`, no `uv run python` parsing, no `Read` tool on tasks.json.

**Prefer MCP tools** (brana server) when available — they return structured JSON with 65% fewer tokens than CLI:
- **Read:** `backlog_get(task_id)`, `backlog_query(status, tag, stream, ...)`, `backlog_search(query)`
- **Write:** `backlog_set(task_id, field, value)`, `backlog_add(subject, stream, ...)`
- **Browse:** `backlog_stats()`

**Fallback to CLI** via Bash if MCP tools are unavailable:
- **Read:** `brana backlog get <id>`, `brana backlog query --status pending`, `brana backlog search "keyword"`, `brana backlog next`
- **Write:** `brana backlog set <id> <field> <value>`, `brana backlog add --json '{...}'`
- **Browse:** `brana backlog stats`, `brana backlog tags`, `brana backlog roadmap`

This applies to EVERY step — CLASSIFY, SPECIFY, DECOMPOSE, BUILD, CLOSE. No exceptions.

---

## Step 0: LOAD

Pull relevant architecture, decision knowledge, and skill matches into context before building. Budget: 30K tokens max.

0. **Goal injection** (task_id known only — skip for freeform builds):
   Read the task's `context` field. Extract every line that starts with `AC:` (case-sensitive).
   ```bash
   # Via CLI (if MCP unavailable):
   brana backlog get {task_id} | python3 -c "
   import json, sys
   t = json.load(sys.stdin)
   lines = [l[3:].strip() for l in (t.get('context') or '').splitlines() if l.startswith('AC:')]
   print('; '.join(lines))
   "
   ```
   - **If AC: lines found:** call `/goal {criteria}` where `{criteria}` is the joined AC: text (semicolons between multiple criteria). This anchors every response in the session to the acceptance criteria without requiring repetition.
   - **If no AC: lines:** proceed without `/goal` — no regression.
   - **Skip for:** freeform builds (no task_id), spike strategy, investigation strategy.

1. **Build query** from available context: `"{project} {task.subject} {task.tags joined} {user_input}"`
2. **Primary — ruflo MCP (run both in parallel — `namespace: "all"` only returns session records; `specs` namespace is unindexed):**
   ```
   mcp__ruflo__memory_search(query: "{query}", namespace: "knowledge", limit: 5, threshold: 0.3)
   mcp__ruflo__memory_search(query: "{query}", namespace: "pattern",   limit: 3, threshold: 0.3)
   ```
   Use `smart: false` (default). `smart: true` is **rejected** — t-1699 spike (2026-05-28): smart:false 56-95ms / top-sim 0.57-0.64 on-topic; smart:true 275-879ms / top-sim 0.47 off-topic (Feynman physics as #1 for "hook enforcement"). MMR runs before limit slice (`afterMmrCount` fixed), so `limit:1` mitigation also fails — same wrong top result. MMR diversity param not exposed in ruflo schema (confirmed). Re-investigate only if ruflo exposes `mmr_lambda` or equivalent.
   Merge results, rank by similarity. Results span: knowledge (dimension docs, ADRs, feature briefs, reflections — all indexed here), pattern (past session learnings).
2b. **Graph edge traversal** (after ruflo search, if `docs/spec-graph.json` exists):
   Collect doc paths from knowledge results. Map ruflo key → file path:
   - `knowledge:dimension:{slug}:*` → `brana-knowledge/dimensions/{slug}.md`
   - `knowledge:decision:{slug}:*` → `docs/architecture/decisions/{slug}.md`
   - `knowledge:reflection:{slug}:*` → `docs/reflections/{slug}.md`
   - `knowledge:feature:{slug}:*` → `docs/architecture/features/{slug}.md`

   For each doc path, find 1-hop neighbors via inline graph query:
   ```bash
   uv run python3 -c "
   import json, sys
   with open('docs/spec-graph.json') as f:
       g = json.load(f)
   doc = sys.argv[1]
   seen = set(sys.argv[2:])  # already-loaded paths from ruflo results
   deps = [e for e in g['edges'] if (e['from']==doc or e['to']==doc) and e['type']=='depends_on']
   infs = [e for e in g['edges'] if (e['from']==doc or e['to']==doc) and e['type']=='informs']
   neighbors = []
   for e in deps + infs:
       n = e['to'] if e['from']==doc else e['from']
       if n not in seen:
           neighbors.append(n)
           seen.add(n)
       if len(neighbors) >= 3:
           break
   for n in neighbors:
       print(n)
   " "{doc_path}" "{already_loaded_1}" "{already_loaded_2}" ...
   ```
   For each returned neighbor: read its first 50 lines for context.
   - **Cap:** max 3 graph-derived docs total (across all ruflo results). `depends_on` edges checked before `informs`.
   - **Skip if:** spec-graph.json doesn't exist, no knowledge results from ruflo, or graph query returns no neighbors.
   - This is best-effort enrichment — never blocks LOAD.
3. **Fallback — tag-based grep** (if MCP unavailable):
   ```bash
   grep -rl "{keywords}" ~/enter_thebrana/brana-knowledge/dimensions/ --include="*.md" | head -5
   grep -rl "{keywords}" docs/architecture/ docs/reflections/ --include="*.md" | head -5
   ```
   Read the top 3 matching files (first 80 lines each).
   For skills fallback: `brana skills suggest --query "{keywords}"`
4. **Skill match handling** — if any result has `namespace: "skills"` (or key starts with `skill:`):
   - Score >= 0.5: apply the **`skill-routing.md` gate** — use AskUserQuestion to confirm before loading the domain skill. LOAD is the information source (which skills matched); `skill-routing.md` owns the ask-before-loading gate. Never silently invoke a matched domain skill.
   - Score < 0.5: ignore (too weak to surface)
   - If entering via `/brana:backlog start`, skill suggestion already happened in step 5 — skip duplicate ask.

4a. **JIT skill acquisition** — deterministic tech detection + SKILL.md keywords gate. Triggers when a domain skill is installed but its knowledge was absent from LOAD results.
   <!-- SUNSET: Remove steps 4 and 4a entirely when Skill Registry (t-608) ships. Replace with skill_suggest(tech_context) calls. -->

   **Step 1 — Tech detection** (3-signal chain; first match wins — skip 4a entirely if no signal fires):
   - **Signal 1** — Task description + tags: scan for tech keywords (`"Rust"`, `"[rust]"`, `".rs"`, `"Cargo"`, `"Python"`, `"[python]"`, `".py"`, `"TypeScript"`, `"[typescript]"`, `".ts"`, `".tsx"`, `"Next.js"`, etc.)
   - **Signal 2** — Project manifest files (filesystem-verifiable, most reliable):
     - `Cargo.toml` present → Rust
     - `pyproject.toml` or `uv.lock` present → Python
     - `package.json` + `tsconfig.json` present → TypeScript
   - **Signal 3** — File paths in task description/context: extract extensions from mentioned paths (`.rs` → Rust, `.py` → Python, `.ts`/`.tsx` → TypeScript)

   **Step 2 — Skill match**: scan installed `SKILL.md` files for `keywords` overlap with detected tech terms. If no match: skip 4a (no skill to offer).

   **Step 3 — Tech-aware LOAD check**: inspect LOAD result keys (from steps 2 and 2b above). If any key contains one of the matched skill's `keywords` → skill knowledge already in context → skip 4a. If NO key matches → skill knowledge absent → proceed to Step 4.

   **Step 4 — Ask**:
   ```
   question: "Detected {tech} context. {skill} knowledge not loaded. Load it now?"
   header: "Skill Gap"
   options:
     - "Load {skill} now (Recommended)"
     - "Search marketplace for alternatives"
     - "Skip"
   ```
   - **"Load now"**: read the matched skill's procedure file into context:
     ```bash
     find ~/.claude/skills system/skills -name "*.md" -path "*{skill-slug}*" | head -1 | xargs head -200
     ```
     Continue the build with the skill's knowledge loaded. No restart needed.
   - **"Search marketplace"**: invoke acquire-skills:
     ```
     Skill(skill="brana:acquire-skills", args="{tech keywords}")
     ```
     After completion: read the newly installed procedure file into context. Continue.
   - **"Skip"**: proceed without. LOAD never blocks. Append to task context:
     ```bash
     brana backlog set {task_id} context --append "skill-gap-warning: {skill} available but not loaded (skipped $(date +%Y-%m-%d))"
     ```
     Auditable via `brana backlog search "skill-gap-warning"`.

   **Guard rails:**
   - Only trigger for `code` execution tasks (skip external/manual)
   - Only trigger once per LOAD invocation (don't re-offer if user skipped)
   - If entering via `/brana:backlog start` AND the task's context contains `skill_gap_checked`: skip (backlog step 5 already handled it)
   - If entering via `/brana:backlog start` but NO `skill_gap_checked` in context: run 4a anyway (safety net — step 5 may have been skipped)
   - If zero signals fire in Step 1: skip 4a entirely (no tech inferred)

5. **Summarize loaded knowledge** as a brief context preamble (2-5 bullets). Do not show raw results — synthesize what's relevant to the build task (prior decisions, related architecture, known constraints).

> **☑ Checkpoint — LOAD** (M+ builds with task_id):
> ```bash
> mkdir -p ~/.claude/run-state
> printf '{"step":"LOAD","completed":"%s","task_id":"%s"}\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "{task_id}" >> ~/.claude/run-state/{task_id}.jsonl
> ```

---

## Step 0a: CROSS-REFERENCE

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

- **Feature/Greenfield/Migration:** LOAD, CLASSIFY, SPECIFY, DECOMPOSE, BUILD, EXTRACT, EVALUATE, PERSIST, CLOSE
- **Bug fix:** LOAD, CLASSIFY, REPRODUCE, DIAGNOSE, FIX, EXTRACT, EVALUATE, PERSIST, CLOSE
- **Refactor:** LOAD, CLASSIFY, SPECIFY, VERIFY-COVERAGE, BUILD, EXTRACT, EVALUATE, PERSIST, CLOSE
- **Investigation:** LOAD, CLASSIFY, SYMPTOMS, INVESTIGATE, EXTRACT, EVALUATE, PERSIST, REPORT
- **Spike:** LOAD, CLASSIFY, QUESTION, EXPERIMENT, EXTRACT, EVALUATE, PERSIST, ANSWER

Since strategy isn't known yet, create the CLASSIFY task first. After CLASSIFY confirms the strategy, create the remaining steps.

---

## Step 0c: RESUME CHECK

**Size gate:** Same as 0b — skip for Trivial/Small builds.
**Task gate:** Skip if no task ID is associated (freeform builds without a task).

1. **Check for a run-state file:**
   ```bash
   cat ~/.claude/run-state/{task_id}.jsonl 2>/dev/null
   ```
2. **If file exists and non-empty:**
   - Parse completed steps — each line is `{"step":"NAME","completed":"...","task_id":"..."}`
   - Display: "⏩ Resuming {task_id} from checkpoint. Completed: {step1}, {step2}, ..."
   - **Fast-forward:** skip all steps whose names appear in the completed list. Jump to the first step NOT in the file.
   - If CC Task registry from Step 0b exists, mark skipped steps as completed via `TaskUpdate`.
3. **If file is empty or missing:** proceed normally from Step 1.

---

## Step 0d: READINESS CHECK

**Task gate:** Skip if no task_id is present (freeform builds). Skip for spike and investigation strategies (strategy unknown at this point — re-run after CLASSIFY if needed; in practice, spikes and investigations rarely enter via `/brana:backlog start`).

Before CLASSIFY, verify the task is in a buildable state. Read the task via `backlog_get(task_id)` (or `brana backlog get {task_id}`) and check:

| Check | Severity | Signal | Remediation |
|-------|----------|--------|-------------|
| Description filled (>20 chars) | **Hard block** | `description` field empty or short | "Add a description to {task_id} before building: `brana backlog set {task_id} description '...'`" |
| All blocked_by resolved | **Hard block** | any `blocked_by` entry has status != completed | "Resolve blockers first: {list of open blocked_by IDs}" |
| Effort set | **Soft warn** | `effort` field null, AND task is M or L (infer from description length/scope) | "Consider setting effort: `brana backlog set {task_id} effort M`" |
| AC: lines in context (M/L) | **Soft warn** | no lines starting with `AC:` in `context` field, AND effort is M or L | "No AC: lines found — add acceptance criteria for /goal injection: `brana backlog set {task_id} context 'AC: ...'`" |

**Hard blocks** — collect all hard failures, then:
```
AskUserQuestion:
  question: "Readiness check failed for {task_id}: {list of failures}. Fix before building?"
  header: "Readiness"
  options:
    - "Fix now — I'll update the task"
    - "Skip — reason required"
```
If "Fix now": wait for user, then re-read the task and re-run checks.
If "Skip — reason required": require free text. Log to task notes and decision log:
   ```bash
   brana backlog set {task_id} notes --append "Readiness check skipped: {reason}"
   brana decisions log main concern "Readiness check skipped for {task_id}: {reason}" --severity LOW --refs "{task_id}" 2>/dev/null || true
   ```
   Proceed.

**Soft warns** — emit inline (no gate, no question):
```
⚠ {task_id}: effort not set. Consider: `brana backlog set {task_id} effort M`
⚠ {task_id}: no AC: lines in context. /goal injection will be skipped.
```

If all checks pass (or only soft warns remain), proceed silently.

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

### 3-Level Detection (per smart-router pattern)

**Level 1 — Signal match.** Apply the table above. If stream or description keywords produce a clear match (one strategy scores highest), propose it with confidence: high.

**Level 2 — LLM classify.** If no signal matches or multiple strategies tie:
- Build a brief classification prompt from task context:
  "Task: {subject}. Description: {description}. Tags: {tags}. Classify into ONE of: feature, bug-fix, greenfield, refactor, spike, migration, investigation. Respond with strategy_name."
- If LLM returns a strategy with reasonable confidence, propose it with confidence: medium.

**Level 3 — Ask user.** If Level 2 is also ambiguous, present all viable options via AskUserQuestion (this is the existing confirmation step).

The existing AskUserQuestion confirmation always runs regardless of level — but with Level 1/2, the recommended option is pre-selected. Without Level 1/2, all options are equal weight.

> See `system/skills/_shared/smart-router.md` for the shared 3-level pattern. /build and /research both use this pattern.

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

> **☑ Checkpoint — CLASSIFY** (M+ builds with task_id):
> ```bash
> printf '{"step":"CLASSIFY","completed":"%s","task_id":"%s"}\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "{task_id}" >> ~/.claude/run-state/{task_id}.jsonl
> ```

---

## Step 2: APPROVE

**Mandatory for Medium/Large builds.** After CLASSIFY confirms the strategy, present the step sequence and get approval before executing. **Do NOT use CC plan mode (EnterPlanMode) — use AskUserQuestion for approval.**

### Lifecycle gate (always — even S-effort)

Before planning the steps, assess which disciplines apply. State the result explicitly — even if all are "no."

| Discipline | Apply when | Skip when |
|-----------|-----------|-----------|
| **DDD** (Domain-Driven Design) | `docs/domain/` exists AND task introduces or refines a domain entity, aggregate, bounded context, or cross-context change | `docs/domain/` absent, or task is correction/single-file patch |
| **SDD** (Spec-Driven Development) | Behavioral decision with architectural trade-offs (ADR needed) | Pure correction where the task description IS the spec |
| **TDD** (Test-Driven Development) | Code that can be tested (hooks, CLI, scripts, functions) | Docs-only, config-only, procedure files |

Output one line per discipline:
```
DDD: skip — no docs/domain/ in this project (opt-in)
SDD: skip — task description serves as spec (correction, no ADR needed)
TDD: apply — hook code change, write failing test first
```

If DDD applies, read `docs/domain/glossary.md` and use the ubiquitous language consistently. Propose glossary additions for any new terms introduced by the task.
If SDD applies, write or reference the ADR/spec **before** the first Edit/Write call.
If TDD applies, the BUILD step must follow red-green-refactor.

> See [docs/reflections/32-lifecycle.md](../../docs/reflections/32-lifecycle.md) §"The Development Workflow" for the full DDD → SDD → TDD → Code rationale.

### Backlog lifecycle check (M+ tasks with task_id)

For tasks with effort M, L, or XL that have a `task_id`, verify lifecycle artifacts are planned in the backlog before building:

```bash
brana backlog query --tag "sdd,ddd,test,tdd" | grep -i "<task-id or subject keywords>"
# OR
brana backlog search "<subject keywords>" | grep -E "sdd|spec|ddd|test"
```

- **DDD applies and no DDD task in backlog:** surface warning — "No DDD task found for this M+ build. Domain glossary update may be missing."
- **SDD applies and no SDD/spec task in backlog:** surface warning — "No SDD/spec task found. Behavioral spec should be planned before implementation."
- **TDD applies and no test task in backlog:** hard gate — mirror the plan step 11 TDD gate (AskUserQuestion before proceeding).
- **If lifecycle tasks exist:** proceed silently.
- **If task has no task_id or effort < M:** skip this check.

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

**DDD activation (opt-in):** if `docs/domain/glossary.md` exists in the project, read it before research. Use the project's ubiquitous language consistently throughout the spec — don't invent new terms when an existing one exists. If the task description introduces a term not in the glossary, propose adding it during draft signal step 1.

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

2. **Extract ADR if a load-bearing decision was made.** A "load-bearing" decision is one that constrains future implementation choices — picking a stack, a data model, an interface contract, a workflow ordering. If yes:
   - Allocate next ADR number: `ls docs/architecture/decisions/ADR-*.md | tail -1` → +1.
   - Write to `docs/architecture/decisions/ADR-{NNN}-{slug}.md` with sections: Status, Context, Decision, Consequences, Non-Actions.
   - Mark Status: Proposed (or Accepted if already validated).
   - The feature spec then references the ADR by filename instead of embedding the decision body.

   If no load-bearing decision: skip — the embedded "Decision Record" section in the feature spec is sufficient.

3. **Write feature spec** at `docs/features/{slug}.md` (or `docs/architecture/features/{slug}.md` if the project has the restructured layout):
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

   ## Assumptions
   Surface ambiguities before drafting. If a requirement can be interpreted two ways, ask — don't pick.
   - {assumption 1}

   ## Design
   {technical approach — components, files, patterns}

   ## Boundaries
   | Always | Ask First | Never |
   |--------|-----------|-------|
   | {what this change always does} | {what requires confirmation} | {what this change never touches} |

   ## Testing Strategy
   - **Unit:** {pure logic, no I/O — target 70%+ of test budget}
   - **Integration:** {cross-component or DB/file I/O — target 25%}
   - **E2E:** {CLI smoke or UI flow — target 5%, only if behavior can't be captured lower}
   - **Mock policy:** Real > Fake > Stub > Mock — prefer real collaborators; mock only at system boundaries (network, time, external APIs)

   ## Documentation Plan
   - [ ] **User guide** — `docs/guide/features/{slug}.md`: {what users need — behavior, commands, config, examples}
   - [ ] **Tech doc** — `docs/architecture/features/{slug}.md`: {what contributors need — design rationale, extending, key files}
   - [ ] **Existing docs to update** — {list any affected workflow/command/feature docs}

   ## Challenger findings
   {auto-populated after challenger review}
   ```

4. **Challenger review** — spawn a separate challenger agent (context isolation):
   ```
   Agent(subagent_type="challenger", prompt="Review this feature spec: {spec content}")
   ```
   Incorporate findings into the spec's Challenger findings section.

5. **Promote research** — findings that survived into the final spec get upgraded:
   ```bash
   cd "$HOME" && $CF memory store \
     -k "research:{project}:{topic}:{finding-slug}" \
     -v '{"finding": "...", "confidence": 0.6}' \
     --namespace knowledge --upsert
   ```

6. **Persistence confirmation** (Medium/Large builds) — before presenting the spec, confirm all SPECIFY artifacts are persisted on disk. Use AskUserQuestion:
   ```
   question: "SPECIFY artifacts ready for DECOMPOSE?
     · dim doc updates: {N updated — list paths, or 'none — research did not touch dim docs'}
     · ADR: {ADR-NNN-slug.md, or 'none — no load-bearing decision'}
     · feature spec: {path}"
   options:
     - "Confirm — proceed to user review"
     - "Missing artifact — back to draft (specify which)"
     - "Decision is load-bearing — extract ADR first"
   ```
   The "Decision is load-bearing" option loops back to step 2 to extract the ADR before continuing. This gate exists to catch the failure mode where a real architectural choice gets buried inside a feature spec and never surfaces to ADR review.

7. **Present spec to user** for approval. Wait for confirmation before proceeding.

8. Update spec status to `decomposing`.

> **☑ Checkpoint — SPECIFY** (M+ builds with task_id):
> ```bash
> printf '{"step":"SPECIFY","completed":"%s","task_id":"%s"}\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "{task_id}" >> ~/.claude/run-state/{task_id}.jsonl
> ```

### Gate: SPECIFY → DECOMPOSE (Medium/Large only)

Before entering DECOMPOSE, verify the SPECIFY artifact set is persisted on disk:

1. **Feature spec (mandatory)** — check that `docs/architecture/features/{slug}.md` or `docs/features/{slug}.md` exists.
2. **ADR (conditional)** — if step 2 of the Draft signal classified the decision as load-bearing, check that `docs/architecture/decisions/ADR-{NNN}-{slug}.md` exists. The feature spec must reference it by filename. If the spec embeds a populated `Decision Record` block AND no ADR file was written, treat as a load-bearing decision that escaped extraction → block.
3. **Dimension updates (conditional)** — if step 1 of the Draft signal selected dim docs to update, check that those files have a recent commit touching them on this branch (`git diff --name-only main...HEAD | grep brana-knowledge/dimensions/`).

Collect all failures, then gate:
```
question: "SPECIFY → DECOMPOSE gate. Missing: {list}. Fix before proceeding?"
options: ["Fix now (loop back to Draft signal step)", "Skip gate — reason required"]
```
If "Skip gate": require a reason via free text. Log to task notes: `brana backlog set {id} notes --append "SPECIFY→DECOMPOSE gate skipped: {reason}"`.

If all checks pass, proceed silently.

### DECOMPOSE

0. **Assumption check** (after strategy confirmed, before decomposing):
   Scan docs related to the task's tags and description for tracked assumptions. Read frontmatter `assumptions:` sections from relevant docs (dimension docs, ADRs, reasoning docs).

   ```bash
   # Search ruflo for assumptions related to task tags
   source "$HOME/.claude/scripts/cf-env.sh"
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

4. **Sprint contract** (Medium/Large builds with task_id — skip for Trivial/Small and spike/investigation):

   Builder proposes a contract: scope for this build chunk + binary success criteria. Challenger reviews. Agreed contract is written to the task before user approval.

   **Draft the contract:**
   ```
   Sprint Contract — {task_id} — {date}
   ══════════════════════════════════════
   Scope: {one sentence — what will be built in this sprint}

   Success criteria (ISC):
   - {state, not action — "All tests green" not "Run tests"}
   - {measurable end-state verifiable with a command or artifact}

   Out of scope:
   - {what is explicitly deferred}
   ```

   **Challenger review:**
   ```
   Agent(subagent_type="brana:challenger", prompt="Sprint contract review for {strategy} build, task {task_id}.
   Spec summary: {2-3 sentences}
   Contract: {contract text}
   Check: (1) Are criteria binary testable states? (2) Scope aligned with spec? (3) Critical criteria missing? (4) Anything over-scoped? Return numbered findings or 'Contract looks good.'")
   ```
   If challenger raises issues, revise and re-run (max 2 iterations). Unresolved concerns after 2 iterations: surface to user before proceeding.

   **Write agreed contract:**
   ```bash
   brana backlog set {task_id} context --append "Sprint contract {date}: Scope: {scope}. ISC: [{criteria}]"
   brana backlog set {task_id} isc "+{criterion 1}"
   brana backlog set {task_id} isc "+{criterion 2}"
   ```

5. **Present the plan** for approval. Use AskUserQuestion:
   ```
   question: "Task breakdown ready. Approve?"
   options: ["Approve", "Adjust", "Cancel"]
   ```

6. Update spec status to `building`.

> **☑ Checkpoint — DECOMPOSE** (M+ builds with task_id):
> ```bash
> printf '{"step":"DECOMPOSE","completed":"%s","task_id":"%s"}\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "{task_id}" >> ~/.claude/run-state/{task_id}.jsonl
> ```

### Gate: DECOMPOSE → BUILD (Medium/Large only)

Before entering BUILD, verify the task breakdown includes test tasks:
- At least one subtask must mention "test" in its subject or description
- The Documentation Plan from the spec must have entries
- **If either missing:** hard block.
  ```
  question: "BUILD gate: {missing items}. Fix before proceeding?"
  options: ["Add missing items now", "Skip gate — reason required"]
  ```
  If "Skip gate": require a reason. Log: `brana backlog set {id} notes --append "DECOMPOSE→BUILD gate skipped: {reason}"`.

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
            - "Write tests now (Recommended)"
            - "Skip — not a testable change (config, docs, markup)"
            - "Skip — reason required"
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

### ISC Verify (all strategies with task_id, when isc field is set)

Before the BUILD→CLOSE gate, check whether the active task has ISC (Ideal State Criteria):

```bash
brana backlog get {task_id} | jq -r '.isc[]?' 2>/dev/null
```

If the `isc` array is non-empty, verify each item as a binary pass/fail with evidence:

For each criterion:
1. State the criterion explicitly
2. Gather evidence (run a command, read a file, check git status — whatever proves the state)
3. Judge: **PASS** or **FAIL** with one-line evidence summary

Collect results. If any criterion **FAIL**:
```
question: "ISC VERIFY: {N} of {total} criteria failed — {list of failed criteria}. Fix before closing?"
options: ["Fix now", "Skip — reason required"]
```
If "Skip": require reason, log: `brana backlog set {id} notes --append "ISC skipped: {reason}"`.

If all pass (or no isc field): proceed silently.

### Gate: BUILD → CLOSE (Medium/Large feature/greenfield/migration only)

Before entering CLOSE, verify all mandatory artifacts exist on the branch:
1. **Tests:** `git diff --name-only main...HEAD` must include test files (`*test*`, `*spec*`, `tests/`, `__tests__/`)
2. **Docs:** at least one doc file in the diff (`docs/`)
3. **All subtasks completed:** no `in_progress` or `pending` subtasks remain

Check each, collect failures, then gate:
```
question: "BUILD→CLOSE gate. Missing: {list of failures}. Fix before closing?"
options: ["Fix now", "Skip gate — reason required"]
```
If all pass, proceed silently. If "Skip gate": require reason. Log: `brana backlog set {id} notes --append "BUILD→CLOSE gate skipped: {reason}"`.

Bug fix and refactor strategies: skip doc check (only require tests).
Spike and investigation: skip this gate entirely.

### Four Questions Gate (all strategies except spike/investigation)

Before declaring BUILD done, answer all four — out loud, in the response:

1. **Tests pass with actual output?** — run the suite, state the pass count (e.g. "535/535 pass").
2. **All requirements addressed?** — re-read the spec or task description; confirm every criterion is covered.
3. **Assumptions documented?** — every assumption made during BUILD is recorded under `## Assumptions` in the spec.
4. **Evidence provided?** — a test run result, screenshot, or log excerpt proves the behavior works as specified.

If any answer is No, continue working. This gate is blocking, not advisory. Spike and investigation strategies skip it.

### Docs — generate here, not in CLOSE

Run `/brana:docs` immediately after BUILD passes, before CLOSE. CLOSE step 6 is the fallback safety net only.

```
Skill(skill="brana:docs", args="{strategy-appropriate args}")
```

| Strategy | Args |
|----------|------|
| Feature / Greenfield / Migration | `all {task-id}` |
| Bug fix | `update {task-id}` |
| Refactor | `update {task-id}` |

Skip for spike and investigation strategies.

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

> **☑ Checkpoint — REPRODUCE** (M+ builds with task_id):
> ```bash
> printf '{"step":"REPRODUCE","completed":"%s","task_id":"%s"}\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "{task_id}" >> ~/.claude/run-state/{task_id}.jsonl
> ```

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

> **☑ Checkpoint — DIAGNOSE** (M+ builds with task_id):
> ```bash
> printf '{"step":"DIAGNOSE","completed":"%s","task_id":"%s"}\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "{task_id}" >> ~/.claude/run-state/{task_id}.jsonl
> ```

### Gate: REPRODUCE → FIX

Before implementing the fix, verify a failing test was written in REPRODUCE:
- Check `git diff --name-only` and `git diff --cached --name-only` for test file patterns.
- **If test files found:** proceed to FIX.
- **If no test files found:** hard block.
  ```
  AskUserQuestion:
    question: "No failing test written yet. The test IS the spec — write it before fixing. What to do?"
    header: "TDD gate"
    options:
      - "Write test now (Recommended)"
      - "Skip — no test framework available"
  ```
  If "Write test now": loop back to REPRODUCE step 3.
  If "Skip": log reason and proceed.

### FIX

1. **Create branch** (if not already on one):
   ```bash
   git checkout -b fix/{task-id}-{slug}
   ```
2. **Implement the fix** — make the failing test pass.
3. **Run full test suite** — no regressions.
4. **Commit:** `fix(scope): description`

> **☑ Checkpoint — FIX** (M+ builds with task_id):
> ```bash
> printf '{"step":"FIX","completed":"%s","task_id":"%s"}\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "{task_id}" >> ~/.claude/run-state/{task_id}.jsonl
> ```

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

> **☑ Checkpoint — SPECIFY** (M+ builds with task_id):
> ```bash
> printf '{"step":"SPECIFY","completed":"%s","task_id":"%s"}\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "{task_id}" >> ~/.claude/run-state/{task_id}.jsonl
> ```

### VERIFY COVERAGE

1. **Run existing tests** — all must pass. Record baseline: "N tests pass."
2. **Identify coverage gaps** — if the area being refactored lacks tests:
   - Write tests for current behavior FIRST
   - These tests anchor the refactor — behavior must not change
3. **Confirm baseline:** "N tests pass before refactor. Behavior contract is locked."

> **☑ Checkpoint — VERIFY-COVERAGE** (M+ builds with task_id):
> ```bash
> printf '{"step":"VERIFY-COVERAGE","completed":"%s","task_id":"%s"}\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "{task_id}" >> ~/.claude/run-state/{task_id}.jsonl
> ```

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

> **☑ Checkpoint — QUESTION** (M+ builds with task_id):
> ```bash
> printf '{"step":"QUESTION","completed":"%s","task_id":"%s"}\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "{task_id}" >> ~/.claude/run-state/{task_id}.jsonl
> ```

### EXPERIMENT

1. Work in `/tmp/spike-{slug}/` or a scratch directory.
2. Quick prototype — throwaway code.
3. No tests, no commits, no branch.
4. Focus entirely on answering the question.

> **☑ Checkpoint — EXPERIMENT** (M+ builds with task_id):
> ```bash
> printf '{"step":"EXPERIMENT","completed":"%s","task_id":"%s"}\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "{task_id}" >> ~/.claude/run-state/{task_id}.jsonl
> ```

### ANSWER

1. **Result:** yes / no / partially. Present findings.
2. **Store finding** via retrospective pattern:
   ```bash
   cd "$HOME" && $CF memory store \
     -k "spike:{project}:{slug}" \
     -v '{"question": "...", "answer": "...", "conclusion": "yes|no|partial"}' \
     --namespace pattern \
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

> **☑ Checkpoint — SYMPTOMS** (M+ builds with task_id):
> ```bash
> printf '{"step":"SYMPTOMS","completed":"%s","task_id":"%s"}\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "{task_id}" >> ~/.claude/run-state/{task_id}.jsonl
> ```

### INVESTIGATE

1. **Test hypotheses one by one:**
   - Read code paths
   - Run diagnostic commands
   - Check data/state
   - Compare expected vs actual behavior
2. **Document findings as you go** — each hypothesis tested, result, next step.
3. **No code changes** — this is read-only analysis.

> **☑ Checkpoint — INVESTIGATE** (M+ builds with task_id):
> ```bash
> printf '{"step":"INVESTIGATE","completed":"%s","task_id":"%s"}\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "{task_id}" >> ~/.claude/run-state/{task_id}.jsonl
> ```

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
     --namespace pattern \
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

## Shared: Auto-Learning (EXTRACT → EVALUATE → PERSIST)

Runs after main build work, before CLOSE (or before REPORT/ANSWER for investigation/spike). All strategies execute these steps.

### EXTRACT

Identify what was learned during the build.

1. **Diff review** — run `git diff --stat` (or `git diff --stat main...HEAD` on a branch) to see what changed.
2. **Process review** — reflect on the build: what worked, what didn't, what was surprising, what took longer than expected.
3. **Classify findings** using ontology types:
   | Type | When to use |
   |------|-------------|
   | **Pattern** | Reusable solution, workaround, or approach |
   | **ADR** | Architectural decision made during implementation |
   | **FieldNote** | Practical discovery, gotcha, dependency behavior |
   | **Dimension** | New topic area or significant expansion of existing knowledge |
4. **Build-specific signals** — look for: architectural decisions made under pressure, dependency behaviors discovered empirically, error paths that weren't documented, performance characteristics observed.

> **☑ Checkpoint — EXTRACT** (M+ builds with task_id):
> ```bash
> printf '{"step":"EXTRACT","completed":"%s","task_id":"%s"}\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "{task_id}" >> ~/.claude/run-state/{task_id}.jsonl
> ```

### EVALUATE

Score each finding on a 0-10 scale across three dimensions:

| Size | Scope | Novelty | Gate |
|------|-------|---------|------|
| **SMALL** (0-1) | This task only | Already known | Auto-persist |
| **MEDIUM** (2-4) | This project | New twist on existing topic | Inline dedup check via ruflo |
| **LARGE** (5+) | Cross-project | New topic or contradicts existing knowledge | User review, suggest challenger |

**Dedup check** (MEDIUM and LARGE findings — run in parallel):
```
mcp__ruflo__memory_search(query: "{finding summary}", namespace: "knowledge", limit: 2)
mcp__ruflo__memory_search(query: "{finding summary}", namespace: "pattern",   limit: 2)
```
If top result similarity ≥ 0.85, skip persistence (already captured). Otherwise proceed to PERSIST.

> Threshold 0.85 calibrated 2026-05-24 (t-1589): max distinct-pair similarity = 0.59, gap = 0.26.

> **☑ Checkpoint — EVALUATE** (M+ builds with task_id):
> ```bash
> printf '{"step":"EVALUATE","completed":"%s","task_id":"%s"}\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "{task_id}" >> ~/.claude/run-state/{task_id}.jsonl
> ```

### PERSIST

Route each finding by type:

| Type | Destination | Auto/Prompted |
|------|------------|---------------|
| **Pattern** | `mcp__ruflo__memory_store(namespace: "pattern")` + append to relevant memory file | SMALL: auto, MEDIUM+: prompted |
| **ADR** | Draft in `docs/architecture/decisions/` | Always prompted |
| **FieldNote** | Append to relevant doc's Field Notes section | Prompted |
| **Tags/context** | Task context via `brana backlog set {id} context --append "{finding}"` | Auto |

**Pattern persistence format:**

Dedup gate (run before every pattern memory_store — including SMALL auto-persists):
```
mcp__ruflo__memory_search(query: "{finding summary}", namespace: "pattern", limit: 1, threshold: 0.85)
```
- **Hit (similarity ≥ 0.85):** reuse the existing key with `upsert: true` — update confidence, append source_task. Do NOT create a new entry.
- **Miss (< 0.85) or MCP unavailable:** write new entry with a fresh key.

```
mcp__ruflo__memory_store(
  key: "pattern:{project}:{finding-slug}",   # or existing key on hit
  value: "{\"problem\": \"...\", \"solution\": \"...\", \"confidence\": 0.5, \"source_task\": \"{task-id}\"}",
  namespace: "pattern",
  tags: ["client:{project}", "type:{ontology-type}", "strategy:{build-strategy}"],
  upsert: true
)
```

If ruflo unavailable, fall back to appending to project auto memory (`~/.claude/projects/*/memory/`).

**Frontmatter relationships:** If PERSIST created or updated a markdown file (ADR, FieldNote, or doc), add YAML frontmatter relationships to that file:
- `produced_by: [source-doc-path]` — the doc or task that triggered this finding
- `applies_to: [project-or-client]` — if the finding is cross-client transferable
- `depends_on: [related-doc-path]` — if the finding extends or refines an existing doc

If the file already has frontmatter (`---` block), merge into it. If not, prepend a new block. Only add relationships that actually apply — don't force all three on every file.

Post-commit hook will rebuild `spec-graph.json` — new edges appear automatically.

**Graceful degradation:** If no findings worth persisting (trivial build, nothing surprising), skip EVALUATE and PERSIST silently. Don't force learnings where none exist.

> **☑ Checkpoint — PERSIST** (M+ builds with task_id):
> ```bash
> printf '{"step":"PERSIST","completed":"%s","task_id":"%s"}\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "{task_id}" >> ~/.claude/run-state/{task_id}.jsonl
> ```

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
   brana decisions log main decision \
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
       --namespace pattern \
       --tags "client:{project},type:build-learning" \
       --upsert
     ```
   If ruflo unavailable, append to project's auto memory MEMORY.md.

   After storing learnings, call:
   ```
   mcp__ruflo__autopilot_learn()
   ```
   This seeds the autopilot pattern registry from completed task outcomes — no params needed.

4. **Knowledge maintenance** (after tests pass, before docs/merge):

   a. **Field notes**: Review session learnings from the build. If any practical discoveries emerged (unexpected behavior, workarounds, integration gotchas, performance findings), prompt the user:
      ```
      question: "Capture any of these as field notes?"
      options: ["Yes — I'll specify which", "No learnings worth capturing", "Auto-capture all"]
      ```
      Only flag obvious, reusable learnings — don't prompt for every mini-debrief. Store approved field notes:
      ```bash
      source "$HOME/.claude/scripts/cf-env.sh"
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
      source "$HOME/.claude/scripts/cf-env.sh"
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

6. **Generate documentation** via `/brana:docs`:

   Always invoke — strategy determines scope:

   | Strategy | Args | What gets generated |
   |----------|------|-------------------|
   | Feature / Greenfield / Migration | `all {task-id}` | Tech doc + user guide + shared doc updates |
   | Bug fix | `update {task-id}` | Changelog entry + affected doc updates only |
   | Refactor | `update {task-id}` | Changelog entry + architecture doc updates |

   ```
   Skill(skill="brana:docs", args="{args from table above}")
   ```

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

11. **Reconcile check** (post-merge, before docs):
   If `docs/spec-graph.json` exists, check whether merged files appear in any spec-graph node's `impl_files`. If matches found, offer to run `/brana:reconcile`:
   ```
   question: "Merged files touch spec-documented systems: {list}. Run reconcile?"
   options: ["Yes — run /brana:reconcile", "Skip — I'll reconcile later"]
   ```
   If the user says yes, invoke `Skill(skill="brana:reconcile")`.
   If no spec-graph hits, skip silently.

12. **Update living docs** (post-merge, on main):
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

13. **Report:**
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

> **☑ Checkpoint cleanup — CLOSE:** Delete run-state on successful close (M+ builds with task_id):
> ```bash
> rm -f ~/.claude/run-state/{task_id}.jsonl
> ```

---

## Task Integration

### Entry via /brana:backlog start

When `/brana:backlog start <id>` invokes this skill:

1. **Task metadata is pre-loaded:**
   - `subject` → seeds the description
   - `stream` → informs strategy detection
   - `tags` → inform research scope
   - `description` → additional context
   - `context` → prior research, notes, links; `AC:` lines drive goal injection (Step 0 sub-step 0)
   - `blocked_by` → verified all resolved

2. **Skip cross-reference** (task already identified).

3. **CLASSIFY uses the 3-level smart router** (signal match → LLM classify → ask user):
   - Level 1 — stream as primary signal: `roadmap` → feature, `bugs` → bug fix, `tech-debt` → refactor, `experiments` → spike, `research` → investigation. Description signals override if clearer.
   - Level 2 — LLM classify if stream/description are ambiguous.
   - Level 3 — AskUserQuestion if still unclear.

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
   brana backlog add --json '{"subject":"{description}","work_type":"{from strategy}","type":"task","execution":"code"}'
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

| Size | Signal | SPECIFY depth | DECOMPOSE detail | Enforcement gates |
|------|--------|--------------|-------------------|-------------------|
| **Trivial** | 1 file, obvious fix | Skip SPECIFY | No decomposition | None |
| **Small** | 1-3 files, scope clear | Light (no research) | Inline — no separate step | None |
| **Medium** | 4+ files, design needed | Full research loop | Full task breakdown | Hard gates at transitions |
| **Large** | New skill/system, unknown scope | Deep research + challenger | Full + dependencies | Hard gates at transitions |

Claude proposes the size. User can override: "this is bigger than it looks" or "just do it, it's simple."

---

## Rules

1. **CLASSIFY is mandatory.** Uses the 3-level smart router (signal → LLM → ask). Never skip the confirmation step. Never silently apply a strategy.
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
