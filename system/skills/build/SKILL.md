---
name: build
description: "Build anything — features, bug fixes, refactors, spikes, migrations. Auto-detects strategy, integrates with backlog, enforces TDD. The unified dev command."
effort: high
model: sonnet
keywords: [development, implementation, tdd, feature, bug-fix, refactor, coding, fix, broken, hook, deploy, test, debug, error, crash, migrate, investigate]
task_strategies: [feature, bug-fix, refactor, spike, greenfield, migration, investigation]
stream_affinity: [roadmap, bugs, tech-debt, experiments]
argument-hint: "[decompose] [description or task ID]"
group: execution
depends_on:
  - backlog
  - challenge
  - retrospective
allowed-tools:
  - Agent
  - AskUserQuestion
  - Bash
  - Edit
  - EnterPlanMode
  - Glob
  - Grep
  - Read
  - Skill
  - Task
  - TaskCreate
  - TaskList
  - TaskUpdate
  - WebFetch
  - WebSearch
  - Write
  - mcp__ruflo__hive-mind_memory
  - mcp__ruflo__memory_search
  - mcp__ruflo__memory_store
  - mcp__ruflo__agent_spawn
  - mcp__ruflo__claims_claim
  - mcp__ruflo__claims_release
  - ToolSearch
status: stable
growth_stage: evergreen
---

<!-- PROCEDURE_FILE: procedures/build.md -->
This skill's full procedure is in a separate file for startup performance (ADR-034).
Read and execute `system/procedures/build.md` from the plugin root directory.
If the path doesn't resolve, use Glob to find `**/procedures/build.md`.
