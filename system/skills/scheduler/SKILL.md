---
name: scheduler
description: "Manage scheduled jobs — create, update, list, run remote agents on cron. Use when setting up recurring tasks, checking job status, or managing automation."
effort: low
model: haiku
keywords: [cron, schedule, jobs, systemd, timer, recurring]
task_strategies: [feature, bug-fix]
stream_affinity: [roadmap, tech-debt]
argument-hint: "[status|logs|enable|disable|run|validate|deploy|teardown] [job]"
group: utility
allowed-tools:
  - Bash
  - AskUserQuestion
status: stable
growth_stage: evergreen
---

<!-- PROCEDURE_FILE: procedures/scheduler.md -->
This skill's full procedure is in a separate file for startup performance (ADR-034).
Read and execute `system/procedures/scheduler.md` from the plugin root directory.
If the path doesn't resolve, use Glob to find `**/procedures/scheduler.md`.
