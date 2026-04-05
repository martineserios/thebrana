---
depends_on:
  - docs/architecture/decisions/ADR-027-auto-learning-loop.md
  - docs/architecture/decisions/ADR-028-ontology-v2.md
  - docs/architecture/decisions/ADR-029-six-job-taxonomy.md
  - docs/architecture/decisions/ADR-030-maintenance-unification.md
  - docs/architecture/decisions/ADR-031-doc-enforcement-hook.md
  - docs/architecture/decisions/ADR-032-smart-router.md
---

# Operating Model — Technical Documentation

## Overview
The operating model implements a 6-step auto-learning loop (LOAD->WORK->EXTRACT->EVALUATE->PERSIST->DECAY) across 4 thinking skills, a 6-job taxonomy, unified maintenance, and ontology-aware knowledge graph.

## Components Built

### Auto-Learning Loop (ADR-027)
- **LOAD**: Added to brainstorm, build, research, review. Queries ruflo memory at skill start.
- **EXTRACT**: Added to same 4 skills + /close. Classifies findings by ontology type.
- **EVALUATE**: 3-tier gate (SMALL auto, MEDIUM inline, LARGE challenger).
- **PERSIST**: Routes findings to ruflo, docs, or memory by type.
- **DECAY**: Implemented as /reconcile --scope knowledge. Stale dims, log bloat, ruflo noise.

### Key Files
| Component | Location |
|-----------|----------|
| Ontology schema | docs/brana-ontology.yaml |
| Graph CLI | system/cli/rust/src/commands/graph.rs |
| /ship skill | system/skills/ship/SKILL.md |
| Smart router | system/skills/_shared/smart-router.md |
| Doc-gate hook | system/hooks/doc-gate.sh |
| 6 ADRs | docs/architecture/decisions/ADR-027 through ADR-032 |

### Skills Modified
- brainstorm, build, research, review — LOAD + EXTRACT + EVALUATE + PERSIST
- close — DOC-CHECK + auto-reconcile trigger
- reconcile — 4 domains (consistency, security, propagation, knowledge)

### ADRs
027 Auto-learning loop, 028 Ontology v2, 029 6-job taxonomy, 030 Maintenance unification, 031 Doc-enforcement hook, 032 Smart router
