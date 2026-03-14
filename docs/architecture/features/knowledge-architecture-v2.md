---
title: "Knowledge Architecture v2 — Implementation Spec"
status: in-progress
date: 2026-03-14
adr: ADR-021
research: brana-knowledge/dimensions/knowledge-architecture.md
---

# Knowledge Architecture v2 — Feature Brief

Implementation spec for ADR-021. This is the SPECIFY output — to be challenged in PLAN, then broken into tasks for BUILD.

## Architecture Overview

5 layers, each building on the previous:

```
Layer 5: Automated Cadence (scheduler — zero manual triggers)
Layer 4: Embedded Maintenance (every command maintains knowledge)
Layer 3: Knowledge Graph (ontology + typed spec-graph + ruflo namespaces)
Layer 2: Reasoning Docs (axioms, assumptions, IBIS, temporal, field notes)
Layer 1: Raw Materials (dimensions, ADRs, CLAUDE.md, system/)
```

## Layer 1: Raw Materials

Mostly unchanged. Add:

- **Typed relationship links** in dimension docs: `[ADR-019 assumes](path.md)` instead of bare `[doc NN](path.md)`
- **"Assumptions" section** in ADR template (MADR v4.0 pattern): claim, evidence, what breaks if wrong
- **Classify dimensions** as "maintain" (active staleness enforcement) vs "snapshot" (timestamped, no enforcement)

## Layer 2: Reasoning Docs

### Per-Document Structure

```yaml
# Frontmatter (self-reporting)
version: 2.1.0                     # SemVerDoc
status: active                      # active|superseded|historic
valid_from: 2026-02-01             # bi-temporal
valid_to: null
last_verified: 2026-03-14
confidence_tier: architecture       # tech(6mo)|architecture(18mo)|methodology(36mo)
maturity: evergreen                 # seedling|budding|evergreen
assumptions:
  - claim: "ruflo is enhancement, not hard dependency"
    if_wrong: "graceful degradation section needs rewrite"
    last_verified: 2026-03-14
```

Body sections: Axioms, Assumptions, IBIS reasoning (opt-in), Conclusions (traceable), Typed links, Changelog (append-only), Field Notes (append-only).

### Reflection Disposition

| Current | Becomes | Key Change |
|---|---|---|
| R1 (08) | ADR-020 | Triage verdicts as decision record |
| R2 (14, 65KB) | ARCHITECTURE.md (~25KB) + generated component-index.md | Split reasoning from inventory |
| R3 (31) | ASSURANCE.md + validate.sh code | Philosophy in doc, checks in code |
| R4 (32) | LIFECYCLE.md | Add axioms + changelog (minimal) |
| R5 (29) | VENTURE.md | Add axioms + changelog (minimal) |
| Doc 24 | Kill | Per-doc changelogs replace it |
| Doc 17 | Archive | Doc 18 is THE roadmap |

## Layer 3: Knowledge Graph

### Ontology Schema

File: `brana-ontology.yaml` (~50 lines)

```yaml
entity_types:
  - Dimension       # research doc
  - Reflection       # reasoning doc
  - ADR              # architecture decision
  - Skill            # /brana:* command
  - Agent            # specialized subagent
  - Hook             # lifecycle event handler
  - Rule             # behavioral directive
  - Task             # backlog item
  - Assumption       # explicit tracked assumption
  - FieldNote        # practical learning
  - Axiom            # first principle

relationship_types:
  # Reasoning
  - assumes:        [Reflection, ADR] → Assumption
  - derives_from:   [Conclusion] → [Assumption, Axiom]
  - supersedes:     [ADR, Reflection] → [ADR, Reflection]
  # Implementation
  - implements:     [Skill, Hook, Agent] → [ADR, Reflection]
  - enforces:       [Hook] → [Rule, ADR]
  - tests:          [FitnessFunction] → [Assumption, Axiom]
  # Knowledge
  - informs:        [Dimension] → [Reflection, ADR]
  - enriches:       [FieldNote] → [Dimension, Reflection]
  - triggers:       [FieldNote] → [Research]
  - contradicts:    [FieldNote, Research] → [Assumption]
  # Temporal
  - valid_during:   [any] → TimeRange
  - confidence:     [Assumption] → DecayTier
```

### Implementation

- Extend `spec_graph.py` to output typed edges (currently: references, referenced_by, impl_files)
- Store in `spec-graph.json` (same format, more edge types)
- Python BFS traversal for multi-hop queries (~160 nodes, no database needed)
- Ruflo namespaces: `assumptions`, `field-notes`, `decisions` (alongside existing `knowledge`, `patterns`)

### Deferred (Scale Triggers)

| Feature | Threshold | Auto-Creates Task When |
|---|---|---|
| AgentDB Cypher | > 500 graph nodes | validate.sh Check 19 |
| Full GraphRAG | > 10 typed edges/node | validate.sh Check 21 |
| Witness chains | > 50 cross-client field notes | validate.sh Check 22 |
| Temperature tiering | > 10K ruflo entries | validate.sh Check 20 |
| Reflexion episodes | promotion rate < 20% | /brana:review monthly |

## Layer 4: Embedded Maintenance

### Per-Command Integration

| Command | Knowledge Actions (automatic) |
|---|---|
| `/brana:build` | Phase 0 internal search. Assumption check in PLAN. Field notes + verify + changelog + reindex on CLOSE |
| `/brana:research` | Phase 0 internal first. Findings → field notes. Contradictions → flag assumptions |
| `/brana:close` | Field notes → docs. Changelogs updated. Assumptions verified. Reindex |
| `/brana:backlog` | Assumption staleness in priority. Field notes in task context |
| `/brana:review` | Knowledge health section automatic |
| `/brana:reconcile` | Traces typed deps. Flags assumption_stale drift |
| `/brana:onboard` | Surfaces cross-client field notes |
| `/brana:retrospective` | Learnings → ruflo patterns + field notes |

### Fitness Functions (validate.sh)

| Check | What | Trigger |
|---|---|---|
| 15 | Assumption freshness (> confidence_tier threshold) | Every commit |
| 16 | Changelog currency (file modified, changelog not updated) | Every commit |
| 17 | Status consistency (active but no changes in 12 months) | Every commit |
| 18 | Graph integrity (orphaned assumptions, broken dep edges) | Every commit |
| 19-22 | Scale triggers (see Layer 3 deferred) | Monthly |

### Commands Replaced

| Kill | Replace With |
|---|---|
| `/brana:apply-errata` | Per-doc changelogs |
| `/brana:maintain-specs` | `/brana:verify-docs` (fitness checks) |
| `/brana:re-evaluate-reflections` | Merged into verify-docs |
| Doc 24 errata log | Per-doc changelogs + fitness functions |

## Layer 5: Automated Cadence

### Scheduler Jobs (update existing + add new)

Update existing:
- `staleness-report`: project path `enter` → `thebrana`, add assumption freshness
- `knowledge-review`: skill `/knowledge-review` → `/brana:memory review`, add field notes count
- `morning-check`: add stale assumptions + pending field notes alerts
- `weekly-review`: add knowledge health section

Add new:
```json
{
  "assumption-health": {
    "schedule": "Mon *-*-* 09:05:00",
    "command": "./validate.sh --assumptions-only",
    "_comment": "Weekly assumption freshness check"
  },
  "scale-triggers": {
    "schedule": "*-*-01 10:30:00",
    "command": "./validate.sh --scale-triggers",
    "_comment": "Monthly deferred feature threshold check"
  },
  "field-notes-review": {
    "schedule": "*-*-15 10:00:00",
    "command": "./system/scripts/field-notes-report.sh",
    "_comment": "Bi-monthly pending field notes report"
  }
}
```

### Cadence Summary

| Frequency | What | Manual Action Required |
|---|---|---|
| Every commit | Fitness checks 15-18 + reindex | None |
| Daily | morning-check (surfaces issues) | Read 2-line report |
| Weekly | review + assumption-health + staleness | Review knowledge section in weekly |
| Monthly | knowledge audit + scale triggers + field notes review | Act on flagged items |

## Implementation Phases (Revised)

| Phase | What | Effort | Depends On | Verification |
|---|---|---|---|---|
| **0** | Fix scheduler paths (enter → thebrana) | 30 min | Nothing | brana-scheduler --dry-run |
| **1** | ADR-021 finalized + minimal ontology (5+5) | 1 session | Phase 0 | YAML validates, ontology covers existing doc types |
| **2** | Wire /brana:close for field notes (keep/archive) | 1 session | Phase 1 | /close produces field note in doc |
| **3** | R2 split (reasoning vs inventory) — own phase | 1-2 sessions | Phase 1 | Combined content covers original (diff) |
| **4** | Add minimal metadata to R3-R5 (3 fields) | Half session | Phase 1 | Frontmatter validates |
| **5** | Ruflo namespaces + index assumptions/field-notes | Half session | Phase 2 | memory_search returns results |
| **6** | /brana:research Phase 0 (internal-first) | 1 session | Phase 5 | Research queries internal before web |
| **7** | Extend spec-graph with typed edges | 1 session | Phase 1 | Typed edges in spec-graph.json |
| **8** | validate.sh fitness functions (with grace period) | 1 session | Phases 5, 7 | 23 checks pass on current docs |
| **9** | Wire /build CLOSE + remaining commands | 1 session | Phases 5, 8 | 6+ commands do knowledge actions |
| **10** | Kill cascade commands + archive doc 24 (after 2-week soak) | Half session | Phases 8, 9 validated 2 weeks | No drift increase |

Each phase independently valuable. No big-bang migration. Archive old reflections read-only for 30 days (cold-start).

## Challenge Resolutions (2026-03-14)

Five challenge rounds produced the following adjustments to the original design:

### Phase Reordering (Critical)
Original phases front-loaded schema/structure (1-4) and back-loaded feedback loops (7-9). Reordered to get `/close` + field notes working by phase 2. Feedback loop is the engine — schema serves it, not the reverse.

### Minimal Viable Everything
- Ontology: 11+12 → 5 entity types + 5 relationship types (extend when ambiguity proves it)
- Temporal metadata: 6 dimensions → 3 new fields (last_verified, status, maturity)
- Field notes lifecycle: 5 actions → 2 (keep/archive). Add sophistication after 1 month of usage
- SemVerDoc + confidence tiers: deferred to second phase (3 months)

### Safety Gates
- Phase 10 (kill old commands) gated on phases 8+9 validated for 2+ weeks
- "Work IS maintenance" claim only after 6+ commands wired (not after 2)
- Old reflection docs kept read-only in docs/archive/reflections/ for 30 days (cold-start mitigation)
- Grace period flag in validate.sh for freshly migrated docs (avoid noisy first week)

### Resolved Questions

1. **R2 reasoning vs inventory line:** "If derivable from system/ files = inventory (generate). If explains WHY things compose = reasoning (keep)." Dry-run classification before splitting.
2. **Cold-start:** Archive old reflections read-only for 30 days.
3. **Ontology enforcement:** validate.sh check: typed links in reasoning docs required. PreToolUse hook warns but doesn't block.
4. **Confidence tier scope:** Per-doc for v1. Upgrade to per-assumption only if too coarse.
5. **Field notes cap:** 20 per doc. Oldest unactioned auto-prompt for archive. 20+ signals doc needs revision.
6. **Schema format:** YAML file (brana-ontology.yaml). spec-graph.json references schema, doesn't embed it.

### Testing Strategy (per phase)

| Phase | Verification |
|---|---|
| 0 | scheduler.json paths resolve → brana-scheduler --dry-run |
| 2 | /close produces field note → verify it appears in doc |
| 3 | R2 split: combined content covers original → diff check |
| 5 | ruflo memory_search --namespace assumptions returns results |
| 8 | validate.sh runs 23 checks without false positives on current docs |
| 10 | 2-week soak: no drift increase after old commands removed |

## Open Questions (Resolved)

All original open questions resolved during challenge phase — see Challenge Resolutions above.

## Assumptions (Explicit)

| # | Assumption | Risk if Wrong | Mitigation |
|---|---|---|---|
| 1 | Solo operator maintains 3 new frontmatter fields | Fields go stale | validate.sh flags missing/stale. session-end auto-updates last_verified |
| 2 | /brana:close runs consistently | Field notes never appended | session-end hook captures minimal field note as fallback |
| 3 | Semantic drift is rare enough for structural checks | Docs say X, code does Y | Second phase: quarterly manual review of 5 random assumptions |
| 4 | 160 nodes won't hit 500 in 6 months | Scale trigger fires too early | ~280 nodes realistic in 12 months — safe |
| 5 | brana-knowledge stays separate repo | Cross-repo field notes coordination | post-commit hook in brana-knowledge handles reindexing |
| 6 | Claude consistently applies ontology types | Typed links inconsistent | validate.sh check + PreToolUse warning |

## Second Phase Items (with triggers)

| # | What | Trigger | Task |
|---|---|---|---|
| 1 | Ruflo precision@k evaluation | 3 months after Phase 5 live | t-429 |
| 2 | Expand ontology (5+5 → more) | Ambiguity causes misclassification | t-430 |
| 3 | Add SemVerDoc + confidence tiers | 3 months after Phase 4 | t-431 |
| 4 | Expand field notes lifecycle (2 → 5 actions) | 1 month after Phase 2 | t-432 |
| 5 | Wire remaining 6 commands | After core loop validated | Phase 9 |
| 6 | LLM-assisted semantic drift detection | Quarterly review shows >20% drift | t-433 |
| 7 | Per-assumption confidence tiers | Per-doc tiers prove too coarse | t-434 |
| 8 | GraphRAG (nano-graphrag) | Scale trigger: >500 nodes or >10 edges/node | t-105 (existing) |
| 9 | AgentDB Cypher | Scale trigger: >500 nodes | t-435 |
| 10 | Cross-client field note governance | >50 cross-client field notes | t-436 |
| 11 | Update CLAUDE.md + docs/README.md | After phases 3-4 | Phase 4 deliverable |

## How Deferred Items Surface (Alert & Follow-Up Process)

The core principle: **you never remember to check anything. The system surfaces items through channels you already use.**

### Three Surfacing Mechanisms

#### 1. Scale Triggers (automatic — validate.sh + scheduler)

Scale triggers are threshold checks embedded in validate.sh. They run:
- **On every commit** (checks 19-22, fast — just count nodes/entries)
- **Monthly** (scheduler job `scale-triggers`, deeper analysis)

When a threshold crosses:
```
validate.sh Check 19: SCALE TRIGGER — spec-graph.json has 512 nodes (threshold: 500)
  → Action: Auto-creating task for AgentDB Cypher evaluation
  → See: t-435
```

The check creates the task in tasks.json if it doesn't already exist (idempotent). You see it next time you run `/brana:backlog next` or in your morning-check report.

**Tasks covered:** t-435 (Cypher >500 nodes), t-436 (witness chains >50 cross-client notes), t-105 (GraphRAG >10 edges/node)

#### 2. Time-Based Triggers (scheduler → morning-check/weekly-review)

Some second-phase items activate after elapsed time, not thresholds. The scheduler tracks phase completion dates and surfaces reviews at the right time.

Implementation: `system/scripts/second-phase-check.sh` reads tasks.json for second-phase tasks, checks if their trigger conditions are met, and reports.

```bash
# In scheduler.json — runs weekly alongside assumption-health
"second-phase-review": {
    "type": "command",
    "command": "./system/scripts/second-phase-check.sh",
    "project": "~/enter_thebrana/thebrana",
    "schedule": "Mon *-*-* 09:10:00",
    "enabled": true,
    "_comment": "Weekly: check if any second-phase triggers have fired"
}
```

The script checks:
- t-429: Has Phase 5 been live for 3 months? → surface ruflo precision eval
- t-431: Has Phase 4 been live for 3 months? → surface SemVerDoc review
- t-432: Has Phase 2 been live for 1 month? → surface field notes lifecycle review
- t-433: Is it time for quarterly assumption drift review?

When triggered, the script:
1. Updates the task's `context` field: "Trigger fired YYYY-MM-DD. Review this item."
2. Sets `priority: P2` (moves it into the active queue)
3. The next morning-check reports: "1 second-phase item triggered: t-429 (ruflo precision eval)"

**You see it in your morning report and weekly review.** No separate alert channel.

#### 3. Usage-Pattern Triggers (embedded in commands)

Some items trigger when usage patterns reveal a problem — not on schedule.

| Task | How It Surfaces |
|---|---|
| t-430 (ontology expansion) | validate.sh detects untyped links in reasoning docs → warns: "5 links without relationship type. Consider ontology expansion (t-430)" |
| t-432 (field notes lifecycle) | field-notes-review (bi-monthly scheduler) reports: "15 field notes with action=keep older than 60 days. Current keep/archive may be too coarse — see t-432" |
| t-433 (semantic drift) | `/brana:verify-docs` runs quarterly manual assumption check → if >20% drift, reports: "Semantic drift rate 25%. Consider LLM-assisted detection (t-433)" |
| t-434 (per-assumption tiers) | validate.sh assumption-freshness check flags a doc as fresh but contains a stale tech assumption → "Per-doc tier missed stale assumption. Consider per-assumption tiers (t-434)" |

### How You Experience This (User Flow)

```
Morning (daily, automatic):
  "Good morning. Knowledge status:
   - 0 scale triggers crossed
   - 1 second-phase review due: t-429 ruflo precision (Phase 5 live 3mo)
   - 2 assumptions approaching staleness
   - 3 field notes pending review"

Weekly (Friday, automatic):
  "Knowledge health this week:
   - Assumptions: 23 tracked, 21 fresh, 2 approaching threshold
   - Field notes: +2 added (via /close), 1 promoted, 1 archived
   - Second phase: t-429 due for review (triggered Monday)
   - Scale: 172/500 nodes, 650/10K entries — nominal"

When you pick up t-429:
  /brana:backlog start t-429
  → Strategy: investigation (auto-classified from stream: research)
  → Context loaded: "Trigger fired 2026-06-14. Evaluate ruflo precision@k..."
  → You run 20 queries, score results, decide: sufficient or activate GraphRAG
```

### Summary: No Manual Tracking

| Trigger Type | Mechanism | Where You See It |
|---|---|---|
| Scale (node count, entry count) | validate.sh checks 19-22 | Morning report + backlog |
| Time-based (3 months, 1 month) | second-phase-check.sh (weekly scheduler) | Morning report + weekly review |
| Usage-pattern (drift rate, untyped links) | Embedded in validate.sh + commands | Inline warnings during work |
| All triggers | Auto-set priority P2 on task | `/brana:backlog next` shows it |
