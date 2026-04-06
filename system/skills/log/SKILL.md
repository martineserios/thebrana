---
name: log
description: "Capture events — links, calls, meetings, ideas, observations — into a searchable append-only log. Includes bulk mode for WhatsApp dumps and URL-to-task promotion. Use when something happened and you want to capture it quickly."
effort: low
keywords: [logging, events, capture, meetings, links, observations, whatsapp, bulk]
task_strategies: [feature, spike]
stream_affinity: [roadmap, docs]
argument-hint: "[event text or bulk]"
group: capture
model: haiku
allowed-tools:
  - Read
  - Write
  - Edit
  - Glob
  - Grep
  - Bash
  - AskUserQuestion
status: stable
growth_stage: evergreen
---

<!-- PROCEDURE_FILE: procedures/log.md -->
This skill's full procedure is in a separate file for startup performance (ADR-034).
Read and execute `system/procedures/log.md` from the plugin root directory.
If the path doesn't resolve, use Glob to find `**/procedures/log.md`.
