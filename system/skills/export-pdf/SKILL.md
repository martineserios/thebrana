---
name: export-pdf
description: "Convert a markdown file to PDF using mdpdf. Use when exporting proposals, SOPs, or any markdown document to PDF."
effort: low
keywords: [pdf, export, markdown, document, proposal, sop]
task_strategies: [feature]
stream_affinity: [docs]
argument-hint: "[file.md]"
group: utility
model: haiku
allowed-tools:
  - Bash
  - Read
  - Glob
  - AskUserQuestion
status: stable
growth_stage: evergreen
---

<!-- PROCEDURE_FILE: procedures/export-pdf.md -->
This skill's full procedure is in a separate file for startup performance (ADR-034).
Read and execute `system/procedures/export-pdf.md` from the plugin root directory.
If the path doesn't resolve, use Glob to find `**/procedures/export-pdf.md`.
