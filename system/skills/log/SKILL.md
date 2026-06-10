---
name: log
description: "Capture events — links, calls, meetings, ideas — into an append-only log. Bulk mode for WhatsApp dumps. Use when something happened."
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
Read and execute `../../procedures/log.md` resolved against this skill's base directory (the path announced when the skill loads) — i.e. `{base-dir}/../../procedures/log.md`. This form is valid in both the repo layout and the deployed-plugin layout.
If the path doesn't resolve, use Glob to find `**/procedures/log.md`.
