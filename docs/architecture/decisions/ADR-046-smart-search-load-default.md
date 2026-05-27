# ADR-046: Keep smart:false as LOAD Default (smart:true Deferred)

**Status:** Accepted  
**Date:** 2026-05-27  
**Deciders:** Martín Rios  
**Tags:** ruflo, smart-search, memory, load

---

## Context

The ruflo `memory_search_unified` call supports a `smart` flag that enables query expansion and MMR (Maximal Marginal Relevance) reranking. The hypothesis was that `smart:true` would improve LOAD result quality in brainstorm and research procedures by returning more semantically diverse, contextually expanded results.

Task t-1552 ran a spike (2026-05-27) to measure the real-world cost and benefit of enabling `smart:true` as the default for all LOAD calls.

### Spike Conditions

- **ruflo version tested:** v3.6.30 (initial), v3.10.3 (after upgrade)
- **Baseline:** `smart:false`, `namespace: "knowledge"` + `namespace: "pattern"` in parallel
- **Test scope:** brainstorm.md + research.md LOAD procedures
- **Threshold:** p95 latency >500ms = reject (human-perceptible pause in skill startup)

### Findings

**ruflo v3.6.30 — 100% failure rate:**  
`smart:true` triggered a `Duplicate export of ControllerRegistry` module conflict. Every call errored. Root cause: loose dependency in v3.6.30's ControllerRegistry. Fixed by upgrading to v3.10.3.

**ruflo v3.10.3 — two remaining blockers:**

| Metric | smart:false (baseline) | smart:true |
|--------|----------------------|------------|
| p50 latency | ~199ms | ~3,300ms (cold) |
| p95 latency | ~303ms | >500ms threshold exceeded |
| Error rate | 0% | 0% (after upgrade) |
| MMR diversity | n/a | over-diversified (unrelated results surfaced) |

1. **Cold-start latency:** First `smart:true` call per session takes ~3.3s (7× over threshold). SmartRetrieval initializes query expansion models lazily on first use. No warmup mechanism currently available.
2. **MMR over-diversification:** Reranking penalizes semantically similar results so aggressively that it surfaces unrelated patterns. Net quality drop vs. smart:false.

Both blockers are tracked in t-1699 with candidate fixes (startup warmup call, MMR diversity parameter tuning).

---

## Decision

**Keep `smart:false` as the LOAD default across all procedures.**

`smart:true` is NOT enabled as the LOAD default at this time.

---

## Rationale

- Baseline `smart:false` is within threshold (p95 ~303ms < 500ms) and returning acceptable quality results.
- `smart:true` cold-start (3.3s) would add a perceptible pause at the start of every brainstorm/research skill invocation — unacceptable UX.
- MMR over-diversification means the quality trade-off is negative, not just neutral.
- The ControllerRegistry fix in v3.10.3 removes the hard blocker, but the two remaining blockers (cold-start + MMR) must be resolved before re-evaluating.

---

## Rollback Threshold

If `smart:true` is enabled in the future, the adoption criterion is:

- **p95 latency ≤ 500ms** on a warm session (not just cold-start measurement)
- **MMR diversity score** does not surface patterns with similarity < 0.25 to the query
- **Error rate = 0%** on the target ruflo version

If any criterion fails after enabling, revert to `smart:false` immediately.

---

## Scope (when re-evaluating)

When t-1699 resolves the blockers, the re-evaluation scope is:

| Procedure | smart:true candidate? |
|-----------|----------------------|
| brainstorm.md LOAD | Yes — confirmed by spike design |
| research.md LOAD | Yes — confirmed by spike design |
| build.md LOAD | No — excluded pending separate validation |
| sitrep.md LOAD | No — latency-sensitive, use smart:false unconditionally |

`namespace:all` is also excluded: session records score a constant 0.5 and contaminate results below the 0.55 threshold (separate issue from smart mode).

---

## Consequences

- LOAD calls remain `smart:false` — no change to existing procedure code.
- t-1699 tracks the two remaining blockers (cold-start warmup + MMR tuning).
- This ADR gates re-evaluation: t-1699 must cite this ADR when proposing the flip.
- ruflo version must be ≥ v3.10.3 for any future smart:true test (v3.6.30 hard-fails).

---

## References

- t-1552: Spike — memory quality test harness (completed 2026-05-27, verdict: keep smart:false)
- t-1699: Fix ruflo smart:true cold-start + MMR over-diversification (pending)
- t-1547: MS2 — Memory Quality milestone (parent)
- ruflo CLAUDE.md field note: `namespace:all` + threshold:0.55 behavior (v3.6 → v3.10 change)
