---
last_verified: 2026-03-14
status: active
maturity: seedling
generated: true
---

# Component Index

> **Auto-generated inventory.** This file lists system components derivable from `system/` files. For architectural reasoning (WHY things compose this way), see [ARCHITECTURE.md](ARCHITECTURE.md).
>
> TODO: Auto-generate from `system/` directory structure via `spec_graph.py` (Phase 7, t-450).

## Plugin Structure

```
system/
├── .claude-plugin/plugin.json    ← Plugin manifest
├── skills/                       ← /brana:* slash commands
├── agents/                       ← 11 specialized sub-agents
├── hooks/                        ← Event hooks (PreToolUse, SessionStart, SessionEnd)
├── commands/                     ← Agent commands (maintain-specs, apply-errata, etc.)
└── CLAUDE.md                     ← Mastermind identity
```

## Identity Layer

```
~/.claude/                        ← Deployed via bootstrap.sh
├── CLAUDE.md                     ← Global identity
├── rules/                        ← 13 behavioral rules
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
| challenger | Opus | Adversarial review |
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
| /brana:build | Development | Unified dev command — 7 strategies |
| /brana:close | Development | Session end — learnings, handoff |
| /brana:backlog | Planning | Task management across phases/streams |
| /brana:onboard | Setup | Scan and diagnose a project |
| /brana:align | Setup | Implement project structure |
| /brana:review | Business | Weekly/monthly health checks |
| /brana:research | Knowledge | Topic research + dimension refresh |
| /brana:memory | Knowledge | Recall, pollinate, review, audit |
| /brana:reconcile | Maintenance | Detect spec-vs-implementation drift |
| /brana:challenge | Quality | Adversarial plan/decision review |
| /brana:pipeline | Business | Sales pipeline tracking |
| /brana:venture-phase | Business | Business milestone execution |
| /brana:financial-model | Business | Revenue projections |
| /brana:log | Operations | Event capture (links, calls, ideas) |
| /brana:plugin | System | Manage Claude Code plugins |

## Hook Inventory

| Hook | Event | Purpose |
|------|-------|---------|
| pre-tool-use.sh | PreToolUse | SDD gate + cascade throttle |
| session-start.sh | SessionStart | Pattern recall + task context |
| session-end.sh | SessionEnd | Flywheel metrics + learning flush |
| post-tool-use.sh | PostToolUse | Log successes, detect corrections |
| post-tool-use-failure.sh | PostToolUseFailure | Error categorization |
| task-sync.sh | PostToolUse | tasks.json → GitHub Issues sync |
| post-pr-review.sh | PostToolUse | PR reviewer nudge |
| post-plan-challenge.sh | PostToolUse | Challenger nudge |
| post-tasks-validate.sh | PostToolUse | Schema validation + auto-rollup |
| post-sale.sh | PostToolUse | Deal closure detection |

## Recommended Plugins

| Plugin | Role |
|--------|------|
| Context7 MCP (Upstash) | Real-time library docs |
| ruflo MCP | Cross-project memory |
| security-guidance (Anthropic) | Safety net |
| pr-review-toolkit (Anthropic) | Code review |

## Research Resources

See [14-mastermind-architecture.md](../archive/reflections/14-mastermind-architecture.md) research table for the original 22-source bibliography.
