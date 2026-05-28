# Agents Architecture

> Design principles and routing for brana agents. For complete per-agent behavior specs, see [Agent Reference](../reference/agents.md).

## Design Principles

- **Agent results are inputs, not decisions.** The main context presents findings to the user. File modifications happen in main context after approval.
- **Most agents are read-only.** Most agents disallow Write, Edit, and NotebookEdit. Agents with `memory: true` (challenger, debrief-analyst, memory-curator, pr-reviewer) may write to `~/.claude/agent-memory/` for cross-session recall.
- **Auto-delegation is rule-based.** The `delegation-routing` rule (in `~/.claude/rules/`) defines triggers — agents fire without being asked when the situation matches.
- **Model selection by task complexity.** Haiku for fast/cheap work, Sonnet for moderate analysis, Opus for deep reasoning. Challenger uses Sonnet intentionally — a different model than the Opus parent context catches blind spots the originating model can't see.

## Routing Table

| Agent | Model | Auto-fires when |
|-------|-------|-----------------|
| memory-curator | Haiku | Starting work, familiar problem, stuck |
| client-scanner | Haiku | New client, project health check |
| venture-scanner | Haiku | New business project |
| challenger | Sonnet | Plan or architecture decision forming (calibrated: CALIBRATION.md) |
| debrief-analyst | Opus | End of implementation session |
| scout | Haiku | Research tasks (spawned by skills) |
| archiver | Haiku | Retiring a client |
| daily-ops | Haiku | Session start on venture project |
| metrics-collector | Haiku | `/brana:review` runs |
| pipeline-tracker | Haiku | Pipeline tracking, deal events |
| pr-reviewer | Sonnet | PR creation (auto-triggered via hook) |
| gemini | Haiku | `/brana:gemini` skill invoked — research and doc delegation via agy |

## Agent Groups

| Group | Agents | Purpose |
|-------|--------|---------|
| Knowledge | memory-curator, scout | Pattern recall, fast research |
| Diagnostic | client-scanner, venture-scanner | Project assessment |
| Review | challenger, debrief-analyst, pr-reviewer | Quality and learning |
| Business | daily-ops, metrics-collector, pipeline-tracker | Venture operations |
| Lifecycle | archiver | Client retirement |
| Execution | gemini | Gemini delegation via agy |

## Hook-Triggered Agents

| Hook | Agent | Event |
|------|-------|-------|
| `post-plan-challenge.sh` | challenger | After ExitPlanMode |
| `post-pr-review.sh` | pr-reviewer | After `gh pr create` |
| `session-start.sh` | daily-ops | Venture project detected |

## Agent Anatomy

Every agent lives at `system/agents/{name}.md`:

```yaml
---
name: agent-name
description: "One-line description with 'Use when' and 'Not for' guidance."
model: haiku          # haiku | sonnet | opus
memory: false         # true → agent can write to ~/.claude/agent-memory/
maxTurns: 10          # optional — caps agentic loop iterations
permissionMode: plan  # optional — plan | bypassPermissions | default
isolation: worktree   # optional — worktree (git isolation for the agent)
color: purple         # optional — UI color hint for the agent bubble
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

# Agent Name

Instructions for the agent...
```

### Frontmatter Field Reference

| Field | Type | Default | Purpose |
|-------|------|---------|---------|
| `name` | string | required | Agent identifier; matches filename |
| `description` | string | required | Routing hint — include "Use when" and "Not for" |
| `model` | enum | inherit | `haiku` · `sonnet` · `opus` |
| `memory` | bool | false | `true` allows writes to `~/.claude/agent-memory/` for cross-session recall |
| `maxTurns` | int | unlimited | Caps agentic loop iterations to prevent runaway agents |
| `permissionMode` | enum | default | `plan` requires plan approval before edits; `bypassPermissions` skips prompts |
| `isolation` | enum | none | `worktree` gives agent a clean git worktree (auto-cleaned if no changes) |
| `color` | string | none | UI color hint for the agent bubble in Claude Code |
| `tools` | list | all | Allowlist of tools the agent may call |
| `disallowedTools` | list | none | Blocklist — overrides `tools` allowlist |

The `model` field controls cost and capability. The `description` includes explicit "Use when" and "Not for" guidance to help with routing decisions.

## Field Notes

### 2026-05-11: Agent file count != functional agent count — filter by model: frontmatter
`ls system/agents/` returns 13 files but only 12 are functional agents. `CALIBRATION.md` is a calibration doc for challenger-calibration and has no `model:` frontmatter line. Any tool or doc that counts agents by file count will overcount by 1. Correct count: `grep -l '^model:' system/agents/*.md | wc -l`. Generalizes: always filter by the defining frontmatter field, not raw file count.
Source: reconcile consistency scan 2026-05-11

### 2026-04-08: Session JSONL telemetry is global — bucket by repo root for debrief accuracy
A single CC session can straddle multiple project roots. Correction counts in `brana-session-*.jsonl` are global — a hot file in a sibling venture (28 corrections on `ventures/ai-native-education/`) inflated the thebrana debrief during a t-1088 session. Fix: when reading session JSONL, filter events by `file.startsWith(repo_root)` before computing `correction_rate` and `cascade_rate`. Tracked as t-1092.
Source: t-1088 session debrief

### 2026-05-28: Agent type and skill registries are separate — both must exist for delegation
`Agent(subagent_type="brana:gemini")` fails at runtime if `system/agents/gemini.md` is absent, even if the `/brana:gemini` skill exists. The skill registry (SKILL.md scanning) and the agent type registry (system/agents/*.md) are independent lookup systems. Rule: whenever a skill delegates via `Agent(subagent_type=)`, the corresponding agent definition file must also exist. Fix for t-1705 confirmed this: creating system/agents/gemini.md resolved the runtime failure.
Source: t-1705 / close 2026-05-28

### 2026-05-19: Layered challenger — three rounds for M+ architecture decisions
A single challenger pass misses layered issues: the fixes for round-1 CRITICALs introduce new failure modes that only round 2 catches. For M+ architecture decisions, run challenger at minimum twice, ideally three times. Round 1: surface CRITICALs. Round 2: verify the proposed fixes actually hold (check code, not just the plan text). Round 3: confirm no new issues introduced. Stop when verdict is PROCEED WITH CHANGES or PROCEED — not just after the first RECONSIDER. Validated on brana backlog web UI (t-1501): R1 found stdio-only + write race; R2 found save_tasks still bare fs::write + latency gate theater; R3 confirmed fixes held and issued PROCEED WITH CHANGES.
Source: brainstorm(backlog-ui) 2026-05-19
