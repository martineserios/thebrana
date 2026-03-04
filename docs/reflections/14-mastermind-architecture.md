# 14 - Mastermind Architecture: Single Brain, All Projects

How to run a single Claude Code instance with claude-flow that accumulates knowledge across every project while maintaining project-specific context. The "single evolving brain" system.

> **Architecture redesign complete (2026-02-25):** [39-architecture-redesign.md](../39-architecture-redesign.md) merged enter/ into thebrana/ (Phases 0–4 done). The workspace is now a single unified repo with `docs/` (specs) + `system/` (implementation). brana-knowledge/ is an active indexed KB with semantic retrieval via claude-flow embeddings.

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
│  ReasoningBank, SONA trajectories,          │
│  cross-project patterns, learned failures   │
│  Lives at: ~/.swarm/memory.db               │
├─────────────────────────────────────────────┤
│  CONTEXT — What am I working on right now?  │
│  Project CLAUDE.md, rules, skills, agents   │
│  Lives at: project/.claude/                 │
└─────────────────────────────────────────────┘
```

Claude Code's native hierarchy handles layers 1 and 3 — `~/.claude/CLAUDE.md` is always loaded (the mastermind), and `project/.claude/CLAUDE.md` layers on top when you're in a project. Claude-flow's ReasoningBank fills layer 2 — the cross-project memory that native Claude Code can't do.

The hooks are the glue connecting all three.

---

## The Full Directory Architecture

```
~/.claude/                                    THE MASTERMIND
├── CLAUDE.md                                 ← Identity + universal principles
├── skills/                                      ← 39 deployed skills (SKILL.md + optional bundled scripts)
│   ├── memory/SKILL.md                       ← Knowledge ops: recall, pollinate, review, audit
│   ├── project-onboard/SKILL.md              ← Bootstrap a new project with relevant knowledge
│   ├── retrospective/SKILL.md                ← End-of-session learning extraction
│   ├── decide/SKILL.md                       ← Create ADRs in docs/decisions/
│   ├── tasks/SKILL.md                        ← Plan, track, and execute tasks across phases and streams
│   ├── knowledge/                            ← First bundled skill (ADR-011)
│   │   ├── SKILL.md                          ← Browse, annotate, review, reindex knowledge
│   │   ├── generate-index.sh                 ← Generate INDEX.md for brana-knowledge
│   │   └── index-knowledge.sh                ← Index dimensions into claude-flow memory
│   └── ...                                   ← +32 more (build-phase, research, reconcile, respondio, etc.)
├── skill-catalog.md                             ← Vetted external skills (version-pinned, not installed)
├── agents/
│   ├── scout.md                              ← Haiku-powered fast research agent
│   ├── memory-curator.md                     ← Knowledge lifecycle management
│   ├── project-scanner.md                    ← Project structure analysis
│   ├── venture-scanner.md                    ← Business project analysis
│   ├── challenger.md                         ← Opus adversarial review (read-only)
│   ├── debrief-analyst.md                    ← Opus session learning extraction
│   ├── archiver.md                           ← Knowledge backup and export
│   ├── daily-ops.md                          ← Daily operational checks for venture projects
│   ├── metrics-collector.md                  ← Gather data for venture skills
│   ├── pipeline-tracker.md                   ← Pipeline tracking and deal analysis
│   └── pr-reviewer.md                       ← PR diff review on gh pr create (read-only + gh CLI)
├── scripts/
│   ├── cf-env.sh                             ← Discover claude-flow binary, export $CF
│   ├── memory-store.sh                       ← Store key-value in memory with fallback
│   ├── backup-knowledge.sh                   ← Trigger brana-knowledge backup
│   ├── index-knowledge.sh                    ← Index brana-knowledge into claude-flow memory
│   ├── generate-index.sh                     ← Generate knowledge base INDEX.md
│   ├── skill-graph.sh                        ← Skill interaction and dependency diagram
│   └── verify-counts.sh                      ← Post-deploy count verification (ADR-007)
├── commands/
│   ├── session-handoff.md                    ← Rolling session continuity log (dated sections)
│   ├── init-project                          ← Bootstrap new project with CLAUDE.md + structure
│   ├── maintain-specs.md                     ← Cascade spec changes: dimension → reflection → roadmap
│   ├── refresh-knowledge.md                  ← Research external updates to dimension docs
│   ├── re-evaluate-reflections.md            ← Cross-check reflections against dimensions
│   ├── apply-errata.md                       ← Apply pending errata through layer hierarchy
│   └── repo-cleanup.md                       ← Commit accumulated spec doc changes
├── rules/
│   ├── universal-quality.md                  ← Always: test before ship, no secrets in code
│   ├── self-improvement.md                   ← Always: innate learning loop — capture, apply, reflect automatically
│   ├── git-discipline.md                     ← Always: conventional commits, worktrees, branch protection
│   ├── sdd-tdd.md                            ← Always: spec-before-code, test-before-code
│   ├── context-budget.md                     ← Always: 4-tier context thresholds (55/70/85%), expensive-op guards
│   ├── doc-linking.md                        ← Always: use formal markdown links when referencing docs
│   ├── delegation-routing.md                 ← Always: auto-delegate to agents, suggest skills by trigger
│   ├── memory-framework.md                   ← Always: CLAUDE.md vs MEMORY.md separation, reference-not-cache
│   ├── task-convention.md                     ← Always: check tasks.json before branching, status flow
│   ├── pm-awareness.md                       ← Always: check issues before starting work
│   ├── research-discipline.md                ← Always: read project docs before web search
│   └── work-preferences.md                   ← Always: parallelism, simplicity, automation through usage
├── memory/
│   └── MEMORY.md                             ← Auto memory (first 200 lines always in context)
└── settings.json                             ← Global hooks (PreToolUse, SessionStart, SessionEnd, PostToolUse, PostToolUseFailure)

~/.swarm/                                     CLAUDE-FLOW INTELLIGENCE
├── memory.db                                 ← ReasoningBank (ALL projects, tagged by domain)
└── hnsw.index                                ← HNSW vector index for semantic search

~/projects/
├── alpha/                                    PROJECT-SPECIFIC LAYER
│   └── .claude/
│       ├── CLAUDE.md                         ← "This is an e-commerce platform. Next.js + Supabase + Stripe..."
│       ├── rules/
│       │   ├── api-conventions.md            ← paths: "src/api/**" — REST conventions for this project
│       │   ├── db-patterns.md                ← paths: "src/db/**" — Supabase patterns, RLS rules
│       │   └── testing.md                    ← paths: "**/*.test.*" — this project's testing approach
│       ├── skills/
│       │   ├── deploy/SKILL.md               ← Project-specific deployment workflow
│       │   └── migrate/SKILL.md              ← Database migration procedure
│       └── agents/
│           └── domain-expert.md              ← "You understand e-commerce: inventory, payments, fulfillment"
│
├── beta/
│   └── .claude/
│       ├── CLAUDE.md                         ← "This is a Rust CLI tool. clap + tokio + serde..."
│       ├── rules/
│       └── skills/
│
└── gamma/
    └── .claude/
        ├── CLAUDE.md                         ← "React Native mobile app. Expo + React Query..."
        └── ...
```

---

## How Context Composes When You Work

When you `cd ~/projects/alpha && claude`:

```
Loaded automatically:
  1. ~/.claude/CLAUDE.md              ← "I am a mastermind. My principles are..."
  2. ~/.claude/rules/*                ← Universal quality, git discipline, learning triggers
  3. ~/.claude/memory/MEMORY.md       ← Cross-project auto memory (first 200 lines)
  4. ~/projects/alpha/.claude/CLAUDE.md  ← "This project is an e-commerce platform..."
  5. ~/projects/alpha/.claude/rules/* ← path-scoped project rules

Available on demand:
  6. ~/.claude/skills/*               ← /memory recall, /memory pollinate, etc.
  7. ~/.claude/commands/*             ← /session-handoff, /init-project (slash commands)
  8. ~/projects/alpha/.claude/skills/* ← /deploy, /migrate (project-specific)
  9. All installed plugins             ← pr-review-toolkit, security-guidance, etc.

Triggered by hooks:
  10. SessionStart → queries ReasoningBank for alpha-relevant patterns
  11. SessionEnd → extracts learnings, stores in ReasoningBank
```

You don't configure anything when switching projects. You just `cd` and the layers compose naturally through Claude Code's native instruction hierarchy.

---

## Agent + Skill Symbiosis

Skills are user-invocable workflows (`/command`). Agents auto-delegate when the model decides. They overlap intentionally — agents are safety nets, not replacements. If a user invokes a skill, the skill runs. If a user doesn't, the model may auto-delegate to an agent that covers the same domain.

### Five Integration Patterns

**Pattern A: Skill spawns agent as worker.** Orchestrator skills delegate focused work to agents via the Task tool. The skill controls the workflow; the agent does the heavy lifting in a forked context. Example: `/build-phase` spawns memory-curator for recall and debrief-analyst for end-of-cycle extraction.

**Pattern B: Agent preloads skill knowledge.** Agents can have skills preloaded via the `skills:` YAML field — full skill content injected at startup, not just available for invocation. Use sparingly: only for small domain knowledge skills where the agent always needs that context. Large skills bloat the agent's context window.

**Pattern C: Auto-delegation fills skill invocation gaps.** Vercel's eval found skills aren't invoked 56% of the time even when available. Explicit "Use when..." descriptions raise invocation from 53% to 79%. Agents fill the remaining gap (79% to ~95%) via auto-delegation — the model routes to a relevant agent when the user doesn't invoke the corresponding skill. **Key architectural implication:** static markdown in context (CLAUDE.md/AGENTS.md) achieves **100%** availability — passive context always beats skill-based retrieval. The knowledge architecture should prioritize what goes in always-loaded context based on availability risk: always-needed knowledge → CLAUDE.md (100%), explicit workflows → skills (79% with good descriptions + agents close the gap). **Status (Mar 2026):** All 39 deployed skills have explicit "Use when..." trigger descriptions in their SKILL.md frontmatter. All skills include `AskUserQuestion` in `allowed-tools` — interactive confirmations use selectable options instead of plain text prompts, with batching (up to 4 questions per call). Context budget raised to ~26KB to accommodate trigger text, context-budget rule, additional skills, and workflow practice rules.

**Pattern D: Multi-agent workflows.** For subagents: agents cannot spawn other agents (subagent limitation). Orchestration stays in the main context via skills that use the Task tool to spawn multiple agents in parallel. The skill is the conductor; agents are the musicians. For Agent Teams (experimental, Feb 2026): peer-to-peer coordination with shared task lists and DAG dependencies — but at 2x token cost (~800k vs ~440k for 3-worker team), no file locking, and disabled by default. **Use subagents for production orchestration; reserve Agent Teams for genuinely parallel multi-file work where peer coordination justifies the experimental status and cost.**

**Pattern E: Skill bundles executable scripts.** Pure-markdown skills hit a ceiling for automation-heavy workflows ([ADR-011](../decisions/ADR-011-skills-bundling.md)). Skills can bundle `.sh`/`.py` scripts alongside SKILL.md in subdirectories. `deploy.sh` copies the entire skill folder and `chmod +x` all bundled scripts. First example: `/knowledge` bundles `generate-index.sh` (INDEX.md generation) and `index-knowledge.sh` (dimension → claude-flow memory indexing). Use when a skill's workflow requires repeatable shell logic that would otherwise live in `scripts/` with no clear ownership. Keep scripts focused — one concern per file, invocable standalone or from the SKILL.md workflow.

### The Agent Roster

| Agent | Model | Purpose | Tools |
|-------|-------|---------|-------|
| **scout** | Haiku | Fast research, file discovery | Read-only |
| **memory-curator** | Haiku | Knowledge lifecycle: recall, store, promote, demote | Read, Bash (claude-flow) |
| **project-scanner** | Haiku | Project structure analysis for onboarding/alignment | Read-only |
| **venture-scanner** | Haiku | Business project analysis for venture onboarding | Read-only |
| **challenger** | Opus + Gemini | Adversarial review: Opus reasoning + Gemini doc-grounded second opinion via NotebookLM | Read-only (no Write/Edit/Bash) |
| **debrief-analyst** | Opus | Session learning extraction, errata identification | Read-only |
| **archiver** | Haiku | Knowledge backup and export | Read, Bash |
| **daily-ops** | Haiku | Daily operational checks for venture projects | Read-only |
| **metrics-collector** | Haiku | Gather data for venture skills (growth-check, weekly-review, monthly-close) | Read-only |
| **pipeline-tracker** | Haiku | Pipeline tracking and deal analysis | Read-only |
| **pr-reviewer** | Sonnet | PR diff review: security, logic, style, completeness | Read-only + Bash (gh CLI) |

### Key Principle

Agents are safety nets, not replacements. The community builds skills (portable, cross-agent). Agents are brana's complementary layer — they catch what uninvoked skills miss and provide focused workers that skills can delegate to.

### Agent Boundaries

Each agent description includes "Not for..." constraints that disambiguate auto-delegation routing. When multiple agents cover adjacent domains (e.g., scout vs memory-curator for research, project-scanner vs venture-scanner for diagnostics), explicit negative boundaries prevent the model from routing to the wrong agent. Model distribution: Haiku (8 agents — fast, cheap tasks), Opus (2 agents — challenger, debrief-analyst — where reasoning depth justifies the cost), Sonnet (1 agent — pr-reviewer — code understanding without Opus cost).

---

## Workspace Architecture: Directory Roles

The brana ecosystem lives in two repositories. `cd` into thebrana to activate the unified architect+operator role — the global brain follows you everywhere, and the local CLAUDE.md tells it what job you're doing.

```
~/enter_thebrana/
├── thebrana/                   ARCHITECT + OPERATOR — design and build the system
│   ├── .claude/CLAUDE.md       ← "You are the architect+operator."
│   ├── docs/                   ← Specs: reflections/, roadmaps, decisions/
│   ├── system/                 ← Implementation: skills, rules, hooks, agents
│   ├── deploy.sh               ← system/ → ~/.claude/
│   └── validate.sh             ← Pre-deploy checks
│
└── brana-knowledge/            KNOWLEDGE BASE — deep dives on any topic
    ├── dimensions/             ← One doc per topic (33 docs, semantically indexed)
    ├── research-sources.yaml   ← Tracked sources with trust tiers
    └── backup/                 ← System knowledge exports
```

### How Context Loads

When you `cd ~/enter_thebrana/thebrana && claude`:

1. **Global identity** — `~/.claude/CLAUDE.md` ("I am a mastermind. I accumulate knowledge across projects.")
2. **Global rules** — `~/.claude/rules/*` (12 rules: quality, self-improvement, git, SDD/TDD, memory framework, context budget, doc-linking, task convention, etc.)
3. **Global auto memory** — `~/.claude/memory/MEMORY.md` (first 200 lines, cross-project observations)
4. **Local CLAUDE.md** — `thebrana/.claude/CLAUDE.md` ("You are the architect+operator. Here's the document structure and system layout.")
5. **Local rules** — `thebrana/.claude/rules/*` (project-specific, if any)

The same 5 steps happen in any project. Steps 1-3 are always the same (the brain's identity). Steps 4-5 change based on where you are.

### Design Decision: Directory Separation, Not Repo Separation

The cognitive separation between architect and operator is directory-based: `docs/` for specs, `system/` for implementation. Branch conventions preserve the boundary: `docs/*` branches for spec work (no `system/` edits), `feat/*` branches for implementation (should also touch `docs/` when behavior changes).

brana-knowledge is a separate repo because it's a library (no backlog, no tasks), not an active project. Dimension docs are the source of truth — semantically indexed into claude-flow memory via `index-knowledge.sh`, retrievable from any session via `memory_search`.

---

## The Hooks That Make the Brain Work

Five hook types connect the layers. Three handle learning (SessionStart, SessionEnd, PostToolUse). One handles enforcement (PreToolUse). One handles error recovery (PostToolUseFailure).

### PreToolUse — "Is this allowed right now?"

```
Before Write or Edit executes:
  1. Check if project has opted into SDD enforcement (docs/decisions/ exists)
  2. Check if on a feat/* branch
  3. If both: verify spec or test activity exists on this branch
  4. If no spec/test activity → block with permissionDecision: "deny"
     "Create an ADR (/decide) or write tests before implementation."

  Pure git operations, no claude-flow dependency, <100ms latency.
  Always allows spec/test file writes. Passes through on non-feat branches.
```

This is the enforcement gate. Everything else in the system (rules, skills) suggests discipline. This hook enforces it. See "Project Enforcement" section below for the full design.

### SessionStart — "Remember what you know"

```
On every session start:
  1. Detect current project from git root
  2. Query ReasoningBank for project-tagged patterns
  3. Priority recall: search for high-confidence correction patterns
     (confidence >= 0.8) from this project — surface them first so
     proven fixes are available early if similar errors arise
  4. Fallback: grep native auto memory if claude-flow unavailable
  5. Inject task context (from tasks.json: current phase, next unblocked task)
  6. Check self-learning flags from previous session:
     - .needs-backprop → "System files changed, consider /back-propagate"
     - pending-learnings.md → "N unprocessed sessions, consider /debrief"
  7. Log recalled patterns to session JSONL for promotion tracking
```

This is the moment where the single brain activates — it doesn't start from zero, it starts from everything it's ever learned. The correction-pattern priority recall (Wave 3) ensures that proven fixes from past sessions are surfaced before generic patterns.

### SessionEnd — "Remember what you learned"

```
On every session end:
  1. Read session JSONL (/tmp/brana-session-{id}.jsonl)
  2. Compute compound metrics (Wave 1 + t-043):
     - corrections: same file re-edited (indicates plan revision)
     - test_writes: test file edits detected
     - cascades: 3+ consecutive failures on same target
     - edits: total Edit/Write tool uses
     - test_passes, test_fails: Bash test runner outcomes (t-043)
     - lint_passes, lint_fails: Bash linter outcomes (t-043)
  3. Compute flywheel rates (Wave 4 + t-043):
     - correction_rate = corrections / edits (lower = better planning)
     - auto_fix_rate = failure→success recoveries / failures (higher = better)
     - test_write_rate = test_writes / edits (higher = better TDD)
     - cascade_rate = cascades / failures (lower = better error handling)
     - test_pass_rate = test_passes / (test_passes + test_fails) — "N/A" if no tests ran
     - lint_pass_rate = lint_passes / (lint_passes + lint_fails) — "N/A" if no lints ran
     - delegation_count = Task tool invocations
  4. Store session summary in ReasoningBank (patterns namespace)
  5. Store flywheel metrics separately (metrics namespace) for trending
  6. Write to Layer 0: sessions.md, pending-learnings.md (if CF fails)
  7. Auto-generate minimal handoff note if /session-handoff wasn't called
  8. Detect system file drift → write .needs-backprop flag for next session
```

### PostToolUse + PostToolUseFailure — "Notice important moments"

```
PostToolUse — fires on successful tool use:
  1. Log event to session JSONL with tool name and target file
  2. Correction detection (Wave 1): if the last JSONL entry was an
     Edit/Write to the SAME file, classify as "correction" instead of
     "success" — indicates the previous edit needed revision
  3. Test-file detection (Wave 1): if target matches test patterns
     (*.test.*, *.spec.*, /tests/, test_*), classify as "test-write"
  4. Test/lint command detection (t-043): if Bash command matches a
     test runner (npm test, pytest, cargo test, etc.), classify as
     "test-pass". If it matches a linter (eslint, shellcheck, ruff,
     etc.), classify as "lint-pass".

PostToolUseFailure — fires when a tool fails:
  1. Test/lint command detection (t-043): if Bash command matches a
     test runner, classify as "test-fail" (error_cat=test-fail).
     If linter, classify as "lint-fail" (error_cat=lint-fail).
     Otherwise, default to "failure" (error_cat=command-fail).
  2. Categorize error type: edit-mismatch, write-fail, command-fail,
     test-fail, lint-fail, network-fail, tool-fail
  3. Cascade detection (Wave 1): if the last 2 JSONL entries were also
     failures (including test-fail/lint-fail) on the SAME target,
     mark cascade=true
  4. Log to session JSONL with error category and cascade flag

Both write to /tmp/brana-session-{id}.jsonl — the shared event stream
that SessionEnd reads to compute compound metrics and flywheel rates.

  5. PR review nudge (t-044): if Bash command matches `gh pr create`,
     emit additionalContext suggesting the user spawn the pr-reviewer
     agent for automated code review. Handled by post-pr-review.sh.
```

> **Hook format details:** See [09-claude-code-native-features.md](../../../brana-knowledge/dimensions/09-claude-code-native-features.md) for the full hook JSON format, event list, stdin/stdout contracts, and async constraints.

### Team-Level Hooks (v3.1 Extension)

When using Agent Teams, two additional Claude Code events extend the learning loop:

- **TeammateIdle** — fires when a teammate goes idle. claude-flow v3.1's `teammate-idle` hook can auto-assign pending tasks from the shared task list.
- **TaskCompleted** — fires when a task is marked complete. claude-flow v3.1's `task-completed` hook trains patterns from successful tasks (requires `--task-id`).

These are optional extensions to the 3-hook core above. They matter when teammates work independently — without them, only the lead's session contributes to the learning loop. With them, every teammate's completions feed the ReasoningBank.

> **v3.1 analysis:** See [07-claude-flow-plus-claude-4.6.md](../../../brana-knowledge/dimensions/07-claude-flow-plus-claude-4.6.md) "v3.1 Update" section for what's shipped vs planned, AutoMemoryBridge architecture, and adoption strategy.

---

## Scheduled Automation: The Out-of-Session Layer

Hooks fire within interactive sessions. The scheduler fires between them — running maintenance tasks on a cadence without human presence.

**brana-scheduler** is a thin bash+jq wrapper over systemd user timers ([ADR-002](../decisions/ADR-002-scheduler-thin-layer-over-systemd.md), accepted 2026-02-19). It gives the brain a heartbeat: jobs run on schedule, results flow into claude-flow memory, and the next `/morning` session sees what happened overnight.

### Architecture

```
~/.claude/scheduler/
├── scheduler.json          ← job configs (schedule, allowedTools, model, retry)
├── logs/{job}/             ← timestamped run logs
└── status/{job}.status     ← last exit code + timestamp

systemd user timers → brana-scheduler-runner.sh → job command → log + memory
```

The runner handles: config-driven retry with exponential backoff, `flock` concurrency guards, OnFailure desktop notifications (via a companion systemd unit), and an output-to-memory pipeline that stores run summaries in claude-flow (`namespace: scheduler-runs`, key: `sched:{job}:{date}`).

### Relationship to Other Layers

| Layer | Fires when | Example |
|-------|-----------|---------|
| Hooks | During a session, per event | SessionStart recalls patterns, SessionEnd extracts learnings |
| Scheduler | Between sessions, on cadence | Weekly staleness check, overnight research refresh |
| Skills | On user invocation | `/maintain-specs`, `/research`, `/growth-check` |
| Agents | On auto-delegation | challenger reviews a plan, scout researches a topic |

Skills can run headless via `claude -p "Execute /skill-name"` — the scheduler invokes them the same way a user would, just unattended.

### Current Jobs

- **staleness-report** (weekly, Monday 08:00) — layer-aware spec doc freshness check (`scripts/staleness-report.sh`)
- Additional jobs configured in `scheduler.json`, deployed via `brana-scheduler deploy`

---

## The ReasoningBank Schema (Cross-Project Brain)

> **Alpha caveat:** claude-flow (which hosts ReasoningBank) is alpha software. Every call must be wrapped in error handling with fallback to Layer 0 (auto memory files at `~/.claude/projects/*/memory/`). Schema may change between versions — pin your version and run `memory init --force` after upgrades. **After every install/upgrade**, also install the missing sql.js dependency: `npm install sql.js --prefix $(dirname $(which claude-flow))/..` (not declared in package.json but dynamically imported at 19+ sites — see errata #25). See [05-claude-flow-v3-analysis.md](../../../brana-knowledge/dimensions/05-claude-flow-v3-analysis.md) for the full stability assessment.

Each pattern stored with rich metadata:

```json
{
  "id": "pat_2026_0209_001",
  "type": "solution",
  "domain": "project-alpha",
  "tags": ["nextjs", "supabase", "auth", "rls", "jwt"],
  "problem": "Supabase RLS policies weren't applying to server-side API routes",
  "solution": "Server-side routes need the service_role key, not the anon key. But use it through a server client, never expose it.",
  "failed_approaches": [
    "Tried disabling RLS temporarily — broke other queries",
    "Tried passing user JWT from client — doesn't work in server context"
  ],
  "confidence": 0.95,
  "usage_count": 3,
  "created": "2026-01-15",
  "last_used": "2026-02-08",
  "transferable": true
}
```

Pattern types:
- **solution** — problem + what worked + what didn't
- **failure** — what went wrong and why (equally valuable)
- **architecture** — structural decisions and their rationale
- **debugging** — root cause paths and diagnostic approaches

The `tags` field enables cross-pollination. When working on project-gamma (React Native + Supabase), querying for "supabase auth" finds patterns from project-alpha even though they're different projects.

---

## The Mastermind CLAUDE.md

The identity document — who this brain IS:

```markdown
# Mastermind

You are a single intelligence that works across multiple projects.
You accumulate knowledge, patterns, and judgment over time.

## Core Principles

1. **Learn from everything.** Every session teaches something.
   Extract patterns, especially from failures.

2. **Cross-pollinate.** A solution from one project might solve
   a problem in another. When stuck, ask: "Have I seen this before?"

3. **Project-specific context matters.** Each project has its own
   architecture, conventions, and constraints. Respect them.
   Don't force patterns from project-alpha onto project-beta.

4. **Confidence-weighted recall.** Not all memories are equal.
   A pattern that worked 5 times with passing tests > a pattern
   you tried once.

5. **Know what you don't know.** If ReasoningBank has no patterns
   for a problem, say so. Don't hallucinate past experience.

## Before Starting Work

- Query ReasoningBank for relevant patterns (use /memory recall)
- Review project-specific CLAUDE.md for current architecture
- Check auto memory for recent session context

## After Completing Work

- Extract and store learnings (automatic via SessionEnd hook)
- Update project CLAUDE.md if architecture changed
- Flag universal patterns for cross-project use

## Project Portfolio

@~/.claude/memory/portfolio.md
```

---

## Six Mastermind Skills

> **Never use `npx`** to invoke claude-flow — it creates isolated package caches with missing dependencies (errata #25, lesson #17). Use the globally installed `claude-flow` binary. The deployed skills in thebrana use a smart discovery pattern for environments where PATH may not include nvm bins.

### 1. `/memory recall` — "What do I already know about this?"

```markdown
---
name: memory
description: Query the cross-project ReasoningBank for patterns relevant to the
  current task. Use before starting complex work to leverage past experience.
allowed-tools: [Bash, Read, AskUserQuestion]
---

Before solving this problem, search your accumulated knowledge:

1. Run: claude-flow memory search --query "$ARGUMENTS"
2. Review returned patterns. For each:
   - Which project did this come from?
   - What was the confidence score?
   - Is it directly applicable or needs adaptation?
3. Summarize what you already know that's relevant.
4. Identify gaps — what's new about this problem that past patterns don't cover?

If no patterns found, say so honestly. Start fresh.
```

### 2. `/memory pollinate` — "What would my other projects teach me?"

```markdown
---
name: memory
description: Find solutions from OTHER projects that might apply to the current
  problem. Useful when stuck or when starting something a different project already solved.
allowed-tools: [Bash, Read, AskUserQuestion]
---

Search for cross-project patterns:

1. Identify the core problem type: auth? performance? data modeling? error handling? testing?
2. Query ReasoningBank with technology-agnostic terms:
   claude-flow memory search --query "$ARGUMENTS"
3. For each pattern from a DIFFERENT project:
   - Explain the original context (project, tech stack, problem)
   - Explain how the solution could transfer to THIS project
   - Note what would need to change (different framework, different constraints)
4. Propose an adapted solution.
```

### 3. `/retrospective` — "What did I learn this session?"

```markdown
---
name: retrospective
description: Store a learning or pattern in the knowledge system.
allowed-tools: [Bash, Read, Write, Glob, Grep, AskUserQuestion]
---

1. Structure the learning as a pattern:
   - problem, solution, tags, confidence: 0.5 (quarantined),
     correction_weight: 0, transferable: false

2. Store via claude-flow (primary) or auto memory (fallback)

3. Review recalled patterns — promotion tracking:
   a. Useful patterns: increment recall_count
      - recall_count >= 3 → promote (confidence: 0.8, transferable: true)
      - correction_weight >= 2 → fast-track promote (same thresholds)
   b. Harmful patterns: demote (confidence: 0.1)

4. Correction-weight check (Wave 3): scan session JSONL for correction
   events. If a pattern's solution resolved multiple corrections on the
   same file or error type, increment that pattern's correction_weight.
   Patterns proven through active correction are promoted faster than
   those proven only through recall.

5. Backup knowledge artifacts
```

The `correction_weight` field (Wave 3) creates a fast track: patterns that resolve real errors during active work earn promotion at 2 corrections instead of the standard 3 recalls. This rewards battle-tested fixes over passively recalled knowledge.

### 4. `/project-onboard` — "I'm starting a new project"

```markdown
---
name: project-onboard
description: Bootstrap a new project with relevant knowledge from all other projects.
  Queries ReasoningBank for patterns matching the new project's tech stack and domain.
allowed-tools: [Bash, Read, Write, AskUserQuestion]
---

A new project is being set up. Help it benefit from everything you've learned:

1. Analyze the project: tech stack, framework, language, domain
2. Query ReasoningBank for ALL patterns matching these technologies
3. Group findings:
   - Architecture patterns that worked in similar stacks
   - Common pitfalls to avoid (from failures in other projects)
   - Testing strategies that proved effective
   - Performance patterns worth applying from day one
4. Suggest initial .claude/ structure:
   - CLAUDE.md skeleton based on similar projects
   - rules/ based on technology conventions you've learned
   - skills/ for workflows this tech stack needs
5. Create a "lessons from the portfolio" section in the new project's CLAUDE.md
```

### 5. `/project-retire` — "Archive this project's knowledge"

```markdown
---
name: project-retire
description: When a project is done or archived, distill ALL its learnings into
  universal patterns. Nothing is lost when a project ends.
allowed-tools: [Bash, Read, Write, AskUserQuestion]
---

This project is being archived. Extract everything valuable:

1. Read the project's CLAUDE.md, rules/, and auto memory
2. Query ReasoningBank for ALL patterns tagged with this project
3. For each pattern, evaluate:
   - Is this transferable? → Promote to universal tags
   - Is this project-specific? → Archive but keep accessible
   - Is this outdated? → Mark low confidence
4. Write a "project obituary" to ~/.claude/memory/retired/project-name.md:
   - What the project was
   - Key technical decisions and their outcomes
   - Top 5 most valuable patterns extracted
   - Mistakes not to repeat
5. Update portfolio.md
```

### 6. `/project-align` — "Get this project aligned with brana practices"

Active alignment pipeline — the bridge between diagnostic (`/project-onboard`) and enforcement (PreToolUse hooks). Runs a 5-phase process: DISCOVER (interview), ASSESS (28-item checklist), PLAN (gap-based action list), IMPLEMENT (create files and structure), VERIFY (before/after comparison), DOCUMENT (ReasoningBank + report).

Three tiers: minimal (foundation only, 4 items), standard (foundation + SDD + TDD, 13 items), full (all 7 groups, 28 items). Works on both greenfield and brownfield projects. See [27-project-alignment-methodology.md](../../../brana-knowledge/dimensions/27-project-alignment-methodology.md) for the full methodology.

### Beyond the Six: `/research` — "What's new in the world?"

The six skills above manage *internal* knowledge — what you've learned, how to transfer it, how to align projects. `/research` manages *external* knowledge acquisition: checking sources, following references, discovering new creators. It's the atomic primitive that `/refresh-knowledge` orchestrates across docs. Source registry, trust tiers, version pinning, leads queue, and recursive discovery are formalized in [33-research-methodology.md](../../../brana-knowledge/dimensions/33-research-methodology.md).

### Beyond the Six: Venture Operating System — "Run the business"

The core six skills + `/research` handle the *development system*. A parallel layer of venture management skills handles the *business system*: daily operational checks (`/morning`), weekly cadence reviews (`/weekly-review`), monthly financial close (`/monthly-close`), forward planning (`/monthly-plan`), sales pipeline (`/pipeline`), growth experiments (`/experiment`), content strategy (`/content-plan`), and financial modeling (`/financial-model`). These skills compose into a daily operating system for startups and SMBs. See [34-venture-operating-system.md](../../../brana-knowledge/dimensions/34-venture-operating-system.md) for the full architecture, MCP integrations, and skill cadences.

### Beyond the Six: Task Management — "Plan and track work"

The `/tasks` skill provides structured project planning: hierarchical task tracking (phase > milestone > task), multi-stream support (roadmap, bugs, tech-debt, docs, experiments, research), branch integration, and portfolio-wide visibility. Data lives in `{project}/.claude/tasks.json` — git-tracked, zero dependencies. A PostToolUse hook handles schema validation and automatic parent rollup. See [ADR-002](../decisions/ADR-002-tasks-as-data-layer.md) for the data layer decision and [ADR-003](../decisions/ADR-003-agent-driven-task-execution.md) for agent-driven execution — subagent spawning per task with DAG-aware wave parallelism and compose-then-write for code tasks.

### Beyond the Six: Spec Maintenance Loop — "Keep specs and implementation in sync"

Four commands form a closed maintenance loop within thebrana (specs in `docs/` ↔ implementation in `system/`). Each handles one direction of change propagation:

| Command | Direction | Purpose |
|---------|-----------|---------|
| `/refresh-knowledge` | external → specs | Research external updates to dimension docs |
| `/maintain-specs` | specs → specs | Cascade changes upward: dimension → reflection → roadmap |
| `/reconcile` | specs → implementation | Detect drift, fix `system/` to match current specs in `docs/` |
| `/back-propagate` | implementation → specs | Update `docs/` when `system/` changes (new skills, rules, hooks, config) |

The loop runs in both directions: when specs evolve, `/maintain-specs` cascades internally and `/reconcile` pushes forward to implementation. When implementation evolves, `/back-propagate` pushes backward to specs. `/refresh-knowledge` feeds the loop with external updates. `/build-phase` orchestrates greenfield implementation from specs and triggers `/back-propagate` on completion. See [25-self-documentation.md](../25-self-documentation.md) for the full command architecture and flow diagrams.

---

## The Project Portfolio — Meta-Knowledge

A living document the mastermind maintains at `~/.claude/memory/portfolio.md`:

```markdown
# Project Portfolio

## Active Projects

### project-alpha (e-commerce)
- **Stack:** Next.js 16, Supabase, Stripe, Tailwind
- **Domain:** E-commerce (inventory, payments, fulfillment)
- **Key patterns:** Supabase RLS for multi-tenant auth, Stripe webhook idempotency
- **Current phase:** Feature development, 80% test coverage
- **Last session:** 2026-02-09 — fixed payment reconciliation bug

### project-beta (CLI tool)
- **Stack:** Rust, clap, tokio, serde
- **Domain:** Developer tooling (code generation)
- **Key patterns:** thiserror+anyhow error handling, tokio async patterns
- **Current phase:** Beta testing
- **Last session:** 2026-02-07 — added parallel file processing

## Cross-Project Insights
- Auth patterns from alpha transferable to any Supabase project
- Beta's error handling strategy should be the default for all Rust projects
- Testing approach from beta (property-based + unit) caught more bugs than alpha's (unit only)

## Retired Projects
- See ~/.claude/memory/retired/ for archived learnings
```

---

## The "Living Brain" Flow

How knowledge compounds over time:

```
Day 1: Start project-alpha
  └─ No patterns yet. Learn everything fresh.
  └─ SessionEnd hook stores 12 patterns.

Day 5: Working on project-alpha
  └─ SessionStart recalls 12 patterns. Start informed.
  └─ Solve a tricky auth bug. Store pattern.
  └─ Now 47 patterns for alpha.

Day 8: Start project-beta (Rust CLI)
  └─ /project-onboard → "No Rust patterns yet, but from alpha you know:
     testing strategy, git workflow, error handling philosophy."
  └─ Apply testing discipline from alpha to beta.
  └─ Learn Rust-specific patterns. Store them.

Day 15: Back to project-alpha
  └─ SessionStart recalls alpha patterns + notices beta learned
     something about parallel processing that could help alpha's
     batch order processing.
  └─ Cross-pollination happens naturally.

Day 30: Start project-gamma (React Native + Supabase)
  └─ /project-onboard → "From alpha: Supabase RLS patterns, auth flow,
     webhook handling. From beta: async patterns, error handling."
  └─ Gamma starts with 30% of its problems already solved.

Month 3: The mastermind has 500+ patterns across 5 projects.
  └─ New projects bootstrap in minutes, not days.
  └─ Common mistakes are caught before they happen.
  └─ The brain suggests solutions you've used before in other contexts.
```

---

## Plugin & Skill Recommendations

### The Foundation Stack

| What | Role in the System |
|------|-------------------|
| **security-guidance** (Anthropic) | Universal safety net across all projects |
| **commit-commands** (Anthropic) | Consistent git workflow everywhere |
| **Context7 MCP** (Upstash) | Real-time library docs — the mastermind always has current knowledge. Fetches version-specific documentation on demand, preventing stale training-data errors. |
| **claude-flow MCP** | Cross-project memory via ReasoningBank. **Scope:** use only the memory commands (`memory search`, `memory store`, `memory init`) from claude-flow's 170+ MCP tool surface — skip the rest unless a specific need arises. **Note:** AgentDB (the graph DB backend) is stalled — last npm publish Jan 2, 2026. The fallback strategy (claude-flow embeddings CLI + SQLite) is the primary path forward. See [05-claude-flow-v3-analysis.md](../../../brana-knowledge/dimensions/05-claude-flow-v3-analysis.md) and [39-architecture-redesign.md](../39-architecture-redesign.md) section 7.5. |
| **LSP plugins** for your languages | Type intelligence at zero cost, per-project |
| **claude-md-management** (Anthropic) | Keeps each project's CLAUDE.md healthy |

### The Quality Layer

| What | Role in the System |
|------|-------------------|
| **pr-review-toolkit** (Anthropic) | Universal code review — the reviewer agent carries standards across projects |
| **Trail of Bits security skills** | Professional audit skills — install globally, apply everywhere |
| **Superpowers TDD pattern** (borrow) | Encode as a global rule: "test before code" discipline travels with the brain |
| **Superpowers debugging pattern** (borrow) | 3-failure escalation as a global rule — prevents brute-force debugging in any project |

### The Learning Layer

| What | Role in the System |
|------|-------------------|
| **hookify** (Anthropic) | Create per-project hooks easily without manual JSON |
| **Custom SessionStart/SessionEnd hooks** | The glue — ReasoningBank queries on start, learning extraction on session end |
| **CC Notify** (community) | Know when long cross-project background tasks finish |

---

## Project Enforcement: Development Discipline

The mastermind doesn't just *suggest* development practices — it can *enforce* them. CLAUDE.md compliance alone achieves ~80% adherence for complex workflows (documented in Claude Code issues #21119, #6120, #15443). For critical discipline, enforcement must be deterministic.

### The Enforcement Hierarchy

Four enforcement levels, each stronger than the last:

| Level | Mechanism | Compliance | Where It Lives |
|-------|-----------|-----------|---------------|
| **Convention** | Rules files (`.claude/rules/`) | ~80% | `sdd-tdd.md` — documents expectations |
| **Workflow** | Skills (on-demand invocation) | ~85-95% | `/decide` — creates ADRs, `/domain-model` — creates domain specs (future) |
| **Enforcement** | PreToolUse hooks | ~100% | `pre-tool-use.sh` — blocks violations |
| **Structural** | Architecture linters (CI/CD) | ~100% | ArchUnit, dependency-cruiser, import-linter — enforce bounded context boundaries |

Convention sets expectations. Skills provide the workflow. Hooks enforce the gate. Linters validate the structure.

**Active alignment:** The `/project-align` skill (see [27-project-alignment-methodology.md](../../../brana-knowledge/dimensions/27-project-alignment-methodology.md)) actively creates the structure projects need for enforcement — it's the bridge between "the mastermind can enforce" and "the project is ready for enforcement."

See [32-lifecycle.md](./32-lifecycle.md) for the full DDD → SDD → TDD development workflow, discipline ordering, detailed enforcement mechanisms, multi-agent context isolation, and the connection to the learning loop. See [11-ecosystem-skills-plugins.md](../../../brana-knowledge/dimensions/11-ecosystem-skills-plugins.md) section 5 for the enforcement tools landscape.

---

## What Makes This Different from "Just Using Claude Code"

Plain Claude Code gives you:
- Project-specific context (CLAUDE.md, rules, skills) — great
- Auto memory within a project — good but siloed
- No cross-project knowledge transfer — the gap

This system adds:

| Capability | How |
|-----------|-----|
| **Cross-project pattern memory** | ReasoningBank — what you learned in project A is available in project B |
| **Confidence-weighted recall** | Patterns that worked 5 times rank higher than one-time solutions |
| **Failure memory** | What DIDN'T work is stored and recalled to prevent repeating mistakes |
| **Progressive mastery** | The system gets better at every domain it touches, compounding over time |
| **New project bootstrapping** | Day-1 knowledge from the entire portfolio via `/project-onboard` |
| **Knowledge preservation** | Projects end, but their learnings live on via `/project-retire` |
| **Development discipline** | Three-layer enforcement (DDD → SDD → TDD): domain modeling, spec-before-code, test-before-code — deterministic where possible, convention where not |

The single brain isn't just "the same Claude everywhere." It's a Claude that remembers, learns, and transfers knowledge — getting measurably better with every project it touches.

---

## Context Engineering: What Anthropic's Research Tells Us

Findings from Anthropic's engineering blog (see [21-anthropic-engineering-deep-dive.md](../../../brana-knowledge/dimensions/21-anthropic-engineering-deep-dive.md)) that directly inform the mastermind's architecture.

### Context Rot and Just-In-Time Loading

Context engineering = optimizing token allocation within finite attention budgets. As context grows, model performance degrades (n-squared complexity, gradient not cliff). The ~26KB context budget is a first-order architectural constraint. For the formal decision framework (where new information belongs, tier placement criteria, failure modes), see [35-context-engineering-principles.md](../../../brana-knowledge/dimensions/35-context-engineering-principles.md).

Two principles from Anthropic's research: (1) keep always-loaded instructions minimal — "for each line ask: would removing this cause mistakes?" (2) load data just-in-time rather than pre-loading — skills activate on demand, SessionStart injects a digest not everything.

See [32-lifecycle.md](./32-lifecycle.md) for practical context management strategies (compaction, structured note-taking, sub-agent architectures).

### Sub-Agent Summary Sizing

When sub-agents explore extensively (tens of thousands+ tokens), they should return condensed summaries of **1,000-2,000 tokens**. This achieves separation of concerns while protecting the main context window.

**Implication for brana:** The scout agent (Haiku-powered research) and any skill with `context: fork` should be instructed to return concise summaries, not raw findings. Encode this in the scout agent's system prompt: "Return findings in 1,000-2,000 tokens maximum."

### Context Budget Guard (Feb 2026)

The `context-budget.md` rule enforces runtime context discipline beyond the static budget ceiling. Four thresholds: below 55% proceed normally, 55-70% yellow zone (prefer summaries, avoid loading new large files, consider delegation), 70-85% compact first, above 85% delegate to a fresh subagent. Context accuracy degrades gradually as the window fills (context rot — Chroma 18-model study confirms all models degrade, some as early as 50K of 1M), so intervention starts at 55% rather than waiting for 70%. Applies to any operation with 5+ file reads, 3+ WebFetch calls, or 5+ scout spawns. Bulk file edits (5+ files) use a Python script instead of individual Read+Edit calls. WebFetch is treated as expensive (50-100K tokens/call) — prefer WebSearch for metadata, fetch only HIGH-priority items.

The `/research` skill enforces a 3-phase metadata-first protocol: Phase 1 scouts use WebSearch only (no content fetching), Phase 2 triages from metadata incrementally, Phase 3 does targeted WebFetch for HIGH-priority items only (max 3 scouts, max 2 fetches each). Scouts write to temp files and return 2-line summaries — main context never ingests raw scout output.

### Three Long-Horizon Strategies

| Strategy | Best For | Brana Mapping |
|---|---|---|
| **Compaction** | Long back-and-forth sessions | `/compact` command + PreCompact hook |
| **Structured Note-Taking** | Iterative development with milestones | SessionEnd hook + auto memory + CONTEXT.md |
| **Sub-Agent Architectures** | Parallel exploration | Scout agent + `context: fork` skills |

All three strategies should be available. The SessionStart hook reads the notes. The SessionEnd hook writes them. Sub-agents keep exploration noise out of the main context.

### Token Budget as Primary Constraint

Quantified relationships from Anthropic's data:
- Agents use **~4x more tokens** than chat interactions
- Multi-agent systems use **~15x more tokens** than chats
- Token usage explains **80% of the variance** in benchmark performance
- Tool Search: 85% token reduction. Programmatic Tool Calling: 37% reduction.

**Implication for brana:** Every architectural decision should be evaluated through the lens of token efficiency. The context budget (~26KB) is the single most important constraint. Skills that produce verbose output must use `context: fork`. The scout agent should be the default for exploration, not the main context.

---

## Evaluating the Brain

See [31-assurance.md](./31-assurance.md) for the full verification framework: structural checks, behavioral tests (learning loop round-trip, quarantine transitions, skill activation), outcome evaluation (RAG metrics, record/playback, grading outcomes not paths), knowledge health indicators, and user feedback calibration.

---

## Self-Describing Configuration and User Feedback

See [32-lifecycle.md](./32-lifecycle.md) for self-describing configuration (frontmatter for skills/rules, `.claude/` as documentation, staleness and locality), the user feedback loop ([00-user-practices.md](../00-user-practices.md)), and the graduation pathway from manual practices to automated enforcement.

---

## Two Persistence Systems: What Goes Where

Brana has two persistence systems. They serve different purposes and must not overlap.

### The Backlog (`30-backlog.md`) — Work Items

The **single system for anything actionable**: things to research, build, fix, evaluate, explore. Visible in the repo, numbered, prioritized, with status and notes.

**What belongs here:**
- Research leads ("look into E2B sandboxes")
- Feature ideas ("add /whatsapp-notify skill")
- Tech debt ("refactor hook error handling")
- Evaluation tasks ("benchmark ZeroClaw vs NanoClaw")
- Anything with a verb: research, build, fix, evaluate, compare, spike

**Why one system:** Two tracking systems (backlog + claude-flow leads) means items get lost, duplicated, or forgotten. The backlog is where you look. Everything actionable goes there.

### Claude-flow Memory — Patterns and Context

The **system for things that inform work**, not things that ARE work. Stored in claude-flow's ReasoningBank (`.swarm/memory.db`) or auto memory files (`~/.claude/projects/*/memory/`).

**What belongs here:**
- **Patterns** — "Haiku scouts can't write temp files" (namespace: `patterns`)
- **Session metadata** — "session 8: kapso research, 1 commit, 4 learnings" (namespace: `patterns`, tag: `session-close`)
- **Architectural decisions** — "chose Kapso over raw Baileys for WhatsApp" (namespace: `decisions`)
- **Cross-project learnings** — "Supabase RLS needs service_role key server-side" (tag: `transferable`)

**What does NOT belong here:**
- Work items, to-dos, leads, or anything with a "do this" implication
- Duplicate facts that live in project files (rates, endpoints, versions)
- Behavioral directives ("always X", "never Y") — those go in `rules/*.md`

### The Rule

> **If it has a verb (research, build, fix, evaluate) → backlog.**
> **If it's a fact, pattern, or lesson → claude-flow memory.**
> **If it's a directive (always, never, must) → rules/ or CLAUDE.md.**

Skills like `/research` propose backlog items in their reports. The user decides which get added. No skill writes directly to claude-flow leads — that created a shadow backlog nobody checked.

---

## Open Questions

### Architecture
1. **How aggressive should cross-pollination be?** Should SessionStart always inject cross-project patterns, or only when explicitly asked? Too much = noise. Too little = missed connections.

### Privacy & Isolation
6. **Project isolation when needed?** Sometimes you DON'T want cross-project contamination — a client project shouldn't leak patterns to a competitor's project. Need a "walls" mechanism.

7. **Sensitive pattern filtering?** Some learnings contain project-specific secrets or business logic. Need a way to mark patterns as non-transferable.

### Advanced Ideas
9. **Project DNA matching?** Each project gets a vector embedding of its architecture. New problems are matched against the most similar project's DNA, not just tag overlap.

See [32-lifecycle.md](./32-lifecycle.md) for lifecycle-related open questions: brain size limits (#3), background learning (#8), apprentice mode (#10).

---

## Research Resources

| # | Author | Topic | Source | Takeaway |
|---|--------|-------|--------|----------|
| 1 | aaditsh | this guy literally built a system that makes | [LI](https://www.linkedin.com/posts/aaditsh_this-guy-literally-built-a-system-that-makes-activity-7323675948703277056-0WdA) | — |
| 2 | akash-g-7a5224246 | treat tools as part of your ontology instead | [LI](https://www.linkedin.com/posts/akash-g-7a5224246_treat-tools-as-part-of-your-ontology-instead-share-7424540964263936000-d_W7?utm_source=share&utm_medium=member_android&rcm=ACoAAARWJLkBjqr70A1PjBg5r3-pHzy3QmyBYwc) | — |
| 3 | aurimas-griciunas | as an %F0%9D%97%94%F0%9D%97%9C %F0%9D%97%98%F0%9D%97%BB%F0%9 | [LI](https://www.linkedin.com/posts/aurimas-griciunas_as-an-%F0%9D%97%94%F0%9D%97%9C-%F0%9D%97%98%F0%9D%97%BB%F0%9D%97%B4%F0%9D%97%B6%F0%9D%97%BB%F0%9D%97%B2%F0%9D%97%B2%F0%9D%97%BF-you-should-also-activity-7418994190577143809-1YeF?utm_source=share&utm_medium=member_android&rcm=ACoAAARWJLkBjqr70A1PjBg5r3-pHzy3QmyBYwc) | — |
| 4 | eordax | ai roadmap learning | [LI](https://www.linkedin.com/posts/eordax_ai-roadmap-learning-activity-7326581191111761922-cfVA?utm_source=share&utm_medium=member_android&rcm=ACoAAARWJLkBjqr70A1PjBg5r3-pHzy3QmyBYwc) | — |
| 5 | gursannikov | ai softwarearchitecture engineering | [LI](https://www.linkedin.com/posts/gursannikov_ai-softwarearchitecture-engineering-share-7426168928265224192-hmCQ?utm_source=share&utm_medium=member_android&rcm=ACoAAARWJLkBjqr70A1PjBg5r3-pHzy3QmyBYwc) | — |
| 6 | hoenig-clemens-09456b98 | architecture of emergence | [LI](https://www.linkedin.com/posts/hoenig-clemens-09456b98_architecture-of-emergence-ugcPost-7425648136406257664-GWRz?utm_source=share&utm_medium=member_android&rcm=ACoAAARWJLkBjqr70A1PjBg5r3-pHzy3QmyBYwc) | — |
| 7 | hugo-mendoza-sui | softwarearchitecture ai artificialintelligence | [LI](https://www.linkedin.com/posts/hugo-mendoza-sui_softwarearchitecture-ai-artificialintelligence-activity-7378821911054561280-tYRt?utm_source=share&utm_medium=member_android&rcm=ACoAAARWJLkBjqr70A1PjBg5r3-pHzy3QmyBYwc) | — |
| 8 | julio-andres-olivares | para ser un ai engineer tienes que saber | [LI](https://www.linkedin.com/posts/julio-andres-olivares_para-ser-un-ai-engineer-tienes-que-saber-activity-7417947598910763009-e1QD?utm_source=share&utm_medium=member_android&rcm=ACoAAARWJLkBjqr70A1PjBg5r3-pHzy3QmyBYwc) | — |
| 9 | lucas-petralli | since i started working with llms ive become | [LI](https://www.linkedin.com/posts/lucas-petralli_since-i-started-working-with-llms-ive-become-ugcPost-7422254208306831360-5GR8?utm_source=share&utm_medium=member_android&rcm=ACoAAARWJLkBjqr70A1PjBg5r3-pHzy3QmyBYwc) | — |
| 10 | mariano-i-m-rey | mi tool stack de ai que s o s uso durante | [LI](https://www.linkedin.com/posts/mariano-i-m-rey_mi-tool-stack-de-ai-que-s%C3%AD-o-s%C3%AD-uso-durante-activity-7361026179417464832-IMpA?utm_source=share&utm_medium=member_android&rcm=ACoAAARWJLkBjqr70A1PjBg5r3-pHzy3QmyBYwc) | — |
| 11 | michalkurkowski | the context i work with is scattered across | [LI](https://www.linkedin.com/posts/michalkurkowski_the-context-i-work-with-is-scattered-across-share-7423328836488093696-CToz?utm_source=share&utm_medium=member_android&rcm=ACoAAARWJLkBjqr70A1PjBg5r3-pHzy3QmyBYwc) | — |
| 12 | migueloteropedrido | 99 of my agent projects follow this structure | [LI](https://www.linkedin.com/posts/migueloteropedrido_99-of-my-agent-projects-follow-this-structure-activity-7341049262434127872-AjUl?utm_source=share&utm_medium=member_android&rcm=ACoAAARWJLkBjqr70A1PjBg5r3-pHzy3QmyBYwc) | — |
| 13 | migueloteropedrido | building agent architectures on aws start | [LI](https://www.linkedin.com/posts/migueloteropedrido_building-agent-architectures-on-aws-start-activity-7391766811337277441-ztQh?utm_source=share&utm_medium=member_android&rcm=ACoAAARWJLkBjqr70A1PjBg5r3-pHzy3QmyBYwc) | — |
| 14 | migueloteropedrido | systems engineering for llm products your | [LI](https://www.linkedin.com/posts/migueloteropedrido_systems-engineering-for-llm-products-your-share-7422928471363842048-1ion?utm_source=share&utm_medium=member_android&rcm=ACoAAARWJLkBjqr70A1PjBg5r3-pHzy3QmyBYwc) | — |
| 15 | migueloteropedrido | the architecture of realtime phone agents | [LI](https://www.linkedin.com/posts/migueloteropedrido_the-architecture-of-realtime-phone-agents-activity-7394305974267944960-PDVi?utm_source=share&utm_medium=member_android&rcm=ACoAAARWJLkBjqr70A1PjBg5r3-pHzy3QmyBYwc) | — |
| 16 | paoloperrone | containers got kubernetes ai agents got | [LI](https://www.linkedin.com/posts/paoloperrone_containers-got-kubernetes-ai-agents-got-share-7420635960624762880-D6dF?utm_source=share&utm_medium=member_android&rcm=ACoAAARWJLkBjqr70A1PjBg5r3-pHzy3QmyBYwc) | — |
| 17 | shubhamsaboo | practical guide to master context engineering | [LI](https://www.linkedin.com/posts/shubhamsaboo_practical-guide-to-master-context-engineering-activity-7351437254445215744-NX0k?utm_source=share&utm_medium=member_android&rcm=ACoAAARWJLkBjqr70A1PjBg5r3-pHzy3QmyBYwc) | — |
| 18 | svpino | context engineering is the new prompt engineering | [LI](https://www.linkedin.com/posts/svpino_context-engineering-is-the-new-prompt-engineering-activity-7402333375560273920-o4yK?utm_source=share&utm_medium=member_android&rcm=ACoAAARWJLkBjqr70A1PjBg5r3-pHzy3QmyBYwc) | — |
| 19 | that-aum | context engineering for ai agents | [LI](https://www.linkedin.com/posts/that-aum_context-engineering-for-ai-agents-ugcPost-7353252392311676928-AfBY) | — |
| 20 | foundationcapital.com | context graphs ais trillion dollar opportunity > | [article](https://foundationcapital.com/context-graphs-ais-trillion-dollar-opportunity/) | — |
| 21 | dan-abramov | A Social Filesystem | [article](https://overreacted.io/a-social-filesystem/) | Dan Abramov (React creator). Social filesystem: apps reactive to standardized files instead of owning data in silos. Collections/Records/Lexicons parallel brana's Dimensions/Specs/Reflections. Key: "apps reactive to data, not data reactive to apps" — roadmaps derived from reflections, not reverse. Data independence + graceful degradation. Validates brana's layered architecture. |
| 22 | marcuspatman | agenticops agenticai ai | [LI](https://www.linkedin.com/posts/marcuspatman_agenticops-agenticai-ai-activity-7384809986796789761-yIYJ) | — |

