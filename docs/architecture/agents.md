# Agent Roster

> 11 specialized sub-agents that auto-delegate when the situation matches. Agents are defined as markdown files in `system/agents/` with YAML frontmatter specifying model, tools, and disallowed tools.

## How Agents Work

Agents are spawned as sub-processes by Claude Code's Agent tool. They receive a task, work autonomously using their allowed tools, and return findings to the main context. The user then decides what to act on.

Key principles:
- **Agent results are inputs, not decisions.** The main context presents findings to the user.
- **Agents are mostly read-only.** All agents disallow Write, Edit, and NotebookEdit. Some have Bash for CLI commands (e.g., `gh`, `git`, `claude-flow`).
- **Auto-delegation is rule-based.** The `delegation-routing` rule defines triggers — agents fire without being asked when the situation matches.

## Agent Details

### scout

| | |
|---|---|
| **Model** | Haiku |
| **Tools** | Read, Glob, Grep, WebSearch, WebFetch |
| **Fires when** | Research tasks, spawned by skills like `/research` |

Fast research agent for codebase exploration and web search. Finds files, searches code, and fetches external information. Returns concise, structured findings (1,000-2,000 tokens). Cannot run commands or write files.

### memory-curator

| | |
|---|---|
| **Model** | Haiku |
| **Tools** | Bash, Read, Glob, Grep |
| **Fires when** | Starting work on a topic, encountering a familiar problem, periodic checks |

Recalls patterns from the knowledge system, cross-pollinates across projects, and checks knowledge health. Uses claude-flow CLI for semantic search. Returns relevant patterns and health assessments.

### project-scanner

| | |
|---|---|
| **Model** | Haiku |
| **Tools** | Bash, Read, Glob, Grep |
| **Fires when** | Entering an unfamiliar project, project health checks |

Scans project structure, detects tech stack (by reading manifest files), and checks brana alignment. Returns a structured diagnostic with stack info, alignment gaps, and recommendations.

### venture-scanner

| | |
|---|---|
| **Model** | Haiku |
| **Tools** | Bash, Read, Glob, Grep |
| **Fires when** | First encounter with a business project, business health audits |

Diagnoses a business project — classifies its stage, recommends stage-appropriate frameworks, and identifies gaps. Scans for business artifacts (SOPs, OKRs, metrics, pipeline) and maps them to a maturity model.

### challenger

| | |
|---|---|
| **Model** | Opus |
| **Tools** | Read, Glob, Grep |
| **Fires when** | Plan or architecture decision is forming, after `ExitPlanMode` |

Adversarial review agent. Stress-tests plans and decisions with three challenge flavors: pre-mortem ("what kills this?"), simplicity challenge ("what's the simplest version?"), and assumption check ("what are we taking for granted?"). Strictly read-only — no Bash access.

### debrief-analyst

| | |
|---|---|
| **Model** | Opus |
| **Tools** | Bash, Read, Glob, Grep |
| **Fires when** | End of implementation sessions, notable learnings emerge |

Extracts errata, learnings, and patterns from work sessions. Reads recent git history, changed files, and session context. Classifies findings into errata (factual corrections), process learnings (workflow improvements), and issues (problems to track).

### pr-reviewer

| | |
|---|---|
| **Model** | Sonnet |
| **Tools** | Read, Glob, Grep, Bash |
| **Fires when** | After `gh pr create` (via post-pr-review hook) |

Reviews PR diffs for code quality, security, bugs, and style. Uses `gh` CLI to read PR data and project files for context. Returns a structured review with severity-rated findings. Auto-triggered on PR creation.

### daily-ops

| | |
|---|---|
| **Model** | Haiku |
| **Tools** | Bash, Read, Glob, Grep |
| **Fires when** | Session start on a venture project (via session-start-venture hook) |

Produces a daily focus card for venture projects — health snapshot, pending actions, experiments in progress, key metrics. Scans SOPs, OKRs, pipeline, and metrics directories.

### metrics-collector

| | |
|---|---|
| **Model** | Haiku |
| **Tools** | Bash, Read, Glob, Grep |
| **Fires when** | `/growth-check`, `/weekly-review`, or `/monthly-close` run |

Collects venture metrics from multiple sources — health snapshots, experiment results, pipeline data, financial records. Returns organized raw data for skills to analyze.

### pipeline-tracker

| | |
|---|---|
| **Model** | Haiku |
| **Tools** | Bash, Read, Glob, Grep |
| **Fires when** | Pipeline or deal-related work is happening |

Reads deal records, identifies overdue follow-ups, spots stage-stuck deals, and summarizes conversion trends. Works with the `/pipeline` skill for CRM tracking.

### archiver

| | |
|---|---|
| **Model** | Haiku |
| **Tools** | Bash, Read, Glob, Grep |
| **Fires when** | Retiring a project (via `/project-retire`) |

Scans a project's accumulated knowledge and categorizes patterns as transferable (useful in other projects), historical (project-specific, archive only), or deletable (stale/irrelevant). Supports the project retirement workflow.

## Auto-Delegation Triggers

The `delegation-routing` rule maps situations to agents:

| Situation | Agent |
|-----------|-------|
| Starting work, familiar problem, stuck | memory-curator |
| New project, project health check | project-scanner |
| New business project | venture-scanner |
| Plan or architecture decision forming | challenger |
| End of implementation session | debrief-analyst |
| Research tasks (spawned by skills) | scout |
| Retiring a project | archiver |
| Session start on venture project | daily-ops |
| Growth-check, weekly-review, monthly-close | metrics-collector |
| Pipeline tracking, deal events | pipeline-tracker |
| After PR creation | pr-reviewer |

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

The `model` field controls cost and capability. Haiku for fast/cheap tasks, Sonnet for moderate analysis, Opus for deep reasoning. All agents disallow file modification tools.
