---
title: brana v2 Compute Model — Layered Execution Stack
status: shaped
created: 2026-05-22
supersedes:
  - docs/ideas/brana-efficiency-without-power-loss.md
  - docs/ideas/claude-gemini-orchestration.md
  - t-1586 (Ruflo Multi-Agent Integration phase)
---

# brana v2 Compute Model

> Three workstreams — efficiency tuning, Gemini delegation, Ruflo multi-agent — were
> designed independently. They are one initiative. They all attack the same constraint:
> brana runs on a single compute source (Claude's token pool, serial execution).
> Together they define a layered execution stack.

## The Problem

- All work runs on Claude's token pool, serially
- Close always spawns Opus regardless of session depth
- Sub-agents (Agent()) spawn without cost tracking or ownership
- Governance on M+ decisions uses a single challenger voice
- Two parallel sessions have no coordination or visibility into each other
- Gemini tokens go unused while Claude handles bulk, repetitive, brana-agnostic work
- Ruflo and Gemini are designed as separate, non-interacting workers

## The Stack

```
┌──────────────────────────────────────────────────────────────────┐
│                          CLAUDE                                  │
│          orchestrates · judges · writes to repo                  │
│          the only entity that touches brana system               │
│                                                                  │
│   ┌──────────────────────────┐      ┌──────────────────────────┐ │
│   │          RUFLO           │      │         GEMINI           │ │
│   │  coordinates Claude      │      │  stateless worker        │ │
│   │  sub-agents              │      │  /tmp/ only              │ │
│   │                          │      │                          │ │
│   │  claims · hive-mind      │      │  brana-agnostic tasks    │ │
│   │  autopilot · memory      │      │  atomic · fire-forget    │ │
│   └──────────────────────────┘      └──────────────────────────┘ │
│            ▲                                    ▲                 │
│            │ Claude reads/writes                │ Claude dispatches│
│            │ (always mediated)                  │ and reads result │
└────────────┼────────────────────────────────────┼─────────────────┘
             │                                    │
             └──── no direct connection ──────────┘
                   Claude is the only bridge
```

**Key relationship:** Ruflo and Gemini do not interact directly. Claude is always the
bridge. Ruflo enriches before Gemini executes; Gemini output is stored back to Ruflo
after Claude reads and validates it.

## The Ruflo–Gemini Pipeline

Ruflo and Gemini are complementary, not overlapping. They form a pipeline:

```
ENRICH  → ruflo memory_search(smart:true) builds context file
           brana patterns, client conventions, prior findings

EXECUTE → agy -p /tmp/context.md → /tmp/result.md
           Gemini runs the task enriched by ruflo knowledge

APPLY   → Claude reads /tmp/result.md
           Claude uses Write/Edit to land anything in the repo
           All CC hooks fire normally

PERSIST → Claude calls ruflo pattern_store(tags:["source:agy-delegation"])
           Findings enter knowledge base
           Future ENRICH calls retrieve them
```

**Compounding loop:** each delegation cycle makes the next one better.
Gemini's output teaches future Gemini calls via ruflo.

## Routing Hierarchy

The single question every step asks: **who runs this?**

```
Is this brana-system work?
(git, hooks, tasks.json, architecture decisions, anything in system/)
  YES → Claude only. Never delegate.

  NO — Is it atomic, system-isolated, context-enrichable?
    NO  → Claude only (needs in-session state or multi-step)

    YES — Is it convention-sensitive?
          Known types: boilerplate generation, test scaffolding, ADR drafts,
          naming/structure decisions, any output that will be applied to the repo
          and must match codebase conventions to be correct.
          DEFAULT: when in doubt → treat as convention-sensitive.
          A false positive (non-sensitive task aborts when ruflo is down) is
          acceptable — the fallback is "use Claude directly."
          A false negative (convention-sensitive task routes to unenriched Gemini)
          silently produces convention-violating output. Bias toward caution.

      YES — Is ruflo available?
        NO  → ABORT. Error: "ruflo required for convention-sensitive task —
               use Claude directly." Do not fall back to unenriched Gemini.
        YES → Gemini (agy_delegate) with ENRICH step mandatory.
               Enriched by ruflo. Output to /tmp/. Claude applies.

      NO  — Is it a sub-agent needing cost tracking / ownership?
        YES → ruflo agent_spawn (coordination substrate)
              Claims ownership. Queryable per-project ledger.

        NO  — Is it parallel, bulk, or token-heavy for Claude?
          YES → Gemini (agy_delegate)
                ENRICH step optional (ruflo-down → proceed with warning).
                Output to /tmp/. Claude applies.

          NO  → Claude inline
```

## Hard Constraints

```
NEVER:
  Gemini writes to ruflo directly
  Gemini writes to repo paths directly
  Ruflo coordinates Gemini as a peer agent
  Gemini participates in hive-mind quorum
  Gemini calls brana CLI
  agy touches tasks.json

ALWAYS:
  Gemini output → /tmp/ only
  Claude mediates all ruflo writes after Gemini executes
  Hive-mind quorum workers → Claude only (require brana judgment)
  Claude is the only entity that dispatches Gemini — Ruflo never calls agy directly
```

## Confirmed Architecture Decisions (ADR input)

1. **Claude is the only system writer.** Git, tasks.json, hooks, ruflo stores — all go
   through Claude after reading agy output.

2. **Ruflo coordinates Claude sub-agents only.** agent_spawn, claims, hive-mind are
   Claude-to-Claude primitives. Gemini is dispatch-only — fire-and-forget.

3. **Gemini is dispatched, never coordinated.** agy is stateless (no session ID, no
   resume). It cannot hold claims, report mid-task status, or join hive-mind.

4. **Hive-mind quorum = Claude workers only.** Quorum requires brana ADR context and
   in-session judgment. Gemini doesn't have either.

5. **/tmp/ invariant is absolute.** MCP server hardcodes /tmp/ output. Callers cannot
   override.

6. **Efficiency: Sonnet for debrief-analyst.** Debrief is structured extraction, not
   open-ended reasoning. Opus earns its cost for adversarial review and architecture
   design only.

7. **Weight-adaptive close.** `[NOT YET IMPLEMENTED — Phase 0]`
   LIGHT mode runs inline (no agent spawn). FULL mode spawns
   debrief-analyst on Sonnet. Classification is based on git diff --stat output.

   FULL triggers when ANY of these conditions are true:
   - ≥2 commits in the session, OR
   - Any changed file matches: `.rs .ts .tsx .js .jsx .py .sh .toml .yaml .yml`, OR
   - Any `.json` file under `system/` or `.claude/` (behavioral config)

   LIGHT when ALL changed files are:
   - `.md`, OR
   - `state/*.json` or `tasks.json` (state files, not config), OR
   - `inbox/` (transient drop folder)

   Ambiguous cases resolved explicitly: `.sh` hook edits → FULL (behavioral, high-stakes).
   `tasks.json` only → LIGHT (state). `settings.json` → FULL (behavioral config).
   The extension list is committed to code in `close.md`, not inferred from prose.
   Tests must cover all three ambiguous cases before Phase 0 is marked done.

## Build Phases

Ordered by dependency and risk. Phases 0–1 unblock everything else.

### Phase 0 — Efficiency Quick Wins
**Effort:** 2 × S · **Blockers:** none · **Ships independently**

| Task | File | Change |
|------|------|--------|
| debrief-analyst opus → sonnet | `system/agents/debrief-analyst.md` line 5 + both CLAUDE.md agents tables | 3-line edit — all three in same commit or sitrep reports show model mismatch |
| Weight-adaptive close | `system/procedures/close.md` Step 1 | Branch after git log/diff using explicit extension list (see decision 7) |

Escape hatches: `/brana:close --light` forces light mode, `/brana:close --full` forces full.
Tests required before done: `.sh` edit → FULL, `tasks.json` only → LIGHT, `settings.json` → FULL.

**Implementation stub for close.md Step 1** (insert after the existing git log + git diff
commands, before the "both empty → minimal handoff" check):

```bash
# Weight classification — do not use --stat (gives line counts, not extensions)
CHANGED_FILES=$(git diff --name-only HEAD~"$COMMIT_COUNT"..HEAD 2>/dev/null)

# Check for --light / --full escape hatches first
if [[ "$*" == *"--light"* ]]; then CLOSE_MODE="LIGHT"
elif [[ "$*" == *"--full"* ]]; then CLOSE_MODE="FULL"
# FULL if ≥2 commits
elif [[ "$COMMIT_COUNT" -ge 2 ]]; then CLOSE_MODE="FULL"
# FULL if any code/behavioral file changed
elif echo "$CHANGED_FILES" | grep -qE '\.(rs|ts|tsx|js|jsx|py|sh|toml|yaml|yml)$'; then CLOSE_MODE="FULL"
elif echo "$CHANGED_FILES" | grep -qE '^(system|\.claude)/.*\.json$'; then CLOSE_MODE="FULL"
# Otherwise LIGHT
else CLOSE_MODE="LIGHT"
fi
```

Key: use `git diff --name-only`, not `--stat`. `--stat` outputs `N insertions` per file —
extension extraction from stat output requires fragile parsing. `--name-only` gives one
filepath per line, directly greppable.

---

### Phase 1 — ADR + Unified Routing Rule
**Effort:** 2 × S · **Blockers:** none · **Gates Phases 2–6**

| Task | Output |
|------|--------|
| ADR: "brana compute hierarchy" | `docs/architecture/decisions/ADR-0XX-compute-hierarchy.md` |
| Update `delegation-routing.md` | Unified 4-question heuristic + routing table covering all three tiers |

ADR must lock all 7 confirmed decisions above before any delegation wiring lands.

---

### Phase 2 — Ruflo Wiring Layer
**Effort:** S each · **Blockers:** Phase 1 · **Corresponds to t-1587 subtasks**

| ID | Task | Blocker |
|----|------|---------|
| t-1589 | Calibrate memory dedup threshold | — |
| t-1588 | Wire claims in close + backlog start | — |
| t-1590 | Add memory dedup gate to close + build | t-1589 |
| t-1591 | Sitrep: autopilot_predict shadow + memory_search_unified | — |
| t-1592 | Sitrep: claims_board snapshot (source 7) | — |
| t-1593 | Two-session claims coordination smoke test | t-1588, t-1592 |

**Failure modes — two cases, not one:**

- **Coordination calls** (claims_claim, claims_release, claims_board, memory dedup,
  sitrep signals) → Ruflo down: skip silently, fall back to current behavior. These
  calls improve visibility and quality but do not gate correctness.

- **ENRICH step on convention-sensitive tasks** (boilerplate, test scaffolding, ADR
  drafts — any task marked ⚠️ in the routing tree) → Ruflo down: abort with explicit
  error. Do not proceed with unenriched Gemini. Convention-violating output silently
  applied to the repo is worse than no output. This rule takes precedence over any
  "skip silently" default anywhere in the system.

---

### Phase 3 — Gemini Layer B + C
**Effort:** M · **Blockers:** Phase 1 · **Corresponds to t-1576, t-1577, t-1584**

| Step | Task | Output |
|------|------|--------|
| 3a | Add `agy_delegate` to brana-mcp Rust crate | `system/cli/rust/crates/brana-mcp/src/tools/agy_delegate.rs` |
| 3b | Build `/brana:gemini` skill (Layer C, foreground v1) | `system/skills/gemini/SKILL.md` |
| 3c | Rules update | `delegation-routing.md`, `git-discipline.md`, `cwd-discipline.md` |

Note: Layer A (Bash `agy -p`) is already usable today. Phases 3a–3c add the typed
contract and full lifecycle.

---

### Phase 4 — Ruflo–Gemini Pipeline
**Effort:** S · **Blockers:** Phase 2 + Phase 3 · **New — from this session**

| Task | Change |
|------|--------|
| Add ENRICH step to `/brana:gemini` | Before agy call: `ruflo memory_search(smart:true)` → context written to `/tmp/context-{ts}.md`, merged into agy prompt |
| Add PERSIST step to `/brana:gemini` | After APPLY: Claude calls `ruflo pattern_store(tags:["source:agy-delegation"])` — tag is for audit only, not retrieval routing; smart:true does not filter by tag |
| Compounding loop validation | Quality comparison test — not retrieval presence (see below) |

This closes the loop. Without this phase, Ruflo and Gemini remain parallel but isolated.
With it, each Gemini delegation enriches future ones.

**Compounding loop validation protocol** (must pass before Phase 4 is marked done):

0. **Retrieval gate** (prerequisite — run before quality comparison):
   Run 3 seeding delegations with ENRICH enabled (any representative tasks).
   Then call `memory_search(query: <test task description>, threshold: 0.6, limit: 3)`.
   If zero results returned → loop is already broken. Phase 4 does not ship.
   Stop here — do not proceed to steps 1–6. The embedding distance is too large for
   the loop to compound; investigate PERSIST tagging or ruflo index configuration first.

1. Pick one repeatable task type (e.g. "summarize competitor API docs into scorecard").
2. Run it 3× using **Layer A directly** (`agy -p "<task description>"`) — before ENRICH
   is wired. This is the unenriched control group. No `--no-enrich` flag needed.
   Record outputs. (This step must run before step 4 in the Phase 4 build sequence.)
3. Wire ENRICH + PERSIST (the Phase 4 tasks). Run 3 seeding delegations via
   `/brana:gemini` to build up ruflo context.
4. Run the same task 3× via `/brana:gemini` with ENRICH now live. Record outputs.
5. Score all 6 outputs on three criteria (0–2 each): brana convention alignment,
   specificity to project context, absence of generic filler.
6. Pass condition: ENRICH-enabled group mean ≥ ENRICH-disabled group mean + 1 point.
   If not met, Phase 4 does not ship — the loop does not compound.

Confirming that prior outputs appear in retrieval results is not validation. Ruflo can
retrieve stale or irrelevant results and the retrieval check still passes. The quality
comparison across the two group means is the only falsifiable test of the compounding claim.

---

### Phase 5 — Agent Cost Attribution + Hive-Mind
**Effort:** M · **Blockers:** Phase 1 · **Corresponds to t-1594 subtasks**

| ID | Task |
|----|------|
| t-1595 | Replace Agent() with agent_spawn in brainstorm scouts |
| t-1596 | Replace Agent() with agent_spawn in review metrics-collector |
| t-1597 | Replace Agent() with agent_spawn in build subtask delegation |
| t-1598 | agent_spawn cost attribution smoke test |
| t-1599 | Hive-mind quorum calibration (baseline vs single challenger, 10 real plans) |
| t-1600 | Wire 3-worker quorum into brainstorm M+ governance gate |
| t-1601 | Wire 3-worker quorum into brana:challenger |
| t-1638 | [adr] Write + merge quorum ADR from t-1599 calibration data · **blocked_by t-1599** |

**t-1599 must define pass/fail criteria before the run starts** (ADR blocked_by this):

- **Agreement rate** *(initial: 2/3 workers align on verdict)*  
  If 3-way split → escalate to user, don't auto-proceed.
- **Latency budget** *(initial: ≤2× single-challenger wall time)*  
  Above this → not viable for M+ governance gate.
- **Failure condition** *(initial: <7/10 plans reach quorum agreement → downgrade)*  
  Downgrade = revert to single-challenger + file task to investigate worker prompt quality.

These are starting thresholds, not locked values. After t-1599 runs, revised thresholds
land in t-1638 (the quorum ADR) — that is the update mechanism. If data challenges a
threshold, update it in the ADR draft before merging. The spec thresholds above are
the pre-run baseline only; the ADR is the authoritative post-run record.

---

### Phase 6 — Swarm Orchestration
**Effort:** L · **Blockers:** Phase 5 validated (see below) · **Corresponds to t-1602 subtasks**

**"Phase 5 validated" definition — all three must be true:**
1. t-1599 calibration passed: ≥7/10 plans reached quorum agreement within the latency budget
2. t-1600 + t-1601 wired and smoke-tested on at least one real M+ brainstorm session
3. t-1638 (quorum ADR) written and merged to main — this is the explicit gate task

If any of these three is false, Phase 6 does not start. The gate is outcome-based,
not temporal — completing Phase 5 tasks is not sufficient.

| ID | Task |
|----|------|
| t-1603 | Wire swarm_init + coordination_orchestrate into backlog execute |
| t-1604 | Wire claims_* per task in backlog execute waves |
| t-1605 | Add daa_agent_create persistent roles (anita-architect, brana-challenger) |
| t-1606 | Wire autopilot_learn at build CLOSE + fix COMMIT |
| t-1607 | Add agent_pool check in backlog start for background delegation · **blocked_by t-1507** |

---

## What Changes Per Workflow

### `/brana:close`
```
BEFORE: always Opus debrief-analyst
AFTER:
  light session (docs/state only, ≤1 commit) → inline summary, no agent
  deep session  (code edits or ≥2 commits)   → Sonnet debrief-analyst
  both:  claims_release + memory dedup gate
```

### `/brana:brainstorm` M+
```
BEFORE: serial Agent() scouts + single challenger
AFTER:
  LOAD     → memory_search(smart:true)
  SCOUTS   → ruflo agent_spawn (parallel, cost-tracked)
  RESEARCH → agy_delegate for bulk/brana-agnostic summaries (enriched by ruflo)
  GOVERN   → hive-mind 3-worker quorum
  PERSIST  → autopilot_learn records outcome
```

### `/brana:sitrep`
```
BEFORE: no cross-session visibility
AFTER:
  source 7: claims_board → in-flight tasks with session ownership
  source 8: autopilot_predict → next likely task (shadow mode first)
```

### Two sessions running simultaneously
```
BEFORE: no coordination, potential tasks.json conflicts
AFTER:
  Session A: claims_claim(t-NNN) → visible in claims_board
  Session B: claims_claim(t-MMM) → visible in claims_board
  Either session's sitrep shows both, with owners
  agy output → /tmp/ always, Claude applies, no race condition
```

## Delta: What's New vs Existing Backlog

| Status | Items |
|--------|-------|
| **Existing, keep** | t-1586..t-1607 (Phases 2, 5, 6) |
| **Existing, keep** | t-1576, t-1577, t-1584 (Phase 3) |
| **New tasks needed** | Phase 0: 2 efficiency tasks |
| **New tasks needed** | Phase 1: ADR + delegation-routing.md update |
| **New tasks needed** | Phase 4: ENRICH + PERSIST wiring + loop validation (3 tasks) |
| **Superseded ideas** | `brana-efficiency-without-power-loss.md` → absorbed here |
| **Superseded ideas** | `claude-gemini-orchestration.md` → absorbed here (detail preserved) |

## Engineering Disciplines

- **DDD:** ADR (Phase 1) gates all implementation. Write from confirmed decisions above.
- **TDD:**
  - `agy_delegate` unit tests: /tmp/ path enforcement, timeout handling, malformed
    output detection, error on non-zero exit.
  - `agy_delegate` **integration test** (required, not optional): run the real MCP
    server, invoke `agy_delegate` with a minimal prompt, assert the JSON-RPC response
    envelope contains no agy stdout bleed. A unit test mocking the subprocess does not
    catch the actual contamination path — only a live MCP server invocation does.
  - Close weight-adaptive gate: unit tests covering all three ambiguous extension cases
    (.sh → FULL, tasks.json only → LIGHT, settings.json → FULL).
  - Hive-mind quorum calibration (t-1599) — see Warning 3 criteria.
- **SDD:** `docs/architecture/features/brana-v2-compute-model.md` as the living spec.
  Update `agent-interaction-architecture.md` to reference this as the current shape.
- **Docs:** Update `delegation-routing.md` (unified). No user-facing docs — internal
  system feature.

## Prerequisites Not Blocking v1

- **t-1507** (atomic tasks.json write) — blocks t-1607 (Phase 6). Two distinct risks:
  - *File corruption* (partial writes under concurrent access) — covered by t-1507's
    atomic temp+rename fix to `save_tasks`.
  - *Lost update* (two agents read same state, both modify, one overwrites the other) —
    NOT covered by t-1507. This is a separate open issue. Assess the actual concurrent
    write surface when t-1607 is implemented; file a follow-up task if agent_spawn
    sub-agents write task status updates back to tasks.json concurrently.
  t-1507 is a prerequisite for corruption safety. Lost-update risk is known and open.
- **t-1549** (ruflo v3.6 tool audit) — required before smart:true enablement (separate
  phase t-1545). Does not block Phases 0–4 of this initiative.
