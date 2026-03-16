# Agent Observability & Learning Extraction

> Brainstormed 2026-03-16. Status: idea.

## Problem

Brana agents produce rich behavioral data (transcripts, events, decisions) but nobody systematically mines it for learnings. Improvements are discovered ad-hoc, corrections repeat across sessions, and patterns go undetected. The current debrief-analyst agent produces free-form findings that often become boilerplate. No feedback loop exists to track whether learnings improve behavior.

## Proposed Solution

Two complementary systems:

1. **Learning extraction** (v1, works now) — post-session analysis that mines agent behavior for patterns using structured extraction templates, stores findings with confidence scores, and promotes recurring findings to rules/hooks/tasks through human curation.

2. **Operational monitoring** (v2+, when chat-agents ship) — real-time health metrics (latency, errors, budget tracking, alerting). Architecture defined in [chat-agents-monitoring.md](../architecture/features/chat-agents-monitoring.md).

### Architecture

```
         Operational Monitoring              Learning Extraction
         (v2+ — real-time)                   (v1 — post-session)
         ┌──────────────────┐                ┌──────────────────┐
         │ Events (JSONL)   │───── feeds ───→│ Extraction        │
         │ Metrics          │                │ Templates         │
         │ Health checks    │                │                   │
         │ Alerts           │                │ Findings          │
         └────────┬─────────┘                └────────┬─────────┘
                  │                                    │
                  │         ┌──────────────┐          │
                  └────────→│ Decision Log │←─────────┘
                            │ + Ruflo      │
                            └──────┬───────┘
                                   │
                            ┌──────▼───────┐
                            │ Rule Promotion│
                            │ + Feedback    │
                            └──────────────┘
```

### Structured Extraction Templates

Instead of "summarize what happened", the analyzer runs N specific extractors, each looking for one type of pattern. Each template defines:
- **Trigger** — when to run (e.g., cascade count > 0, correction rate > 0.2)
- **Input** — what data to analyze (event JSONL, transcript, both)
- **Prompt** — focused question forcing specific, codebase-relevant findings
- **Output schema** — typed JSON, not prose

Example templates:

| Template | Trigger | Extracts |
|----------|---------|----------|
| `error-pattern` | failures > 2 or cascades > 0 | Root cause, failed approach, better approach, affected files |
| `user-correction` | correction_rate > 0.2 | What agent did wrong, what user wanted, prevention rule |
| `tool-efficiency` | always | Redundant calls, wrong order, unnecessary steps |
| `decision-quality` | challenger findings in session | Decision made, alternatives considered, outcome |

### Finding Lifecycle

Findings mature through explicit stages with human interaction at every promotion:

```
RAW FINDING (extracted by debrief-analyst)
    │
    ▼
QUARANTINE (confidence: 0.3)
    │   First occurrence. Stored in decision log + ruflo.
    │   Surfaced in /brana:review weekly as "new findings."
    │
    ▼ (same pattern extracted again in another session)
RECURRING (confidence: 0.5, recall_count > 1)
    │   /brana:close Step 10 surfaces it:
    │   "This appeared 3 times. Review?"
    │     → Dismiss → archived, won't surface again
    │     → Keep watching → stays recurring
    │     → Promote → moves to discussion
    │
    ▼
DISCUSSION (user decides implementation path)
    │   a) Make it a rule → write rules/*.md
    │   b) Make it a task → /brana:backlog add
    │   c) Make it a hook → write hooks/ entry
    │   d) Update a skill → modify skill prompt
    │   e) Just remember → high-confidence ruflo memory
    │
    ▼
IMPLEMENTED (resolved_by: rules/X.md or t-NNN)
    │   Original finding archived with resolution reference.
    │
    ▼
VALIDATED (/brana:review checks: did the pattern stop?)
    │   YES → finding confirmed effective
    │   NO  → re-open, investigation needed
```

### User Interaction Points

| When | What happens | User role |
|------|-------------|-----------|
| `/brana:close` Step 10 | "3 findings ready for review" with context | Dismiss / keep watching / promote |
| `/brana:review` weekly | "12 new, 3 recurring, 1 ready for promotion" | Batch review, decide priorities |
| Promotion discussion | "Pattern: X. Options: rule, hook, or task?" | Pick implementation path |
| Validation | "Rule X added 2 weeks ago. Correction rate -15%." | Acknowledge or adjust |

### Dual Storage

| Need | Store | How |
|------|-------|-----|
| **Recall** (semantic, "what do we know about X?") | Ruflo memory | `memory_store` with embeddings → `memory_search` at session start |
| **Aggregate** (counting, trending) | Decision log | `decisions.py log` writes JSONL → `jq` queries by type/severity/date |

### Workflow Integration

| Existing component | Change | Effort |
|-------------------|--------|--------|
| **debrief-analyst agent** | Add structured extraction templates to its prompt | S |
| **`/brana:close` Step 6** | Pass templates to debrief-analyst, store typed findings | S |
| **`/brana:close` Step 10** | Surface recurring findings, offer promotion paths | S |
| **`session-start.sh`** | Recall relevant findings, inject as session context | S |
| **`/brana:review`** | Add findings aggregation section (new, recurring, promoted) | S |
| **`brana ops learnings`** | New CLI subcommand: query findings by type/severity/frequency | M |

## Research Findings

- Brana's existing monitoring infrastructure (JSONL events, Rust metrics engine, decision log, ruflo) covers ~70% of what's needed
- Two stores (decision log + ruflo) already serve aggregation and recall — no new storage needed
- Industry best practices for LLM observability recommend a conversation → message → span logging hierarchy (OpenTelemetry GenAI conventions)
- Proyecto Anita has built per-channel observability scripts (webhook health, message status) — patterns transferable to chat-agents monitoring
- Existing flywheel metrics (correction_rate, cascade_rate, etc.) provide the quantitative signal for extraction template triggers

## Risks

- **Noisy findings** → Structured templates with triggers prevent running expensive analysis on clean sessions. Human curation at `/brana:close` filters noise.
- **CC transcript format fragility** → v1 uses event JSONL (brana-controlled). Transcript analysis deferred to v1.1.
- **Over-engineering for chat-agents** → v1 works entirely within current CLI sessions. Chat-agent integration deferred to v2.
- **LLM analysis cost** → Templates have triggers. Only run on sessions with anomalies. Estimated 1-2 extra Claude calls per session with issues.

## Phased Roadmap

| Phase | What | Effort |
|-------|------|--------|
| **v1: Learning extraction** | Templates + debrief enhancement + dual storage + rule promotion + `brana ops learnings` | S-M |
| **v1.1: Transcript analysis** | CC transcript parser feeds extraction templates with richer conversation context | S |
| **v2: Unified event bus** | Shared event schema for CC + chat-agents + scheduled jobs | M |
| **v3: Operational monitoring** | t-422 implementation: latency, errors, health checks, alerting for Session Manager | M-L |

## Next Steps

1. Define 3-4 extraction templates (error-pattern, user-correction, tool-efficiency, decision-quality) as YAML specs
2. Enhance debrief-analyst agent prompt with structured template system
3. Add findings storage to `/brana:close` Step 6 (decision log + ruflo)
4. Add findings recall to `session-start.sh` hook
5. Add rule promotion flow to `/brana:close` Step 10
6. Add `brana ops learnings` CLI subcommand
7. Add findings aggregation to `/brana:review`
