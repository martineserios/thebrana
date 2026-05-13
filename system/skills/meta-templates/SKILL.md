---
name: meta-templates
description: "Manage Meta WhatsApp templates — submit, status, audit, pull, appeal. Use for any WhatsApp BSP client with ~/.config/brana/meta/<client>.env provisioned."
effort: low
keywords: [meta, whatsapp, templates, waba, submit, audit, appeal, drift, classification, utility, marketing]
task_strategies: [feature]
stream_affinity: [roadmap, tech-debt]
argument-hint: "[submit <yaml> | pull | status [--name X] | audit [--save] | appeal <name>]"
group: utility
model: haiku
allowed-tools:
  - Bash
  - Read
  - Glob
status: stable
growth_stage: evergreen
---

<!-- PROCEDURE_FILE: procedures/meta-templates.md -->
This skill's full procedure is in a separate file for startup performance (ADR-034).
Read and execute `system/procedures/meta-templates.md` from the plugin root directory.
If the path doesn't resolve, use Glob to find `**/procedures/meta-templates.md`.
