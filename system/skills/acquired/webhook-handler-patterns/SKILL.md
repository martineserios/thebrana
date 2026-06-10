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
# Webhook Handler Patterns

## When to Use This Skill

- Following the correct webhook handler order (verify → parse → handle idempotently)
- Implementing idempotent webhook handlers
- Handling errors and configuring retry behavior
- Understanding framework-specific gotchas (raw body, middleware order)
- Building production-ready webhook infrastructure

## Resources

### Handler Sequence

- references/handler-sequence.md (upstream `references/handler-sequence.md`, not installed locally) - Verify first, parse second, handle idempotently third

### Best Practices

- references/idempotency.md (upstream `references/idempotency.md`, not installed locally) - Prevent duplicate processing
- references/error-handling.md (upstream `references/error-handling.md`, not installed locally) - Return codes, logging, dead letter queues
- references/retry-logic.md (upstream `references/retry-logic.md`, not installed locally) - Provider retry schedules, backoff patterns

### Framework Guides

- references/frameworks/express.md (upstream `references/frameworks/express.md`, not installed locally) - Express.js patterns and gotchas
- references/frameworks/nextjs.md (upstream `references/frameworks/nextjs.md`, not installed locally) - Next.js App Router patterns
- references/frameworks/fastapi.md (upstream `references/frameworks/fastapi.md`, not installed locally) - FastAPI/Python patterns

## Quick Reference

### Handler Sequence

1. **Verify signature first** — Use raw body; reject invalid requests with 4xx.
2. **Parse payload second** — After verification, parse or construct the event.
3. **Handle idempotently third** — Check event ID, then process; return 2xx for duplicates.

### Response Codes

| Code | Meaning | Provider Behavior |
|------|---------|-------------------|
| `2xx` | Success | No retry |
| `4xx` | Client error | Usually no retry (except 429) |
| `5xx` | Server error | Retry with backoff |
| `429` | Rate limited | Retry after delay |

### Idempotency Checklist

1. Extract unique event ID from payload
2. Check if event was already processed
3. Process event within transaction
4. Store event ID after successful processing
5. Return success for duplicate events

## Related Skills

- stripe-webhooks, shopify-webhooks, github-webhooks (provider-specific patterns)
- hookdeck-event-gateway (webhook infrastructure with guaranteed delivery, retries, replay)
