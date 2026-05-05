---
name: verify-docs
description: "Periodic doc verification — runs validate.sh structural check, samples N assumption rows for manual semantic review. No LLM. Run quarterly to collect drift evidence; if >20% drift, unblocks t-441 (LLM-assisted check)."
effort: low
keywords: [verify, docs, assumptions, drift, semantic, freshness, quarterly]
task_strategies: [investigation]
stream_affinity: [docs, tech-debt]
argument-hint: "[--sample N] [--json] [--seed N]"
group: brana
model: haiku
allowed-tools:
  - Bash
  - Read
  - AskUserQuestion
status: stable
growth_stage: prototype
---

<!-- PROCEDURE_FILE: procedures/verify-docs.md -->
This skill's full procedure is in a separate file for startup performance (ADR-034).
Read and execute `system/procedures/verify-docs.md` from the plugin root directory.
If the path doesn't resolve, use Glob to find `**/procedures/verify-docs.md`.
