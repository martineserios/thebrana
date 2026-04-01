# Ruflo Native Integration

> Brainstormed 2026-03-31. Status: idea (in progress).

## Problem

Brana treats ruflo as an optional CLI tool. It uses 6 of 218 MCP tools, stores flat key-value entries while 33 advanced tables sit empty. The MCP server pointed to a stale 42-entry database while the CLI had 1,006 entries. Ruflo's learning engine — trajectories, causal graphs, pattern confidence, agent orchestration, ReflexionMemory — is completely untapped.

## Core Decision

**MCP is the backbone. Skills call ruflo MCP directly. CLI is for local-only tools.**

> Revised 2026-04-01 after verifying 15 agentdb controllers active. The CLI intermediary
> pattern (`skill → brana CLI → $CF → ruflo`) made sense when ruflo had 6 basic ops. With
> 15 controllers offering hierarchical tiers, context synthesis, trajectory tracking,
> consolidation, batch, and feedback, piping through a CLI wrapper loses all the richness.
> Skills have native MCP access — use it.

| Context | Transport | What it accesses |
|---------|-----------|-----------------|
| Skills + agents | **MCP direct** (`mcp__ruflo__*`) | All controllers: hierarchical-store/recall, session-start/end, context-synthesize, trajectory, feedback, batch |
| Hooks (shell) | **CLI** (`$CF memory store/search`) | Basic memory ops only. Hooks stay fast, no MCP. |
| Rust CLI | **Local only** — no ruflo wrapper | Backlog (tasks.json), transcription (whisper), files, feeds, inbox, batch indexing |

### What moves out of the CLI

`brana session write/read/history` → **replaced by direct MCP calls from skills.**

| Old (CLI intermediary) | New (MCP direct) |
|----------------------|-----------------|
| Close → `brana session write` → `$CF memory store` | Close → `hierarchical-store(tier: "episodic")` + `session-end` |
| Sitrep → `brana session read --json` | Sitrep → `hierarchical-recall(tier: "working")` + `hooks_intelligence_pattern-search` |
| Session-start hook → `brana session read --json` | Hook: `$CF memory search --namespace session` (basic). First skill call: `session-start` via MCP (rich, ReflexionMemory replay) |
| Session-end hook → `brana session write --minimal` | Hook: `$CF memory store --namespace session` (basic fallback) |
| `brana session history` (linear browse) | `memory_search(namespace: "session", query: "topic")` (semantic search) |

### What stays in the CLI (local-only tools)

```
brana backlog   — tasks.json management (local file, no ruflo)
brana transcribe — whisper audio transcription (local binary)
brana files     — large file tracking + R2 remotes (local manifest)
brana feed      — RSS/Atom polling (local HTTP)
brana inbox     — Gmail IMAP polling (local IMAP)
brana learn index — mechanical batch indexing (calls $CF for bulk writes)
```

### Graceful degradation

Skills: try MCP → fall back to `$CF` via Bash → fall back to MEMORY.md.
Hooks: always use `$CF` (shell context, can't call MCP).
If ruflo is completely down: hooks write to `pending-learnings.md`, skills work without memory.

## Architecture Layers

```
JUDGMENT LAYER (Skills / LLM)
  What to learn, what's transferable, what to recall.
  Calls mcp__ruflo__* directly — all 15+ controllers.
  Examples: hierarchical-store, context-synthesize,
  session-end, trajectory-start, pattern-search.

HOOK LAYER (Shell scripts)
  Session start/end, PostToolUse recording.
  Calls $CF (ruflo CLI) for basic memory ops.
  Writes flag files for deferred MCP calls.

MECHANICAL LAYER (Rust CLI)
  Local-only tools: backlog, transcription, files, feeds, inbox.
  Batch indexing via $CF for bulk knowledge writes.
  No ruflo wrapper — those concerns live in skills now.

RUFLO (Infrastructure)
  MCP server + SQLite + HNSW + ONNX embeddings.
  15 active AgentDB controllers (v3.5.48 + ESM patch).
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

## Enrichment Matrix #4-#10 (deepened)

### #4: research × cross-namespace search + hierarchical recall

> **Redesigned 2026-04-01** after challenger review + controller verification.
> Original plan used `context-synthesize` + `pattern-search` — both unimplemented upstream
> (ruflo@3.5.48, ContextSynthesizer never registered, reasoningBank disabled).
> Redesigned around tools that actually work.

**Problem now:** Research skill Phase 0 runs 4 parallel `$CF memory search` calls across namespaces (knowledge, assumptions, field-notes, decisions). Returns raw fragments — the LLM has to synthesize them into usable context manually, burning tokens on assembly instead of analysis.

**With ruflo MCP (working tools only):**

```
Phase 0 — Internal Search (replace 4 CLI calls with 2 MCP calls):

  Call 1: mcp__ruflo__memory_search(
    query: "{TOPIC} {TAGS}",
    namespace: "all",
    limit: 15,
    threshold: 0.4
  )
  → Cross-namespace semantic search in ONE call
  → Returns results tagged with source namespace (knowledge, patterns, etc.)
  → Replaces: 4x $CF memory search

  Call 2: mcp__ruflo__agentdb_hierarchical-recall(
    query: "{TOPIC}",
    tier: "episodic",
    topK: 5
  )
  → Surfaces patterns from past sessions on this topic
  → New capability: "you researched JWT auth 3 sessions ago, found X"
  → Returns only entries explicitly promoted to episodic tier
```

**Data flow:**
- memory_search returns results with `.namespace` field → LLM groups by provenance:
  decisions carry authority, assumptions are speculative, field-notes are observational
- hierarchical-recall returns episodic patterns → surface as "Related prior work:" section
  before Phase 1 (Wide Scan)
- If memory_search returns >10 high-similarity results (>0.7) → narrow Phase 1 web search
  to gaps only, not full topic re-scan

**Wiring changes to `system/skills/research/SKILL.md`:**
- Phase 0: replace 4 CLI calls with 2 MCP calls (above)
- Phase 2 (Triage): after scout returns, `embeddings_compare(finding, top_memory_result)`
  — if similarity > 0.92, mark as "already known" and skip deep dive
  (threshold 0.92 per challenger review — 0.85 risks suppressing contradictions)
- Phase 15 (Store leads): replace `$CF memory store` with
  `agentdb_hierarchical-store(key, value, tier: "episodic")` — leads are warm, not permanent
- Add `mcp__ruflo__memory_search`, `mcp__ruflo__agentdb_hierarchical-recall`,
  `mcp__ruflo__embeddings_compare`, `mcp__ruflo__agentdb_hierarchical-store` to allowed-tools

**Fallback:** If MCP unavailable, fall back to current 4x CLI search.

**Future upgrade path:** When ruflo ships `context-synthesize` and `pattern-search`,
swap memory_search → context-synthesize (gets pre-assembled narrative instead of fragments)
and add pattern-search as supplementary source. The skill structure won't need to change —
just the tool calls in Phase 0.

---

### #5: sitrep × hooks intelligence pattern-search (+ hierarchical-recall after #9+#10)

> **Revised 2026-04-01** after challenger review (verdict: PROCEED WITH CHANGES).
> Original plan: 3 hierarchical-recall calls. Challenger found 2 of 3 return empty today.
> Discovery: `hooks_intelligence_pattern-search` is the working pattern search (bypasses
> broken `agentdb_pattern-search`). Redesigned to ship 1 call now, add tiers later.

**Problem now:** Sitrep reads from 5 local sources (TaskList, git, backlog CLI, session JSON, conversation). Zero memory context — can't surface "you were debugging X last week" or "pattern Y from client Z might apply here." It's a status dump, not contextual awareness.

**Session state also changes:** Sitrep Source 4 currently calls `brana session read --json` (local file). Per the architecture revision (MCP as backbone), this becomes a direct `memory_search(namespace: "session")` call — semantically searchable, not file-dependent.

**Phase 1 — Ship now (1 MCP call):**

```
Source 6 — Memory Context:

  mcp__ruflo__hooks_intelligence_pattern-search(
    query: "{TASK_SUBJECT} {BRANCH}",
    topK: 3,
    minConfidence: 0.3,
    namespace: "pattern"
  )
  → Confidence-scored patterns from HNSW vector search
  → Returns results from 476 existing entries
  → 26ms warm, ~500ms cold (ONNX model load)
```

**Output rules (per challenger):**
- Suppress results below 0.25 similarity
- If all results below threshold, omit Memory Context section entirely
- Use plain-language labels: "from past sessions" not "[episodic]"
- If a correction pattern matches current task, surface it explicitly

```markdown
**Memory context:**
- {pattern description, confidence: 0.35} — from past sessions
- Note: past correction on this topic — {correction}
```

**Phase 2 — Ship after #9+#10 populate tiers (add 1 more call):**

```
  mcp__ruflo__agentdb_hierarchical-recall(
    query: "{BRANCH} {TASK_SUBJECT}",
    tier: "working",
    topK: 3
  )
  → Hot patterns from current/recent sessions (only useful after close writes to tiers)
```

Output gains: `- {pattern} — from this session`

**Learning health:** Moved to `/brana:memory review` per challenger — not actionable in sitrep.

**Wiring changes:**
- Phase 1: add `mcp__ruflo__hooks_intelligence_pattern-search` to sitrep allowed-tools. 1 tool, 1 call.
- Phase 2: add `mcp__ruflo__agentdb_hierarchical-recall` after #9+#10 land.
- Source 4: replace `brana session read --json` with `memory_search(namespace: "session", limit: 1)` (semantic, ruflo-native).

**Fallback:** If MCP unavailable, skip Source 6 entirely. Source 4 falls back to `brana session read --json` (local file). Sitrep works as today — local-only.

**Effort:** S (Phase 1). M (Phase 2 — depends on #9+#10).

---

### #6: ruflo orchestration layer — hive-mind, claims, agent registry, coordination

> **Revised 2026-04-01** after challenger review (verdict: RECONSIDER) + workflow context.
> Original plan: ruflo as parallel-agent coordinator within one session.
> Challenger found: CC agents can't call MCP, hive-mind is write-only, claims aren't file locks.
> Reframe: ruflo as **multi-session awareness + task concurrency + agent analytics + workflow orchestration**.

**Workflow context:** User runs one terminal per client (no IDE). Multiple terminals open
simultaneously across different projects (somos, anita, thebrana). Sometimes two parallel
sessions on the same client. Tasks range from small fixes to large multi-subtask builds
broken down via `brana backlog plan` (phase → milestone → task → subtask).

#### 6A: Hive-mind → Cross-session blackboard

**Not for:** parallel agents within one session (they can't call MCP).
**For:** awareness between multiple Claude Code sessions — same client or cross-client.

**How it works:** All sessions share one hive-mind through the MCP server (ruflo-mcp.sh
sets cwd to `~`, so `~/.claude-flow/hive-mind/` is shared). Per-client isolation via key
prefixes (`client:somos:*`).

**Level 1: Same-client session awareness**

```
Terminal 1a: /brana:build t-200 (large task, 5 subtasks)
  → hive-mind_memory(set, "client:somos:build:t-200", {
      session: "session-A",
      status: "in-progress",
      branch: "feat/t-200-auth-middleware",
      subtasks_total: 5,
      subtasks_done: 0,
      current_subtask: "t-200a",
      files_touched: ["src/auth.rs", "src/middleware.rs"],
      started: "2026-04-01T14:00:00Z"
    })

Terminal 1b (parallel session, same client): /brana:sitrep
  → hive-mind_memory(list) → filter "client:somos:*"
  → "Session A is building t-200 (auth middleware) — subtask 1/5
     Editing: src/auth.rs, src/middleware.rs
     → Pick a different task, or wait for A to finish"

Terminal 1b: brana backlog next
  → hive-mind_memory(get, "client:somos:build:t-200") → t-200 in progress
  → Skips t-200, skips t-202 (blocked by t-200), picks t-201

Subtask done in 1a:
  → hive-mind_memory(set, ..., { subtasks_done: 1, current_subtask: "t-200b" })
  → Terminal 1b sitrep now shows: "Session A: t-200 — 1/5 subtasks done"
```

**Level 2: Cross-client awareness**

```
Any terminal: /brana:sitrep
  → hive-mind_memory(list) → filter all "client:*:build:*" keys
  → **Active sessions:**
    - somos (terminal 1): building t-200 auth middleware — 2/5 subtasks, 45 min active
    - anita (terminal 2): researching WhatsApp templates — 3 sources found
    - thebrana (terminal 3): this session (ruflo integration brainstorm)
```

**Level 3: Build plan progress (backlog plan integration)**

`brana backlog plan` breaks work into phases/milestones/tasks. Hive-mind tracks the plan:

```
hive-mind_memory(set, "plan:somos:ph-010", {
  total_tasks: 4,
  completed: 0,
  in_progress: {"t-200": "session-A"},
  blocked: ["t-202", "t-203"],
  available: ["t-201"],
  updated: "2026-04-01T14:30:00Z"
})

Terminal 1b: brana backlog next → reads plan → picks t-201 (available, unclaimed)
Both sessions finish → plan auto-updates → t-202 unblocks
```

**Level 4: Scheduled jobs + handoff**

```
Oracle cron (reindex-knowledge, 03:00):
  → hive-mind_memory(set, "job:reindex", {status: "done", sections: 436, at: "03:00"})

Morning session: /brana:sitrep
  → "Knowledge reindex ran at 03:00, indexed 436 sections"

/brana:close in terminal 1:
  → hive-mind_broadcast("somos session closed. t-200 at 3/5 subtasks. Next: t-200d, t-200e.")
  → Next session-start on somos picks this up
```

**Brana consumers:**

| Consumer | Operation | What it enables |
|----------|----------|----------------|
| `/brana:build` start | `memory(set, "client:{c}:build:{task}", {...})` | Announce what you're working on |
| `/brana:build` subtask done | `memory(set, ...)` update progress | Live progress tracking |
| `/brana:build` end | `memory(set, status: "done")` + `broadcast(...)` | Signal completion |
| `/brana:close` | `broadcast("session closed. state: ...")` | Handoff to next session |
| `/brana:sitrep` | `memory(list)` filter `client:*` | Cross-session + cross-client view |
| `brana backlog next` | `memory(get, "plan:{phase}")` | Skip claimed/blocked tasks |
| `brana backlog start` | `memory(set, ...)` | Announce task start |
| Session-start hook | `memory(list)` check for active/stale | Resume + stale cleanup |
| Oracle scheduler | `memory(set, "job:{name}", {...})` | Job status visible to sessions |
| `/brana:review` | `memory(list)` all clients | Portfolio-wide session overview |

#### 6B: Claims → Task-level locking

**Not for:** file conflict prevention (worktrees handle that).
**For:** preventing two sessions from working on the same task.

```
Terminal 1a: brana backlog start t-200
  → claims_claim("task:t-200", "session:A", context: "auth middleware, est 30 min")
  → ✓ Claimed. Branch created, build starts.

Terminal 1b: brana backlog start t-200
  → claims_claim("task:t-200", "session:B") → DENIED
  → hive-mind_memory(get, "client:somos:build:t-200")
  → "t-200 claimed by session A (2/5 subtasks done, 15 min in). Try t-201?"

Session A crashes (no /brana:close):
  → Next session-start: claims_list(status: "active")
  → "Stale claim on t-200 from session A (45 min old, no heartbeat)"
  → Prompt user: release + resume, or leave claimed?
```

**Claims + hive-mind together:** Claims is the lock (can I work on this?), hive-mind is the
context (what's happening?). `brana backlog start` does both: claim the task + announce in
hive-mind. `brana backlog next` checks both: skip claimed + skip in-progress.

**Phase-level claims:** Claim a whole phase so another session doesn't start executing it:
```
claims_claim("phase:ph-010", "session:A", context: "executing 4 tasks")
```

**Brana consumers:**

| Consumer | Operation |
|----------|----------|
| `brana backlog start` | `claims_claim("task:{id}", "session:{s}")` |
| `brana backlog next` | `claims_list(status: "active")` → filter out claimed |
| `/brana:build` end | `claims_release("task:{id}", "session:{s}")` |
| `/brana:close` | `claims_list(claimant: "session:{s}")` → release all |
| Session-start hook | `claims_list(status: "active")` → detect stale (>1h, no heartbeat) |
| `/brana:sitrep` | `claims_board()` → show claimed tasks |

#### 6C: agent_spawn → Agent analytics registry

**Not for:** spawning CC subprocesses (CC Agent tool does that).
**For:** tracking agent execution history for cost analysis and model routing improvement.

```
/brana:build spawns subagents:
  agent_spawn("scout", task: "research JWT patterns", model: "haiku")    → registered
  agent_spawn("builder", task: "implement auth middleware", model: "sonnet") → registered
  → CC Agent(...) does the actual work

After agent completes:
  hooks_intelligence_trajectory-step(action: "scout:JWT", quality: 0.9)
  hooks_intelligence_trajectory-step(action: "builder:auth", quality: 0.7)

/brana:review weekly:
  → agent_list() → "23 agents this week. Haiku scouts: 85% success.
     Sonnet builders: 92%. Model routing saved ~$12 vs all-opus.
     2 haiku tasks needed sonnet retry — flag for routing adjustment."
```

**Brana consumers:**

| Consumer | Operation |
|----------|----------|
| `/brana:build` (subagent spawn) | `agent_spawn(type, task, model)` before `Agent(...)` |
| `/brana:research` (scout spawn) | `agent_spawn("scout", task, model)` |
| `/brana:challenge` (opus spawn) | `agent_spawn("challenger", task, "opus")` |
| After agent completes | `trajectory-step(action, quality)` |
| `/brana:review` | `agent_list()` → cost/success analytics |
| Model routing improvement | Compare routed model vs actual outcome over time |

#### 6D: coordination_orchestrate → Skill pipeline formalization

**Not for:** coordinating CC Agent subprocesses.
**For:** defining multi-step skill workflows as resumable, trackable pipelines.

```
/brana:maintain-specs (currently: sequential script, no tracking):
  coordination_orchestrate(
    task: "maintain-specs",
    strategy: "pipeline",
    agents: ["errata", "reflections", "synthesis", "hygiene"]
  )
  → Each step tracked. If step 2 fails, resume from step 2 next time.

/brana:review monthly (currently: manual sequence):
  coordination_orchestrate(
    task: "monthly-review",
    strategy: "parallel",
    agents: ["metrics-collector", "pipeline-tracker"]
  )
  → Then sequential merge into report.

/brana:build execute phase (DAG execution):
  coordination_orchestrate(
    task: "phase:ph-010",
    strategy: "parallel",
    agents: ["t-200", "t-201"]  // independent tasks in wave
  )
  → Formalized wave execution with status per task.
```

**Brana consumers:**

| Consumer | Strategy | What it formalizes |
|----------|----------|-------------------|
| `/brana:maintain-specs` | pipeline | errata → reflections → synthesis → hygiene |
| `/brana:review monthly` | parallel → merge | metrics + pipeline + financials → report |
| `/brana:build` phase execute | parallel (DAG waves) | wave-by-wave task execution |
| `/brana:research` multi-scout | parallel | N scouts on different aspects → synthesize |

#### Build execution (revised from original)

The original orchestration flow (hive-mind as agent coordinator) is replaced. For build
execution, the ruflo value is **model routing + trajectory tracking + task claims**, not
agent-to-agent coordination:

```
/brana:build execute phase ph-010:

  Step 1 — Claim phase:
    claims_claim("phase:ph-010", "session:{s}")
    hive-mind_memory(set, "plan:somos:ph-010", {status: "executing", ...})

  Step 2 — Build DAG waves from blocked_by graph (unchanged)

  Step 3 — For each wave, for each task:
    a. hooks_model-route(task: "{subject}") → haiku/sonnet/opus
    b. claims_claim("task:{id}", "session:{s}")
    c. agent_spawn(type: "builder", task, model) → analytics registry
    d. hive-mind_memory(set, "client:{c}:build:{task}", {status: "in-progress"})
    e. Agent(prompt, isolation: "worktree") → actual execution
    f. On complete: claims_release + hive-mind update + trajectory-step

  Step 4 — Merge worktrees (unchanged)
  Step 5 — claims_release("phase:ph-010") + hive-mind update + trajectory-end

Parallel session sees progress via hive-mind. Can't duplicate work via claims.
```

**Effort:** L (largest enrichment — 4 subsystems).
**Dependencies:** #9+#10 (session loop, trajectory tracking).
**Implementation:** P9 — last. Re-evaluate after P1-P4 deliver real usage data.

**What NOT to build:**
- No consensus voting between agents (overkill, agents are dumb workers)
- No agent-to-agent communication mid-execution (orchestrator manages)
- No auto-merge worktrees (orchestrator merges, user reviews)
- No retry logic inside agents (orchestrator re-spawns on failure)

---

### Project scope within clients

> Discussed 2026-04-01. Challenger reviewed hard-isolation approach (separate directories per
> project) — found 3 critical code-level blockers (CLI resolves tasks.json from git root,
> session state scopes to git root, task-sync slug derivation breaks). Rejected in favor of
> soft isolation via scope field.

**Approach: `project` field on tasks (Path B — soft isolation)**

One field, one filter flag. No structural changes to CLI resolution, session state, hooks,
or task-sync. Single tasks.json per client. Optional — clients without projects work as today.

```json
{
  "id": "t-200",
  "subject": "Auth middleware",
  "project": "ai-agent",
  "stream": "roadmap",
  "type": "task",
  "parent": "ms-050"
}
```

**CLI changes (S effort):**
- `brana backlog next --project ai-agent` → filter by project
- `brana backlog query --project ai-agent` → filter by project
- `brana backlog roadmap --project ai-agent` → show only that project's tree
- `brana backlog stats --group-by project` → stats per project
- `brana backlog plan --project ai-agent "description"` → set project on phase + children
- `brana backlog add --project ai-agent ...` → set project on new task
- No `--project` flag → shows all projects (current behavior, backward compatible)

**Phases inherit project:**
```json
{ "id": "ph-010", "subject": "Conversation engine", "project": "ai-agent", "type": "phase" }
```

**Ruflo integration — project in tags/keys:**
- Hive-mind: `client:somos:project:ai-agent:build:t-200`
- Claims: `task:somos:ai-agent:t-200`
- Memory store tags: `client:somos,project:ai-agent`
- Pattern recall: `memory_search` returns all client patterns; post-filter by project tag
  when scoped, or show all for cross-pollination

**What doesn't change:** tasks.json location, git repo structure, session state, hooks,
task-sync, portfolio.md format. Single-project clients just don't use the field.

---

### #7: index-knowledge — upgraded shell script + dedup skill

> **Revised 2026-04-01** after 2 challenger reviews.
> Original: LLM-based `/brana:index` skill replaces shell script entirely.
> Challenger C3: shell parsing costs $0 and is 1000x faster for mechanical section splitting.
> Challenger C1/C2: `hierarchical-store` is ephemeral (in-memory stub), `agentdb_batch`
> writes to episodes table not memory_entries. Neither usable for knowledge indexing.
> Final: Approach C — upgrade the battle-tested shell script, add dedup as periodic job.

**Problem now:** `index-knowledge.sh` stores 436 sections from 45 dimension docs. Flat
namespace, no tier classification, no dedup, no orphan cleanup, only indexes one doc category.

**What changes (Approach C):**

```
index-knowledge.sh (upgraded, still shell, still $0):

  1. EXPAND to 7 doc categories:
     brana-knowledge/dimensions/*.md     → 45 docs, ~436 sections
     docs/architecture/*.md              → ~5 docs, ~30 sections
     docs/reflections/*.md               → ~5 docs, ~40 sections
     docs/architecture/decisions/*.md    → ~15 docs, ~30 sections
     docs/architecture/features/*.md     → ~10 docs, ~20 sections
     docs/ideas/*.md                     → ~5 docs, ~20 sections
     docs/research/*.md                  → ~3 docs, ~15 sections
     Total: ~590 sections (vs current 436)

  2. CLASSIFY tier by path:
     case "$filepath" in
       */dimensions/*|*/architecture/*|*/reflections/*|*/decisions/*) tier="semantic" ;;
       */features/*) tier="episodic" ;;  # could be promoted to semantic when shipped
       */ideas/*) tier="working" ;;
       */research/*) tier="episodic" ;;
       *) tier="episodic" ;;
     esac

  3. STORE with tier as tag (not key prefix — keeps existing key scheme):
     $CF memory store \
       -k "knowledge:dimension:${doc_slug}:${section_slug}" \
       -v "$value" \
       --namespace knowledge \
       --tags "source:brana-knowledge,type:dimension,doc:${filename},tier:${tier}" \
       --upsert

  4. ORPHAN CLEANUP (new):
     List all knowledge:* keys in ruflo.
     Compare against actual ## sections on disk.
     Delete entries for removed/renamed sections.
     (Runs only on full reindex, not incremental)
```

**Dedup (separate periodic `claude -p` job, not on indexing hot path):**

```json
{
  "name": "knowledge-dedup",
  "schedule": "monthly 1st 04:00",
  "type": "skill",
  "prompt": "Search ruflo memory namespace 'knowledge'. For each pair of entries,
    call embeddings_compare. Flag pairs with >0.95 similarity. Report duplicates.
    Do not delete — just report for review.",
  "model": "haiku",
  "allowedTools": "mcp__ruflo__memory_search,mcp__ruflo__memory_list,mcp__ruflo__embeddings_compare",
  "timeout": 300
}
```

**Cross-references (deferred to t-823):**

`causal-edge` works via bridge-fallback (durable — writes to `memory_entries`). But cross-ref
extraction from `[[links]]` requires content parsing. Add when knowledge graph queries have
a consumer (currently nothing queries edges).

**What does NOT change:**
- Key scheme: `knowledge:dimension:{doc_slug}:{section_slug}` (same as today)
- Namespace: `knowledge` (same)
- `--upsert` idempotency (same)
- 5% error tolerance (same)
- Triggers: post-commit hook, weekly scheduler, manual (same)

**What `hierarchical-store` WOULD have enabled (deferred to t-823):**
- Real tier metadata (not just tags) → tier-specific recall queries
- Automatic promotion (episodic → semantic after confidence threshold)
- TTL-based expiry (working tier → 24h auto-purge)
- NightlyLearner consolidation across tiers

All of this becomes available when ruflo exports `HierarchicalMemory`. Until then, tiers
are advisory tags that consumers can filter on: `memory_search(namespace: "knowledge")` +
post-filter on `tier:semantic` tag.

**Effort:** S (shell script upgrade + scheduler config). Dedup job: S (separate).

---

### #8: pre-tool-use × file-based claims

> **Revised 2026-04-01** after challenger review (verdict: RECONSIDER).
> Original design had 3 critical bugs: cleanup/naming mismatch (100% orphan rate),
> empty SESSION_ID permanent lock, TOCTOU race. All fixed in revised design below.

**Problem now:** `pre-tool-use.sh` enforces spec-first and cascade throttle. No awareness
of other sessions. Two parallel sessions editing the same file = last write wins.

**Design decisions (from challenger):**
- **Advisory, not blocking** — warn, don't deny. Prevents frustration on shared files.
- **10-min TTL** — files unlock after inactivity, not held for entire session.
- **Atomic mkdir** — `mkdir` is atomic on Linux, prevents TOCTOU race.
- **Repo-relative paths** — worktrees hash correctly (same logical file = same hash).
- **No ruflo in hot path** — file-based only, <5ms overhead.

**Implementation:**

```bash
# pre-tool-use.sh — file claim block (new, before spec-first check)
# Guard: skip if no session ID
[ -z "$SESSION_ID" ] && exit 0

# Normalize to repo-relative path (worktree-safe)
REL_PATH="${FILE_PATH#"$GIT_ROOT/"}"
FILE_HASH=$(echo -n "$REL_PATH" | md5sum | cut -c1-16)  # match cascade convention
CLAIM_DIR="/tmp/brana-claims/${FILE_HASH}.lock"

if mkdir "$CLAIM_DIR" 2>/dev/null; then
  # Atomic claim acquired (no TOCTOU race)
  echo "$SESSION_ID" > "$CLAIM_DIR/owner"
  echo "$(date +%s)" > "$CLAIM_DIR/ts"
elif [ "$(cat "$CLAIM_DIR/owner" 2>/dev/null)" != "$SESSION_ID" ]; then
  # Different session holds this claim — check TTL
  CLAIM_TS=$(cat "$CLAIM_DIR/ts" 2>/dev/null || echo 0)
  NOW=$(date +%s)
  if [ $((NOW - CLAIM_TS)) -gt 600 ]; then
    # Stale (>10 min no edits) — take over
    echo "$SESSION_ID" > "$CLAIM_DIR/owner"
    echo "$NOW" > "$CLAIM_DIR/ts"
  else
    OWNER=$(cat "$CLAIM_DIR/owner" 2>/dev/null)
    # Advisory warning (don't deny — user might be editing different sections)
    echo "WARN: $REL_PATH claimed by session $OWNER ($((NOW - CLAIM_TS))s ago)"
  fi
else
  # Already owned by this session — refresh timestamp
  echo "$(date +%s)" > "$CLAIM_DIR/ts"
fi
```

**Session boundary hooks:**

```bash
# session-end.sh — release all claims for this session
find /tmp/brana-claims -name "owner" -exec grep -l "$SESSION_ID" {} \; 2>/dev/null | \
  while read f; do rm -rf "$(dirname "$f")"; done

# session-start.sh — detect stale claims (>1h, from crashed sessions)
find /tmp/brana-claims -name "ts" -mmin +60 2>/dev/null | \
  while read f; do
    STALE_OWNER=$(cat "$(dirname "$f")/owner" 2>/dev/null)
    echo "WARN: stale claim from session $STALE_OWNER — clearing"
    rm -rf "$(dirname "$f")"
  done
```

**Two claim systems, two scopes:**
- **File claims (#8, this):** per-file, advisory, 10-min TTL, shell-only, /tmp/brana-claims/
- **Task claims (#6B):** per-task, enforced, session-duration, ruflo MCP, `claims_claim/release`
- No sync needed between them — they solve different problems at different granularity.

**Wiring changes:**
- `system/hooks/pre-tool-use.sh`: add file claim block (above)
- `system/hooks/session-end.sh`: add claim cleanup
- `system/hooks/session-start.sh`: add stale claim detection
- New helper: `system/hooks/lib/file-claims.sh` — extracted functions for reuse

**Effort:** S. ~30 lines of bash across 3 hooks.

---

### #9: session-start — keep existing + stale claim cleanup

> **Revised 2026-04-01** after challenger review + additionalContext imperative test.
> Original: deferred flag file → first skill calls trajectory-start + hive-mind + session-start.
> Challenger found: additionalContext imperatives unreliable (tested — LLM treats system
> context as informational, not commands). `agentdb_session-start` redundant with existing
> `$CF memory search`. Trajectory tracking works as start+end pair in close (#10).
> Final: change almost nothing. The hook already works.

**What stays (existing hook, no changes):**

| Job | What | How |
|-----|------|-----|
| Job 1 | Pattern recall | `$CF memory search --namespace pattern` (durable, 4s timeout) |
| Job 2 | Correction patterns | `$CF memory search --namespace pattern type:correction` |
| Session state | Last session context | `$CF memory search --namespace session --limit 1` (fallback: `brana session read --json`) |
| Config drift | Detect stale configs | `config-drift.sh` |
| Task context | Active task injection | `tasks.json` query |

**What's new (XS effort):**

```bash
# session-start.sh — add stale file claim cleanup (from #8)
find /tmp/brana-claims -name "ts" -mmin +60 2>/dev/null | while read f; do
  rm -rf "$(dirname "$f")"
done
```

**What moved to other enrichments:**

| Feature | Moved to | Reason |
|---------|----------|--------|
| Trajectory start | **#10 close** | Start+end together works (verified: SONA learns, EWC consolidates, confidence assigned). No need for session-long trajectory — session summary is the learning unit. |
| Hive-mind announce | **Lazy init** — sitrep or build creates it on first run | additionalContext imperatives don't work (tested). Flag file + preamble overengineered for 1 call. |
| `agentdb_session-start` | **Dropped** | Redundant with `$CF memory search` the hook already does. Bridge-fallback returns same data. |

**Why not add MCP calls to session-start:**
1. Hook is shell — can't call MCP
2. `$CF` CLI doesn't return trajectory IDs (returns general status instead)
3. additionalContext imperatives unreliable (tested: system context ≠ commands to execute)
4. Flag file + skill preamble = overengineered for 1-2 calls across 15+ skills
5. Lazy init from sitrep/build/close is simpler and just as effective

**Effort:** XS — one `find` command for stale claim cleanup. Everything else stays or moves to #10.

---

### #10: close × session state to ruflo + hive-mind + claims release

> **Revised 2026-04-01** after challenger review (verdict: PROCEED WITH CHANGES).
> Original: trajectory start+end, dual-write patterns, replace brana session write.
> Challenger found: (C1) zero-step trajectory is pattern-store with overhead — dropped.
> (C2) Replacing local session state removes crash safety — keep local as primary.
> (W2) hooks_intelligence_pattern-store falls to bridge-fallback, not HNSW-indexed — dropped.
> Final: 3 additive MCP calls, keep everything that works, don't replace anything.

**Problem now:** Close skill stores patterns and session state. Works fine. But no
cross-session signaling, no task unlocking, no searchable session history.

**What stays unchanged:**

| Step | What | How |
|------|------|-----|
| Debrief | Extract learnings | Debrief-analyst agent (unchanged) |
| Patterns | Store learnings | `$CF memory store --namespace pattern` (primary, durable, HNSW-indexed) |
| Field notes | Archive observations | `$CF memory store --namespace field-notes` (unchanged) |
| Session state | Write local state | `brana session write` (primary, local, crash-safe, always works) |
| MEMORY.md | Critical patterns | Dual-write for confidence >= 0.8 (unchanged) |
| Session-end hook | Flywheel metrics | `$CF memory store` (crash-safe fallback) |

**What close gains (3 MCP calls, all additive):**

```
CLOSE SKILL — Step 7 (Session wrap) — 3 NEW CALLS:

  # 1. Session state to ruflo (SECONDARY — for searchability, not replacement)
  mcp__ruflo__memory_store(
    key: "session:{PROJECT}:{timestamp}",
    value: "{accomplished, learnings, next, metrics — full session state JSON}",
    namespace: "session",
    tags: ["client:{PROJECT}", "branch:{BRANCH}"],
    upsert: true
  )
  → Makes session history semantically searchable across sessions
  → brana session write (local JSON) remains primary read path
  → This is the searchable mirror for: memory_search(namespace: "session", query: "JWT auth")

  # 2. Cross-session close announcement (best-effort, transient)
  mcp__ruflo__hive-mind_memory(
    action: "set",
    key: "client:{PROJECT}:session:{SESSION_ID}",
    value: { status: "closed", summary: "...", next: [...] }
  )
  → Other terminals see session ended + what's next
  → Transient (in-memory, lost on MCP restart) — OK for session announcements

  # 3. Task claim release (guarded — only if task was claimed)
  if active_task exists:
    mcp__ruflo__claims_release(
      issueId: "task:{active_task}",
      claimant: "session:{SESSION_ID}"
    )
  → Unlocks task for other sessions
  → No-op if no task was claimed (guarded)
```

**What was dropped (with reasons):**

| Feature | Reason dropped | Future path |
|---------|---------------|-------------|
| Trajectory start+end | 0-step trajectory = pattern-store with overhead. SONA learns from intermediate steps, not from a summary string at the end. | Re-add when session-long trajectories are possible — needs a mechanism to start at session begin. See note below. |
| `hooks_intelligence_pattern-store` | Falls to bridge-fallback, not HNSW-indexed (`hnswIndexed: false`). `$CF memory store --namespace pattern` is more reliable. | Re-add when ruflo's ReasoningBank controller works end-to-end. |
| `agentdb_causal-edge` | Optional — works via bridge-fallback but no consumer queries edges yet. | Add when knowledge graph queries have a consumer (e.g., maintain-specs via MCP). |
| `agentdb_feedback` | Optional — works via bridge-fallback but no learning loop consumes it. | Add when model routing learning loop exists (#6C). |
| `agentdb_session-end` | Bridge-fallback → same as `memory_store`. Redundant. | Add when NightlyLearner consolidation works (t-823). |
| Replace `brana session write` | Removing local write removes crash safety. Ruflo dependency for session state is a regression. | Local stays primary. Ruflo is the searchable secondary. |

> **Future: session-long trajectory tracking.**
> SONA trajectories are valuable when they span a session: trajectory-start at begin,
> trajectory-step per accomplishment, trajectory-end at close. This requires starting
> the trajectory at session begin — currently blocked because:
> - Shell hooks can't call MCP (trajectory-start needs MCP)
> - `$CF` CLI doesn't return trajectory IDs
> - additionalContext imperatives are unreliable (tested)
>
> Possible future mechanisms:
> - CC plugin PostToolUse hook (runs in LLM context, could start trajectory on first tool call)
> - ruflo CLI adds `trajectory start --format json` that returns trajectoryId
> - CC adds a "first interaction" hook type that runs in LLM context
>
> Track: when any of these become available, re-enable trajectory-start in #9 and
> trajectory-end in #10. SONA will then learn from real session trajectories.

**Session-end hook additions (shell, crash-safe fallback):**

```bash
# session-end.sh — add to existing hook:

# 1. Session state to ruflo (backup, in case close skill didn't run)
$CF memory store -k "session:$PROJECT:$(date +%s)" \
  -v "$SUMMARY_JSON" --namespace session \
  --tags "client:$PROJECT,type:session-summary" --upsert

# 2. File claim cleanup (#8)
find /tmp/brana-claims -name "owner" -exec grep -l "$SESSION_ID" {} \; 2>/dev/null | \
  while read f; do rm -rf "$(dirname "$f")"; done
```

**Source of truth hierarchy:**
1. **Session state read:** `brana session read --json` (local, fast, always works)
2. **Session state search:** `memory_search(namespace: "session")` (cross-session, semantic)
3. **Pattern read:** `memory_search(namespace: "pattern")` (HNSW-indexed)
4. **Pattern search:** `hooks_intelligence_pattern-search` (HNSW+BM25 hybrid, reads same store)

**Wiring changes:**
- Close skill: add 3 MCP tools to allowed-tools (`memory_store`, `hive-mind_memory`,
  `claims_release`). Fold into existing Step 7 (session wrap).
- Session-end hook: add session state backup + file claim cleanup.

**Effort:** S (was M — reduced by dropping trajectory, dual-write, and state replacement).

---

## Cross-Cutting Wiring Observations

### Shell ↔ MCP gap

The recurring constraint: hooks run in shell, MCP tools only work in LLM context.

| Enrichment | Shell or LLM? | Resolution |
|------------|---------------|------------|
| #4 research | LLM (skill) | Direct MCP calls — no gap |
| #5 sitrep | LLM (skill) | Direct MCP calls — no gap |
| #6 execute | LLM (skill) | Direct MCP calls — no gap |
| #7 index | Shell (script) | Hybrid: shell parses → skill/CLI ingests |
| #8 pre-tool-use | Shell (hook) | File-based locks, sync with ruflo at session boundaries |
| #9 session-start | Shell (hook) | Deferred flag → first skill call does MCP |
| #10 close | LLM (skill) + Shell (hook) | Skill does MCP directly, hook does `$CF` fallback |

**Pattern:** Skills call MCP directly — no CLI intermediary. Hooks use `$CF` (shell, no choice). Hybrid components (#7, #10) split mechanical work (shell) from intelligent work (MCP).

### hooks_intelligence as the working pattern layer

> Discovered 2026-04-01: ruflo's `hooks_intelligence_*` tools bypass the broken agentdb
> bridge and provide a working pattern search, trajectory tracking, and SONA learning.
> Use these wherever the enrichment matrix originally specified `agentdb_pattern-search`.

| agentdb tool (broken/limited) | hooks_intelligence equivalent (works) |
|------------------------------|--------------------------------------|
| `agentdb_pattern-search` | `hooks_intelligence_pattern-search` — HNSW+BM25 hybrid, 26ms |
| `agentdb_pattern-store` | `hooks_intelligence_pattern-store` — HNSW-indexed |
| (no equivalent) | `hooks_intelligence_trajectory-start/step/end` — SONA learning |
| (no equivalent) | `hooks_intelligence_attention` — MoE/Flash/Hyperbolic similarity |
| (no equivalent) | `hooks_intelligence_learn` — force SONA cycle with EWC++ |
| (no equivalent) | `hooks_intelligence_stats` — learning health dashboard |

Use `hooks_intelligence_*` for pattern operations. Use `agentdb_*` for hierarchical tiers,
session management, batch, and causal edges.

### Tool budget per enrichment (updated 2026-04-01 — MCP direct, hooks_intelligence discovery)

| # | MCP tools (skill calls directly) | Shell fallback ($CF) | Added to |
|---|--------------------------------|---------------------|----------|
| 4 | memory_search(ns:all), hierarchical-recall, embeddings_compare, hierarchical-store | 4x $CF memory search | research skill |
| 5 | hooks_intelligence_pattern-search (Phase 1), hierarchical-recall (Phase 2) | skip | sitrep skill |
| 6 | hive-mind_init/shutdown, claims_claim/status, agent_spawn | — | backlog skill |
| 7 | hierarchical-store, embeddings_compare, hooks_intelligence_pattern-store | $CF memory store loop | index skill wrapper |
| 8 | (none — file-based locks) | — | pre-tool-use hook |
| 9 | session-start, hierarchical-recall, hooks_intelligence_trajectory-start | $CF memory search | session-start (hook=shell, first skill=MCP) |
| 10 | session-end, hierarchical-store, hooks_intelligence_trajectory-end | $CF memory store | close skill (MCP) + session-end hook (shell fallback) |

### Implementation order (revised from phased rollout)

Priority based on value/effort ratio:

1. **#9 + #10 (session loop)** — P2 effort, foundational. Every session starts learning and ends consolidating. All other enrichments benefit from trajectory tracking.
2. **#4 (research)** — P2 effort. Research is the most memory-intensive skill. Context-synthesize immediately improves recall quality.
3. **#5 (sitrep)** — P1 effort (just add 1 tool call). Quick win, high visibility.
4. **#7 (index-knowledge)** — P3 effort. Requires CLI changes + hybrid pipeline. But enables tiered recall for everything else.
5. **#8 (pre-tool-use claims)** — P2 effort. File-based approach is simple. Real value only when running parallel sessions.
6. **#6 (execute orchestration)** — P7 effort. Most complex, most dependencies. Implement last.

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

## Upstream-Blocked: Upgrade Path When ruvnet/ruflo#1492 Lands

> **Verified 2026-04-01 on ruflo@3.5.48.** 4 agentdb controllers are unimplemented upstream.
> Same pattern as ruvnet/ruflo#1216 (ExplainableRecall). Track #1492 for resolution.
> When these land, upgrade enrichments as follows:

### context-synthesize (ContextSynthesizer)

**Current workaround:** `memory_search(namespace: "all", limit: 15)` + LLM assembly.
**When available:** Swap to `context-synthesize(query, maxEntries: 15)` in:
- #4 research Phase 0 (replaces memory_search — gets pre-assembled narrative)
- #5 sitrep (add as optional Source 7 — synthesized project context)
- #9 session-start (richer than hierarchical-recall alone)

### pattern-search (ReasoningBank)

**Current workaround:** `memory_search(namespace: "patterns")` — no confidence filter, no BM25 hybrid.
**When available:** Add to:
- #4 research Phase 0 Call 3 (surfaces past research sessions with confidence scores)
- #5 sitrep (confidence-scored patterns in memory context section)
- #10 close (validate stored patterns against existing via confidence-aware dedup)

### batch (BatchOperations)

**Current workaround:** Loop `hierarchical-store` or `memory_store` individually.
**When available:** Swap loops to single `batch(operation: "insert", entries: [...])` in:
- #7 index-knowledge (10-50x speedup — 500 entries per call vs 1-by-1)
- #10 close bulk field-note archival

### causal-edge (CausalMemoryGraph bridge)

**Current workaround:** spec-graph.json for doc relationships. No task→learning links.
**When available:** Add to:
- #7 index-knowledge (doc cross-references as `relation: "references"`)
- #10 close Step 5 (task→learning links as `relation: "produced"`)
- Research (finding→source links as `relation: "sourced-from"`)
- Eventually: replace spec-graph.json edges entirely (after maintain-specs becomes a skill)

### feedback (LearningSystem)

**Current workaround:** None — feedback is no-op.
**When available:** Add to:
- #10 close Step 7 (`feedback(taskId, success, quality)` for session quality)
- #6 execute (`feedback` per completed subtask for model routing learning)
- Build skill (`feedback` after test pass/fail for TDD learning)

---

## CRITICAL: Tool Durability Matrix (verified 2026-04-01)

> `hierarchical-store` writes to an in-memory stub that vanishes on MCP restart.
> `HierarchicalMemory` and `MemoryConsolidation` are NOT exported from agentdb's index.js.
> The controller-registry falls back to `createTieredMemoryStub()` — a `Map` with keyword
> matching, no SQLite, no embeddings. Tracked: ruvnet/ruflo#1492, brana t-823.

| Tool | Durable? | Backend | Use for persistent data? |
|------|----------|---------|------------------------|
| `memory_store` / `memory_search` | **YES** | SQLite `memory_entries` + HNSW | **YES** — primary storage |
| `hooks_intelligence_pattern-store/search` | **YES** | Same SQLite via HNSW | **YES** — pattern operations |
| `embeddings_compare` | N/A | Stateless | **YES** — dedup utility |
| `session-start` / `session-end` | **YES** | Bridge fallback → `memory_store` | **YES** — via fallback |
| `causal-edge` | **YES** | Bridge fallback → `memory_store` | **YES** — via fallback |
| `feedback` | **YES** | Bridge fallback → `memory_store` | **YES** — via fallback |
| `hierarchical-store` / `hierarchical-recall` | **NO** | In-memory Map, lost on restart | **NO** — do not use |
| `context-synthesize` | **NO** | Reads from hierarchical (ephemeral) | **NO** — returns empty after restart |
| `agentdb_batch` (for knowledge) | **NO** | Writes to `episodes` table, not `memory_entries` | **NO** — wrong table |
| `agentdb_consolidate` | **NO** | Operates on empty stub | **NO** — no-op |

**Rule: Only use durable tools for persistent data. Use `memory_store` with namespace + tags
for organization. Use `hooks_intelligence_pattern-store` for pattern operations. Tier
classification goes in tags (`tier:semantic`), not in `hierarchical-store`.**

**Impact on enrichment matrix:**
- #5 (sitrep): `hierarchical-recall` → use `hooks_intelligence_pattern-search` instead (already revised)
- #7 (index): `hierarchical-store` → use `memory_store` with tier tags (Approach C)
- #9 (session-start): `session-start` works (bridge fallback). No `hierarchical-recall` for tier-specific recall.
- #10 (close): `hierarchical-store` for learnings → use `memory_store` with tier tags. `session-end` works (bridge fallback).
- #4 (research): `hierarchical-store` for leads → use `memory_store` with tier tags.

**When to re-check (t-823):** After ruflo upgrade, test: `hierarchical-store` → restart MCP →
`hierarchical-recall`. If data persists, re-enable hierarchical tiers across all enrichments.

---

## Open Questions

1. ~~Should spec-graph.json edges migrate entirely to ruflo causal_edges, or coexist?~~ **Answered:** Coexist initially. spec-graph.json is consumed by maintain-specs (shell context). Causal edges are for knowledge relationships (MCP context). Migrate spec-graph edges to ruflo causal_edges when maintain-specs becomes a skill (currently a command).
2. ~~Should `brana learn` be new Rust CLI subcommands, or extend existing `brana ops`?~~ **Answered:** New `brana learn` subcommand group. `ops` is operational health. `learn` is knowledge operations: `brana learn index`, `brana learn consolidate`, `brana learn export`. Keeps concerns separate.
3. ~~Which enrichment matrix combinations to implement first?~~ **Answered:** #9+#10 (session loop) → #4 (research) → #5 (sitrep) → #7 (index) → #8 (claims) → #6 (execute). See "Implementation order" in cross-cutting observations.
4. How to handle ruflo version upgrades (pin? test before update? migration path?)
5. **New:** Should `agentdb_session-start` be called from a deferred flag (Option B) or should we add CLI support for it? Deferred flag is simpler but adds a "first skill call" delay.
6. **New:** `agentdb_batch` doesn't accept a tier parameter. How do we handle tiered batch indexing? Key-prefix encoding (`knowledge:semantic:...`) is the current proposal — does ruflo's `hierarchical-recall` respect key prefixes, or does it need actual tier metadata?

---

## Phased Rollout (revised 2026-04-01 — durability-aware)

> Updated after discovering `hierarchical-store` is ephemeral. All phases now use only
> durable tools: `memory_store/search`, `hooks_intelligence_pattern-store/search`,
> `embeddings_compare`, bridge-fallback tools (session-end, causal-edge, feedback).
> Phases marked "after t-823" depend on ruflo exporting `HierarchicalMemory`.

| Phase | What | Enrichment # | Effort | Status |
|-------|------|-------------|--------|--------|
| P0 | Fix MCP server (wrapper script, correct DB, ESM patch) | — | S | ✅ Done |
| P1 | Index-knowledge upgrade: 7 doc categories, tier tags, orphan cleanup | #7 | S | Ready |
| P2 | Sitrep: add `hooks_intelligence_pattern-search` as Source 6 | #5 | S | Ready |
| P3 | Session loop: `session-start/end` (bridge fallback) + trajectory tracking | #9, #10 | M | Ready |
| P4 | Research adopts MCP: `memory_search(ns:all)` + dedup via `embeddings_compare` | #4 | M | Ready |
| P5 | Task claims: `claims_claim/release` for task-level locking across sessions | #6B | S | Ready |
| P6 | Hive-mind: cross-session blackboard for build progress + plan tracking | #6A | M | Ready |
| P7 | Model routing: `hooks_model-route` in build execute | #6C | S | Ready |
| P8 | Agent analytics: `agent_spawn` registry + trajectory tracking per subagent | #6C | S | After P3 |
| P9 | Coordination: `coordination_orchestrate` for skill pipeline formalization | #6D | M | After P3 |
| — | **After t-823 (ruflo exports HierarchicalMemory):** | | | |
| P10 | Tiered storage: migrate tier tags → real `hierarchical-store` tiers | #7, #9, #10 | M | After t-823 |
| P11 | Context synthesis: `context-synthesize` for research + sitrep | #4, #5 | S | After t-823 |
| P12 | Consolidation: NightlyLearner auto-promotion + decay + dedup | #10 | M | After t-823 |
