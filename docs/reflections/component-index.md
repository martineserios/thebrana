---
last_verified: 2026-04-06
status: active
maturity: seedling
generated: true
depends_on:
  - docs/reflections/ARCHITECTURE.md
---

# Component Index

> **Auto-generated inventory.** This file lists system components derivable from `system/` files. For architectural reasoning (WHY things compose this way), see [ARCHITECTURE.md](ARCHITECTURE.md).
>
> TODO: Auto-generate from `system/` directory structure via `brana graph build` (Phase 7, t-450).

## Plugin Structure

```
system/
├── .claude-plugin/plugin.json    ← Plugin manifest
├── skills/                       ← /brana:* slash commands
├── agents/                       ← 11 specialized sub-agents
├── hooks/                        ← Event hooks (PreToolUse, SessionStart, SessionEnd, SubagentStart, TaskCompleted)
├── commands/                     ← Agent commands (repo-cleanup; maintain-specs/apply-errata retired Phase 12)
└── CLAUDE.md                     ← Mastermind identity
```

## Identity Layer

```
~/.claude/                        ← Deployed via bootstrap.sh
├── CLAUDE.md                     ← Global identity
├── rules/                        ← 14 behavioral rules
├── scripts/                      ← Helper scripts (cf-env, memory-store, index-knowledge)
├── memory/MEMORY.md              ← Auto memory (first 200 lines always in context)
├── statusline.sh                 ← Status bar
└── scheduler/                    ← Scheduled jobs
```

## Agent Roster

| Agent | Model | Purpose |
|-------|-------|---------|
| scout | Haiku | Fast research, file discovery |
| memory-curator | Haiku | Knowledge lifecycle |
| client-scanner | Haiku | Project structure analysis |
| venture-scanner | Haiku | Business project analysis |
| challenger | Sonnet | Adversarial review |
| debrief-analyst | Opus | Session learning extraction |
| archiver | Haiku | Knowledge backup and export |
| daily-ops | Haiku | Daily operational checks |
| metrics-collector | Haiku | Data gathering for reviews |
| pipeline-tracker | Haiku | Pipeline tracking |
| pr-reviewer | Sonnet | PR diff review |

## Skill Catalog

See `system/skills/*/SKILL.md` for full skill definitions.

| Skill | Category | Purpose |
|-------|----------|---------|
| /brana:acquire-skills | Setup | Find and install skills for tech gaps |
| /brana:align | Setup | Implement project structure |
| /brana:backlog | Planning | Task management across phases/streams |
| /brana:brainstorm | Planning | Interactive idea maturation |
| /brana:build | Development | Unified dev command — 7 strategies |
| /brana:challenge | Quality | Adversarial plan/decision review |
| /brana:client-retire | Lifecycle | Archive client patterns |
| /brana:close | Development | Session end — learnings, handoff |
| /brana:do | Routing | Route freeform text to best skill |
| /brana:docs | Documentation | Generate and update living docs |
| /brana:export-pdf | Utility | Convert markdown to PDF |
| /brana:gsheets | Integration | Google Sheets via MCP |
| /brana:ship | Deployment | Ship a build — pre-flight, deploy, verify, monitor |
| /brana:log | Operations | Event capture (links, calls, ideas) |
| /brana:memory | Knowledge | Recall, pollinate, review, audit |
| /brana:onboard | Setup | Scan and diagnose a project |
| /brana:plugin | System | Manage Claude Code plugins |
| /brana:reconcile | Maintenance | Detect spec-vs-implementation drift |
| /brana:research | Knowledge | Topic research + dimension refresh |
| /brana:retrospective | Learning | Store learnings and patterns |
| /brana:review | Business | Weekly/monthly health checks |
| /brana:scheduler | System | Manage scheduled jobs |
| /brana:sitrep | Operations | Context recovery after compression |

## Hook Inventory

| Hook | Event | Purpose |
|------|-------|---------|
| pre-tool-use.sh | PreToolUse | SDD gate + cascade throttle |
| tdd-gate.sh | PreToolUse | TDD enforcement — blocks impl writes without tests |
| plan-mode-gate.sh | PreToolUse | Gate EnterPlanMode access |
| worktree-gate.sh | PreToolUse | Enforce worktree usage on dirty repos |
| session-start.sh | SessionStart | Pattern recall + task context |
| session-end.sh | SessionEnd | Flywheel metrics + learning flush |
| subagent-context.sh | SubagentStart | Inject context into subagents |
| subagent-tracker.sh | SubagentStart+SubagentStop | Track agent spawns/completions |
| step-completed.sh | TaskCompleted | Build step completion tracking |
| stopfailure-logger.sh | StopFailure | Log API errors to JSONL |
| post-tool-use.sh | PostToolUse | Log successes, detect corrections |
| post-tool-use-failure.sh | PostToolUseFailure | Error categorization + cascade detection |
| post-plan-challenge.sh | PostToolUse | Challenger nudge |
| post-pr-review.sh | PostToolUse | PR reviewer nudge |
| post-tasks-validate.sh | PostToolUse | Schema validation + auto-rollup |
| post-sale.sh | PostToolUse | Deal closure detection |
| task-completed.sh | PostToolUse (Bash) | Task completion + GitHub Issues sync |
| config-drift.sh | (utility) | Compare system/ source vs deployed ~/.claude/ |

## Recommended Plugins

| Plugin | Role |
|--------|------|
| Context7 MCP (Upstash) | Real-time library docs |
| ruflo MCP | Cross-project memory |
| security-guidance (Anthropic) | Safety net |
| pr-review-toolkit (Anthropic) | Code review |

## Research Resources

See [14-mastermind-architecture.md](../archive/reflections/14-mastermind-architecture.md) research table for the original 22-source bibliography.
