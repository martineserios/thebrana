# Brana Operating Model

> Designed 2026-04-04. Status: idea.
> Research: 18 sources (Karpathy x2, Letta, AnimaWorks, Anthropic official, 12-Factor Agents, Sirchmunk, Cognee, Knwler, CC memory, harness engineering, autoresearch adoption, KG patterns, context engineering).
> Patterns: `brana-knowledge/dimensions/49-auto-learning-patterns.md`

## Core Principles

> Knowledge should **flow in at work start** and **flow out at work end.** The automation, not the simplicity, is the transferable principle. — from Karpathy

> Harness engineering defines static governance. Brana extends it with **auto-learning**: a harness that captures learning from each session and propagates it back into the system. — extends Gundecha

> **Shrink the search space, not grow the agent.** Autonomous iteration works only in small, measurable spaces. — from Karpathy autoresearch

---

## 1. The 6 Jobs

Everything a solo operator does falls into 6 jobs. Auto-learning is not a job — it's a **property** embedded in all thinking-jobs.

```
┌──────────────────────────────────────────────────────────────┐
│                  THE SOLO OPERATOR'S 6 JOBS                  │
│                                                              │
│  AUTO-LEARNING LOOP (embedded in all thinking-jobs)          │
│  LOAD → WORK → EXTRACT → EVALUATE → PERSIST  (+weekly DECAY)│
│                                                              │
├──────────────────────────────────────────────────────────────┤
│  1. DECIDE        "What should I work on?"                   │
│  2. UNDERSTAND    "What do I need to know?"                  │
│  3. BUILD         "Make the thing"                           │
│  4. SHIP          "Get it to users"                          │
│  5. MAINTAIN      "Keep it healthy"                          │
│  6. GROW          "Build the business"                       │
│                                                              │
│  + CAPTURE (lightweight, anytime)                            │
│  + KNOWLEDGE HEALTH (weekly DECAY cycle)                     │
└──────────────────────────────────────────────────────────────┘
```

### 1. DECIDE

| Activity | Skill |
|----------|-------|
| Triage incoming work | `/brana:backlog triage` |
| Plan a phase | `/brana:backlog plan` |
| Pick next task | `/brana:backlog next` |
| Think through an idea | `/brana:brainstorm` |

### 2. UNDERSTAND

Unified under `/brana:research` with 4 strategies:

| Strategy | Trigger | Output |
|----------|---------|--------|
| **research** (default) | "What is X?" | Dimension doc update/creation |
| **evaluate** | "Should we use X or Y?" | ADR (decision record) |
| **learn** | "I'm starting with X tech" | Dimension doc + gotchas + learning path |
| **investigate** | "Why is X broken?" | Root cause + gotcha + fix recommendation |

Plus `/brana:onboard` for exploring new codebases.

### 3. BUILD

| Activity | Skill |
|----------|-------|
| Feature | `/brana:build` (strategy: feature) |
| Bug fix | `/brana:build` (strategy: bug-fix) |
| Refactor | `/brana:build` (strategy: refactor) |
| Migration | `/brana:build` (strategy: migration) |
| Spike | `/brana:build` (strategy: investigation) |

### 4. SHIP

**Proposed: `/brana:ship`** — 6 generic steps, project-specific implementation per step.

| Step | Purpose |
|------|---------|
| **Pre-flight** | Is this safe to deploy? (tests, build, env config, rollback plan) |
| **Deploy** | Push it out (project-specific: Railway, bootstrap, publish) |
| **Document** | Record what shipped (changelog, version bump, notify, close tasks) |
| **Verify** | Did it work? (smoke tests, health checks) |
| **Monitor** | Is it stable? (watch errors 15-30 min, check metrics) |
| **Rollback** | (conditional) Undo if needed |

### 5. MAINTAIN

**Unified under `/brana:maintain`** — absorbs audit + reconcile + maintain-specs.

| Domain | Checks |
|--------|--------|
| **Security** | Secrets in config, hook permissions, PreToolUse deny gates |
| **Infra** | Disk space, ruflo DB health, backup freshness |
| **Consistency** | Spec ↔ implementation drift, CLAUDE.md ↔ skills, spec-graph ↔ files |
| **Propagation** | Pending errata cascade (dimension → reflection → roadmap) |
| **Knowledge** | Stale dimensions, event log bloat, ruflo noise, orphan docs |
| **Code** | Outdated deps, security advisories (future) |

**Close integration:** `/brana:close` auto-detects brana system file changes → triggers `--scope consistency,propagation` automatically.

**Retires:** `/brana:audit`, `/brana:reconcile`, `/brana:maintain-specs`.

### 6. GROW

| Activity | Skill |
|----------|-------|
| Business review | `/brana:review` |
| Client onboarding | `/brana:onboard` |
| Content creation | `/brana:harvest` |
| Positioning/strategy | `/brana:brainstorm` |

### CAPTURE (utility, not a job)

| `/brana:log` | Log events, URLs, notes |

---

## 2. The Auto-Learning Loop

Embedded in all thinking-jobs. Steps 1-5 run per-skill. Step 6 on a weekly schedule.

```
┌──────────────────────────────────────────────────────────────┐
│                    THE AUTO-LEARNING LOOP                     │
│                                                              │
│  1. LOAD      ← pull relevant knowledge into context         │
│  2. WORK      ← do the actual task                           │
│  3. EXTRACT   ← identify what was learned                    │
│  4. EVALUATE  ← quality gate (tiered by significance)        │
│  5. PERSIST   ← store learnings in the right place           │
│  6. DECAY     ← forget what's no longer valuable             │
│                                                              │
│  ┌─→ 1 → 2 → 3 → 4 → 5 ─────→ next session ──────────┐    │
│  │                                    6 (weekly) ───────┘    │
│  └───────────────────────────────────────────────────────┘   │
└──────────────────────────────────────────────────────────────┘
```

### Which Skills Get It

| Skill | LOAD scope | WRITE-BACK |
|-------|-----------|------------|
| `/brana:brainstorm` | Dimensions + ideas + recent research | Auto: idea doc. Prompt: dimensions. |
| `/brana:build` | Architecture + feature brief + decisions | Auto: task context. Prompt: decisions. |
| `/brana:research` | Existing dimensions + sources YAML | Auto: dimension update. Prompt: new dimensions. |
| `/brana:review` | Metrics + pipeline + event log + health | Auto: event log. Prompt: strategic findings. |

All other skills stay untouched.

### Step 1: LOAD

- Build query: `"{project} {task.subject} {task.tags} {user_input}"`
- Primary: `memory_search(query, namespace: "all", limit: 5, threshold: 0.4)`
- Fallback: tag-based grep across dimensions + reflections
- Budget: 30K tokens max (configurable per skill)

### Step 2: WORK

Unchanged — skills execute as today.

### Step 3: EXTRACT

At skill end, LLM identifies: facts learned, decisions made, patterns observed.

### Step 4: EVALUATE (Tiered Quality Gate)

| Signal | SMALL (score 0-1) | MEDIUM (score 2-4) | LARGE (score 5+) |
|--------|-------------------|---------------------|-------------------|
| **Scope** | Single task | This project | Multiple clients |
| **Novelty** | Already known | New on existing topic | New topic or contradicts |
| **Type** | Tag, URL, context | Dimension update, gotcha | ADR, new dimension, cross-client |

| Size | Gate | Speed | Cost |
|------|------|-------|------|
| SMALL | None — auto-persist | Instant | Zero |
| MEDIUM | Inline eval (dedup, consistency, scope, source) | ~5s | ~2K tokens |
| LARGE | Challenger agent (Opus) + human | ~30s + human | ~10K tokens |

### Step 5: PERSIST

| Finding type | Auto (SMALL) | Prompted (MEDIUM/LARGE) |
|-------------|-------------|------------------------|
| Task context, event log, tags, URLs | Yes | — |
| Dimension doc update | — | Append to existing |
| New dimension doc | — | Create in brana-knowledge |
| Architecture decision | — | New ADR |
| Cross-client pattern | — | Memory file |

### Step 6: DECAY

Three targets, continuous (stale warnings during LOAD) + weekly scan:

**Stale dimensions:** >90 days + no search hits → staleness marking in frontmatter. LOAD shows warning.

**Event log bloat:** >90 day entries → archive with pre-archive digest (themes + counts).

**Ruflo noise:** Old/low-confidence entries → soft decay (lower ranking) → hard decay at 180 days (prompted delete). Tracked in `decay-tracker.json`.

---

## 3. Memory Hierarchy (Letta OS Model)

```
┌─────────────────────────────────────────────────────────┐
│  CORE MEMORY (always in context — loaded by CC harness) │
│  CLAUDE.md + Rules + MEMORY.md                          │
│  ~30-50K tokens. Always available.                      │
├─────────────────────────────────────────────────────────┤
│  ARCHIVAL MEMORY (searched on demand — loaded by skills)│
│  brana-knowledge/dimensions/ + docs/reflections/        │
│  + ruflo memory entries (1364 entries, 5 namespaces)    │
│  Searched via ruflo or grep. Top 3-5 docs loaded.       │
├─────────────────────────────────────────────────────────┤
│  EXTERNAL (fetched when needed — not cached)            │
│  Web search, GitHub repos, API docs, MCP tools          │
└─────────────────────────────────────────────────────────┘
```

MAINTAIN vs AUTO-LEARN: different targets, shared DECAY.
- MAINTAIN = product health (code, infra, deps, security)
- AUTO-LEARN = knowledge health (dimensions, memory, patterns)
- Overlap: brana's own specs (both product AND knowledge)

---

## 4. Job Composability

Jobs nest and compose — they're not sequential:

```
BUILD can trigger UNDERSTAND (diagnosis needed for a bug)
UNDERSTAND can trigger BUILD (spike/prototype helps understanding)
GROW can trigger UNDERSTAND (market research needed)
DECIDE can trigger UNDERSTAND (triaging requires investigation)
```

The auto-learning loop runs at **every level** — outer job and inner sub-flows both produce knowledge.

---

## 5. Smart Router

Skills auto-detect strategy via 3-level escalation. All logic in skill markdown — no code.

### Entry Routing

| Level | Mechanism | Coverage |
|-------|-----------|----------|
| **1. Signal match** | Tags, stream, keywords, git state | ~60-70% |
| **2. LLM classify** | Prompt template classifies from context | ~25-30% |
| **3. Ask user** | AskUserQuestion with options | ~5-10% |

### Mid-Workflow Rerouting

Gate checks at each step: can't reproduce → investigate. Root cause found → back to build. Scope grew → reroute to feature.

### Router Self-Learning

1. Log every routing decision to ruflo (`namespace: "routing"`)
2. Weekly: detect reroute patterns ("4/6 security bugs rerouted → promote to Level 1 rule")
3. After 10+ consistent reroutes, suggest new Level 1 signal rule

---

## 6. Documentation Discipline

### The Chain

```
DDD → dimension docs, domain glossary     (what we're building)
SDD → ADRs, feature briefs, specs         (how we're building it)
TDD → test files                           (does it work correctly)
```

### Current State

- DDD→SDD→TDD defined in `docs/reflections/32-lifecycle.md`
- TDD/SDD enforcement: `tdd-gate.sh` (PreToolUse deny on feat/fix branches)
- 26 ADRs in `docs/architecture/decisions/`

### Diagnosis

**72% of behavioral commits (124/172) have no doc updates.** Root causes: most work on main (bypasses gates), no doc enforcement mechanism.

**Critical insight:** The auto-learning loop IS the primary fix. EXTRACT detects changes → PERSIST prompts updates. Automation replaces discipline that fails 72%.

### Two Parallel Tracks

**Track 1 (primary): Auto-learning loop** — EXTRACT catches undocumented changes, EVALUATE drafts ADRs, PERSIST writes docs. Solves 90%.

**Track 2 (insurance): Branch + enforcement** — nudge to create branches, scoped doc-update hook on feat/fix, ADR lifecycle management. Catches the 10%.

### 5 Gaps

1. **Doc-update hook** — scoped to behavioral files on feat/fix branches
2. **ADR lifecycle** — `status: superseded` frontmatter + staleness checks
3. **Auto-ADR** — LARGE findings auto-draft ADRs
4. **Domain glossary** — template in /onboard
5. **ADR staleness** — /maintain consistency domain

---

## 7. Component Model

| Component | Role | Analogy |
|-----------|------|---------|
| **Skill** | Workflow definition (steps, gates, decisions) | Playbook / SOP |
| **Command** | Reusable operation, no interaction | Function |
| **Agent** | Focused worker, bounded scope, returns results | Employee with a task |
| **CLI** | Deterministic data operations | Database query |
| **Main context** | Orchestrator (reads playbook, spawns workers) | Project manager |

---

## 8. What NOT to Build

| Temptation | Why skip | Source |
|------------|---------|--------|
| Full knowledge graph (Neo4j, Cognee) | 33 docs don't justify graph infra | KG research |
| Adversarial evaluator for ALL findings | Tiered evaluation is sufficient | Anthropic |
| Memory-as-git (Letta Code) | Markdown files already in git | Letta Code |
| Embedding-free RAG (Sirchmunk) | v0.0.1; ruflo works | Sirchmunk |
| Self-editing core memory | Agent rewriting CLAUDE.md is risky | Letta |
| Nightly consolidation | Weekly is sufficient at brana's scale | AnimaWorks |

---

## 9. Research Evidence

18 sources → 10 structural patterns + 3 meta-patterns. Full analysis in `brana-knowledge/dimensions/49-auto-learning-patterns.md`.

**Key patterns:** The Ratchet (persist > discard), Intent/Execution Separation, Bounded Search Space, Knowledge-From-Use, Two Clocks (fast capture + slow consolidation), Tiered Access, Forgetting as Feature, Observable Metrics, Progressive Disclosure, Adversarial Validation.

**Meta-patterns:** The Learning Triangle (CONSTRAIN + PRODUCE + VALIDATE), Two Clocks, Simplicity Wins at Every Scale.

---

## 10. Measurement Framework (Ratchet-Gated)

Each phase only ships if the previous phase's metrics hit targets. No evidence = no expansion.

### Primary Metric: Doc-Update Rate

```
BEFORE: 28% of behavioral commits include doc updates
Month 1 target: >50%
Month 3 target: >70%
Measurement: git log analysis (same method as the 72% diagnosis)
```

### Per-Step Metrics

| Metric | What it measures | Target | How to collect |
|--------|-----------------|--------|---------------|
| **Doc-update rate** | % behavioral commits with docs | >50% (m1), >70% (m3) | `git log` analysis |
| **EXTRACT accuracy (precision)** | % of suggestions that match real changes | >70% | Compare EXTRACT output vs `git diff` |
| **EXTRACT accuracy (recall)** | % of real changes that EXTRACT caught | >60% | Compare EXTRACT output vs `git diff` |
| **Accept rate** | % of suggestions user accepted | >40% | Track in session state JSON |
| **Skip rate** | % of suggestions user skipped | <60% | Track in session state JSON |
| **Close duration** | Time added to /close by EXTRACT | <2x current | Track in session state JSON |
| **Ontology type usage** | Which entity types are loaded/extracted/persisted | >0 in 30 days | Track in session state JSON |
| **Relationship usage** | Which relationship types are traversed/written | >0 in 30 days | Track in session state JSON |

### Collection

Appended to session state JSON during /close:
```json
"extract_metrics": {
  "behavioral_files_changed": 5,
  "findings_proposed": 3,
  "findings_accepted": 2,
  "findings_skipped": 1,
  "close_duration_seconds": 180
}
```

30-day review: `brana session history --json | jq '[.[].extract_metrics]'`

### Ratchet Gate

If month 1 metrics don't hit targets → fix EXTRACT, don't add LOAD.
If EXTRACT accuracy <50% → the LLM prompt needs improvement, not more steps.
If skip rate >80% → suggestions aren't useful, not a discipline problem.

### Challenger Critique (2026-04-04)

Opus adversarial review found 3 critical issues:
1. Full loop is too ambitious for a 72%-failure system → graduated monthly rollout
2. Ontology v2 (15 types) contradicts cited sources → start with 5 types
3. Rollout puts doc enforcement last → reorder to pain-first

Full challenge report stored in decision log. Verdict: PROCEED WITH CHANGES.

## 11. Phased Rollout (Revised — Pain-First, Evidence-Gated)

Reordered after challenger review: highest-pain items first, evidence gates between phases.

### Phase A: Foundation (Month 1)

| Step | What | Effort |
|------|------|--------|
| **A1** | EXTRACT-only in /close (diff-based doc update prompting) | 1-2 days |
| **A2** | Doc-enforcement hook (behavioral files on feat/fix branches) | 1 day |
| **A3** | 6-job taxonomy as CLAUDE.md reorganization | 1 hour |

**Gate:** After 30 days, measure doc-update rate. If <50%, fix A1/A2 before proceeding.

### Phase B: Knowledge Loading (Month 2, if Gate A passes)

| Step | What | Effort |
|------|------|--------|
| **B1** | Add LOAD to 4 thinking skills (ruflo search + graph edges) | 2 days |
| **B2** | Ontology v1.5 (5 types + 3 relationships in frontmatter) | 1 day |
| **B3** | Retire /audit + /maintain-specs, fold into /reconcile | 1 day |

**Gate:** EXTRACT accuracy >60% AND doc-update rate >50%.

### Phase C: Full Loop (Month 3, if Gate B passes)

| Step | What | Effort |
|------|------|--------|
| **C1** | Move EXTRACT into thinking skills (per-skill, not just /close) | 1-2 days |
| **C2** | Add EVALUATE (tiered gate: SMALL/MEDIUM/LARGE) | 1-2 days |
| **C3** | PERSIST routing (auto SMALL, prompt MEDIUM/LARGE) | 1 day |

**Gate:** Accept rate >40%, skip rate <60%.

### Phase D: Maturity (Month 4+, if Gate C passes)

| Step | What | Effort |
|------|------|--------|
| **D1** | DECAY (weekly scan, staleness marking, archive) | 1-2 days |
| **D2** | `brana graph` Rust CLI (ontology-aware, replaces spec_graph.py) | 2-3 days |
| **D3** | UNDERSTAND strategies (evaluate, learn, investigate) | 2-3 days |
| **D4** | SHIP skill (6 generic steps) | 2-3 days |
| **D5** | Smart router (levels 1+2 only, no self-learning) | 1-2 days |

### Deferred (gated on Phase D evidence)

- Full ontology v2 (15 types) — add when workflow demands
- Smart router self-learning — add when reroute data justifies
- Obsidian as human interface — add when graph visualization is a real need
- Unified /maintain mega-skill — add if /reconcile expansion proves insufficient

---

## 12. Ontology + Knowledge Graph

### Approach: Ontology First → Graph Emerges

1. **Ontology spec** (`docs/brana-ontology.yaml`) defines the semantic structure: 15 entity types, 11 relationships, 6 axioms
2. **Frontmatter annotations** on docs declare typed relationships (depends_on, informs, applies_to, etc.)
3. **Computed graph** from frontmatter → extends spec-graph.json with typed edges. Built by script/hook.
4. **LOAD step** follows graph edges for smarter knowledge loading (not just vector similarity)

### Two Interfaces, Same Files

```
Obsidian (human interface)          Claude Code + ruflo (machine interface)
├── Graph view (typed edges)        ├── LOAD (semantic search + graph traversal)
├── Dataview (query frontmatter)    ├── PERSIST (write markdown + frontmatter)
├── Breadcrumbs (navigation)        ├── MAINTAIN (consistency checks)
└── Visual gap detection            └── DECAY (staleness + noise)
         │                                    │
         └────── same markdown files ─────────┘
                  (git repo = vault)
```

No Obsidian MCP needed — they share the filesystem. Git syncs both views.

### Key Obsidian Plugins
- **Dataview** — query frontmatter as structured data
- **Graph Link Types** — colored typed edges in graph view
- **Wikilink-types** — type relationships inline, auto-syncs to frontmatter
- **Breadcrumbs** — hierarchical navigation

### How the Ontology Powers the Auto-Learning Loop

| Loop Step | Ontology role |
|-----------|-------------|
| **LOAD** | Follows typed edges (informs, depends_on) to load relevant docs — not just similarity |
| **EXTRACT** | Entity types provide vocabulary for classifying findings (Pattern? ADR? FieldNote?) |
| **EVALUATE** | Axioms power the quality gate (contradicts → flag, supersedes → auto-status) |
| **PERSIST** | Entity types determine WHERE to store (Pattern → ruflo, ADR → decisions/, FieldNote → dimension). ALSO writes new frontmatter relationships (produced_by, applies_to). |
| **DECAY** | Graph-aware pruning: orphan nodes (no edges), stale nodes (last_verified), contradiction detection |

### How Each Job Uses Ontology Relationships

| Job | Key relationships used |
|-----|----------------------|
| **DECIDE** | `blocked_by`, `depends_on` (transitive) — surface hidden blockers |
| **UNDERSTAND** | `informs` (auto-load relevant dims), `contradicts` (flag conflicting research) |
| **BUILD** | `implements` (link code to specs), `decided_by` (load justifying ADR) |
| **SHIP** | `produced_by` (changelog from graph edges, not git log parsing) |
| **MAINTAIN** | `implements` (check links valid), `supersedes` (check chains complete), orphan detection |
| **GROW** | `applies_to` (cross-client patterns → content ideas, cross-pollination) |

### Three Layers (Schema → Data → Graph)

```
ONTOLOGY (stable schema — rarely changes)
  docs/brana-ontology.yaml: 15 types, 11 relationships, 6 axioms

FRONTMATTER (instance data — grows every session via PERSIST)
  Each markdown file's YAML: typed relationships (depends_on, informs, etc.)

GRAPH (computed — auto-recomputes on commit, never manually edited)
  docs/spec-graph.json: typed nodes + typed edges + axiom-derived edges
```

The ontology grows from use: PERSIST writes frontmatter → graph recomputes → LOAD follows new edges next session.

### spec-graph.json Upgrade Path

Current: 211 nodes (all untyped), 568 untyped edges, 103 orphans (49%), zero typed edges.

Target: `brana graph` Rust CLI subcommand (replaces spec_graph.py). Reads ontology YAML + doc frontmatter + markdown links. Writes typed nodes + typed edges + axiom-computed edges. Subcommands: build, orphans, query, path, stats, validate.

### Creators to Follow
See `memory/reference_ontology-kg-creators.md`: Lindenberg, Seale, Jorgenson, Vanderseypen, Kamau, Zaveckas.

## 12. Full Interaction Map

How ontology, ruflo, memory, knowledge base, and the auto-learning loop interact:

```
LOAD (skill start)
  ├── ruflo memory_search(namespace: "all") → top 5 by similarity
  ├── spec-graph.json → follow typed edges (depends_on, informs)
  ├── MEMORY.md → already in context (core memory)
  └── Stale check: frontmatter staleness → warn user
       ▼
WORK (skill executes with enriched context)
       ▼
EXTRACT (skill end)
  └── Ontology entity types = vocabulary for classification
      "Is this a Pattern? ADR? FieldNote? Assumption?"
       ▼
EVALUATE (tiered)
  ├── ruflo memory_search → novelty check (dedup)
  ├── Ontology axioms → contradicts? supersedes? transferable?
  └── Tier: SMALL (auto) / MEDIUM (inline) / LARGE (challenger)
       ▼
PERSIST (route by type)
  ├── Pattern → ruflo memory_store(namespace: pattern) + memory/ file
  ├── FieldNote → append to dimension doc + ruflo(namespace: field-notes)
  ├── ADR → docs/architecture/decisions/ADR-NNN.md
  ├── Dimension update → brana-knowledge/dimensions/
  ├── Tags/URLs/context → auto (SMALL, no prompt)
  │
  ALSO:
  ├── Write frontmatter relationships (produced_by, applies_to, etc.)
  ├── ruflo memory_store → indexed with embedding for future LOAD
  └── Post-commit hook → spec-graph recomputes → new edges appear
       ▼
(weekly)
DECAY
  ├── Stale dimensions → spec-graph orphans + ruflo access tracking
  ├── Event log bloat → archive with digest
  ├── Ruflo noise → soft decay (lower ranking) → hard decay (180d, prompted)
  └── Graph health → orphan nodes, contradiction checks, supersession chains
```

### Data Flow

```
Component           WRITES TO              READS FROM
─────────           ────────               ──────────
Markdown files  ◄── PERSIST (findings)  ──► LOAD (Read tool)
Frontmatter     ◄── PERSIST (relations) ──► spec-graph builder
spec-graph.json ◄── post-commit hook    ──► LOAD, MAINTAIN, DECAY
ruflo           ◄── PERSIST, DECAY      ──► LOAD, EVALUATE, EXTRACT
brana-ontology  ◄── rarely changed      ──► EXTRACT, EVALUATE, PERSIST
MEMORY.md       ◄── /close, manual      ──► always in context (CC)
decay-tracker   ◄── LOAD (bump access)  ──► DECAY (identify stale)
```

**In one sentence:** The ontology defines the vocabulary, ruflo provides the search, frontmatter stores the relationships, spec-graph computes the full picture, the auto-learning loop keeps it all flowing, and DECAY prevents drowning in accumulation.

## Supersedes

This operating model consolidates and supersedes the following earlier idea docs:

| Superseded doc | Covered by section |
|---------------|-------------------|
| `agent-observability-learning.md` | Auto-learning loop (EXTRACT step) |
| `dynamic-skill-routing.md` | Smart Router (section 5) |
| `skill-auto-router.md` | Smart Router (section 5) |
| `enforcement-vs-injection.md` | Documentation Discipline (section 6) |
| `resilient-pattern-store.md` | Memory Hierarchy (section 3) + MCP-first ruflo |
| `session-aware-loop-integration.md` | Auto-learning loop embedded in all thinking-skills |

Note: `ruflo-native-integration.md` remains active — it covers ruflo controller details and upstream issues beyond the operating model's scope.

## Related

- Ontology: `docs/brana-ontology.yaml`
- Patterns: `brana-knowledge/dimensions/49-auto-learning-patterns.md`
- Complexity audit: `memory/feedback_complexity-audit.md`
- Lifecycle spec: `docs/reflections/32-lifecycle.md`
- Current architecture: `docs/reflections/14-mastermind-architecture.md`
