---
name: verify-docs
description: "Periodic doc verification — runs validate.sh structural check, samples assumption rows for semantic review. Run quarterly to collect drift evidence."
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
Read and execute `../../procedures/verify-docs.md` resolved against this skill's base directory (the path announced when the skill loads) — i.e. `{base-dir}/../../procedures/verify-docs.md`. This form is valid in both the repo layout and the deployed-plugin layout.
If the path doesn't resolve, use Glob to find `**/procedures/verify-docs.md`.
