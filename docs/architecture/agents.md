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

## Agent Groups

| Group | Agents | Purpose |
|-------|--------|---------|
| Knowledge | memory-curator, scout | Pattern recall, fast research |
| Diagnostic | client-scanner, venture-scanner | Project assessment |
| Review | challenger, debrief-analyst, pr-reviewer | Quality and learning |
| Business | daily-ops, metrics-collector, pipeline-tracker | Venture operations |
| Lifecycle | archiver | Client retirement |

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

### 2026-04-08: Session JSONL telemetry is global — bucket by repo root for debrief accuracy
A single CC session can straddle multiple project roots. Correction counts in `brana-session-*.jsonl` are global — a hot file in a sibling venture (28 corrections on `ventures/ai-native-education/`) inflated the thebrana debrief during a t-1088 session. Fix: when reading session JSONL, filter events by `file.startsWith(repo_root)` before computing `correction_rate` and `cascade_rate`. Tracked as t-1092.
Source: t-1088 session debrief
