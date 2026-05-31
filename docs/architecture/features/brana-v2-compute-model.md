---
title: brana v2 Compute Model — Living Spec
status: active
created: 2026-05-24
source: canonical
depends_on: ADR-040, ADR-041
---

# brana v2 Compute Model

> Three workstreams — efficiency tuning, Gemini delegation, Ruflo multi-agent — form one
> initiative. They all attack the same constraint: brana runs on a single compute source
> (Claude's token pool, serial execution).

## The Stack

```
┌──────────────────────────────────────────────────────────────────┐
│                          CLAUDE                                  │
│          orchestrates · judges · writes to repo                  │
│          the only entity that touches the brana system           │
│                                                                  │
│   ┌──────────────────────────┐      ┌──────────────────────────┐ │
│   │          RUFLO           │      │         GEMINI           │ │
│   │  coordinates Claude      │      │  stateless worker        │ │
│   │  sub-agents              │      │  /tmp/ only              │ │
│   │                          │      │                          │ │
│   │  claims · hive-mind      │      │  brana-agnostic tasks    │ │
│   │  autopilot · memory      │      │  atomic · fire-forget    │ │
│   └──────────────────────────┘      └──────────────────────────┘ │
│            ▲                                    ▲                 │
│            │ Claude reads/writes                │ Claude dispatches│
└────────────┼────────────────────────────────────┼─────────────────┘
             │                                    │
             └──── no direct connection ──────────┘
                   Claude is the only bridge
```

Ruflo and Gemini do not interact directly. Claude always mediates.
Ruflo enriches context before Gemini executes; Gemini output is stored back to Ruflo
after Claude reads and validates it.

## Routing Hierarchy

Walk top-to-bottom, first match wins:

```
Is this brana-system work?
(git, hooks, tasks.json, system/, architecture decisions)
  YES → Claude only. Never delegate.

  NO — Is it atomic, system-isolated, context-enrichable? (4-question test)
    NO  → Claude only (needs in-session state or multi-step coordination)

    YES — Is it convention-sensitive?
          Types: boilerplate, test scaffolding, ADR drafts, repo-destined output.
          Default: when in doubt → treat as convention-sensitive.

      YES — Is ruflo available?
        NO  → ABORT. "ruflo required for convention-sensitive task."
        YES → Gemini (mcp__brana__agy_delegate via /brana:gemini)
              ENRICH mandatory. Output /tmp/. Claude applies.

      NO  — Is it a sub-agent needing cost tracking?
        YES → ruflo agent_spawn.

        NO  — Is it parallel, bulk, or token-heavy?
          YES → Gemini (agy_delegate). ENRICH optional.
          NO  → Claude inline.
```

## Hard Constraints

```
NEVER:
  Gemini writes to ruflo directly
  Gemini writes to repo paths
  Ruflo coordinates Gemini as a peer agent
  Gemini participates in hive-mind quorum
  Gemini calls brana CLI or touches tasks.json

ALWAYS:
  Gemini output → /tmp/ only (Layer B) or system/scheduler/outputs/ (Layer A sweeps)
  Claude mediates all ruflo writes after Gemini executes
  Hive-mind quorum workers → Claude only
  Claude is the only entity that dispatches Gemini
```

## Phase Map

| Phase | Name | Status | Key Tasks |
|-------|------|--------|-----------|
| 0 | Efficiency quick wins | ✅ done | t-1646 (weight-adaptive close), debrief-analyst → Sonnet |
| 1 | Routing rules | ✅ done | t-1627 (delegation-routing.md baseline) |
| 2 | Ruflo wiring | pending | t-1599 (hive-mind calibration — not started) |
| 3 | Gemini layer | ✅ done | t-1576 (agy_delegate MCP), t-1577/t-1584 (/brana:gemini skill) |
| 4 | ENRICH + PERSIST | ✅ done | t-1629 (ENRICH), t-1631 (PERSIST), t-1634 (compounding loop validated) |
| 5 | Hive-mind quorum | pending | t-1599 calibration → t-1638 ADR (blocked by Phase 2) |
| 6 | Full integration | pending | t-1602 subtasks (blocked by Phase 5) |

## Ruflo–Gemini Pipeline (Phase 4)

```
ENRICH  → ruflo memory_search(knowledge + pattern, limit=3)
           inject brana patterns + prior findings into prompt

EXECUTE → mcp__brana__agy_delegate(task, context, output_format)
           agy runs enriched prompt, output captured in /tmp/

APPLY   → Claude reads agy output from MCP response
           Claude uses Write/Edit to land artifacts in repo
           All CC hooks fire normally

PERSIST → ruflo pattern_store(tags: ["source:agy-delegation"])
           findings enter knowledge base
           future ENRICH calls retrieve them (compounding loop)
```

## Compounding Loop

Each delegation cycle makes the next one better. Gemini's validated output teaches future
calls via ruflo. Quality improves measurably with ENRICH enabled.

**Validation result (t-1634, 2026-05-25): PASS**

| Condition | Mean score (/ 6) |
|-----------|-----------------|
| ENRICH-off | 3.33 |
| ENRICH-on  | 6.0 |
| Gap | +2.67 (threshold: +1.0) |

All 3 ruflo-stored patterns surfaced as concrete, project-specific rules in every ENRICH-on
run. ENRICH-off hit the thiserror/anyhow split from training data but consistently missed
brana-specific patterns (MCP stdio panic hook, JoinError two-layer handling).
See `claude-gemini-orchestration.md §Phase 4` for full protocol and scoring breakdown.

## Pending Decisions

- **Quorum thresholds** — locked after t-1599 calibration run (Phase 5)
- **`--bg` background delegation** — deferred to v2; requires t-1507 (atomic tasks.json write)
- **agy binary hash pinning** — deferred; needs sha2 crate added to brana-mcp

## Key Files

| File | Purpose |
|------|---------|
| `docs/architecture/decisions/ADR-040-compute-hierarchy-claude-ruflo-gemini.md` | 7 architectural decisions (locked gate for Phases 2–6) |
| `docs/architecture/decisions/ADR-041-agy-invocation-contract.md` | Layer A vs B, /tmp/ invariant, version pinning |
| `docs/architecture/features/claude-gemini-orchestration.md` | agy failure-mode spec (adversarial spike) |
| `system/cli/rust/crates/brana-mcp/src/tools/agy_delegate.rs` | Layer B MCP tool implementation |
| `system/skills/gemini/SKILL.md` + `system/procedures/gemini.md` | /brana:gemini skill |
| `system/scheduler/templates/agy-sweep.sh.template` | Layer A sweep template |
| `system/rules/delegation-routing.md` | Routing rule (always-load) |
| `docs/architecture/features/ruflo-integration-map.md` | Tool-group map, ToolSearch preambles, hive-mind quorum gate specs |

---

## Field Notes

### 2026-05-31: Subscription mode blocks ruflo calibration tasks
`ruflo agent_execute` and hive-mind LLM workers require `ANTHROPIC_API_KEY`. In subscription mode (no API credits) these tools fail with auth errors. Any backlog task whose DoD requires running N plans through ruflo workers is permanently blocked until API key access is granted. Resolution: cancel the task, document the working assumption (e.g. `majority` quorum threshold) as "pending re-calibration if API key available", and move on. Do not defer indefinitely — stale "pending" tasks pollute the roadmap.
Source: C3 resolution — t-1599 + t-1638 cancelled 2026-05-31
