---
name: ship
description: "Ship a build — pre-flight checks, deploy, document, verify, monitor. 6 generic steps with project-specific implementation. Use when deploying code, publishing packages, or releasing."
effort: medium
keywords: [deploy, ship, release, publish, rollback, production]
task_strategies: [feature]
stream_affinity: [roadmap]
argument-hint: "[target or task-id]"
group: execution
allowed-tools:
  - Bash
  - Read
  - Write
  - Edit
  - Glob
  - Grep
  - AskUserQuestion
  - Task
  - TaskCreate
  - TaskList
  - TaskUpdate
status: experimental
growth_stage: seed
---

<!-- PROCEDURE_FILE: procedures/ship.md -->
This skill's full procedure is in a separate file for startup performance (ADR-034).
Read and execute `system/procedures/ship.md` from the plugin root directory.
If the path doesn't resolve, use Glob to find `**/procedures/ship.md`.
