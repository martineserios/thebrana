# Agent Definition Gaps — Unused CC Frontmatter Fields

> Researched 2026-04-13. Source: Claude Code official docs + community analysis.
> Status: ideas — none implemented.

## Context

Brana has 12 specialized agents in `system/agents/`. Current frontmatter uses 6 fields:
`name`, `description`, `model`, `effort`, `tools`, `disallowedTools`.

Claude Code officially supports 16+ fields. Brana uses 6. The gaps below are all supported
today — no CC version upgrade required.

**Note:** `AGENTS.md` is community jargon, not an official CC concept. Brana's
`system/agents/` + plugin distribution is the correct structure. Nothing broken.

---

## Gap 1: `memory` — Per-Agent Institutional Memory

### What it does

CC auto-creates `~/.claude/agent-memory/<name>/` and injects the first 200 lines of
`MEMORY.md` into the agent's system prompt at every invocation. The agent accumulates
its own knowledge across sessions — separate from the global `~/.claude/projects/*/memory/`
and ruflo.

### Why it matters for brana

Brana agents currently have zero institutional memory of their own. debrief-analyst runs
at session end, classifies patterns — but next session it starts fresh, with no memory of
recurring patterns it's seen before, calibration adjustments made, or false positives it
should skip. challenger similarly has no memory of which types of plans it tends to approve
or reject for this project.

With `memory`, each agent builds a profile over time:
- debrief-analyst tracks recurring errata themes, known correction patterns
- memory-curator tracks what it has already migrated, what rules it has extracted
- pr-reviewer accumulates codebase-specific conventions it has learned from past reviews
- challenger tracks which plan types for this project pass vs. recur as failure modes

### Candidates (priority order)

| Agent | Why `memory` helps | What it would store |
|-------|--------------------|---------------------|
| **debrief-analyst** | Runs at every session end — highest accumulation rate | Recurring errata types, calibration notes, known false positives |
| **memory-curator** | Needs to know what it already processed | Migration state, known stale entries, rules already extracted |
| **pr-reviewer** | Learns codebase conventions over time | Project-specific patterns, known acceptable deviations, anti-patterns seen |
| challenger | Calibration state | Plan types that consistently pass/fail for this project |

### Implementation

```yaml
---
name: debrief-analyst
description: "..."
model: opus
effort: high
memory: true        # ← enables ~/.claude/agent-memory/debrief-analyst/MEMORY.md
tools:
  - Bash
  - Read
  - Glob
  - Grep
disallowedTools:
  - Write
  - Edit
  - NotebookEdit
---
```

The agent body should include instructions on how to read and update its memory:
```markdown
## Memory

At startup, read your memory (auto-injected above). Use it to:
- Skip patterns you've already classified and stored
- Apply calibration notes from prior sessions
- Recognize recurring themes faster

At the end of each run, append new durable learnings to your MEMORY.md.
```

### Effort / Value
- Effort: **S per agent** (add `memory: true` to frontmatter + memory-read/write instructions to body)
- Value: **HIGH** — agents that run repeatedly compound knowledge instead of starting fresh every time

---

## Gap 2: `maxTurns` — Runaway Guard

### What it does

Caps the number of agentic turns before CC halts the agent. Prevents cost runaway on
open-ended agents that get stuck in loops or hit unexpected complexity.

### Why it matters for brana

debrief-analyst runs on Opus with `effort: max`. It has Bash access (git log, file reads).
If it gets stuck (missing files, unexpected repo state, ambiguous session data) it can loop
indefinitely — at Opus pricing. No current guard exists.

scout is the other high-risk agent: it uses WebSearch/WebFetch, which can chain recursively
on rich result pages.

### Candidates

| Agent | Model | Risk | Suggested `maxTurns` |
|-------|-------|------|----------------------|
| **debrief-analyst** | Opus | Highest (cost + open-ended) | 15 |
| **scout** | Haiku/Sonnet | Medium (web recursion) | 20 |
| challenger | Sonnet | Low (read-only, bounded) | 10 |
| memory-curator | Haiku | Low | 10 |

### Implementation

```yaml
maxTurns: 15
```

One field, zero body changes needed.

### Effort / Value
- Effort: **XS** (one line per agent)
- Value: **MEDIUM** — prevents edge-case cost runaway, especially on debrief-analyst (Opus)

---

## Gap 3: `permissionMode: plan` — Declarative Read-Only

### What it does

`permissionMode: plan` makes an agent read-only at the CC level — it cannot write files,
run destructive commands, or make external calls. More declarative and complete than
blocking individual tools via `disallowedTools`.

### Why it matters for brana

challenger and scout currently use `disallowedTools: [Write, Edit, Bash, NotebookEdit]`
as a proxy for read-only. But `disallowedTools` is a denylist — if CC adds a new write
tool in a future version, challenger would silently gain write access. `permissionMode: plan`
is a positive declaration: "this agent can only read, always."

Also more ergonomic: instead of listing every write tool to block, one field covers all.

### Candidates

| Agent | Current approach | Better approach |
|-------|-----------------|-----------------|
| **challenger** | `disallowedTools: [Write, Edit, Bash, NotebookEdit]` | `permissionMode: plan` |
| **scout** | reads + WebSearch/WebFetch (no explicit disallow) | `permissionMode: plan` + explicit tool allowlist |
| archiver | `disallowedTools: [Write, Edit, NotebookEdit]` | `permissionMode: plan` |

### Implementation

```yaml
permissionMode: plan
tools:
  - Read
  - Glob
  - Grep
# disallowedTools no longer needed — permissionMode: plan covers it
```

### Effort / Value
- Effort: **XS** (swap disallowedTools for permissionMode on 3 agents)
- Value: **LOW–MEDIUM** — correctness improvement, future-proof against new CC write tools

---

## Gap 4: `skills` — Preloaded Skill Content at Startup

### What it does

The `skills` field in an agent definition preloads full skill content into the agent's
context at startup — before the agent receives its task. Different from skill invocation:
the content is just there, passively, every time.

This is the AGENTS.md pattern Vercel proved: static knowledge in context outperforms
"should I invoke this skill?" decision-making. Applied to agents: challenger always has
the SDD spec pattern in context, pr-reviewer always has code conventions.

### Why it matters for brana

challenger currently reads CALIBRATION.md at runtime (it's referenced in the body).
But it has no preloaded knowledge of brana's SDD spec, ADR format, or common plan
failure modes. A challenger with the SDD spec preloaded would immediately recognize
spec-quality issues without needing to grep for the format.

pr-reviewer has no preloaded knowledge of brana's Rust conventions, skill frontmatter
schema, or hook patterns. It reviews PRs cold every time.

### Candidates

| Agent | Skill to preload | Why |
|-------|-----------------|-----|
| **challenger** | `brana:rust-skills` or SDD spec pattern | Recognizes spec + code quality issues immediately |
| **pr-reviewer** | `brana:rust-skills`, `brana:build` conventions | Reviews PRs with project context preloaded |
| debrief-analyst | `brana:close` procedure (knows what it's looking for) | Better errata classification |

### Implementation

```yaml
skills:
  - brana:rust-skills
```

### Effort / Value
- Effort: **S** (field addition + validate skill loading works via plugin)
- Value: **MEDIUM** — agents start better-informed, especially challenger and pr-reviewer

---

## Gap 5: `isolation: worktree` — Safe Isolated Execution

### What it does

Runs the agent in a temporary git worktree — an isolated copy of the repo. The worktree
is auto-cleaned if no changes were made. If changes were made, the path and branch are
returned for review.

### Why it matters for brana

pr-reviewer is the primary candidate: it reads code to review PRs but should never
modify the working tree. Currently it uses `disallowedTools` as a guardrail.
`isolation: worktree` would give it a truly isolated environment — even if it somehow
gained write access, changes would land in the worktree, not the live repo.

Challenger is a secondary candidate for the same reason.

### Candidates

| Agent | Risk without isolation |
|-------|----------------------|
| **pr-reviewer** | Reads live repo — disallowedTools is the only guard |
| challenger | Read-only by design, but isolation adds defense-in-depth |

### Implementation

```yaml
isolation: worktree
```

### Effort / Value
- Effort: **XS**
- Value: **LOW** — defense-in-depth for agents that are already read-only by design

---

## Gap 6: `color` — Visual Differentiation

### What it does

Tags each agent with a color in the CC UI for quick visual identification.

### Suggested palette

| Agent | Color | Rationale |
|-------|-------|-----------|
| challenger | red | adversarial |
| debrief-analyst | blue | analytical |
| memory-curator | purple | knowledge |
| pr-reviewer | orange | review |
| scout | yellow | fast/discovery |
| daily-ops | green | operational |
| venture-scanner | cyan | business |
| client-scanner | teal | diagnostic |
| archiver | gray | archival |
| metrics-collector | indigo | data |
| pipeline-tracker | amber | pipeline |

### Effort / Value
- Effort: **XS** (one field per agent)
- Value: **LOW** — cosmetic, but useful in multi-agent sessions

---

## Priority Order

| Gap | Field | Effort | Value | Do first? |
|-----|-------|--------|-------|-----------|
| Per-agent memory | `memory` | S/agent | HIGH | Yes — debrief-analyst first |
| Runaway guard | `maxTurns` | XS | MEDIUM | Yes — debrief-analyst + scout |
| Declarative read-only | `permissionMode` | XS | LOW–MEDIUM | Opportunistic |
| Skill preloading | `skills` | S | MEDIUM | After memory gap is closed |
| Worktree isolation | `isolation` | XS | LOW | Opportunistic |
| Visual color | `color` | XS | LOW | Last |

**Fast wins batch** (XS effort, do in one pass): `maxTurns` on 2 agents, `permissionMode`
on 3 agents, `color` on all 12, `isolation` on pr-reviewer. 30 minutes total.

**Higher-value work**: `memory` field + per-agent body instructions (debrief-analyst,
memory-curator, pr-reviewer). Each agent needs a `## Memory` section explaining how to
read prior memory and what to write back.

---

## Sources

- Claude Code official agent docs (code.claude.com/docs/agents)
- Community analysis: addyosmani/agent-skills, OpenClaw, SuperClaude patterns
- Brana agents: `system/agents/` (12 files)
- Vercel AGENTS.md eval: confirmed static-in-context > invocation-decision pattern
