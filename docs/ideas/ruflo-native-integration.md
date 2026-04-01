# Ruflo Native Integration

> Brainstormed 2026-03-31. Status: idea (in progress).

## Problem

Brana treats ruflo as an optional CLI tool. It uses 6 of 218 MCP tools, stores flat key-value entries while 33 advanced tables sit empty. The MCP server pointed to a stale 42-entry database while the CLI had 1,006 entries. Ruflo's learning engine — trajectories, causal graphs, pattern confidence, agent orchestration, ReflexionMemory — is completely untapped.

## Core Decision

**MCP as primary transport, CLI as fallback for hooks.**

Reason: The advanced ruflo features (agentdb, trajectories, hooks intelligence, workflows, hive-mind, claims) are only accessible via MCP tools. The CLI only exposes basic `memory` operations. Skills and agents run in LLM context where MCP tools are native. Hooks run in shell context where CLI is the only option.

| Context | Transport | Access |
|---------|-----------|--------|
| Skills + agents | MCP (`mcp__ruflo__*`) | All 218 tools |
| Hooks (shell) | CLI (`$CF memory store/search`) | 6 basic memory ops |
| Rust CLI (`brana learn`) | CLI (`$CF`) | Wraps mechanical operations |

## Architecture Layers

```
JUDGMENT LAYER (Skills / LLM)
  What to learn, what's transferable, what to recall.
  Calls mcp__ruflo__* directly.

MECHANICAL LAYER (Rust CLI)
  Confidence math, trajectory recording, consolidation,
  decay, knowledge indexing.
  Calls ruflo CLI ($CF) from shell context.

HOOK LAYER (Shell scripts)
  Session start/end, PostToolUse recording.
  Calls brana CLI (which calls ruflo CLI).

RUFLO (Infrastructure)
  MCP server (218 tools) + SQLite + HNSW +
  ONNX embeddings + AgentDB controllers.
  Storage: ~/.swarm/memory.db
```

## Knowledge Tier Model

Ruflo's `agentdb_hierarchical-store` provides 3 memory tiers:

### Working Tier (hot, session-scoped)
- TTL: 24h unless promoted
- Recall: always, first priority
- Contents: current session patterns, active research findings, field notes from current build, build context, cross-client patterns surfaced this session
- Write trigger: during session
- Promotion: to episodic after session ends (if confidence > 0.3)
- Decay: auto-purge after 24h if not promoted

### Episodic Tier (warm, multi-session)
- TTL: 90 days unless promoted
- Recall: when topic matches query
- Contents: session summaries, build learnings, causal edges, errata, validated research, cross-validated patterns, trajectories
- Write trigger: session-end consolidation
- Promotion: to semantic after confidence > 0.8 AND recall_count > 5
- Decay: confidence x 0.95 per week, archive at confidence < 0.2

### Semantic Tier (cold, permanent)
- TTL: none (permanent until superseded)
- Recall: on-demand during SPECIFY, /research, challenger review
- Contents: dimension doc sections (436+), battle-tested patterns, ADR decisions, shipped feature specs, cross-client patterns validated 3+ times, promoted skills, behavioral rules
- Write trigger: weekly consolidation job, index-knowledge
- No decay. Superseded entries get archived with reference.

### Knowledge Indexing

| Source | Tier | Trigger | TTL |
|--------|------|---------|-----|
| Dimension docs (brana-knowledge/) | Semantic | post-commit hook, weekly scheduler | Permanent |
| Research findings (/brana:research, build SPECIFY) | Episodic | skill stores as discovered | 90 days |
| Feature specs (shipped) | Semantic | post-commit on docs/architecture/ | Permanent |
| Feature specs (in-progress) | Episodic | during build | 90 days |
| ADRs | Semantic | post-commit on docs/decisions/ | Permanent |
| Field notes | Episodic | close skill captures | 90 days |
| Idea docs | Working | during brainstorm | 24h |
| Session patterns | Working → Episodic | during session → promoted at session-end | 24h → 90d |

Cross-references between docs stored as `agentdb_causal-edge` (replaces spec-graph.json edges for knowledge relationships).

Dedup: `embeddings_compare` before storing — skip if > 0.95 similarity match exists.

Batch writes: `agentdb_batch` for bulk indexing (up to 500 per call).

## Confidence Math

Patterns have a confidence score (0.0–1.0) that determines visibility and tier placement.

### Initial Values
- Session learning: 0.5 (unvalidated)
- Research finding: 0.3 (speculative)
- Dimension doc section: 0.9 (curated)
- Cross-client transfer: inherits source confidence

### Events

| Event | Effect |
|-------|--------|
| Recalled and used in a build | +0.1 |
| Recalled but ignored | -0.05 |
| Cross-client validation | +0.2 |
| Build that used pattern succeeded | +0.1 |
| Build that used pattern failed/rework | -0.15 |
| Weekly time decay | ×0.95 |
| Contradicted by newer pattern | -0.3 |

All values clamped to [0.0, 1.0].

### Tier Thresholds

```
  0.0     0.2      0.3           0.8        1.0
  ARCHIVE  WORKING  EPISODIC     SEMANTIC
```

- working → episodic: confidence > 0.3 at session end
- episodic → semantic: confidence > 0.8 AND recall_count > 5
- semantic → episodic: confidence drops below 0.6
- episodic → archive: confidence drops below 0.2
- working → purge: 24h TTL expires

### Decay Curve
- 0.95/week: unused pattern dies in ~6 months
- One validation per month keeps it alive
- Cross-client validation fast-tracks to permanent

---

## DDD → SDD → TDD Chain (ruflo-enriched)

The full quality enforcement chain with ruflo at every step. Each gate learns from enforcement — feeding pass/fail back to ruflo to improve future predictions.

### DDD Gate (Domain-Driven — before SPECIFY)

Checks if domain knowledge exists in ruflo's semantic tier before allowing feature work.

**Scope:** Only fires for strategy=feature/greenfield/migration AND effort >= M. Bug fixes, refactors, spikes, and small tasks skip entirely.

**Flow:**
1. Query `agentdb_hierarchical-recall(tier=semantic, query="{task tags}")`
2. If results: PASS silently, inject top 3 into context
3. If no results: ASK user (not block):
   - "Run /brana:research first" (recommended for L/XL)
   - "Proceed — I know this domain" (logs override)
   - "Skip — domain irrelevant" (passes silently)
4. Track overrides: 5+ successful builds after override → ruflo learns "this domain doesn't need DDD". 3+ failures after override → ruflo warns "DDD overrides on this domain correlate with rework."

### SDD Gate (Spec-Driven — before BUILD)

Checks if a feature spec exists (file or ruflo entry) before allowing implementation.

**Scope:** Same as DDD gate — feature/greenfield/migration, effort >= M.

**Flow:**
1. Check file: `docs/architecture/features/{task-slug}.md`
2. If no file: query `agentdb_pattern-search(query="spec:{task-id}")`
3. If neither: ASK user — write spec or override with reason
4. If spec exists: inject summary into context

**Ruflo enrichment at SPECIFY:** `memory_search` for past patterns, `agentdb_context-synthesize` for draft from knowledge, `agentdb_pattern-search` for similar past specs.

### TDD Gate (Test-Driven — before implementation)

Existing `tdd-gate.sh` + ruflo learning.

**Scope:** All strategies on feat/* branches (unchanged).

**New with ruflo:**
- After test pass/fail: `agentdb_feedback(success, context)`
- Over time: ruflo predicts which task types tend to fail TDD and suggests test strategies

### Gate Learning Loop

All three gates feed ruflo. Over sessions, enforcement adapts:
- Domains that never need DDD → gate auto-skips
- Task types that always pass SDD → gate relaxes
- Test patterns that correlate with success → ruflo suggests at TDD gate
- Override patterns that correlate with failure → ruflo escalates

## Enrichment Matrix

Each brana component × each ruflo capability group. Top 10 highest-value combinations:

| # | Combination | What it enables |
|---|-------------|----------------|
| 1 | build × hooks intelligence trajectory | Every build becomes a learning trajectory |
| 2 | build × claims | Parallel subagents don't stomp each other's files |
| 3 | build × hive-mind | Parallel subtasks coordinate via shared blackboard |
| 4 | research × agentdb context-synthesize | Ruflo synthesizes context from stored knowledge |
| 5 | sitrep × agentdb hierarchical-recall | Recall from the right memory tier based on context |
| 6 | backlog execute × agent spawn + hive-mind | Parallel task execution through ruflo orchestration |
| 7 | index-knowledge × agentdb hierarchical-store + batch | Proper tiered indexing with batch writes |
| 8 | pre-tool-use × claims | Check file locks before editing in parallel sessions |
| 9 | session-start × agentdb session-start | Full ReflexionMemory replay instead of basic recall |
| 10 | close × agentdb session-end | NightlyLearner consolidation automatically |

Full matrix (all components × all groups) documented in brainstorm conversation 2026-03-31.

## Subagent Protocol + Hive-Mind Execution

### Two modes of parallel execution

**Mode 1: Build execution (code tasks)**
Orchestrator spawns subagents in worktrees. Each agent gets a self-contained protocol:
1. ORIENT → read spec + files
2. TEST FIRST → write failing test
3. IMPLEMENT → make test pass (edit only claimed files)
4. VERIFY → run tests (max 2 retries)
5. COMMIT → git commit
6. REPORT → hive-mind broadcast + claims release

No user interaction. Claims prevent file conflicts. Hive-mind broadcasts completion. 10-min timeout per agent.

**Mode 2: Discussion/analysis (research, review, brainstorm)**
Spawn agents with different PROFILES to analyze a topic from multiple angles simultaneously:

```
/brana:research "JWT auth patterns":
  → mcp__ruflo__hive-mind_init(topology="mesh")  // peer-to-peer, no queen
  → Spawn 3 agents:
    Agent A (profile: security-auditor): "Analyze JWT security risks"
    Agent B (profile: architect): "Evaluate JWT architecture patterns"
    Agent C (profile: researcher): "Find latest JWT best practices 2026"
  → All work in parallel, share findings via hive-mind_memory
  → Each broadcasts key findings when done
  → Orchestrator synthesizes: reads all broadcasts + shared memory
  → Presents unified research with attributed perspectives
```

This applies to:
- `/brana:research` — multiple scout perspectives on a topic
- `/brana:brainstorm` DISCUSS phase — challenger + architect + domain expert agents
- `/brana:build` SPECIFY — research + security + performance review in parallel
- `/brana:review` — metrics analyst + strategy advisor + risk assessor

### Orchestrator responsibilities (both modes)

1. Build DAG waves (code tasks) or spawn mesh (discussion tasks)
2. Claim files (code) or assign topics (discussion)
3. Spawn all agents in ONE message (parallel)
4. Monitor via hive-mind broadcasts
5. Merge worktrees (code) or synthesize findings (discussion)
6. Track trajectories for SONA learning

### Key: agents with no dependencies work in parallel

The DAG determines waves. Within a wave, all tasks are independent — spawn them simultaneously. Backlog execute already defines this, but with ruflo hive-mind, agents can also share intermediate state during execution (not just report at the end).

## Enrichment Matrix #4-#10 (quick pass — deepen next session)

### #4: research × agentdb context-synthesize
Instead of raw `memory_search` returning chunks, call `agentdb_context-synthesize` to get a synthesized narrative from stored knowledge. Research skill gets a coherent summary, not a list of fragments. Also use multi-profile agents (Mode 2) for parallel research perspectives.

### #5: sitrep × agentdb hierarchical-recall
Sitrep currently calls `brana session read --json`. With ruflo: `agentdb_hierarchical-recall` across tiers — working (hot session state) + episodic (recent patterns) + semantic (domain knowledge). Sitrep becomes context-aware, not just session-aware. Surfaces "you were working on X, and related patterns suggest Y."

### #6: backlog execute × agent spawn + hive-mind
Already designed above (subagent protocol). Execute spawns agents via `agent_spawn` (gets model routing), coordinates via `hive-mind`, prevents conflicts via `claims`. The orchestrator is the queen. This replaces the current "spawn Agent tools and hope" approach with structured orchestration.

### #7: index-knowledge × agentdb hierarchical-store + batch
Replace `index-knowledge.sh` (flat `memory_store` per section) with tiered indexing: dimension docs → semantic tier, research → episodic tier, field notes → episodic tier. Use `agentdb_batch` for bulk writes (500 per call). Add `embeddings_compare` for dedup before storing. Cross-references become `agentdb_causal-edge` instead of spec-graph.json edges.

### #8: pre-tool-use × claims
Before any Edit, pre-tool-use hook checks `claims_status(file_path)`. If claimed by another agent (parallel session or worktree), block: "File claimed by {agent}. Wait or work on something else." Enables safe multi-session editing on the same repo.

### #9: session-start × agentdb session-start
Replace basic `memory_search` recall with `agentdb_session-start`. This triggers ReflexionMemory: replays past session patterns, surfaces high-confidence corrections, and primes the SONA trajectory for this session. Richer context injection than a flat search.

### #10: close × agentdb session-end
Replace basic `memory_store` at session end with `agentdb_session-end`. Triggers NightlyLearner consolidation: promotes high-confidence episodic patterns to semantic tier, decays stale patterns, compresses old trajectories. This is the automatic maintenance loop — no manual `brana learn consolidate` needed.

(next session: deepen each, design concrete wiring, challenge, then /brana:backlog plan)

---

## Graceful Degradation

**Golden rule: ruflo failure never blocks work.**

### Failure Mode 1: MCP server not running
- Skills: try CLI (`$CF`), then grep MEMORY.md, then proceed without memory
- Hooks: already use CLI, fall back to MEMORY.md/pending-learnings.md
- Gates: SKIP silently (log the skip, never block a build)

### Failure Mode 2: MCP crashes mid-session
- Current operation falls back to CLI
- Trajectory recording fails silently (best-effort, not critical path)
- Pattern storage queues to `~/.claude/projects/{project}/memory/deferred-patterns.jsonl`
- Session-end and next session-start retry deferred patterns
- User notified via additionalContext, not interrupted

### Failure Mode 3: DB corrupt
- `brana ops health` detects (entry count mismatch vs last backup)
- Restore from `brana-knowledge/backup/swarm/`
- Re-run `index-knowledge.sh` to rebuild from source docs

### Dual-Write Strategy

Ruflo gets everything. MEMORY.md gets only the critical subset:
- Pattern MUST have confidence >= 0.8
- AND tagged as directive or convention
- AND not derivable from code/git
- In practice: ~5-10 entries (MEMORY.md stays under 200 lines)
- memory-review step in /brana:close audits: "is this in ruflo? still needed in MEMORY.md?"

This ensures: if ruflo dies completely, MEMORY.md has the most critical rules. Everything else is recoverable from git (docs) or rebuilt (re-index).

---

## Open Questions

1. Should spec-graph.json edges migrate entirely to ruflo causal_edges, or coexist?
2. Should `brana learn` be new Rust CLI subcommands, or extend existing `brana ops`?
3. Which enrichment matrix combinations to implement first?
4. How to handle ruflo version upgrades (pin? test before update? migration path?)

---

## Phased Rollout (draft)

| Phase | What | Effort |
|-------|------|--------|
| P0 | Fix MCP server (wrapper script, correct DB) | S |
| P1 | Enable tool groups (memory + hooks + embeddings + agentdb) | S |
| P2 | Skills adopt MCP (add mcp__ruflo__* to allowed-tools) | M |
| P3 | Trajectory loop (hooks intelligence in build) | M |
| P4 | Tiered knowledge indexing (replace flat index-knowledge.sh) | M |
| P5 | Causal graph + feedback loop | M |
| P6 | Cross-client pollination with tier-aware recall | M |
| P7 | Advanced (hive-mind, workflows, claims, agent orchestration) | L |
