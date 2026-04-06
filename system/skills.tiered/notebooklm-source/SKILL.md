---
name: notebooklm-source
description: "Guided workflow to prepare and format sources for NotebookLM. Claude reads, reformats, validates, and writes optimized files. User uploads them in the browser. Step-by-step recipe with clear handoff points."
effort: low
keywords: [notebooklm, google, source, format, upload, gemini]
task_strategies: [feature, spike]
stream_affinity: [research, docs]
group: tools
allowed-tools:
  - Read
  - Write
  - Edit
  - Glob
  - Grep
  - Bash
  - Task
  - mcp__notebooklm__ask_question
  - mcp__notebooklm__add_notebook
  - mcp__notebooklm__list_notebooks
  - mcp__notebooklm__select_notebook
  - mcp__notebooklm__get_notebook
  - mcp__notebooklm__search_notebooks
  - mcp__notebooklm__get_health
  - mcp__notebooklm__get_library_stats
  - mcp__notebooklm__setup_auth
  - AskUserQuestion
status: stable
growth_stage: evergreen
---

<!-- PROCEDURE_FILE: procedures/notebooklm-source.md -->
This skill's full procedure is in a separate file for startup performance (ADR-034).
Read and execute `system/procedures/notebooklm-source.md` from the plugin root directory.
If the path doesn't resolve, use Glob to find `**/procedures/notebooklm-source.md`.
