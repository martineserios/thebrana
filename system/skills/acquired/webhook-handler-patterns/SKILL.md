---
name: webhook-handler-patterns
description: "Best practices for webhook handlers: verify → parse → handle idempotently. Covers idempotency, error handling, retry logic, framework-specific gotchas (Express, Next.js, FastAPI). Use when implementing any webhook receiver."
group: brana
keywords: [webhook, handler, idempotency, signature-verification, retry, express, nextjs, fastapi, http]
allowed-tools: [Read, Write, Edit, Glob, Grep, AskUserQuestion]
status: experimental
source: "github.com/hookdeck/webhook-skills/skills/webhook-handler-patterns"
acquired: "2026-05-14"
quarantine: false
---

<!-- PROCEDURE_FILE: procedures/webhook-handler-patterns.md -->
This skill's full procedure is in a separate file for startup performance (ADR-034).
Read and execute `system/procedures/webhook-handler-patterns.md` from the plugin root directory.
If the path doesn't resolve, use Glob to find `**/procedures/webhook-handler-patterns.md`.
