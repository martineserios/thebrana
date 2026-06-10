---
name: gsheets
description: "Google Sheets via MCP — read, write, create, list, share spreadsheets. Use when reading, writing, or managing Google Sheets data."
effort: low
keywords: [google-sheets, spreadsheet, csv, data, read, write, mcp]
task_strategies: [feature, spike]
stream_affinity: [roadmap, research]
argument-hint: "[list|read|write|create|summary|share] [args]"
group: utility
allowed-tools:
  - Read
  - Bash
  - AskUserQuestion
model: haiku
status: stable
growth_stage: evergreen
---

<!-- PROCEDURE_FILE: procedures/gsheets.md -->
This skill's full procedure is in a separate file for startup performance (ADR-034).
Read and execute `../../procedures/gsheets.md` resolved against this skill's base directory (the path announced when the skill loads) — i.e. `{base-dir}/../../procedures/gsheets.md`. This form is valid in both the repo layout and the deployed-plugin layout.
If the path doesn't resolve, use Glob to find `**/procedures/gsheets.md`.
