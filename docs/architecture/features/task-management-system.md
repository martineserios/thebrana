# Feature: Task Management System

**Date:** 2026-02-18
**Status:** building

## Goal

A project planning and task management system that uses JSON files as the data layer, Claude Code as the NL interface, and hooks for enforcement — enabling hierarchical task tracking (phase > milestone > task) with branch integration, multi-stream support, and passive visibility via the status line.

## Audience

Solo developer managing 3-5 projects across code and non-code work.

## Constraints

- Claude Code subscription only — zero external API calls
- Must work for code projects (git, branches, PRs) and non-code (venture, ops)
- Convention rule budget ~80 lines (total rules budget ~23KB)
- No custom MCP servers or external services
- Git-discipline compliance (branches, worktrees, conventional commits)

## Scope (v1)

- tasks.json schema with hierarchy, streams, execution modes
- Convention rule for NL interaction (reads free, writes confirmed)
- /brana:backlog skill with 13 subcommands (v1: 10, v1.1: +execute, +tags, +context)
- PostToolUse hook: JSON validation + parent rollup
- Session start: task context injection
- Status line: phase progress, current task, bug count
- Morning + weekly-review task awareness
- Feature brief + ADR

## v2 Design: Agent Execution

See ADR-003 for agent-driven task execution — subagent spawning per task, DAG-aware wave parallelism, compose-then-write for code tasks.

## Deferred

- GitHub Issues sync (/brana:backlog sync)
- Markdown rendering (/brana:backlog render > roadmap.md)
- Time tracking (estimated vs actual)
- Recurring tasks
- Cross-project dependencies
- Task templates

## Research findings

- Native Claude Code Tasks: session-scoped, metadata doesn't query, insufficient for PM
- claude-flow tasks: agent coordination tool, 4 fixed types, no hierarchy
- Agent SDK: execution layer, requires API key, doesn't solve data persistence
- JSON files: full control, no N+1, git-tracked, zero dependencies

## Design

See ADR-002 for architecture decision. Key components:
1. tasks.json per project (.claude/tasks.json)
2. Convention rule (~80 lines, teaches Claude schema + NL behavior)
3. /brana:backlog skill (13 subcommands: plan, status, roadmap, next, start, done, add, replan, archive, migrate, execute, tags, context)
4. PostToolUse hook (validation + rollup — deterministic enforcement)
5. Session start + status line integration (passive visibility)
