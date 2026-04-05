# Domain Glossary — Operating Model

Terms used across ADRs 027-032, skills, and the auto-learning loop.

## Jobs

| Term | Definition |
|------|-----------|
| **DECIDE** | Choose what to work on. Skills: backlog, brainstorm, sitrep. |
| **UNDERSTAND** | Acquire knowledge needed for work. Skills: research (4 strategies), onboard. |
| **BUILD** | Create or modify artifacts. Skills: build (6 strategies). |
| **SHIP** | Deploy artifacts to users. Skills: ship (6 steps). |
| **MAINTAIN** | Keep systems healthy. Skills: reconcile (4 domains). |
| **GROW** | Expand the business. Skills: review, harvest. |

## Auto-Learning Loop

| Term | Definition |
|------|-----------|
| **LOAD** | Pull relevant knowledge into context at skill start. Ruflo search + graph traversal. Budget: 30K tokens. |
| **EXTRACT** | Identify findings at skill end. Classifies as Pattern, ADR, Dimension, or FieldNote. |
| **EVALUATE** | Score findings on scope (0-10) and novelty. Gate: SMALL (auto), MEDIUM (inline dedup), LARGE (challenger). |
| **PERSIST** | Route accepted findings to correct storage: ruflo, docs, memory files. |
| **DECAY** | Weekly scan removing stale knowledge. 3 targets: stale dimensions, event log bloat, ruflo noise. |
| **Thinking skill** | Skill with full auto-learning loop: brainstorm, build, research, review. |

## Ontology

| Term | Definition |
|------|-----------|
| **Entity type** | Classification of a knowledge node: Dimension, Reflection, ADR, Pattern, Roadmap (active); FieldNote, Assumption, etc. (deferred). |
| **Relationship** | Typed edge between nodes: depends_on (transitive), informs, supersedes (active); contradicts, implements, etc. (deferred). |
| **Axiom** | Invariant enforced by the system: transitivity, supersession chains, contradiction flagging, staleness. |
| **Frontmatter** | YAML metadata at the top of markdown files. Instance data for the ontology. |
| **Typed edge** | Graph edge with an ontology relationship type (vs untyped "references" from markdown links). |
| **Orphan node** | Node with zero edges — flagged for review by DECAY. |

## Routing

| Term | Definition |
|------|-----------|
| **Smart router** | 3-level strategy detection: signal match (deterministic), LLM classify (ambiguous), ask user (uncertain). |
| **Signal** | Deterministic routing rule: tags, stream, keywords, git state. Level 1 of the router. |
| **Strategy** | A skill's operating mode. Build has 6 (feature, bug-fix, refactor, migration, investigation, greenfield). Research has 4 (research, evaluate, learn, investigate). |
| **Reroute** | Mid-workflow strategy change triggered by a gate check (e.g., can't reproduce → investigate). |

## Maintenance

| Term | Definition |
|------|-----------|
| **Domain (reconcile)** | A scope of /reconcile checks: consistency, security, propagation, knowledge. |
| **Doc-gate** | PreToolUse hook blocking commits on feat/fix branches when behavioral files change without docs. |
| **Behavioral file** | File that affects user-visible behavior: skills/, hooks/, agents/, commands/, cli/, rules/. |
| **Ratchet gate** | Evidence threshold between phases. Phase B only ships if Phase A metrics pass. |

## Measurement

| Term | Definition |
|------|-----------|
| **Doc-update rate** | % of behavioral commits that include documentation changes. Baseline: 28%. Target: >50% (month 1), >70% (month 3). |
| **Accept rate** | % of EXTRACT suggestions the user accepted. Target: >40%. |
| **Skip rate** | % of EXTRACT suggestions the user skipped. Target: <60%. |
| **EXTRACT precision** | % of suggestions that match real changes (git diff). Target: >70%. |
| **EXTRACT recall** | % of real changes that EXTRACT caught. Target: >60%. |
