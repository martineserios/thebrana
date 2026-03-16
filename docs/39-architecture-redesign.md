# 39 — Architecture Redesign: Unified Repo + Knowledge System

> First draft design document. Describes the full architectural change from three-repo separation to unified system with active knowledge base. Decisions must be justified. ADRs will be created during implementation.

**Status:** Accepted (ADR-006) — spike passed, versions corrected, ADR written (2026-02-25)
**Backlog items addressed:** #39 (repo architecture), #82 (multi-project workflow), #60 (planning redesign), #64 (system documentation), #57 (portable artifacts)
**Related docs:** 14 (architecture), 09 (Claude Code features), 19 (PM system design), 00 (user practices)

---

## 1. Executive Summary

Three changes, one redesign:

1. **Merge enter into thebrana** — the architect repo becomes a `docs/` directory inside the operator repo. One repo, one backlog, one task system. The cognitive separation between "design" and "build" is preserved by directory structure and branch conventions, not by repo boundaries.

2. **Evolve brana-knowledge into an active knowledge base** — from a backup vault to the personal knowledge system. Dimension docs for any topic, reflection docs for cross-cutting synthesis, design thinking techniques for creative expansion. The Second Brain's "Resources" layer, powered by first-principles analysis.

3. **Wire retrieval into brana** — AgentDB/claude-flow indexes the knowledge base for semantic search. Any project session can query digested knowledge. The knowledge feeds both project work and brana self-improvement.

The goal: **work on projects, learn from everything, improve the system continuously, with minimal friction between these activities.**

---

## 2. Current Architecture

### 2.1 Three Repos, Three Roles

```
~/enter_thebrana/
├── enter/              ← Architect: specs, research, plans (git repo)
├── thebrana/           ← Operator: system/, deploy.sh → ~/.claude/ (git repo)
├── brana-knowledge/    ← Vault: backup exports (git repo)
├── projects/           ← Ventures: psilea, palco, etc. (separate git repos)
└── personal/           ← Life OS: tasks, journal (git repo)
```

### 2.2 How Knowledge Flows Today

```
Enter (specs) ──/build-phase──→ Thebrana (system/) ──deploy.sh──→ ~/.claude/
     ↑                                  │
     └──────/back-propagate─────────────┘
     ↑                                  │
     └──────/reconcile──────────────────┘

Projects use deployed brana (~/.claude/) via /build-feature, /debrief, etc.
Learnings flow back via /brana:retrospective → ruflo memory → future sessions.
```

### 2.3 Three Task Management Layers

| Layer | Location | Scope |
|-------|----------|-------|
| Brana ideas | `enter/30-backlog.md` | Architecture, research, design (82 items) |
| Brana operations | `thebrana/.claude/tasks.json` | Implementation + project management (38 tasks) |
| Project work | `projects/X/.claude/tasks.json` | Venture/code tasks (per project) |

### 2.4 Knowledge System (Current)

| What | Where | Scope |
|------|-------|-------|
| Development patterns | `~/.swarm/memory.db` (ruflo) | Engineering solutions, corrections |
| Per-project memory | `~/.claude/projects/*/memory/` | Project-specific facts, session handoffs |
| Brana specs | `enter/*.md` (38 docs) | Brana architecture research |
| Research sources | `enter/research-sources.yaml` | Tracked external sources |
| Backups | `brana-knowledge/` | Exports of all the above |

**Gap:** No system for general knowledge (business strategy, technology research, methodology, domain expertise). All knowledge is scoped to development patterns or brana specs.

---

## 3. Problems With Current Architecture

### 3.1 The Feedback Loop Is Too Long

Discovery → fix → deploy currently requires **4 context switches:**

1. Project session → discover brana gap
2. Enter session → create backlog item, research, design
3. Thebrana session → implement the fix
4. Deploy → project benefits

Each switch means: new terminal, new CWD, new Claude Code session, lost context. The overhead is disproportionate for small fixes (tweak a skill description, add a rule, fix a hook instruction).

### 3.2 Enter Trails Implementation

Enter was designed to lead ("design first, build second"). In practice, it trails. The evidence:

- `/back-propagate` exists because implementation diverges from specs
- `/brana:reconcile` exists because specs diverge from implementation
- Neither side is the authoritative leader — they chase each other
- Phase 4 succeeded not because specs were in a separate repo, but because specs were **detailed** (file paths, pseudocode, exit criteria)

The quality of specs matters. The repo boundary doesn't contribute to that quality.

### 3.3 Two Backlogs Create Management Overhead

- Enter backlog: 82 items (ideas, research, design)
- Thebrana tasks: 38 items (implementation, project management)
- Promoting an idea from enter backlog to thebrana task requires manual coordination across repos
- No unified view of "what should brana do next?" without consulting two separate files

### 3.4 Cross-Repo Operations Are Overhead

| Operation | What it does | Overhead |
|-----------|-------------|----------|
| `/back-propagate` | Creates worktree in enter, edits specs | Separate git repo, branch, merge cycle |
| `/brana:reconcile` | Reads enter, writes thebrana | Cross-repo reads, separate commits |
| `/brana:maintain-specs` | Internal to enter | Fine, but triggers reconcile (cross-repo) |

These operations are valuable — the sync discipline is real. But the cross-repo boundary doesn't add value; it adds plumbing.

### 3.5 No General Knowledge System

Brana captures development patterns (ruflo memory) and brana-specific research (enter dimension docs). There is no home for:

- Business domain knowledge (psilocybin science, eye detection technology, real estate markets)
- Methodology knowledge (sales processes, customer discovery, financial modeling)
- Technology knowledge (Rust patterns, WhatsApp API behavior, CRM integrations)
- Cross-domain insights (how psilocybin science informs customer onboarding design)

This knowledge exists in the operator's head and in scattered project docs, but is not persisted, indexed, or retrievable by brana.

---

## 4. Proposed Architecture

### 4.1 Overview

```
~/enter_thebrana/
├── thebrana/                      ← unified repo (enter merged)
│   ├── docs/                      ← current enter content
│   │   ├── 01-38 + 39 *.md       ← dimension/reflection/roadmap docs
│   │   ├── decisions/             ← ADRs
│   │   ├── features/              ← feature briefs
│   │   └── backlog.md             ← unified brana backlog
│   ├── system/                    ← deployed brain (→ ~/.claude/)
│   │   ├── skills/
│   │   ├── hooks/
│   │   ├── rules/
│   │   ├── agents/
│   │   ├── commands/
│   │   └── scripts/
│   ├── .claude/
│   │   ├── CLAUDE.md              ← unified identity
│   │   ├── tasks.json             ← unified operational tasks
│   │   └── rules/
│   ├── .mcp.json                  ← unified (includes ruflo)
│   ├── deploy.sh
│   └── validate.sh
│
├── brana-knowledge/               ← evolved: active knowledge base
│   ├── dimensions/                ← deep dives on ANY topic
│   ├── reflections/               ← cross-cutting synthesis
│   ├── sources.yaml               ← research source registry
│   ├── backup/                    ← current backup content (relocated)
│   └── index/                     ← generated embeddings/graph data
│
├── projects/                      ← unchanged: separate git repos
│   ├── psilea/
│   ├── palco/
│   ├── tinyhomes/
│   └── ...
└── personal/                      ← unchanged: life OS
```

### 4.2 Three Concerns, Three Homes

| Concern | Home | Why |
|---------|------|-----|
| **Brana system** (skills, hooks, rules, agents, specs, backlog) | `thebrana/` | One repo = one feedback loop. Design and build in the same place. |
| **General knowledge** (topics, research, synthesis, sources) | `brana-knowledge/` | Independent, portable, growing. Not coupled to brana's system code. |
| **Project work** (ventures, code, tasks) | `projects/X/` | Independent, portable. Uses deployed brana via `~/.claude/`. |

### 4.3 How Knowledge Flows (New)

```
                    thebrana/ (unified)
                    ┌─────────────────┐
                    │  docs/  ←→  system/  │
                    │  (specs)    (impl)    │
                    │     ↕                 │
                    │  backlog → tasks      │
                    └────────┬────────┘
                             │ deploy.sh
                             ↓
                         ~/.claude/  (deployed brain)
                             │
              ┌──────────────┼──────────────┐
              ↓              ↓              ↓
         projects/      brana-knowledge/  personal/
         psilea/        dimensions/       tasks.md
         palco/         reflections/      life.md
         ...            sources.yaml
              │              ↑
              │    /brana:research  │  /brana:retrospective (transferable)
              └──────────────┘
                  learnings feed knowledge base
```

---

## 5. Decision 1: Merge Enter Into Thebrana

### 5.1 What Moves Where

| Current location | New location |
|-----------------|-------------|
| `enter/*.md` (38 docs) | `thebrana/docs/*.md` |
| `enter/30-backlog.md` | `thebrana/docs/backlog.md` |
| `enter/research-sources.yaml` | `thebrana/docs/research-sources.yaml` |
| `enter/docs/decisions/` | `thebrana/docs/decisions/` |
| `enter/docs/features/` | `thebrana/docs/features/` |
| `enter/CLAUDE.md` | Merged into `thebrana/.claude/CLAUDE.md` |
| `enter/.claude/commands/` | Merged into `thebrana/system/commands/` |
| `enter/.mcp.json` | Merged into `thebrana/.mcp.json` |

### 5.2 Justification

**The cognitive separation is preserved by directory structure, not repo boundary.**

- `docs/` is the thinking space. Pre-commit hooks can enforce "no `system/` edits on `docs/*` branches" if needed.
- `system/` is the building space.
- Branch conventions signal intent: `docs/*` branches for spec work, `feat/*` for implementation.

**Cross-repo operations become same-repo operations.**

| Operation | Before | After |
|-----------|--------|-------|
| `/back-propagate` | Creates worktree in enter repo | Edits `docs/` in same repo, same or parallel branch |
| `/brana:reconcile` | Reads enter, writes thebrana | Reads `docs/`, writes `system/` — same repo |
| `/brana:maintain-specs` | Internal to enter | Internal to `docs/` — unchanged |
| `/build-phase` | Reads enter roadmap, builds in thebrana | Reads `docs/` roadmap, builds in `system/` — same repo |

**One backlog, one task system.**

- `docs/backlog.md` replaces enter's `30-backlog.md` — all brana ideas in one place
- `.claude/tasks.json` is the single operational task tracker
- Promoting backlog → task is a same-repo operation (no context switch)

**Phase 4 quality is about spec detail, not repo separation.**

The MEMORY.md note proves this: "Phase 4 had the most detailed WIs — file paths, logic pseudocode, template content, exit criteria. Implementation was near-1:1 with zero rework." The detail was in the docs, not in the repo boundary. Detailed docs in `thebrana/docs/` will produce the same quality.

### 5.3 Unified CLAUDE.md

The merged CLAUDE.md combines architect + operator identities:

```markdown
# thebrana — The Brain

Part of enter_thebrana. This repo IS the brana system: specs, architecture
decisions, research (docs/) AND implementation, deployment, maintenance (system/).

## Two Workspaces

- docs/   — Think here. Specs, research, reflections, roadmap. No code.
- system/ — Build here. Skills, hooks, rules, agents. Deploys to ~/.claude/.

## Architect Commands (docs/ workspace)
/brana:maintain-specs, /back-propagate, /brana:reconcile, /refresh-knowledge, /brana:challenge, /decide

## Operator Commands (system/ workspace)
/build-phase, /build-feature, /deploy, /validate

## Shared Commands
/debrief, /brana:retrospective, /session-handoff, /brana:backlog
```

Root CLAUDE.md covers both roles. If needed, a nested `docs/CLAUDE.md` can add architect-specific context that loads when Claude touches files in `docs/` (Claude Code's lazy subdirectory loading).

### 5.4 External Validation

**Composio agent-orchestrator (#457):** 30 parallel agents + orchestrator built 40K lines of TypeScript in 8 days. Architecture uses a Planner/Executor split (mirrors enter/thebrana), but keeps them in one system. The "agents improving the agent system" pattern validates brana's self-improvement loop, and the single-repo choice supports the merge decision.

**Boris Tane annotation cycle (#462):** The Claude Code creator uses research.md → plan.md → implementation in a single project. No formal memory system, no repo separation between design and build. The annotation cycle (plan.md as shared mutable state, 1-6 review rounds) works because specs and code are in the same context. Validates that colocation doesn't weaken spec quality — it enables tighter review loops.

**Julian Cislo cone-vs-cylinder (#466):** Argues that constraints, not supervision, prevent AI-driven codebases from degrading. The repo boundary was a constraint — but branch conventions (`docs/*` vs `feat/*`) and pre-commit hooks provide the same architectural governance within a single repo. Cislo's "designing rules and testing pipelines around the AI" IS brana's rules/ + hooks/ system.

### 5.5 What Happens to Enter Repo

After migration:
1. Enter becomes a read-only archive with a README pointing to `thebrana/docs/`
2. Git history is preserved via subtree merge (or simple copy + fresh start — history is in GitHub anyway)
3. Enter repo is not deleted — it becomes frozen reference

### 5.6 Impact on CWD-as-Role Model (#82)

| Working on... | CWD | What loads |
|---------------|-----|------------|
| Brana (specs or implementation) | `thebrana/` | Unified CLAUDE.md, ruflo MCP, full system |
| Psilea | `projects/psilea/` | Psilea CLAUDE.md, deployed brana via ~/.claude/ |
| Palco | `projects/palco/` | Palco CLAUDE.md, deployed brana via ~/.claude/ |

The model simplifies: brana work = one CWD (thebrana). Project work = project CWD. No more choosing between enter and thebrana.

---

## 6. Decision 2: Evolve brana-knowledge Into Active Knowledge Base

### 6.1 Current State

brana-knowledge is a backup vault:
```
brana-knowledge/
├── memory/        ← auto-memory snapshots
├── projects/      ← per-project MEMORY.md exports
├── swarm/         ← ruflo memory exports
├── backup.sh
└── restore.sh
```

It stores exports of brana's development knowledge. It is passive — never read during active work, only used for backup/restore.

### 6.2 Proposed Evolution

brana-knowledge becomes an active knowledge base — the personal "Resources" layer (Tiago Forte's PARA), but processed through first-principles analysis rather than raw collection.

```
brana-knowledge/
├── dimensions/                ← deep dives on any topic
│   ├── psilocybin-science.md
│   ├── rust-patterns.md
│   ├── customer-retention.md
│   ├── whatsapp-api.md
│   ├── financial-modeling.md
│   ├── eye-detection-tech.md
│   └── ...
├── reflections/               ← cross-cutting synthesis
│   ├── venture-patterns.md    ← patterns across all ventures
│   ├── automation-stack.md    ← CRM + WhatsApp + scheduling insights
│   ├── first-principles.md   ← methodology connections
│   └── ...
├── sources.yaml               ← research source registry (all domains)
├── backup/                    ← current backup content (relocated)
│   ├── memory/
│   ├── projects/
│   └── swarm/
├── index/                     ← generated (not hand-authored)
│   ├── embeddings.db          ← vector index of all dimensions
│   └── graph.db               ← concept relationship graph
├── CLAUDE.md                  ← knowledge base identity and conventions
└── backup.sh, restore.sh     ← preserved
```

### 6.3 Justification

**Knowledge should be independent of the system that uses it.**

brana-knowledge dimension docs are valuable even without brana installed. A `psilocybin-science.md` dimension doc contains digested, opinionated analysis — useful in any context. Coupling this to thebrana's system code would make knowledge non-portable.

**Knowledge grows differently than system code.**

System code (skills, hooks, rules) changes in discrete releases via deploy.sh. Knowledge grows continuously — every research session, every project experience, every article read. Different git rhythms, different commit patterns.

**The "collector's fallacy" is addressed by the dimension doc pattern.**

[Doc 19](19-pm-system-design.md)'s critique of Second Brain is valid: "capturing aggressively but never processing or using what's captured." The dimension doc pattern forces processing:

1. **Research** — gather sources, read deeply
2. **Analyze** — extract principles, compare frameworks
3. **Synthesize** — write opinionated analysis with decisions and open questions
4. **Connect** — reflection docs bridge across dimensions

This is not bookmarking. It's first-principles knowledge construction.

### 6.4 The Reflection Layer as Creative Engine

Reflection docs in brana-knowledge serve the same function as enter's R1-R5 reflection DAG, but for all knowledge:

- **Cross-domain synthesis:** "What do psilocybin microdosing protocols and software deployment have in common?" (Both are dosing problems — frequency, amount, feedback loops)
- **Pattern transfer:** "The customer retention framework from somos_mirada applies to psilea's reactivation protocol"
- **Challenge assumptions:** "We assumed WhatsApp is the right channel. What if SMS or email converts better for this segment?"

Design thinking techniques (doc 38) enhance this layer:

| Technique | Application in reflections |
|-----------|---------------------------|
| **HMW questions** | "How might we apply the SOP structure from psilea to tinyhomes host onboarding?" |
| **Divergent ideation** | Before writing a reflection, generate 5+ unexpected connections between dimensions |
| **Empathy mapping** | For venture knowledge: model what customers think/feel/do at each stage |

### 6.5 External Validation

**Dulan Perera, Day 52 operating daily in Claude Code (#461):** After 52 consecutive days, Perera reports "every file added makes every session better" — compounding knowledge. His patterns map directly:
- *Context-as-Infrastructure:* structured markdown files in dedicated folders, loaded per task → this IS the dimension doc pattern
- *Codified Workflows as Skills:* tasks done 3+ times become reusable skills → validates brana's skill system
- *Project Scaffolds:* brief → plan → progress → learnings → maps to dimension doc stages (research → analyze → synthesize → connect)
- *Code Execution Over MCPs:* data-heavy ops as executable scripts, not context-consuming MCP calls → supports script-based indexing pipeline (section 7) over MCP-based approaches

**Boris Tane (#462) — research.md as validated pattern:** Tane's research.md → plan.md → implementation mirrors brana-knowledge's dimension → reflection → action flow. His rejection of formal memory ("no CLAUDE.md") works for single-project, single-session work but breaks over 52+ days and multiple domains. Brana-knowledge is necessary for the cross-client, cross-session case. The annotation cycle (plan as shared mutable state with iterative review) is a pattern to add to the `/knowledge` skill — dimension docs should support inline annotation rounds before being finalized.

**Leonardo Tarla, Synthflow AI (#458):** Multi-source knowledge ingestion (PDF, CSV, DOCX, Airtable, Notion, web crawl) → vector store → retrieval-augmented generation. Embeddings route queries to the right data source, then agents call tools. Confirms the two-layer model (section 7.1): human authoring in markdown, machine retrieval via embeddings.

### 6.6 brana-knowledge CLAUDE.md

```markdown
# brana-knowledge — The Knowledge Base

Personal knowledge system. Deep dives on any topic, cross-cutting synthesis,
first-principles analysis. Independent of brana — works without it.

## Structure
- dimensions/  — One doc per topic. Research → analyze → synthesize → decide.
- reflections/ — Cross-cutting. Connect dimensions. Challenge assumptions.
- sources.yaml — Tracked sources with trust tiers and freshness.
- backup/     — System knowledge exports (brana auto-memory, ruflo memory).

## Conventions
- All knowledge base content in English. Projects use their own language.
- Dimension docs follow the same pattern as brana specs: opinionated, concise,
  with explicit decisions and open questions
- Topic-based filenames (customer-retention.md, not 01-customer-retention.md)
- Reflection docs use design thinking: HMW questions, divergent ideation,
  empathy mapping where applicable
- Never store raw bookmarks. Everything is processed through analysis.
```

---

## 7. Decision 3: Retrieval and Storage Backend

### 7.1 The Two-Layer Model

Knowledge has two access patterns:

| Pattern | Need | Solution |
|---------|------|----------|
| **Human authoring** | Write, read, review, version-control | Markdown files in git |
| **Machine retrieval** | "Find knowledge related to X" from any session | Embeddings + graph index |

The authoring layer is markdown files in brana-knowledge (dimension docs, reflections). The retrieval layer is an index built FROM those files, stored in AgentDB/claude-flow.

### 7.2 Technology Stack (verified 2026-02-27)

#### Packages and versions

| Package | Installed | Latest | Role | Status |
|---------|-----------|--------|------|--------|
| **ruflo** | **v3.5.15** | v3.5.15 | Orchestration, MCP, memory + AgentDB | **Active** — upgraded from v3.5.1. 14 patch releases, no breaking changes. |
| **@claude-flow/embeddings** | **alpha.12** | alpha.12 | ONNX embedding generation | Current. Upgraded from alpha.1. |
| **@claude-flow/memory** | — | — | SQLite + AgentDB hybrid backend | **Removed in v3.5.15** — memory ops handled directly by ruflo core. |
| **agentdb** | **3.0.0-alpha.10** | 3.0.0-alpha.10 | Graph DB + Cypher + vector search | **Active** — integrated via ruflo. BM25 hybrid search, reflexion, causal graph, skills. |
| **ruvector** | (dep) | 0.1.100 | Rust vector DB, HNSW, SONA | Hyperactive (100 patches) |
| **@ruvector/rvf** | 0.1.9 | 0.2.0 | Unified vector format SDK | Active, minor version bump |
| **@ruvector/graph-node** | (dep) | 2.0.2 | Native Cypher engine | Active |

All packages by sole maintainer (ruvnet). No cloud dependency — everything runs local.

> **Bridge activation (2026-02-27):** ControllerRegistry shim was originally needed to bridge `memory-bridge.js` → AgentDB v3. **Removed in v3.5.15** — `@claude-flow/memory` package eliminated; ruflo core handles AgentDB directly. BM25 hybrid search confirmed active (provenance: `semantic:X+bm25:Y`).

#### AgentDB v3 three-layer model (from ADR-005)

| Layer | Technology | Knowledge role | Readiness |
|-------|-----------|----------------|-----------|
| **Relational** | better-sqlite3 (via AgentDB) | Metadata: source, author, trust tier, freshness, tags | **Active** — via ruflo memory + AgentDB bridge |
| **Vector** | HNSW (ruvector) + BM25 hybrid | Semantic search + lexical ranking: 0.7 × cosine + 0.3 × BM25 | **Active** — bridge confirmed working (2026-02-27) |
| **Graph** | Cypher engine (@ruvector/graph-node) | Connections: topic A relates to topic B via concept C | **Not ready** — controllers return null. Deferred. |

### 7.3 Spike Results: Embedding Pipeline Validated

**Phase 0.5 spike completed 2026-02-25.** The CLI embedding pipeline works from bare bash — no MCP session needed.

```
$ ruflo embeddings generate --text "customer retention strategies"
  Provider: transformers
  Model: onnx (all-MiniLM-L6-v2)
  Dimensions: 384
  Generation time: 300ms (cached), 2.6s (cold start)

$ ruflo embeddings compare \
    --text1 "customer retention strategies" \
    --text2 "how to keep customers from leaving"
  Similarity: 0.6491 (Moderately similar)    ← correct: related topics

$ ruflo embeddings compare \
    --text1 "customer retention strategies" \
    --text2 "rust memory management patterns"
  Similarity: 0.2327 (Dissimilar)            ← correct: unrelated topics
```

**Key findings:**

| Claim in earlier draft | Reality | Impact |
|----------------------|---------|--------|
| "3ms per embedding" | **~300ms cached, ~2.6s cold start** | 10 docs = ~3s in post-commit hook. Acceptable but not invisible. |
| Embeddings work without MCP | **Confirmed** | Post-commit hook design is valid. |
| No extra dependency needed | **`@claude-flow/embeddings` required** | Not installed by default. Must be in deploy.sh. Without it, silently degrades to 128-dim hash fallback (useless). |
| all-MiniLM-L6-v2, 384 dims | **Confirmed** | Standard sentence-transformer model, good quality for knowledge base scale. |

**Gotcha:** Without `@claude-flow/embeddings` installed, the CLI silently falls back to `hash-fallback` (128-dim deterministic hash). This produces 1.0 for identical text and garbage for everything else. Always check model output says `onnx`, not `hash-fallback`.

### 7.4 Indexing Pipeline (updated with spike data)

```
brana-knowledge/dimensions/*.md
brana-knowledge/reflections/*.md
         │
         ↓  (on-commit hook + weekly scheduled reindex)
    Parse markdown → extract sections by ## headers
         │
         ↓
    Generate embeddings per section
    (ruflo CLI, ~300ms/section cached, all-MiniLM-L6-v2, 384-dim)
         │
         ↓
    Store in ruflo memory (SQLite):
      - Metadata: source file, section, topic, freshness, tags
      - Vector: embeddings for semantic search
         │
         ↓
    Available via ruflo MCP from any session
    (memory-curator agent queries index)
```

**The pipeline is ~100 lines of bash** built on proven primitives. Not a product to install — a script to write.

### 7.5 Active Strategy + Fallback (updated 2026-02-27)

AgentDB is now the active backend via ruflo v3.5.15. SQLite-only is the fallback. ControllerRegistry shim no longer needed (@claude-flow/memory removed in v3.5.15).

| Layer | Active (via AgentDB bridge) | Fallback (if bridge fails) |
|-------|----------------------------|---------------------------|
| **Embeddings** | ONNX local (all-MiniLM-L6-v2, 384-dim) | Same |
| **Storage** | AgentDB (better-sqlite3 + HNSW) | sql.js raw `memory_entries` table |
| **Search** | BM25 hybrid (semantic + lexical, provenance tracking) | Basic cosine similarity via `memory search` |
| **Graph** | Markdown cross-references in reflection docs | Same — Cypher controllers return null, deferred |

The bridge delivers ~90% of AgentDB's value. Remaining gaps: graph layer (Cypher queries), reasoningBank/mutationGuard/attestationLog controllers return null — likely need schema or initialization work in AgentDB v3.

### 7.6 Ecosystem Assessment

The ruvnet ecosystem provides infrastructure, not a product. What exists:
- **Vector search:** ruvector (0.1.100) — HNSW, SONA Learning, sub-ms queries. Hyperactive development.
- **Embeddings:** @claude-flow/embeddings (alpha.12) — ONNX local, transformers.js. Works.
- **Graph:** @ruvector/graph-node (2.0.2) — native Cypher, 10x faster than WASM. Exists.
- **Integration:** agentdb (alpha.3.3) — supposed to unify all three layers. **Stalled.**

What we build on top (~100 lines of bash):
- Markdown parser: extract sections by `##` headers
- Chunk-to-embedding pipeline: call `ruflo embeddings generate` per section
- Storage writer: call `ruflo memory store` with embeddings + metadata
- Post-commit hook + scheduler integration

The ecosystem points in our direction (local-first, vector search, graph relationships). The orchestration layer is ours to write.

---

## 8. Impact on Existing Skills and Workflows

### 8.1 Skills That Change

| Skill | Current behavior | New behavior |
|-------|-----------------|-------------|
| `/build-phase` | Reads `~/enter_thebrana/enter/18-*.md` | Reads `./docs/18-*.md` (relative path) |
| `/back-propagate` | Creates worktree in enter repo, edits specs | Edits `docs/` in same repo (same branch or parallel branch) |
| `/brana:reconcile` | Reads enter, writes thebrana (cross-repo) | Reads `docs/`, writes `system/` (same repo) |
| `/brana:maintain-specs` | Internal to enter repo | Internal to `docs/` directory (unchanged logic) |
| `/brana:research` | Reads `enter/research-sources.yaml` | Reads `./docs/research-sources.yaml` AND `brana-knowledge/sources.yaml` |
| `/debrief` | Falls back to `enter/24-roadmap-corrections.md` | Falls back to `./docs/24-roadmap-corrections.md` |
| `/session-handoff` | CWD-based memory routing | Unchanged — CWD=thebrana for brana work, CWD=project for project work |
| `/brana:retrospective` | Stores in ruflo memory | Additionally: if pattern is transferable AND domain-relevant, suggest writing a brana-knowledge dimension doc |
| `/build-feature` | Unaffected (works from project CWD) | Unaffected. Gains access to knowledge base via memory-curator agent querying indexed brana-knowledge |

### 8.2 New Skills Needed

| Skill | Purpose |
|-------|---------|
| `/knowledge` | Manage brana-knowledge: add dimension doc, write reflection, search knowledge, check freshness. Supports annotation cycle (#462): dimension docs go through iterative review rounds (draft → inline notes → update → finalize) before being considered stable. |
| `/index` or scheduled job | Rebuild embeddings/graph index from brana-knowledge markdown files. Prefer script-based indexing over MCP-based (#461: "data-heavy ops as executable scripts, not context-consuming MCP calls"). |

### 8.3 Workflow Changes

**Before (brana improvement from project work):**
1. Working on psilea → notice brana gap
2. Switch to enter → create backlog item, research
3. Switch to thebrana → implement fix
4. Run deploy.sh → psilea benefits next session

**After:**
1. Working on psilea → notice brana gap
2. Switch to thebrana → create backlog item in `docs/backlog.md`, implement fix in `system/`, run deploy.sh
3. Psilea benefits next session

Two steps eliminated. One context switch instead of three.

**Before (capturing general knowledge):**
1. Read an article about customer retention
2. No system to persist the analysis
3. Knowledge exists only in human memory

**After:**
1. Read an article about customer retention
2. Switch to brana-knowledge → `/brana:research customer-retention` → write/update `dimensions/customer-retention.md`
3. Knowledge is indexed, searchable by brana from any project session
4. Next time psilea needs retention strategy, memory-curator finds the dimension doc

---

## 9. Migration Plan (High Level)

### Phase 0: Preparation — COMPLETED (2026-02-25)
- [x] Create ADR in enter: "ADR-006: Merge enter into thebrana" (also deferred ADR-005)
- [ ] Backup enter repo state (git bundle or tag `pre-merge`)
- [ ] Inventory all cross-repo path references in skills, hooks, commands (challenger found 30 refs across 11 files — see section 14)

### Phase 0.5: Embedding Spike — COMPLETED (2026-02-25)

- [x] CLI command exists: `ruflo embeddings generate --text "..."`
- [x] Model: all-MiniLM-L6-v2 via ONNX, 384 dimensions, ~300ms cached
- [x] Works without MCP session — pure CLI, bash-hook compatible
- [x] Semantic accuracy verified: 0.65 (related) vs 0.23 (unrelated)
- [x] `@claude-flow/embeddings` upgraded to alpha.12 (was alpha.1, silent hash-fallback)
- [x] **deploy.sh must install @claude-flow/embeddings** — without it, degrades to useless hash

**Result: PASS.** Indexing pipeline design is valid. See section 7.3 for full results.

### Phase 1: Merge Enter → Thebrana (1 focused session)

File moves, path updates, config merges, validate cycle. Pure structural migration.

- [ ] Create `thebrana/docs/` directory
- [ ] Copy enter content to `thebrana/docs/` (preserving structure)
- [ ] Merge CLAUDE.md files (architect + operator → unified)
- [ ] Merge `.mcp.json` (add ruflo to thebrana)
- [ ] Merge `.claude/commands/` (enter commands → thebrana)
- [ ] Update all skill path references (`~/enter_thebrana/enter/` → `./docs/` or relative) — 30 refs across 11 files
- [ ] Update pre-commit hooks for unified repo
- [ ] Update validate.sh for unified structure
- [ ] Migrate enter's auto-memory → thebrana's auto-memory (careful diff, not 15-minute rush — see Q5 and section 14)
- [ ] Run full deploy.sh + validate cycle
- [ ] Update [doc 14](reflections/14-mastermind-architecture.md) (architecture), [doc 25](25-self-documentation.md) (self-documentation), [doc 00](00-user-practices.md) (user practices)
- [ ] Archive enter repo (read-only, README pointer)

### Phase 2: Skill Logic Rewrites (follows Phase 1, may extend 1-2 days)

Separated from Phase 1 because these are logic rewrites, not path substitutions. `/back-propagate` and `/brana:reconcile` have multi-step git workflows designed around two-repo operations that need fundamental rethinking.

- [x] Rewrite `/back-propagate` for same-repo operation — now: same-repo `docs/` + cross-repo `brana-knowledge/dimensions/` pattern
- [x] Rewrite `/brana:reconcile` for same-repo operation — now: intra-repo `docs/` → `system/` with optional brana-knowledge scan
- [x] Update `/build-phase` path references — single worktree branch, no two-repo merge dance
- [x] Remove cross-repo worktree logic where no longer needed — also fixed stale refs in research, personal-check, commands, skill-catalog, [doc 14](reflections/14-mastermind-architecture.md)
- [x] Run deploy.sh + validate cycle — passed (also added missing YAML frontmatter to 5 project commands)
- [x] ~~Degraded mode acceptable~~ — not needed, full rewrites completed in one session

### Phase 3: Wire Retrieval Prototype (1 session — BEFORE writing dimension docs)

Validate the full loop before investing in content. Write 1-2 dimension docs AND the indexing pipeline in the same session. If retrieval doesn't work, knowledge base is just another file graveyard.

- [x] Seed dimension docs — 26 docs already in place from Phase 1 redistribution (enter dimension docs → brana-knowledge/dimensions/)
- [x] Indexing pipeline — `system/scripts/index-knowledge.sh`: parses by ## sections, stores in ruflo memory with 384-dim ONNX embeddings. 26 docs → 317 sections → 315 stored (2 encoding errors in [doc 09](dimensions/09-claude-code-native-features.md))
- [x] Memory-curator agent updated — searches knowledge namespace, surfaces dimension doc findings alongside patterns
- [x] **End-to-end test PASSED:** "git worktree workflow" → [doc 26](dimensions/26-git-branching-strategies.md) at 0.63, "testing claude code hooks" → [doc 09](dimensions/09-claude-code-native-features.md) at 0.59, "design thinking" → [doc 38](dimensions/38-design-thinking.md) at 0.53. Cross-doc discrimination works.
- [x] Test passes — retrieval validated, proceed to Phase 4
- [x] On-commit hook — brana-knowledge post-commit runs `index-knowledge.sh --changed` in background
- [x] Weekly full reindex — scheduler template updated (Sunday 3am)
- [x] AgentDB backend activated (2026-02-27) — ruflo v3.5.1 + ControllerRegistry shim. BM25 hybrid search, reflexion, causal graph, skills controllers active. Graph layer deferred (controllers return null).

### Phase 4: Evolve brana-knowledge (ongoing, after retrieval is validated)

Now that the full loop works (write doc → index → retrieve from project session), scale the content.

- [x] Restructure brana-knowledge: add `dimensions/`, `reflections/`, relocate backup content to `backup/` (existing `projects/` and `memory/` dirs → `backup/`)
- [x] Write brana-knowledge CLAUDE.md (English default, topic-based filenames)
- [x] Create auto-generated `dimensions/INDEX.md` script (from YAML frontmatter)
- [x] Update `/brana:research` skill to write general knowledge to brana-knowledge
- [x] Create `/knowledge` skill (with annotation cycle support and `--reindex` flag)
- [x] Create first batch of dimension docs from existing project knowledge (meta-whatsapp-template-classification.md promoted)
- [ ] Growing organically: every `/brana:research` session, every transferable `/brana:retrospective` pattern feeds the knowledge base

---

## 10. Risks and Mitigations

| Risk | Impact | Mitigation |
|------|--------|------------|
| **Git history loss on merge** | Can't `git log --follow` across repo boundary | Accept imperfect history. Tag enter's final state. README documents the merge date. |
| **CLAUDE.md role confusion** | Unified CLAUDE.md serves two roles, instructions may conflict | Use nested `docs/CLAUDE.md` for architect-specific context (lazy loading). Root CLAUDE.md covers shared identity. |
| **Spec discipline weakens** | Without repo boundary, easier to skip spec updates | Pre-commit hook: `feat/*` branches touching `system/` must also touch `docs/` (or explicitly skip with reason). **Tripwire:** if 3 consecutive `feat/*` branches skip `docs/` updates, make the hook mandatory. The repo boundary was a hard constraint; the hook is a soft one — monitor it. |
| **brana-knowledge becomes a graveyard** | Collector's fallacy: docs written but never used | Freshness tracking in sources.yaml. Scheduled `/knowledge review` checks staleness. Quality pipelines that detect and correct knowledge drift (#466). **Critical gate:** retrieval must be validated (Phase 3) BEFORE scaling content (Phase 4). Without retrieval, no one asks for the knowledge. Write 1-2 seed docs + test the full loop before investing in content. |
| **New cross-repo friction (thebrana↔brana-knowledge)** | `/brana:research` reads from brana-knowledge, `/brana:retrospective` writes to it — bidirectional cross-repo ops | Accepted trade-off. brana-knowledge is a library (no backlog, no tasks), not an active project. Cross-repo reads to a library are lower friction than cross-repo syncs between two active clients. |
| **Embedding CLI assumption untested** | Indexing pipeline design assumes `ruflo` CLI generates embeddings without MCP session — never verified | Phase 0.5 spike (10 min) validates or invalidates. If CLI doesn't exist, redesign around Python sentence-transformers or MCP-session-based approach. |
| **Skill rewrites underestimated** | `/back-propagate` and `/brana:reconcile` need logic rewrites, not just path substitution (30 refs across 11 files) | Phase 2 separated from Phase 1. Degraded mode acceptable for a few days while logic is reworked. |
| **AgentDB doesn't mature** | Kill date passes, no graph/vector backend | Fallback to ruflo memory + CLI embeddings. Markdown files are always the source of truth regardless. |
| **Knowledge base grows unbounded** | Too many dimension docs, retrieval quality drops | Follow enter's pattern: 30-50 docs is fine flat. Reflections synthesize and reduce. Archive stale docs. |
| **Migration breaks deployed brana** | Path references wrong after merge, deploy.sh produces broken ~/.claude/ | Migration Phase 1 ends with full deploy + validate cycle. Test in parallel before cutting over. |

---

## 11. Resolved Questions

All questions resolved as of 2026-02-25.

### Q1. Naming convention → Topic-based filenames, flat start

**Decision:** Topic-based filenames (`customer-retention.md`), not numbered.

**Organization strategy — grow into structure:**
- **0-30 docs:** Flat `dimensions/customer-retention.md`. Every doc visible in one `ls`.
- **30-50 docs:** If clusters emerge (5+ business docs, 5+ tech docs), add subfolders (`dimensions/business/`, `dimensions/tech/`).
- **Index:** Auto-generated `dimensions/INDEX.md` from YAML frontmatter in each doc (topic, tags, created, last-updated). A script rebuilds it — same pattern as the embedding index.

Rationale: enter started flat (01-39) and it works at 39 docs. Premature subfolders create wrong taxonomies that need restructuring later. Topic names are self-describing and work with semantic search (machine doesn't need numbers to find `customer-retention.md`).

### Q2. Language convention → English default

**Decision:** Knowledge base in English. Projects use whatever language they need.

Brana specs, knowledge dimensions, and reflections are all in English. Project-facing content (psilea SOPs, palco templates) uses the project's language. This keeps the knowledge base searchable with a single language model and consistent with brana's existing convention.

### Q3. Indexing pipeline trigger → On-commit hook + scheduled safety net

**Decision:** Two-layer trigger — incremental on-commit hook (primary) + weekly scheduled full reindex (safety net).

**On-commit hook (primary):**
- Runs a lightweight bash script, not MCP (per #461: "data-heavy ops as executable scripts, not context-consuming MCP calls")
- **Incremental:** only re-indexes files changed in the commit (`git diff --name-only HEAD~1` → filter `dimensions/` and `reflections/`)
- At ~300ms per embedding (spike-verified), 10 changed docs = ~3s. Noticeable but acceptable for a post-commit hook.
- Falls back gracefully if ruflo binary or @claude-flow/embeddings is missing (skips indexing, logs warning). **Must check for `hash-fallback` model** — if present, embeddings are useless.

**Scheduled job (safety net):**
- Full reindex weekly via brana-scheduler (already deployed)
- Catches edge cases: manual file edits, git operations that bypass hooks, corrupted index
- Runs in background, no interactive session needed

**No separate `/index` skill.** Instead, add a `--reindex` flag to the `/knowledge` skill for the rare force-rebuild case. One fewer skill to remember.

### Q4. Cross-repo references → Acceptable

**Decision:** Yes, reflections in brana-knowledge may link to brana specs in `thebrana/docs/`.

Knowledge→system is a different relationship than specs→implementation. The enter→thebrana merge eliminates the *bidirectional sync* problem (specs chasing implementation and vice versa). Knowledge referencing specs is a one-directional read — no sync overhead, no reconcile needed. If a spec changes, the knowledge reference is still valid (it points to the topic, not a specific version).

### Q5. Auto-memory migration → One-time manual merge during Phase 1

**Decision:** Manually merge enter's MEMORY.md into thebrana's MEMORY.md during Phase 1.

**Why not "let it accumulate naturally":**
- Enter's MEMORY.md contains months of battle-tested patterns (materiality filtering alone saves hours of agent over-reporting)
- Natural accumulation means re-discovering these patterns through failures — the painful way
- A careful merge during Phase 1 preserves all of it

**Challenger note:** This is not a 15-minute task. Do it with a side-by-side diff. Patterns referencing doc numbers or file structures may need adaptation for the new layout. Revisit 2 weeks after migration to catch anything missed.

**Process (added to Phase 1 checklist):**
1. Read enter's `~/.claude/projects/-...-enter/memory/MEMORY.md`
2. Discard structural entries (paths, doc ranges — these change after merge)
3. Merge transferable patterns into thebrana's `~/.claude/projects/-...-thebrana/memory/MEMORY.md`
4. Leave enter's MEMORY.md on disk (frozen, not deleted — in case something was missed)

**What transfers:** roadmap precision pattern, materiality filtering, ruflo v3 gotchas, agent-skill symbiosis, context overflow prevention, bulk triage patterns, scheduler details, CLAUDE.md vs MEMORY.md framework.
**What gets discarded:** project structure paths (change after merge), doc ranges (absorbed), cross-repo references (eliminated).

### Q6. Timeline → Spike first, merge, validate retrieval, then scale content

**Decision (revised after challenge review):**

| Phase | When | Duration | Notes |
|-------|------|----------|-------|
| **Phase 0.5** (embedding spike) | Before anything else | 10 min | Validates or invalidates indexing pipeline design. Gate for Phase 3. |
| **Phase 1** (merge enter → thebrana) | Next focused session | 1 day | File moves, path updates, config merges, validate cycle. Structural only. |
| **Phase 2** (skill logic rewrites) | Follows Phase 1 | 1-2 days | `/back-propagate` and `/brana:reconcile` need logic rewrites, not just path substitution. Degraded mode acceptable while in progress. |
| **Phase 3** (wire retrieval prototype) | After Phase 1 | 1 session | Write 1-2 seed docs + indexing pipeline + end-to-end test. Must pass before scaling content. |
| **Phase 4** (evolve brana-knowledge) | After Phase 3 validates | Ongoing | Scale content, create `/knowledge` skill, grow organically. |

**Key change from v3:** Phase 2 (content) and Phase 3 (retrieval) swapped. Retrieval must be validated before content investment — otherwise knowledge base becomes a second spec graveyard. Phase 1 and Phase 4 (old numbering) unbundled because skill rewrites are logic changes, not path substitutions.

---

## 12. Success Criteria

The redesign succeeds when:

1. **Feedback loop:** Brana improvement from project work takes 2 context switches (project → thebrana → deploy), not 4.
2. **Knowledge retrieval:** Working on psilea, memory-curator finds relevant brana-knowledge dimension doc without being told where to look.
3. **Spec quality maintained:** Next `/build-phase` produces specs as detailed as Phase 4, from `thebrana/docs/` not from a separate repo.
4. **Portability:** `git clone thebrana` + `deploy.sh` sets up the full brain on a new machine. `git clone brana-knowledge` brings all personal knowledge. Projects clone independently.
5. **No graveyard:** brana-knowledge dimension docs are read/used at least once within 90 days of creation (tracked by index freshness).
6. **Compounding knowledge (#461):** "Every file added makes every session better." Measurable: session N+10 completes tasks faster or with fewer tool calls than session N, because knowledge base provides relevant context upfront.
7. **Cylinder, not cone (#466):** After 6 months of knowledge base growth, no architectural drift — constraints (quality pipelines, freshness tracking, reflection synthesis) keep the system bounded. Growth is vertical (depth per topic) not horizontal (unbounded topic sprawl).

---

## 13. Research Sources

External references that informed or validated this design. Backlog link numbers reference `30-backlog.md`.

### Primary Sources (researched, findings integrated)

| # | Author | Key Contribution | Sections Informed |
|---|--------|-----------------|-------------------|
| 457 | prateekkarnal (Composio) | Planner/Executor in one system; 30 agents self-improving the agent system | 5.4 (merge validation) |
| 461 | Dulan Perera | Day 52 daily CC: compounding knowledge, context-as-infrastructure, script-over-MCP | 6.5 (KB validation), 8.2 (indexing), 12 (compounding metric) |
| 462 | Boris Tane | Annotation cycle: plan.md as shared mutable state, research.md pattern, no-formal-memory tradeoff | 5.4 (colocation), 6.5 (annotation cycle), 8.2 (/knowledge skill) |
| 466 | Julian Cislo | Cone-vs-cylinder: constraints prevent drift, pipelines as governance | 5.4 (governance), 10 (graveyard mitigation), 12 (cylinder metric) |

### Secondary Sources (researched, lower direct relevance)

| # | Author | Key Contribution | Notes |
|---|--------|-----------------|-------|
| 458 | Leonardo Tarla (Synthflow) | RAG + vector DB pattern: multi-source ingestion → embeddings → retrieval | Confirms two-layer model (section 7.1). Post not found — findings from author's published Synthflow project. |
| 467 | Chad Mazzola | Claude Code vs Codex comparison | Post not found. General CC vs Codex insights: CC favors interactive steering + knowledge-backed workflows; Codex favors autonomous sandbox execution. |
| 468 | jaeahn19 | Why Claude Code works | Post not found. Synthesized: progressive disclosure, checkpoint-driven workflows, 80% of context solved by .claudeignore + CLAUDE.md + Plan mode. |
| 469 | Marley-Ma | MCP + Playwright integration | Post not found. Researched from official sources: accessibility-tree-based testing, persistent browser state, constrained tool allowlists. Relevant to future e2e testing of knowledge pipeline. |

### Related Sources (discovered during research)

| Source | Key Contribution |
|--------|-----------------|
| claude-reflect-system (haddock-development) | Continual learning: corrections → permanent memory in CLAUDE.md via hooks. Validates brana's /debrief + /brana:retrospective → rules feedback loop. |
| claude-meta (aviadr1) | Meta-rules about rules — self-improving CLAUDE.md through reflection prompts. Validates brana's memory-framework.md pattern. |

---

## 14. Challenge Review

Adversarial review conducted 2026-02-25 (Opus challenger agent). Verdict: **proceed with changes, 3 critical fixes applied, all 3 now resolved.**

### Critical findings (integrated)

| # | Finding | Impact | Resolution |
|---|---------|--------|------------|
| C1 | **Knowledge base graveyard — no retrieval means no demand.** Memory-curator depends on Phase 3 indexing. Without retrieval, knowledge dies on the shelf. | Phase 2 content investment wasted | **Flipped Phase 2↔3.** Retrieval prototype (Phase 3) now comes before content scaling (Phase 4). End-to-end test required: write seed doc → index → retrieve from project session. |
| C2 | **"1 day" underestimates skill rewrites.** 30 hardcoded `~/enter_thebrana/enter/` refs across 11 files. `/back-propagate` and `/brana:reconcile` need logic rewrites, not path substitution. | Migration takes longer, frustration | **Split Phase 1 (structural) from Phase 2 (skill logic).** Degraded mode acceptable while skill logic is reworked. |
| C3 | **Embedding CLI assumption untested.** `ruflo` CLI embedding generation never verified. If it doesn't exist, both primary and fallback indexing designs are invalid. | Entire retrieval architecture invalidated | **RESOLVED.** Phase 0.5 spike completed 2026-02-25. CLI generates real 384-dim ONNX embeddings (all-MiniLM-L6-v2), semantic similarity verified (0.65 related, 0.23 unrelated). See section 7.3. |

### Warnings (documented, mitigations added)

| # | Finding | Resolution |
|---|---------|------------|
| W1 | **Spec discipline weakens** — repo boundary was a hard constraint, pre-commit hook is soft (bypassable with `--no-verify`) | Tripwire added to risk table: 3 consecutive skips → make hook mandatory |
| W2 | **New cross-repo friction** (thebrana↔brana-knowledge) — `/brana:research` reads, `/brana:retrospective` writes | Accepted trade-off, documented in risk table. Library ≠ active project. |
| W3 | **Auto-memory merge is not "15 minutes"** — patterns reference doc numbers and file structures that change | Q5 updated: careful diff, revisit after 2 weeks |

### Observations (noted for implementation)

| # | Finding | Action |
|---|---------|--------|
| O1 | Success criterion #6 (session N+10 faster) is unmeasurable with current tooling | Acknowledge as aspirational until session performance tracking exists |
| O2 | `~/enter_thebrana/` directory name becomes misleading after archive | Defer — rename is cosmetic, not blocking. Address post-migration if it bothers. |
| O3 | Existing brana-knowledge `projects/` and `memory/` dirs (31 files) not mentioned in restructure | Added to Phase 4: relocate to `backup/` alongside existing backup content |
| O4 | Chicken-and-egg: Phase 2 needs Phase 3 for motivation, Phase 3 needs Phase 2 for content | Resolved by Phase 3 resequencing: write seed docs + pipeline in same session |
