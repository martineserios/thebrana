# Memory Taxonomy — Domain Design

**Task:** t-1269  
**Wave:** 1 — Design record  
**Status:** draft  
**Date:** 2026-04-14

---

## Problem Statement

The native project memory system (`~/.claude/projects/thebrana/memory/`) has accumulated 128 files, all typed as `feedback_*.md` regardless of what they actually contain. This catch-all convention produces three compounding failures:

1. **Index overflow.** `MEMORY.md` is the only always-loaded index. It hit 312 lines before trimming — 35% of entries were silently truncated by CC's 200-line cap every session.
2. **Type ambiguity.** A `feedback_*.md` file might contain an invariant rule, a reusable pattern, a domain knowledge claim, an architectural decision, a system reference, or session-ephemeral state. The type is unrecoverable from the filename.
3. **Routing failures.** Without types, write-time routing is a heuristic guess. Content ends up in the wrong canonical home — transferable rules buried in MEMORY.md, ADR-worthy decisions in feedback files, session state mixed with long-lived patterns.

### Evidence

| Signal | Value |
|--------|-------|
| Memory files in project dir | 128 |
| MEMORY.md lines before trim | 312 |
| CC index cap | 200 lines |
| Entries silently dropped per session | ~35% |
| Sessions without visible truncation warning | all |

### Root cause

`/brana:close` Step 5 routes everything through a single heuristic: "useful to someone who hasn't seen this repo? → dimension doc, else → MEMORY.md as `feedback_*.md`." There is no type classification step. Every learning, rule, reference, and architectural decision takes the same path.

---

## Domain Model

Six types. Each has a definition, canonical home, and write-time gate.

### Type 1: Rule

**Definition:** An invariant behavioral directive — "always X" or "never Y" — that applies to every session and requires no context to interpret. Generates a hard constraint on Claude's behavior.

**Canonical home:** `system/rules/*.md` (tracked, deployed via bootstrap.sh)

**Examples:**
- "Never sign commit messages with attribution lines"
- "Always use `uv run` to invoke Python"
- "Never read tasks.json directly — use brana backlog CLI"

**Write-time gate:** Human confirmation required. LLM proposes the rule text; user approves before placement. Placement in `system/rules/` is always manual — never auto-written by Close or any hook. This is Layer 1 (human-authored, load-bearing).

**Cap:** No cap. Each rule file is small; the budget gate enforces per-file size.

---

### Type 2: Pattern

**Definition:** A reusable solution to a recurring problem, with enough context to apply it in a new situation. Has a problem shape, a solution, and a confidence level. Survives across ruflo restarts.

**Canonical home:** `~/.claude/memory/patterns.md` (flat file, not per-pattern files)

**Format:**
```
## {pattern name}
**Problem:** {situation that triggers this}
**Solution:** {what to do}
**Why:** {evidence or reasoning}
**Confidence:** quarantine | proven
**Source:** {task-id or session date}
```

**Examples:**
- "Worktree gate + untracked files → use `git worktree add` + copy, skip stash"
- "Rust scoped threads + atomics: rebind as references before spawn loop"
- "gh CLI --jq piped output fails in Bash sandbox → redirect to temp file first"

**Write-time gate:** Automatic write from `/brana:close` if confidence ≥ quarantine. No human gate. Promoted to `proven` after 3+ sessions of consistent application without contradiction.

**Cap:** 50 entries. At 40, warn. At 50, require pruning before new entries (oldest quarantine entries pruned first).

---

### Type 3: Knowledge

**Definition:** A domain fact, research finding, or conceptual model that enriches future decision-making. Not a directive (unlike Rule), not a solution (unlike Pattern) — it's understanding.

**Canonical home:** `~/.claude/memory/knowledge-staging.md`

**Format:**
```
## {topic}
**Fact:** {the knowledge claim}
**Source:** {doc, session, external ref}
**Confidence:** low | medium | high
**Promote to:** {dimension doc path, once validated}
```

**Examples:**
- "Gemini is a detail-extraction engine, not a synthesis engine"
- "NotebookLM ogg/opus audio not supported — use mp3/wav/m4a"
- "Context rot is a gradient, not a cliff — intervene at 55%, not 70%"

**Write-time gate:** Automatic staging. Promotion to a dimension doc in `brana-knowledge/` requires `/brana:research` or manual review.

**Cap:** 30 entries. Warn at 20. Entries that have been in staging >30 days without promotion are flagged as stale.

---

### Type 4: Decision

**Definition:** An architectural or strategic choice — why we chose X over Y, with the tradeoffs considered. Durable. Referenced by future build sessions to avoid re-litigating.

**Canonical home:** `docs/architecture/decisions/ADR-NNN-*.md` (tracked, committed)

**Format:** Standard ADR template (Status / Context / Decision / Consequences / Non-actions)

**Examples:**
- ADR-033: Pin MCP servers via wrapper scripts instead of npx/uvx
- ADR-034: Skill tiering — universal stub pattern
- ADR-006: Merge enter + thebrana into one repo

**Write-time gate:** `/brana:close` pre-fills an ADR stub and presents it for human review. Human commits. Never auto-committed.

**Cap:** No cap. ADRs are static once accepted.

---

### Type 5: Reference

**Definition:** A pointer to where information lives in an external or cross-project system. Not the information itself — just the routing.

**Canonical home:** `~/.claude/memory/portfolio.md` (cross-project index) or MEMORY.md (project-scoped pointers)

**Examples:**
- "Pipeline bugs tracked in Linear project INGEST"
- "Grafana latency board: grafana.internal/d/api-latency"
- "GitHub Projects: Brana=#8, Anita=#10, Somos=#11, NexEye=#12"

**Write-time gate:** Automatic write from `/brana:close`. No human gate. Duplicates suppressed by URL/path deduplication.

**Cap:** No cap on portfolio.md. MEMORY.md project-scoped references count against the 200-line index budget.

---

### Type 6: Session State

**Definition:** Ephemeral context that helps resume a session — what was accomplished, what's next, what's blocked. Stale after one session.

**Canonical home:** Native memory dir (`~/.claude/projects/{slug}/memory/`) — unchanged from current behavior. Written by session-end-persist.sh, read by session-start hook.

**Format:** Structured JSON (existing `brana session write` schema).

**Write-time gate:** Automatic. Overwritten each session-end.

**Cap:** 1 file per project. No accumulation.

---

## Type Decision Tree

At write time in `/brana:close` Step 5, classify by answering in order:

```
1. Is this ephemeral — only useful for resuming this session?
   → YES: Session State

2. Does this say "always X" or "never Y" with no context needed to apply it?
   → YES: Rule (human gate)

3. Is this a why-we-chose-X architectural choice with explicit tradeoffs?
   → YES: Decision (ADR stub, human gate)

4. Is this a pointer to where something lives in an external system?
   → YES: Reference

5. Is this a reusable solution to a recurring problem shape?
   → YES: Pattern

6. Everything else — domain understanding, research findings, conceptual models
   → Knowledge (staging)
```

---

## Acceptance Criteria

The taxonomy is implemented correctly when all of the following hold:

| Type | Acceptance Criterion |
|------|---------------------|
| Rule | After a session where a new rule was identified, it appears as a draft in the AskUserQuestion prompt. If approved, it lands in `system/rules/`. It never auto-writes to `system/rules/` without user confirmation. |
| Pattern | After `/brana:close`, a new pattern appears in `~/.claude/memory/patterns.md`. After ruflo restart, the pattern is still recoverable (not lost with the HNSW index). `patterns.md` stays under 50 entries. |
| Knowledge | After staging, the entry appears in `knowledge-staging.md`. After 30 days without promotion, a stale warning surfaces in `/brana:memory review`. |
| Decision | After a session where an architectural decision was made, `/brana:close` offers an ADR stub. The stub is never committed without user approval. |
| Reference | After a session mentioning a new external system, the reference appears in `portfolio.md` or MEMORY.md. Duplicates do not accumulate. |
| Session | Session state is written at session-end and consumed at session-start. `brana session read --json` returns structured data. Consumed state is marked (consumed_at non-null) so it's not re-presented. |
| General | `feedback_*.md` creation by `/brana:close` drops to zero new files after taxonomy is live. Existing `feedback_*.md` files are migrated incrementally (15/session, t-1246). |

---

## Non-Goals

- **Not a ruflo replacement.** Ruflo remains the cross-namespace semantic search layer. This taxonomy routes *native* memory (flat files). Ruflo indexes on top.
- **Not cross-client memory unification.** Each project's taxonomy is independent. `~/.claude/memory/portfolio.md` handles cross-project references, but not pattern or knowledge sharing.
- **Not a new file format.** Existing `feedback_*.md` files are not deleted. They are migrated incrementally by type.
- **Not AI-autonomous routing.** Rule and Decision types always require human confirmation. The LLM classifies and drafts; the human decides and places.
- **Not a ruflo dependency.** Pattern storage works without ruflo (`patterns.md` is a flat file). Ruflo can index `patterns.md` as an enhancement, not a requirement.

---

## Open Questions

These were raised during challenger review (2026-04-14). Answers needed before SDD.

1. **Pattern cap enforcement:** Who enforces the 50-entry cap — `/brana:close`, a lint hook, or a scheduled job? Current answer: `/brana:close` reads and counts before writing.
2. **Knowledge promotion trigger:** Is `/brana:research --refresh` the only promotion path for knowledge-staging entries, or should `/brana:close` offer promotion inline?
3. **Existing feedback_*.md migration:** The 30-day stale rule applies to new entries in knowledge-staging. For existing files, wave 3 phase A triage defines the migration manifest. No auto-migration before human review.
