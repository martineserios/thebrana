---
name: client-retire
description: "Archive a client's patterns and mark them as historical. Use when retiring a client or archiving its knowledge for future reference."
effort: low
model: haiku
keywords: [archive, retire, client, historical, cleanup]
task_strategies: [migration]
stream_affinity: [roadmap]
argument-hint: "[client-slug]"
group: execution
allowed-tools:
  - Bash
  - Read
  - Write
  - Glob
  - Grep
  - AskUserQuestion
status: stable
growth_stage: evergreen
---

<!-- PROCEDURE_FILE: procedures/client-retire.md -->
This skill's full procedure is in a separate file for startup performance (ADR-034).
Read and execute `system/procedures/client-retire.md` from the plugin root directory.
If the path doesn't resolve, use Glob to find `**/procedures/client-retire.md`.
