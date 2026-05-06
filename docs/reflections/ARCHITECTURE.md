---
last_verified: 2026-04-12
status: active
maturity: evergreen
version: 1.0.0
confidence_tier: architecture
depends_on:
  - docs/reflections/08-diagnosis.md
informs:
  - docs/reflections/31-assurance.md
  - docs/reflections/32-lifecycle.md
  - docs/reflections/component-index.md
---

# Architecture: Single Brain, All Projects

How a single Claude Code instance with ruflo accumulates knowledge across every project while maintaining project-specific context. The "single evolving brain" system.

> **Relationship to doc 14:** This doc and [14-mastermind-architecture.md](14-mastermind-architecture.md) are complementary, not redundant. This doc is the concise reasoning layer (WHY things compose this way). Doc 14 is the detailed synthesis (directory trees, hook descriptions, agent roster, scheduler architecture) that receives errata corrections and validate.sh audits. The planned split into ARCHITECTURE.md (reasoning) + component-index.md (generated inventory) + archived doc 14 is not yet complete — `component-index.md` remains a stub. Until the split is done, treat both as active. Errata #85.

---

## The Core Insight: Three Layers

The system has three distinct layers, each with its own persistence and scope:

```
┌─────────────────────────────────────────────┐
│  IDENTITY — Who am I?                       │
│  Global CLAUDE.md, universal principles,    │
│  personality, standards, philosophy         │
│  Lives at: ~/.claude/                       │
├─────────────────────────────────────────────┤
│  INTELLIGENCE — What do I know?             │
│  ruflo memory, BM25 hybrid search,         │
│  cross-client patterns, learned failures   │
│  Lives at: ~/.swarm/memory.db               │
│  Single SQLite DB, not git-tracked,         │
│  not parallel-safe. Trade-off: semantic     │
│  search + confidence vs git-native safety.  │
├─────────────────────────────────────────────┤
│  CONTEXT — What am I working on right now?  │
│  Project CLAUDE.md, rules, skills, agents   │
│  Lives at: project/.claude/                 │
└─────────────────────────────────────────────┘
```

Claude Code's native hierarchy handles layers 1 and 3 — `~/.claude/CLAUDE.md` is always loaded (the mastermind), and `project/.claude/CLAUDE.md` layers on top when you're in a project. Ruflo's ruflo memory fills layer 2 — the cross-client memory that native Claude Code can't do.

The hooks are the glue connecting all three.

> **Channel-agnostic extension (2026-03-13):** [ADR-019](../architecture/decisions/ADR-019-brana-chat-sessions.md) extends brana beyond the CLI. A 3-layer session architecture (channel adapters → session manager → brana agent runtime) enables WhatsApp, web widget, and CLI access with tiered capabilities. The three core layers above remain the brain; the session layer is the interface extension.

---

## How Context Composes

When you `cd ~/projects/alpha && claude`:

```
Loaded automatically:
  1. ~/.claude/CLAUDE.md              ← Identity layer
  2. ~/.claude/rules/*                ← Universal rules (14)
  3. ~/.claude/memory/MEMORY.md       ← Cross-project auto memory (first 200 lines)
  4. ~/projects/alpha/.claude/CLAUDE.md  ← Project identity
  5. ~/projects/alpha/.claude/rules/* ← Project-specific rules

Available on demand (via brana plugin):
  6. /brana:build, /brana:backlog, etc.  ← Skills from plugin
  7. Agent commands                    ← maintain-specs, apply-errata, etc.
  8. ~/projects/alpha/.claude/skills/* ← Project-specific skills

Triggered by hooks:
  9. SessionStart → queries ruflo memory for project-relevant patterns
  10. SessionEnd → extracts learnings, stores in ruflo memory
```

You don't configure anything when switching projects. You just `cd` and the layers compose naturally through Claude Code's native instruction hierarchy.

---

## Agent + Skill Symbiosis

Skills are user-invocable workflows (`/command`). Agents auto-delegate when the model decides. They overlap intentionally — agents are safety nets, not replacements.

### Five Integration Patterns

**Pattern A: Skill spawns agent as worker.** Orchestrator skills delegate focused work to agents via the Task tool. The skill controls the workflow; the agent does the heavy lifting in a forked context. Example: `/brana:build` spawns memory-curator for recall and debrief-analyst for end-of-cycle extraction.

**Pattern B: Agent preloads skill knowledge.** Agents can have skills preloaded via the `skills:` YAML field — full skill content injected at startup. Use sparingly: only for small domain knowledge skills where the agent always needs that context.

**Pattern C: Auto-delegation fills skill invocation gaps.** Skills aren't invoked 56% of the time even when available. Explicit "Use when..." descriptions raise invocation from 53% to 79%. Agents fill the remaining gap via auto-delegation. **Key insight:** static markdown in context (CLAUDE.md/AGENTS.md) achieves **100%** availability — passive context always beats skill-based retrieval. The knowledge architecture should prioritize what goes in always-loaded context based on availability risk.

**Pattern D: Multi-agent workflows.** Agents cannot spawn other agents (subagent limitation). Orchestration stays in the main context via skills that use the Task tool to spawn multiple agents in parallel. The skill is the conductor; agents are the musicians. Agent Teams (experimental) offer peer-to-peer coordination at 2x token cost — reserve for genuinely parallel multi-file work.

**Pattern E: Skill bundles executable scripts.** Pure-markdown skills hit a ceiling for automation-heavy workflows ([ADR-011](../architecture/decisions/ADR-011-skills-bundling.md)). Skills can bundle `.sh`/`.py` scripts alongside SKILL.md in subdirectories.

### Key Principles

- Agents are safety nets, not replacements
- Skills are the primary workflow; agents catch uninvoked skill gaps
- Each agent has explicit "Not for..." constraints to prevent misrouting
- Model distribution: Haiku (8 agents), Sonnet (2), Opus (1) — cost vs reasoning depth

> **Dynamic model routing ([ADR-018](../architecture/decisions/ADR-018-dynamic-model-routing.md)):** Agent roster model assignments are defaults. ADR-018 adds per-message complexity scoring that can override static assignments at runtime.

---

## Workspace Architecture: Why Directory Separation

The cognitive separation between architect and operator is directory-based: `docs/` for specs, `system/` for implementation. Branch conventions preserve the boundary: `docs/*` branches for spec work, `feat/*` branches for implementation.

brana-knowledge is a separate repo because it's a library (no backlog, no tasks), not an active project. Dimension docs are semantically indexed into ruflo memory via `index-knowledge.sh`.

For the full directory tree and component inventory, see [component-index.md](component-index.md).

---

## The Hooks: Why Each Exists

Five hook types connect the layers. Three handle learning (SessionStart, SessionEnd, PostToolUse). One handles enforcement (PreToolUse). One handles error recovery (PostToolUseFailure).

> **Platform note:** CC v2.1.x does not dispatch PostToolUse/PostToolUseFailure from plugin `hooks.json`. Workaround: `bootstrap.sh` installs these to `~/.claude/settings.json`. Track CC issue #24529.

### PreToolUse — Enforcement

Three enforcement behaviors:

1. **SDD gate** (Write|Edit) — On `feat/*` branches in projects with `docs/decisions/`, blocks implementation files until spec/test activity exists on the branch. Deterministic enforcement where convention fails.

2. **Cascade throttle** (Write|Edit) — After 3+ consecutive failures on the same target, injects an advisory warning: "This file has failed repeatedly. Stop and reassess." Does not block — warns.

3. **Guard-explore** (Read|Grep|Glob) — Observes whether agents search before reading implementation files. Currently logging only (no blocking). Data collection for search-first enforcement evaluation. Strict profile only.

### Hook Profiles

Hooks support tiered execution via `BRANA_HOOK_PROFILE` (minimal / standard / strict). Default is standard — no behavior change. Strict adds observability hooks (guard-explore). Minimal disables all profiled hooks. Each tier also maps to a CC effort level via `get_profile_effort()` (strict→low, standard→high, minimal→max), exported as `BRANA_EFFORT_LEVEL` at session start. See [hooks architecture](../architecture/hooks.md#hook-profiles).

### SessionStart — Recall

The moment the single brain activates:
1. Query ruflo memory for project-tagged patterns
2. Priority recall: high-confidence correction patterns (>= 0.8) surfaced first
3. Fallback: grep native auto memory if ruflo unavailable
4. Inject task context from tasks.json
5. Check self-learning flags (.needs-backprop, pending-learnings.md)

### SessionEnd — Learning Extraction

`session-end.sh` is an orchestrator that forks three focused sub-scripts in parallel:

- **`session-end-metrics.sh`** — Extracts compound metrics from session JSONL: `correction_rate` (lower = better planning), `auto_fix_rate` (higher = better recovery), `test_write_rate` (higher = better TDD), `cascade_rate` (lower = better error handling), test/lint pass rates
- **`session-end-persist.sh`** — Stores metrics and session summary to ruflo memory (patterns + metrics namespaces). Fallback to Layer 0 auto-memory files if ruflo unavailable
- **`session-end-drift.sh`** — Pushes sync-state, regenerates spec graph, appends decisions log entry

The split keeps each concern independently testable and isolates failures: a ruflo outage doesn't prevent drift sync, and a spec graph error doesn't block metric storage.

### PostToolUse + PostToolUseFailure — Observation

- **Success:** Log event, detect corrections (same file re-edited), detect test writes, track skill invocations
- **Failure:** Categorize errors (edit-mismatch, command-fail, test-fail, lint-fail), detect cascades (3+ failures on same target), write cascade throttle flags

Both write to `/tmp/brana-session-{id}.jsonl` — the shared event stream that SessionEnd reads.

---

## Scheduled Automation: The Out-of-Session Layer

Hooks fire within interactive sessions. The scheduler fires between them — running maintenance tasks on a cadence without human presence.

**brana-scheduler** is a thin bash+jq wrapper over systemd user timers ([ADR-002](../architecture/decisions/ADR-002-scheduler-thin-layer-over-systemd.md)). It gives the brain a heartbeat.

### Relationship to Other Layers

| Layer | Fires when | Example |
|-------|-----------|---------|
| Hooks | During session, per event | SessionStart recalls, SessionEnd extracts |
| Scheduler | Between sessions, on cadence | Weekly staleness, overnight research |
| Skills | On user invocation | `/brana:build`, `/brana:research` |
| Agents | On auto-delegation | challenger reviews a plan |

Skills can run headless via `claude -p "Execute /skill-name"` — the scheduler invokes them the same way.

---

## Deployment Model

thebrana deploys via `git merge to main`. `brana deploy` prints the deployment workflow (merge instructions, no build step). **The file system IS the deployment.**

Skills, hooks, rules, and agents load from disk at session start — so the act of merging to `main` is the act of deploying. No build step, no pipeline.

```
worktree (staging) → git merge → main (deployed)
                                      ↓
                              SessionStart hook
                              loads everything from disk
```

| Layer | Source | How it loads |
|-------|--------|-------------|
| Identity | `~/.claude/` | Installed by `./bootstrap.sh` (run once per machine) |
| Plugin | `system/` → `~/.claude/` | Plugin dir; CC loads at session start |
| Context | `project/.claude/` | CC loads for active project |

**`./bootstrap.sh` is NOT deployment** — it installs the identity layer to `~/.claude/` on a new machine. Deployment of new skills, hooks, or rules is a plain `git merge`.

---

## The ruflo memory: Cross-Client Memory

> **Alpha caveat:** ruflo is alpha. Every call must be wrapped in error handling with fallback to Layer 0 (auto memory files).

Each pattern stored with rich metadata:

```json
{
  "type": "solution|failure|architecture|debugging",
  "domain": "project-tag",
  "tags": ["tech-stack", "domain-concept"],
  "problem": "...",
  "solution": "...",
  "failed_approaches": ["..."],
  "confidence": 0.95,
  "usage_count": 3,
  "transferable": true
}
```

The `tags` field enables cross-pollination: querying "supabase auth" finds patterns from any project that used Supabase.

---

## The Mastermind Identity

Five principles define the brain:

1. **Learn from everything.** Extract patterns, especially from failures.
2. **Cross-pollinate.** Solutions from one project inform others.
3. **Project-specific context matters.** Respect local conventions.
4. **Confidence-weighted recall.** Battle-tested patterns rank higher.
5. **Know what you don't know.** Don't hallucinate past experience.

---

## The Compound Learning Effect

```
Day 1:  Start project-alpha. No patterns. Learn fresh. Store 12 patterns.
Day 5:  SessionStart recalls 12 patterns. Solve auth bug. 47 patterns.
Day 8:  Start project-beta (Rust). Apply testing discipline from alpha.
Day 15: Back to alpha. Beta's parallel processing helps alpha's batch work.
Day 30: Start gamma (RN + Supabase). 30% of problems already solved by alpha.
Month 3: 500+ patterns across 5 projects. New projects bootstrap in minutes.
```

---

## Project Enforcement: The Hierarchy

Four enforcement levels, each stronger than the last:

| Level | Mechanism | Compliance | Where |
|-------|-----------|-----------|-------|
| **Convention** | Rules files | ~80% | `sdd-tdd.md` |
| **Workflow** | Skills (on-demand) | ~85-95% | `/brana:build` SPECIFY |
| **Enforcement** | PreToolUse hooks | ~100% | `pre-tool-use.sh` |
| **Structural** | Architecture linters | ~100% | CI/CD |

Active alignment (`/brana:align`) bridges the gap between "can enforce" and "ready for enforcement."

---

## What Makes This Different

Plain Claude Code gives project-specific context and auto memory. This system adds:

| Capability | How |
|-----------|-----|
| Cross-project pattern memory | ruflo memory |
| Confidence-weighted recall | Proven patterns rank higher |
| Failure memory | What didn't work is stored |
| Progressive mastery | Compounds over time |
| New project bootstrapping | Day-1 knowledge via `/brana:onboard` |
| Knowledge preservation | `/brana:client-retire` |
| Development discipline | 3-layer enforcement (DDD → SDD → TDD) |

---

## Context Engineering: Architectural Implications

From Anthropic's research (see [35-context-engineering-principles.md](../../brana-knowledge/dimensions/35-context-engineering-principles.md)):

- **Context rot is gradual.** All models degrade as context fills — some as early as 50K of 1M. The ~26KB context budget is a first-order constraint.
- **Just-in-time loading.** Keep always-loaded instructions minimal. Load data on demand via skills.
- **Sub-agent summaries.** When sub-agents explore extensively, they return 1,000-2,000 token summaries — protecting the main context.
- **Context budget guard.** Four thresholds (55/70/85%) with escalating interventions. WebFetch costs 50-100K tokens/call — prefer WebSearch.
- **Token efficiency drives architecture.** Agents use ~4x more tokens than chat. Multi-agent: ~15x. Every decision evaluated through token efficiency.

---

## Two Persistence Systems

| If it has... | It goes to... |
|---|---|
| A verb (research, build, fix) | Backlog (tasks.json) |
| A learning or finding | `/brana:retrospective` → taxonomy routing (see below) |
| A directive (always, never) | `system/rules/` — draft displayed, human places |

No shadow backlogs. Skills propose backlog items in reports. Users decide what gets added.

### Memory Routing Taxonomy

`/brana:retrospective` classifies each learning and routes it automatically. Use it after any session.

| Type | Signal | Destination | Gate |
|------|--------|------------|------|
| Rule | "always X" / "never Y" — no context needed | `system/rules/` draft → human places | human |
| Decision | why-we-chose-X, explicit tradeoffs | ADR stub → human commits | human |
| Reference | pointer to where something lives | `~/.claude/memory/portfolio.md` | auto |
| Pattern | reusable solution to a recurring shape | `~/.claude/memory/patterns.md` (cap 50) | auto |
| Knowledge | domain fact, model, research finding | `~/.claude/memory/knowledge-staging.md` (cap 30) | auto |
| Session | resume-only state | native memory dir — skip retrospective | auto |

Cap enforcement runs before every write. MEMORY.md is an index (≤200 lines), not a store.
Spec: [memory-taxonomy-sdd.md](../architecture/features/memory-taxonomy-sdd.md)

---

## Open Questions

1. **Cross-pollination aggressiveness.** Should SessionStart always inject cross-client patterns, or only when asked?
2. **Project isolation.** Need a "walls" mechanism for competitive clients.
3. **Sensitive pattern filtering.** Mark patterns as non-transferable.
4. **Cross-project DNA matching.** Vector embedding of project architecture for better pattern matching. Deferred.

---

## Assumptions

| # | Claim | If Wrong | Last Verified |
|---|---|---|---|
| 1 | Three-layer separation (identity/intelligence/context) is correct decomposition | Layers leak or overlap, need redesign | 2026-03-14 |
| 2 | Ruflo is enhancement, not hard dependency | Graceful degradation section needs rewrite | 2026-03-14 |
| 3 | ~26KB context budget is the right ceiling | Model upgrades or context rot research changes the math | 2026-03-14 |
| 4 | Agent auto-delegation fills 79→95% skill gap | Gap is larger, need different routing strategy | 2026-03-14 |
| 5 | Single-operator memory model works | Multi-user access needs locking, not just append | 2026-03-14 |

## Changelog

### 2026-03-14
- Split from monolithic 14-mastermind-architecture.md (65KB → ~25KB reasoning)
- Inventory sections moved to auto-generated component-index.md
- Added temporal metadata (last_verified, status, maturity)
- Added explicit assumptions table
- Added changelog section (ADR-021 format)

## Field Notes

### 2026-03-31: Reconcile after multi-branch milestones catches real bugs
After merging 8 feature branches for unified session state (t-794), `/brana:reconcile` found 2 actual bugs: an unwired CLI subcommand (mark-consumed existed as Rust fn but had no CLI dispatch) and a missing awk `-F'\t'` for tab-delimited input. Unit tests (30 passing) missed both because they tested functions, not integration. Run reconcile after merging 3+ branches before marking a milestone complete.
Source: session 2026-03-31, /brana:reconcile

### 2026-04-01: additionalContext is informational, not imperative
Hook `additionalContext` JSON field is treated by the LLM as informational context, not commands to execute. Tested: imperative instructions ("call X before first task") were ignored in `--system-prompt` mode. For deferred MCP calls, use lazy init from skills instead.
Source: ruflo integration brainstorm session

### 2026-04-14: branch-verify hook scans staged content, not file paths
`branch-verify.sh` uses `git diff --cached` (full content), not `git diff --cached --name-only`. Any test file containing a `system/hooks/` or `system/rules/` path string as a literal triggers the hook — even when no behavioral file is being staged. Fix: switch to `--name-only` or add `tests/` to an allowlist. Escape hatch: `# --force-main` comment on the `git add` line.
Source: t-1272 commit, session 2026-04-14

### 2026-04-14: New rules without paths: frontmatter blow the context budget
Rules in `system/rules/` without a `paths:` YAML field load unconditionally into every context window. Adding 5 such rules exceeded the 28KB budget gate. Fix: every new rule must include `paths:` frontmatter. Consider adding a validate.sh check.
Source: t-1254, session 2026-04-14

### 2026-04-14: MEMORY.md filename grep needs -i flag for uppercase paths
Grepping MEMORY.md for `feedback_[a-z0-9_-]+\.md` silently misses filenames with uppercase segments (e.g., `feedback_git-checkout-HEAD-reliable-recovery.md`). Always use `grep -i` or `[a-zA-Z0-9_-]` when extracting filenames from MEMORY.md.
Source: t-1248 triage manifest, session 2026-04-14

### 2026-04-14: Memory catch-all without type taxonomy causes context truncation
`feedback_*.md` files used as a catch-all for all memory types (rules, patterns, knowledge, decisions, references, session state) accumulate to 128+ files. MEMORY.md index overflows the 200-line CC cap — 35% of memory index silently dropped per session. Fix: classify at write time into 6 types (rule/pattern/knowledge/decision/reference/session state), each routed to its canonical home. Layer 1 destinations (rules) require human confirmation gate — never auto-route LLM-generated content there.
Source: t-1238, session 2026-04-14

### 2026-04-14: Double challenger collapses architecture plan complexity
Running /brana:challenge on a design, then again on the reshaped plan, collapsed 8 tasks → 5 without losing coverage. Effective combo: pre-mortem (what fails in 3 months?) + simplicity pass (half the complexity, same outcome?). Run both flavors on any architecture task with M+ effort before creating child tasks.
Source: t-1238, session 2026-04-14
