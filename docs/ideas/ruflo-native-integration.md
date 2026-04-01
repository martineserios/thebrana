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

### #5: sitrep × agentdb hierarchical-recall

**Problem now:** Sitrep reads from 5 local sources (TaskList, git, backlog CLI, session JSON, conversation). It has zero memory context — can't surface "you were debugging X last week" or "pattern Y from client Z might apply here." It's a status dump, not contextual awareness.

**With ruflo MCP:**

```
Source 6 — Memory Context (new, parallel with existing 5):

  Call 1: mcp__ruflo__agentdb_hierarchical-recall(
    query: "{BRANCH} {TASK_SUBJECT}",
    tier: "working",
    topK: 3
  )
  → Hot session patterns from current/recent sessions

  Call 2: mcp__ruflo__agentdb_hierarchical-recall(
    query: "{TASK_SUBJECT} {TASK_TAGS}",
    tier: "episodic",
    topK: 3
  )
  → Warm patterns from past sessions on similar work

  Call 3 (only if no active task): mcp__ruflo__agentdb_hierarchical-recall(
    query: "{PROJECT_NAME} recent work",
    tier: "episodic",
    topK: 5
  )
  → What was happening in this project recently?
```

**Data flow:**
- Working tier results → append to "Active context:" section (hot state)
- Episodic tier results → append to "Related patterns:" section (only if confidence > 0.5)
- Cross-client matches → note as "Similar pattern from {other_client}" (transferable only)

**Wiring changes to `system/skills/sitrep/SKILL.md`:**
- Add Source 6 block after Source 5, in parallel with Sources 1-5
- Output template gets new section:

```markdown
**Memory context:**
- [working] {hot pattern from current session}
- [episodic] {warm pattern, confidence: 0.7} — from {date}
- [cross-client] {transferable pattern from other project}
```

- Next action logic gains new rule: "If episodic tier surfaces a correction pattern relevant to current task, mention it: 'Note: past correction on this topic — {pattern}.'"
- Add `mcp__ruflo__agentdb_hierarchical-recall` to allowed-tools

**Fallback:** If MCP unavailable, skip Source 6 entirely. Sitrep works as today — local-only.

**Key constraint:** Sitrep is read-only and fast. Memory calls must not add >2s latency. 3 parallel calls with topK=3-5 should stay under 500ms given HNSW indexing.

---

### #6: backlog execute × agent spawn + hive-mind

**Problem now:** Backlog execute spawns CC Agent tools with string prompts. No coordination between agents — they can stomp files, duplicate work, or miss dependencies. Model routing is a simple cost log, not intelligent selection. No shared state during execution.

**With ruflo MCP:**

```
ORCHESTRATION FLOW (execute a phase with N tasks):

  Step 1 — Init coordination:
    mcp__ruflo__hive-mind_init(
      topology: "hierarchical",  // queen orchestrates workers
      queenId: "orchestrator"
    )

  Step 2 — Build DAG waves from blocked_by graph:
    Wave 0: tasks with no blockers
    Wave 1: tasks blocked only by Wave 0
    ... etc

  Step 3 — For each wave (sequential):
    For each task in wave (parallel):

      a. Claim files:
         mcp__ruflo__claims_claim(
           issueId: "{task-id}",
           claimant: "agent:{task-id}:worker",
           context: "Files: {file_list from spec}"
         )

      b. Spawn agent:
         mcp__ruflo__agent_spawn(
           agentType: "builder",
           task: "{task subject + description}",
           model: "inherit",  // or let ruflo route
           config: {
             worktree: true,
             protocol: "orient-test-implement-verify-commit-report",
             claimed_files: ["{file_list}"],
             timeout_ms: 600000
           }
         )
         → Note: actual execution still via CC Agent tool (ruflo agent_spawn
           provides model routing + registration, not CC subprocess spawning)

      c. CC Agent tool call (actual execution):
         Agent(
           prompt: "...",  // includes claimed files, spec, protocol
           isolation: "worktree",
           mode: "bypassPermissions"
         )

    Wait for all agents in wave to complete.

    d. For each completed agent:
       mcp__ruflo__claims_status(
         issueId: "{task-id}",
         status: "completed"
       )
       mcp__ruflo__agentdb_feedback(
         taskId: "{task-id}",
         success: {true/false},
         quality: {0-1 based on test pass rate},
         agent: "builder:{task-id}"
       )

  Step 4 — Merge worktrees (sequential, by wave order)

  Step 5 — Teardown:
    mcp__ruflo__hive-mind_shutdown()
```

**Key insight:** `agent_spawn` handles MODEL ROUTING and REGISTRATION (which agent is doing what). Actual code execution still goes through CC's `Agent` tool — ruflo doesn't spawn Claude Code subprocesses. The value is:
1. **Claims** prevent file conflicts between parallel agents
2. **Hive-mind** provides a shared memory blackboard during execution
3. **Feedback** records which task types succeed/fail for future routing
4. **Agent_spawn** routes to optimal model (haiku for simple, sonnet for moderate, opus for complex)

**Wiring changes:**
- `system/skills/backlog/SKILL.md` execute section: add orchestration flow above
- New file: `system/skills/backlog/execute-protocol.md` — the self-contained agent protocol (ORIENT→TEST→IMPLEMENT→VERIFY→COMMIT→REPORT)
- Add all claims, hive-mind, agent, and feedback tools to allowed-tools
- Keep existing single-agent fallback for tasks without specs or when ruflo unavailable

**Fallback:** If MCP unavailable, current behavior: spawn CC Agents without coordination. Log a warning.

**Phase dependency:** Requires P7 (hive-mind, claims, agent orchestration). This is the most complex enrichment — implement last.

---

### #7: index-knowledge × agentdb hierarchical-store + batch

**Problem now:** `index-knowledge.sh` stores every `##` section as a flat `memory_store` in the `knowledge` namespace. No tiers — a dimension doc section (curated, permanent) and a field note (transient) get the same treatment. No dedup — re-indexing stores duplicates. No cross-references between related sections.

**With ruflo MCP:**

```
TIERED INDEXING (replace index-knowledge.sh inner loop):

  For each document:
    1. Parse sections (## headers)
    2. Classify source type → tier:
       - brana-knowledge/dimensions/*.md → semantic (permanent, curated)
       - docs/architecture/*.md → semantic (permanent, specs)
       - docs/ideas/*.md → working (24h, speculative)
       - docs/research/*.md → episodic (90 days, findings)
       - Field notes (## Field Notes sections) → episodic

    3. For each section, dedup check:
       mcp__ruflo__embeddings_compare(
         text1: "{section_content}",
         text2: "{closest_existing_entry_value}"
       )
       → If similarity > 0.95: SKIP (duplicate)
       → If similarity 0.80-0.95: UPDATE existing entry (evolved content)
       → If similarity < 0.80: INSERT new entry

    4. Batch write (up to 500 per call):
       mcp__ruflo__agentdb_batch(
         operation: "insert",  // or "update"
         entries: [
           { key: "knowledge:{tier}:{doc_slug}:{section_slug}",
             value: "{section_content}" }
         ]
       )
       Note: agentdb_batch doesn't accept tier — so we encode tier in key prefix
       and use agentdb_hierarchical-store for individual writes when tier matters.

    5. Cross-references (new capability):
       For each internal link ([[doc#section]] or explicit cross-ref):
       mcp__ruflo__agentdb_causal-edge(
         sourceId: "knowledge:{source_doc}:{source_section}",
         targetId: "knowledge:{target_doc}:{target_section}",
         relation: "references",
         weight: 0.8
       )
```

**Batch vs individual trade-off:**
- `agentdb_batch` is fast (500/call) but doesn't support tier assignment
- `agentdb_hierarchical-store` supports tiers but is 1-by-1
- **Decision:** Use `agentdb_batch` for bulk insert/update (speed). Then a second pass with `agentdb_hierarchical-store` for tier promotion of semantic entries. Or: encode tier in key prefix (`knowledge:semantic:...`) and handle tier logic in recall queries.

**Key prefix convention:**
```
knowledge:semantic:{doc_slug}:{section_slug}  — dimension docs, ADRs, shipped specs
knowledge:episodic:{doc_slug}:{section_slug}  — research, field notes, in-progress specs
knowledge:working:{doc_slug}:{section_slug}   — idea docs, brainstorms
```

**Wiring changes:**
- Rewrite `system/scripts/index-knowledge.sh` to call MCP tools (requires the script to run in a context with MCP access — either via a skill wrapper or by adding MCP CLI support)
- **Problem:** Shell scripts can't call MCP tools directly. Options:
  1. Keep as shell script, use CLI (`$CF`) for batch operations (CLI doesn't support batch/hierarchical-store)
  2. Rewrite as skill step (LLM does the indexing via MCP calls)
  3. Add `brana learn index` CLI subcommand that wraps MCP batch operations
  4. **Best option:** Hybrid — shell script parses docs and outputs JSONL, then a skill step ingests via MCP batch. Parsing is mechanical (shell), storage is intelligent (MCP).

**Implementation plan:**
```
index-knowledge.sh (parser) → /tmp/knowledge-index.jsonl
  ↓
brana learn index --from /tmp/knowledge-index.jsonl (Rust CLI)
  ↓
  For each entry: $CF memory store ... (current)
  OR (future): MCP batch via skill invocation
```

**Fallback:** Current flat `memory_store` per section. Works, just less intelligent.

---

### #8: pre-tool-use × claims

**Problem now:** `pre-tool-use.sh` enforces spec-first and cascade throttle. It has no awareness of other sessions or agents editing the same repo. Two parallel sessions can edit the same file simultaneously — last write wins, work gets lost.

**With ruflo MCP:**

```
PRE-TOOL-USE FLOW (new block, before existing spec-first check):

  If tool == "Edit" or tool == "Write":
    file_path = extract from tool args

    # Check if file is claimed by another agent/session
    # Problem: pre-tool-use is a shell hook — can't call MCP directly
    # Solution: CLI wrapper that queries ruflo

    $CF claims status "$file_path" 2>/dev/null
    → If claimed by different session: DENY with message
    → If unclaimed: ALLOW (optionally auto-claim)
    → If claimed by THIS session: ALLOW

  SESSION_ID sourced from CLAUDE_SESSION_ID env var (set by session-start hook)
```

**Critical constraint:** Pre-tool-use hooks run in shell context. MCP tools are not available. This enrichment requires:
1. `ruflo` CLI to support `claims status <file>` (currently MCP-only)
2. OR: a sidecar process that bridges MCP claims to a local lock file
3. OR: use file-based locks (simpler, no ruflo dependency):
   ```bash
   LOCK="/tmp/brana-claims/${FILE_HASH}"
   if [ -f "$LOCK" ] && [ "$(cat $LOCK)" != "$SESSION_ID" ]; then
     echo "DENIED: file claimed by session $(cat $LOCK)"
     exit 1
   fi
   ```

**Recommended approach:** File-based locks for pre-tool-use (fast, no network). Ruflo claims for orchestrated execution (#6) where MCP is available. The two systems sync at session-start (load ruflo claims → local lock files) and session-end (flush local locks → ruflo claims release).

**Wiring changes:**
- `system/hooks/pre-tool-use.sh`: add file lock check before spec-first block
- `system/hooks/session-start.sh`: sync ruflo claims → local `/tmp/brana-claims/`
- `system/hooks/session-end.sh`: release all claims for this session
- New helper: `system/hooks/lib/file-claims.sh` — claim/check/release functions

**Data flow:**
```
session-start.sh:
  $CF claims list --claimant "session:$SESSION_ID" → /tmp/brana-claims/
  (or: query ruflo MCP via skill if available)

pre-tool-use.sh (on Edit/Write):
  source lib/file-claims.sh
  check_claim "$FILE_PATH" "$SESSION_ID"
  → ALLOW or DENY

session-end.sh:
  release_all_claims "$SESSION_ID"
  rm -f /tmp/brana-claims/$SESSION_ID-*
```

**Fallback:** If no lock files exist, allow all edits (current behavior). Claims are advisory, not blocking, for single-session use.

---

### #9: session-start × agentdb session-start

**Problem now:** Session-start hook runs 2 parallel `$CF memory search` calls (patterns + corrections) and injects results as `additionalContext`. It's a flat keyword search — no tier awareness, no trajectory replay, no learning priming. Corrections are filtered by confidence >= 0.8 but there's no episodic replay of "what happened last time you worked on this."

**With ruflo MCP:**

```
SESSION-START FLOW (replace Job 1 + Job 2 with MCP calls):

  # Primary: ReflexionMemory replay (replaces both CLI searches)
  mcp__ruflo__agentdb_session-start(
    sessionId: "$SESSION_ID",
    context: "project:$PROJECT branch:$BRANCH task:$ACTIVE_TASK"
  )
  → Returns: {
      patterns: [...],          // relevant patterns from past sessions
      corrections: [...],       // high-confidence corrections
      reflections: [...],       // episodic memories from similar work
      trajectory: { ... }       // SONA trajectory initialized
    }

  # Secondary: tier-specific recall for enriched context
  mcp__ruflo__agentdb_hierarchical-recall(
    query: "$ACTIVE_TASK $BRANCH",
    tier: "working",
    topK: 3
  )
  → Hot state from interrupted sessions (stashed work, partial builds)
```

**Key difference from current:**
- Current: 2 flat searches → list of entries → inject top 3 as text
- New: 1 structured call → returns categorized patterns + initialized trajectory
- Trajectory init means: every tool call this session can be recorded as a step, building a learning path that `session-end` can analyze

**Integration with existing hook:**

```bash
# session-start.sh changes:

# PHASE 1: Parallel jobs
# Job 1 (REPLACE): Pattern + correction recall via MCP
#   Problem: hook is shell, can't call MCP
#   Solution: Use $CF CLI as bridge, OR move recall to skill context

# Option A: CLI bridge (if ruflo CLI adds session-start subcommand)
RECALL=$($CF agentdb session-start \
  --session "$SESSION_ID" \
  --context "project:$PROJECT branch:$BRANCH" \
  --format json 2>/dev/null)

# Option B: Deferred to skill context
# Hook sets a flag, session-start skill step does the MCP call
echo '{"needs_reflexion": true, "session_id": "'$SESSION_ID'"}' \
  > /tmp/brana-session-start-$SESSION_ID.json
# The first skill invocation checks this flag and calls agentdb_session-start
```

**Recommended approach:** Option B (deferred). Hooks stay fast (shell). The first skill invocation in the session (or sitrep) detects the flag and calls `agentdb_session-start` via MCP. This is cleaner because:
1. Hooks shouldn't block on network calls
2. MCP context is available in skills, not hooks
3. The trajectory ID needs to persist into the LLM context anyway

**Wiring changes:**
- `system/hooks/session-start.sh`: keep existing CLI searches as fallback. Add flag file for deferred MCP call.
- New rule or skill preamble: "If `/tmp/brana-session-start-$SESSION_ID.json` exists, call `agentdb_session-start` before first task."
- Trajectory ID stored in session state: `brana session write --field trajectory_id "$TRAJ_ID"`

**Fallback:** Current CLI searches. ReflexionMemory is additive — its absence means less context, not broken sessions.

---

### #10: close × agentdb session-end

**Problem now:** Close skill stores patterns via `$CF memory store` with flat confidence (0.5). No automatic promotion, no decay, no consolidation. Old patterns accumulate forever. The session-end hook stores a session summary + flywheel metrics but doesn't trigger any learning pipeline.

**With ruflo MCP:**

```
CLOSE SKILL — Step 5 (Store learnings) ENRICHMENT:

  For each learning extracted by debrief-analyst:

    # Store with tier-awareness (replaces flat $CF memory store)
    mcp__ruflo__agentdb_hierarchical-store(
      key: "pattern:{PROJECT}:{short-title}",
      value: '{"problem":"...","solution":"...","confidence":0.5,
               "transferable":false,"correction_weight":0}',
      tier: "episodic"  // new learnings start episodic, not flat
    )

    # Record causal edge: learning ← task that produced it
    mcp__ruflo__agentdb_causal-edge(
      sourceId: "{task-id}",
      targetId: "pattern:{PROJECT}:{short-title}",
      relation: "produced",
      weight: 0.7
    )

CLOSE SKILL — Step 7 (Session wrap) ENRICHMENT:

  # End the SONA trajectory (started at session-start)
  # This triggers NightlyLearner consolidation:
  #   - Patterns recalled AND used this session: confidence +0.1
  #   - Patterns recalled but ignored: confidence -0.05
  #   - Episodic patterns with confidence > 0.8 + recall_count > 5: promote to semantic
  #   - Episodic patterns with confidence < 0.2: archive
  #   - Working tier entries older than 24h: purge

  mcp__ruflo__agentdb_session-end(
    sessionId: "$SESSION_ID",
    summary: "{session_label}: {accomplished_summary}",
    tasksCompleted: {count}
  )

  # Record session quality for model routing learning
  mcp__ruflo__agentdb_feedback(
    taskId: "session:$SESSION_ID",
    success: {overall_success},
    quality: {1.0 - correction_rate},  // fewer corrections = higher quality
    agent: "brana:$PROJECT"
  )
```

**Consolidation effects (automatic, triggered by session-end):**

```
NightlyLearner (ruflo internal, triggered by agentdb_session-end):
  1. Scan episodic tier for promotion candidates:
     - confidence > 0.8 AND recall_count > 5 → promote to semantic
  2. Apply weekly decay to all episodic entries:
     - confidence *= 0.95
  3. Archive stale entries:
     - episodic with confidence < 0.2 → archive
  4. Compress old trajectories:
     - Trajectories older than 30 days → summarize and store as single entry
  5. Dedup check:
     - embeddings_compare across recent entries → merge if > 0.95 similarity
```

**Wiring changes to existing components:**

Session-end hook (`system/hooks/session-end.sh`):
- Keep: session summary + flywheel storage via CLI (fallback)
- Add: call `agentdb_session-end` via CLI if available (`$CF agentdb session-end --session ...`)
- Add: call `agentdb_feedback` for session quality

Close skill (`system/skills/close/SKILL.md`):
- Step 5: replace `$CF memory store` with `agentdb_hierarchical-store(tier: "episodic")`
- Step 5: add `agentdb_causal-edge` for task→learning links
- Step 7: add `agentdb_session-end` call
- Step 7: add `agentdb_feedback` call
- Add all 4 tools to allowed-tools

**Dual-write maintained:** Close still writes critical patterns to MEMORY.md (confidence >= 0.8, directive/convention). NightlyLearner handles the long tail — patterns that need time to prove themselves.

**Fallback:** Current `$CF memory store` + session-end hook behavior. NightlyLearner just doesn't run — manual `brana learn consolidate` would be needed (but nobody runs it anyway, which is the whole point of automating it).

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
| #10 close | LLM (skill) + Shell (hook) | Skill does MCP, hook does CLI fallback |

**Pattern:** Skills (#4, #5, #6) get full MCP access natively. Hooks (#8, #9) need bridging strategies (file flags, lock files). Hybrid components (#7, #10) split mechanical work (shell) from intelligent work (MCP).

### Tool budget per enrichment (updated 2026-04-01 — working tools only)

| # | Tools (works now) | Deferred (upstream-blocked) | Added to |
|---|-------------------|---------------------------|----------|
| 4 | memory_search, hierarchical-recall, embeddings_compare, hierarchical-store | context-synthesize, pattern-search | research skill |
| 5 | hierarchical-recall | pattern-search | sitrep skill |
| 6 | hive-mind_init/shutdown, claims_claim/status, agent_spawn | feedback | backlog skill |
| 7 | hierarchical-store, embeddings_compare | batch, causal-edge | index script + skill wrapper |
| 8 | (none — file-based) | — | pre-tool-use hook |
| 9 | session-start, hierarchical-recall | — | session-start hook/skill |
| 10 | session-end, hierarchical-store | causal-edge, feedback | close skill + session-end hook |

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

## Open Questions

1. ~~Should spec-graph.json edges migrate entirely to ruflo causal_edges, or coexist?~~ **Answered:** Coexist initially. spec-graph.json is consumed by maintain-specs (shell context). Causal edges are for knowledge relationships (MCP context). Migrate spec-graph edges to ruflo causal_edges when maintain-specs becomes a skill (currently a command).
2. ~~Should `brana learn` be new Rust CLI subcommands, or extend existing `brana ops`?~~ **Answered:** New `brana learn` subcommand group. `ops` is operational health. `learn` is knowledge operations: `brana learn index`, `brana learn consolidate`, `brana learn export`. Keeps concerns separate.
3. ~~Which enrichment matrix combinations to implement first?~~ **Answered:** #9+#10 (session loop) → #4 (research) → #5 (sitrep) → #7 (index) → #8 (claims) → #6 (execute). See "Implementation order" in cross-cutting observations.
4. How to handle ruflo version upgrades (pin? test before update? migration path?)
5. **New:** Should `agentdb_session-start` be called from a deferred flag (Option B) or should we add CLI support for it? Deferred flag is simpler but adds a "first skill call" delay.
6. **New:** `agentdb_batch` doesn't accept a tier parameter. How do we handle tiered batch indexing? Key-prefix encoding (`knowledge:semantic:...`) is the current proposal — does ruflo's `hierarchical-recall` respect key prefixes, or does it need actual tier metadata?

---

## Phased Rollout (revised)

| Phase | What | Enrichment # | Effort | Dependencies |
|-------|------|-------------|--------|--------------|
| P0 | Fix MCP server (wrapper script, correct DB) | — | S | ✅ Done |
| P1 | Session loop: agentdb session-start/end in close + session hooks | #9, #10 | M | P0 |
| P2 | Research adopts MCP: context-synthesize + pattern-search | #4 | M | P0 |
| P3 | Sitrep gains memory context: hierarchical-recall | #5 | S | P0 |
| P4 | `brana learn` CLI subcommands (index, consolidate, export) | #7 (partial) | M | P0 |
| P5 | Tiered knowledge indexing: hierarchical-store + batch + dedup | #7 (full) | M | P4 |
| P6 | Causal graph: causal-edge for doc cross-refs + task→learning links | #7, #10 | M | P5 |
| P7 | File claims for pre-tool-use: local lock files + ruflo sync | #8 | S | P1 |
| P8 | Cross-client pollination: tier-aware recall with transferable filter | — | M | P5 |
| P9 | Execute orchestration: hive-mind + claims + agent spawn + feedback | #6 | L | P7, P8 |
