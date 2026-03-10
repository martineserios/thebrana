# Agents Architecture

> 11 specialized sub-agents that auto-delegate when the situation matches. Defined as markdown files in `system/agents/` with YAML frontmatter specifying model, tools, and disallowed tools. For complete behavior specs, see [Agent Reference](../reference/agents.md).

## Design principles

- **Agent results are inputs, not decisions.** The main context presents findings to the user. File modifications happen in main context after approval.
- **All agents are read-only.** Every agent disallows Write, Edit, and NotebookEdit. Some have Bash for CLI commands (e.g., `gh`, `git`, `claude-flow`).
- **Auto-delegation is rule-based.** The `delegation-routing` rule (in `~/.claude/rules/`) defines triggers -- agents fire without being asked when the situation matches.
- **Model selection by task complexity.** Haiku for fast/cheap work (8 agents), Sonnet for moderate analysis (1), Opus for deep reasoning (2).

## Routing table

| Agent | Model | Auto-fires when | Read-only |
|-------|-------|-----------------|-----------|
| memory-curator | Haiku | Starting work, familiar problem, stuck | Yes |
| client-scanner | Haiku | New client, project health check | Yes |
| venture-scanner | Haiku | New business project | Yes |
| challenger | Opus | Plan or architecture decision forming | Yes |
| debrief-analyst | Opus | End of implementation session | Yes |
| scout | Haiku | Research tasks (spawned by skills) | Yes |
| archiver | Haiku | Retiring a client | Yes |
| daily-ops | Haiku | Session start on venture project | Yes |
| metrics-collector | Haiku | `/brana:review` runs (weekly, monthly, check) | Yes |
| pipeline-tracker | Haiku | Pipeline tracking, deal events | Yes |
| pr-reviewer | Sonnet | PR creation (auto-triggered via hook) | Yes |

## Agent groups

### Knowledge agents

- **memory-curator** (Haiku) -- Searches claude-flow memory and native auto memory for relevant patterns. Groups results by confidence tier: Proven (>= 0.7), Quarantined (0.2-0.7), Suspect (< 0.2). Also surfaces knowledge base results from brana-knowledge dimension docs.
- **scout** (Haiku) -- Fast research agent. Searches codebase and web for information. Returns 1,000-2,000 tokens. Phase 1 scouts use WebSearch only; Phase 3 scouts get max 2 WebFetch calls. Cannot write files or run commands.

### Diagnostic agents

- **client-scanner** (Haiku) -- Detects tech stack, scans structure, runs 28-item alignment checklist across 6 groups (Foundation, SDD, TDD, Quality, PM & Memory, Verification). Returns alignment score with visual bars per group.
- **venture-scanner** (Haiku) -- Classifies business stage (Discovery/Validation/Growth/Scale), recommends stage-appropriate framework, runs stage-cumulative gap analysis. Never recommends frameworks above current stage.

### Review agents

- **challenger** (Opus) -- Adversarial review with 4 flavors: pre-mortem, simplicity challenge, assumption buster, adversarial user. Findings classified as Critical/Warning/Observation with verdict (PROCEED, PROCEED WITH CHANGES, RECONSIDER). Strictly read-only -- no Bash.
- **debrief-analyst** (Opus) -- Extracts session findings into 6 categories: errata, process learnings, issues, correction patterns, cascade patterns, test coverage gaps. Applies confidence quarantine to new findings.
- **pr-reviewer** (Sonnet) -- Reviews PR diffs against 4-category checklist: Security (Critical), Logic (High), Style & Convention (Medium), Completeness (Medium). Assigns risk level. Auto-triggered via `post-pr-review.sh` hook.

### Business agents

- **daily-ops** (Haiku) -- Daily focus card for venture projects: top 3 priorities, key metric + trend, blockers, overdue follow-ups, active experiments. Fires via session-start.sh venture detection.
- **metrics-collector** (Haiku) -- Collects health snapshots, experiment results, pipeline data, financial data from project directories and claude-flow. Reports data gaps.
- **pipeline-tracker** (Haiku) -- Pipeline status: deals per stage, overdue follow-ups (no activity 14+ days), stage-stuck deals, conversion trends.

### Lifecycle agents

- **archiver** (Haiku) -- Categorizes a client's patterns as transferable (confidence >= 0.7, not project-specific), historical (project-specific but worth keeping), or deletable (low confidence, never validated). When in doubt, classifies as historical.

## Hook-triggered agents

Several agents are nudged by hooks injecting `additionalContext`:

| Hook | Agent triggered |
|------|----------------|
| `post-plan-challenge.sh` | challenger (after ExitPlanMode) |
| `post-pr-review.sh` | pr-reviewer (after `gh pr create`) |
| `session-start.sh` | daily-ops (venture project detected) |

## Agent anatomy

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
