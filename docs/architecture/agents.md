# Agents Architecture

> Design principles and routing for brana agents. For complete per-agent behavior specs, see [Agent Reference](../reference/agents.md).

## Design Principles

- **Agent results are inputs, not decisions.** The main context presents findings to the user. File modifications happen in main context after approval.
- **All agents are read-only.** Every agent disallows Write, Edit, and NotebookEdit. Some have Bash for CLI commands (e.g., `gh`, `git`, `ruflo`).
- **Auto-delegation is rule-based.** The `delegation-routing` rule (in `~/.claude/rules/`) defines triggers -- agents fire without being asked when the situation matches.
- **Model selection by task complexity.** Haiku for fast/cheap work (8 agents), Sonnet for moderate analysis (2), Opus for deep reasoning (1). Challenger uses Sonnet intentionally — a different model than the Opus parent context catches blind spots the originating model can't see.

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

The `model` field controls cost and capability. The `description` includes explicit "Use when" and "Not for" guidance to help with routing decisions.

## Field Notes

### 2026-04-08: Session JSONL telemetry is global — bucket by repo root for debrief accuracy
A single CC session can straddle multiple project roots. Correction counts in `brana-session-*.jsonl` are global — a hot file in a sibling venture (28 corrections on `ventures/ai-native-education/`) inflated the thebrana debrief during a t-1088 session. Fix: when reading session JSONL, filter events by `file.startsWith(repo_root)` before computing `correction_rate` and `cascade_rate`. Tracked as t-1092.
Source: t-1088 session debrief
