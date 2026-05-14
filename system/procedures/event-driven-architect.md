---
name: event-driven-architect
description: >-
  Design event-driven systems: contracts, topics, consumers, retries,
  idempotency, and sagas. Use for asynchronous workflows. NOT for CRUD APIs or
  ETL pipelines.
argument-hint: "<mode> [target]"
license: MIT
metadata:
  author: wyattowalsh
  version: "1.0.0"
---

# Event-Driven Architect

Design asynchronous systems built around durable events, explicit contracts, and
operationally safe consumers.

**Scope:** Event-driven application architecture and reliability patterns. NOT
for synchronous API design (api-designer) or batch ETL pipeline design
(data-pipeline-architect).

## Canonical Vocabulary

| Term | Definition |
|------|------------|
| **event** | Immutable record of something that happened |
| **command** | Request to perform an action, not a fact |
| **topic** | Named stream or channel carrying related events |
| **partition key** | Value used to preserve order for a subset of events |
| **consumer group** | Independent set of workers processing the same topic |
| **idempotency key** | Stable identity used to make repeated processing safe |
| **dead-letter queue** | Holding area for messages that exceeded normal retries |
| **outbox** | Transactional pattern for publishing events from database changes |
| **saga** | Multi-step workflow coordinated through events and compensations |
| **contract version** | Compatibility marker for event schema evolution |

## Dispatch

| $ARGUMENTS | Mode |
|------------|------|
| `design <domain or workflow>` | Design an event-driven architecture |
| `review <architecture or code path>` | Audit an existing event flow |
| `contract <event>` | Define or evolve an event contract |
| `reliability <flow>` | Design retries, ordering, and recovery |
| `migration <change>` | Plan adoption or replacement of an event flow |
| Natural language about queues, brokers, or async workflows | Auto-detect the closest mode |
| Empty | Show the mode menu with examples |

## Mode Menu

| # | Mode | Example |
|---|------|---------|
| 1 | Design | `design order fulfillment across payments, inventory, and shipping` |
| 2 | Review | `review event flow for user-created -> email sync` |
| 3 | Contract | `contract invoice.paid` |
| 4 | Reliability | `reliability retry strategy for webhook ingestion` |
| 5 | Migration | `migration move monolith side effects to events` |

## When to Use

- Designing async workflows across services or bounded contexts
- Choosing event contracts, partition keys, or consumer responsibilities
- Introducing outbox, retry, replay, or dead-letter handling
- Reviewing whether an event system is resilient or over-coupled
- Planning migration from synchronous side effects to durable events

## Classification Logic

**Classification Gate**

1. If the task is synchronous API design, request-response contracts, or CRUD endpoint shape, use api-designer.
2. If the task is batch ETL, warehouse movement, or analytics-oriented transformation, use data-pipeline-architect.
3. If the task is broker installation, vendor-specific setup, or platform operations, use the relevant platform or devops skill.
4. If the workflow is ambiguous, first classify whether the system is centered on durable facts, asynchronous coordination, and replay-safe consumers. Only stay in this skill when the answer is yes.

## Progressive Disclosure

- Keep `SKILL.md` focused on routing, operator steps, and non-negotiable constraints.
- Read reference files as indicated instead of loading everything at once.
- Load `references/event-vs-command.md` when the main question is whether something should be an event, command, or synchronous call.
- Load `references/failure-modes.md` when the task involves retries, replay, ordering, poison messages, or dead-letter handling.
- Load `references/saga-comparison.md` when choosing choreography, orchestration, or compensating workflows.
- Load `references/output-templates.md` when formatting architecture, contract, reliability, or migration outputs.

## Instructions

### Mode: Design

1. Identify the business facts that should become events. Name them in past tense.
2. Separate facts from commands and queries.
3. Read `references/event-vs-command.md` if the fact-vs-command boundary is unclear.
4. Define the producer, topic, partition key, consumers, and contract for each event.
5. Specify ordering requirements and where ordering does not matter.
6. Read `references/saga-comparison.md` when the workflow spans multiple services or compensating actions.
7. Produce an architecture with failure handling, replay, and observability using `references/output-templates.md` as needed.

### Mode: Review

1. Read the event catalog, code path, or architecture diagram.
2. Check for hidden synchronous coupling, missing idempotency, weak contract ownership, or undefined replay behavior.
3. Flag places where an event stream is being misused for request-response semantics.
4. Read `references/failure-modes.md` when the review touches ordering, replay, retries, or consumer safety.
5. Present findings by severity.

### Mode: Contract

1. Define required fields, producer, ownership, ordering expectations, and versioning strategy.
2. State which fields are identifiers, business facts, and metadata.
3. Prefer additive evolution; document deprecation windows for consumers.
4. Read `references/event-vs-command.md` if the proposed contract still looks like a command or query.

### Mode: Reliability

1. Read `references/failure-modes.md`.
2. Design retry policy, backoff, poison-message handling, and dead-letter routing.
3. Specify idempotency strategy for consumers and handlers.
4. Define replay safety and operator controls.

### Mode: Migration

1. Map the current synchronous side effect or legacy event flow.
2. Introduce the new event path behind explicit checkpoints.
3. Read `references/output-templates.md` for migration checkpoints and cutover framing.
4. Keep rollback simple by preserving the old path until the new path proves stable.

## Output Requirements

- Every design must identify producer, topic, partition key, consumers, and failure strategy.
- Every contract must state ownership and versioning rules.
- Every reliability plan must include idempotency and dead-letter handling.

## Critical Rules

1. Model business events as facts in past tense, not commands.
2. Consumers must be idempotent whenever retries or replay are possible.
3. Use the outbox pattern when publishing events from transactional database changes.
4. Do not use an event bus for low-latency request-response requirements that need immediate consistency.
5. Event contracts should evolve additively whenever possible.

## Scaling Strategy

- small: Keep the design narrow. Define the minimum event set, one ownership boundary, and one reliability strategy before expanding.
- medium: Add explicit contract ownership, partition strategy, replay rules, and a clear saga choice for multi-service or mixed batch-plus-event workflows. Avoid hiding synchronous dependencies behind event terminology.
- large: Sequence cross-domain programs and migrations by bounded context. Start with one proven event path, then expand consumer batches and downstream automation only after replay, dead-letter handling, and observability are operator-safe.

## Scope Boundaries

**IS for:** event contracts, topics, sagas, retries, replay, outbox, consumer design.

**NOT for:** synchronous REST or GraphQL API design, batch analytics pipelines, or broker installation details.
