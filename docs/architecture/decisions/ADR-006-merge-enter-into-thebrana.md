# ADR-006: Merge enter into thebrana

**Date:** 2026-02-25
**Status:** accepted
**Supersedes:** ADR-005 (AgentDB as primary backend — downgraded to deferred; fallback strategy is now primary)

## Context

Brana's architecture currently splits across three repos:

| Repo | Role | Content |
|------|------|---------|
| `enter` | Architect | 39 spec docs (dimension → reflection → roadmap), backlog, research sources, ADRs |
| `thebrana` | Operator | Skills, hooks, rules, agents, commands, scripts, deploy pipeline |
| `brana-knowledge` | Vault | Memory exports, backups |

This separation was designed to enforce the distinction between "designing the system" and "building the system." In practice, it creates friction without contributing to spec quality (see [doc 39](../39-architecture-redesign.md) for full analysis).

### Problems

1. **Feedback loop is too long.** Discovery → fix → deploy requires 4 context switches across repos. Small changes (tweak a skill description, fix a hook instruction) carry the same overhead as large features.

2. **Enter trails implementation.** `/back-propagate` exists because implementation diverges from specs. `/reconcile` exists because specs diverge from implementation. Neither side leads — they chase each other.

3. **Two backlogs create management overhead.** Enter backlog (82 items) and thebrana tasks (38 items) require manual coordination to promote ideas into implementation.

4. **Cross-repo operations are pure plumbing.** `/back-propagate` creates worktrees in enter. `/reconcile` reads enter and writes thebrana. `/maintain-specs` triggers reconcile across repos. The sync discipline is valuable; the repo boundary adds plumbing, not value.

5. **No general knowledge system.** Brana captures development patterns (claude-flow memory) and brana-specific research (enter docs). Business domain knowledge, methodology knowledge, and cross-domain insights have no home.

### What Phase 4 proved

Phase 4 (v0.4.0) had the most detailed work items — file paths, logic pseudocode, template content, exit criteria. Implementation was near-1:1 with zero rework. The quality of specs mattered. The repo boundary didn't contribute to that quality.

## Decision

### 1. Merge enter into thebrana

Enter's content moves to `thebrana/docs/`. One repo, one backlog, one task system. The cognitive separation between "design" and "build" is preserved by directory structure and branch conventions, not by repo boundaries.

**Target structure:**

```
thebrana/
├── docs/                      ← current enter content
│   ├── 01-39 *.md             ← dimension/reflection/roadmap docs
│   ├── decisions/             ← ADRs (including this one)
│   ├── features/              ← feature briefs
│   └── backlog.md             ← unified brana backlog
├── system/                    ← deployed brain (→ ~/.claude/)
│   ├── skills/
│   ├── hooks/
│   ├── rules/
│   ├── agents/
│   ├── commands/
│   └── scripts/
├── .claude/
│   ├── CLAUDE.md              ← unified identity
│   └── tasks.json             ← unified operational tasks
├── deploy.sh
└── validate.sh
```

**Branch conventions replace repo boundary:**
- `docs/*` branches: spec work (no `system/` edits)
- `feat/*` branches: implementation (must also touch `docs/` or explicitly skip)
- Pre-commit hook enforces this, with a tripwire: 3 consecutive skips → mandatory

### 2. Evolve brana-knowledge into active knowledge base

Brana-knowledge transforms from a passive backup vault into an active, indexed knowledge base for general knowledge (business, methodology, technology, cross-domain).

**Structure:**

```
brana-knowledge/
├── dimensions/                ← deep dives on ANY topic
├── reflections/               ← cross-cutting synthesis
├── sources.yaml               ← research source registry
├── backup/                    ← current backup content (relocated)
└── index/                     ← generated embeddings data
```

**Key properties:**
- English as default language (projects use their own language)
- Topic-based filenames (`customer-retention.md`), not numbered
- Flat structure initially, subfolders at 30+ docs
- Auto-generated INDEX.md from YAML frontmatter
- Same dimension→reflection pattern proven by enter's 39 docs

### 3. Wire retrieval via claude-flow embeddings

**Primary strategy (validated by spike):**

| Component | Package | Version | Role |
|-----------|---------|---------|------|
| Orchestration | claude-flow | alpha.50 | MCP, memory, CLI |
| Embeddings | @claude-flow/embeddings | alpha.12 | ONNX generation (384-dim, all-MiniLM-L6-v2) |
| Storage | claude-flow memory | (built-in) | SQLite, namespace/tag queries |

**Spike results (2026-02-25):**
- CLI works without MCP session: `claude-flow embeddings generate --text "..."`
- Speed: ~300ms cached, ~2.6s cold start (NOT 3ms as docs claim)
- Semantic accuracy: cosine 0.65 (related) vs 0.23 (unrelated)
- `@claude-flow/embeddings` MUST be installed — without it, silently degrades to useless 128-dim hash

**AgentDB deferred:**

AgentDB (alpha.3.3) is stalled — last npm publish Jan 2, 2026. @claude-flow/memory references alpha.3.7 which doesn't exist on npm. Kill date: 2026-06-24. If it matures, upgrade. If not, the embeddings + SQLite path is complete.

**Supersedes ADR-005:** ADR-005 proposed AgentDB v3 as primary backend with phased migration. This ADR downgrades AgentDB to deferred/optional. The fallback strategy described in ADR-005 (continue with claude-flow memory + embeddings) becomes the primary strategy.

## Migration Plan

| Phase | What | Duration | Status |
|-------|------|----------|--------|
| 0 | This ADR + pre-merge prep | — | **Done** |
| 0.5 | Embedding spike | 30 min | **Done** (2026-02-25) |
| 1 | Structural merge (file moves, path updates, config merges) | 1 session | Pending |
| 2 | Skill logic rewrites (`/back-propagate`, `/reconcile` for same-repo) | 1-2 days | Pending |
| 3 | Retrieval prototype (1-2 seed docs + indexing pipeline + end-to-end test) | 1 session | Pending |
| 4 | Scale brana-knowledge content | Ongoing | Pending |

**Phase 1 checklist:** see [doc 39](../39-architecture-redesign.md), section 9 for full work items (13 items, including 30 path refs across 11 files).

**Phase 2 note:** `/back-propagate` and `/reconcile` need logic rewrites, not path substitution. Degraded mode (manual edits) acceptable while logic is reworked.

**Phase 3 gate:** retrieval must work end-to-end before Phase 4 content investment. Write seed doc → index → retrieve from project session. If this fails, knowledge base is just a file graveyard.

## Consequences

### Positive

- **Single feedback loop.** Discover gap → fix spec → fix code → deploy, all in one repo. No context switches.
- **Simplified maintenance.** `/back-propagate` and `/reconcile` become intra-repo operations (no cross-repo worktrees).
- **Unified backlog.** One view of "what should brana do next?"
- **General knowledge unlocked.** Business, methodology, and cross-domain insights get a structured, indexed, retrievable home.
- **Compounding returns.** Every session adds knowledge; every future session benefits from retrieval.

### Negative

- **Git history fragmentation.** `git log --follow` won't cross the repo boundary. Mitigated by tagging enter's final state.
- **Spec discipline relies on hooks, not boundaries.** Repo boundary was a hard constraint; pre-commit hooks are soft (bypassable with `--no-verify`). Tripwire at 3 skips.
- **New cross-repo friction with brana-knowledge.** `/research` reads from it, `/retrospective` writes to it. Accepted: library reads are lower friction than active-project syncs.
- **30 hardcoded path references.** Skills, hooks, and commands reference `~/enter_thebrana/enter/`. Phase 1 updates these; Phase 2 rewrites the complex ones.

### Risks

See [doc 39](../39-architecture-redesign.md), section 10 for full risk table (10 risks with mitigations).

## References

- [39-architecture-redesign.md](../39-architecture-redesign.md) — full analysis and migration details
- [ADR-005](./ADR-005-agentdb-v3-unified-knowledge-backend.md) — AgentDB proposal (deferred by this ADR)
- [14-mastermind-architecture.md](../reflections/14-mastermind-architecture.md) — current architecture (pre-merge)
- [Doc 24](../24-roadmap-corrections.md), errata #73-76 — cascade findings from [doc 39](../39-architecture-redesign.md) maintain-specs run
