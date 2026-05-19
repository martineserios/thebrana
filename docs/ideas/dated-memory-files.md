---
title: Unified Knowledge Routing Gateway — brana memory write
status: idea
created: 2026-05-19
---

# Unified Knowledge Routing Gateway — `brana memory write`

> Brainstormed 2026-05-19. Status: idea.
> Related: [`session-continuity-multi-session.md`](./session-continuity-multi-session.md) (t-1461),
> [`memory-consolidation-kairos.md`](./memory-consolidation-kairos.md) (Lint+Heal)

## Problem

The model routes learnings to destinations (`feedback_*.md`, `project_*.md`, ruflo, CLAUDE.md,
`~/.claude/rules/`) ad-hoc by convention. Two compounding failures:

1. **Routing is inconsistent** — the same class of learning lands in different buckets across
   sessions. "deploy by merging to main" is in `feedback_*` but should be a `convention`.
   "always use uv" is in MEMORY.md `User Preferences — CRITICAL` but should be `user_*`.
2. **Some destinations are unreliable** — ruflo has stability issues, `~/.claude/rules/`
   scoping is broken (ignores path filters), no enforcement prevents the model from writing
   directly to the wrong destination.
3. **Parallel writes clobber each other** — two CC sessions closing on the same project
   both write `feedback_slug.md`. Last write wins, earlier session's learning is lost.
   (Related but distinct from t-1461, which fixes session state JSON merging.)

Memory files are unstructured markdown — can't auto-merge two versions without LLM assistance.
Dated files sidestep merge entirely by making every write independent.

## Proposed Solution

### Core: `brana memory write` CLI gateway

Replace ad-hoc model writes with a single CLI command:

```bash
brana memory write \
  --type feedback \     # feedback | project | user | pattern | convention | field-note | adr
  --scope project \     # project | global | cross-project
  --slug "tdd-no-exceptions" \
  --content "..."
```

**Model classifies. CLI routes.** `--type + --scope → deterministic destination`:

| Type | Scope | Destination | Write mode |
|------|-------|-------------|------------|
| `feedback` | project | `~/.claude/projects/{p}/memory/feedback_slug_<ts>.md` | **dated** |
| `feedback` | global | `~/.claude/memory/feedback_slug_<ts>.md` | **dated** |
| `project` | project | `~/.claude/projects/{p}/memory/project_slug.md` | **upsert** |
| `user` | global | `~/.claude/memory/user_slug.md` | **upsert** |
| `pattern` | cross-project | ruflo `pattern:*` + `~/.claude/memory/` | **versioned** |
| `convention` | project | `.claude/CLAUDE.md` conventions section | **append** |
| `field-note` | project | relevant dimension doc `## Field Notes` | **append** |
| `adr` | project | `docs/architecture/decisions/draft-NNNN.md` | **create** |

### Companion: `brana memory index`

Regenerates MEMORY.md from the filesystem — scans `*_*.md` files per slug, picks newest
by timestamp in filename, writes the index. Model **never touches MEMORY.md directly**.
Triggered by: session-start hook (shell script first, Rust CLI later).

### Enforcement: PreToolUse hook

Blocks direct `Write` tool calls to `*/memory/*.md` paths with:
"Use `brana memory write` — direct writes to memory paths are not allowed."
Same pattern as "don't read tasks.json directly — use `brana backlog`."

## Classification Decision Tree

1. Does this tell me how to **behave in future sessions** (model behavioral rule)? → `feedback`
2. Is this a **current project state fact** (will become outdated, last-write-wins)? → `project`
3. Is this about **who the user is** (stable profile)? → `user` (global)
4. Would this help **other clients** facing the same problem? → `pattern` (cross-project)
5. Is this about **how this project's workflow operates** (not model behavior)? → `convention`
6. Is this a **technical surprise** — unexpected behavior of a tool/platform? → `field-note`
7. Was an **architectural decision** made or implied? → `adr`

### Three current misclassifications this fixes

- `feedback_thebrana-deploy-merge-to-main.md` → should be `convention` (project workflow rule)
- "always use uv to run Python" in MEMORY.md → should be `user_*` (user preference, global)
- "brana session write is replace-not-merge" → should be BOTH `project_*` (bug state) AND
  `feedback_*` (behavioral awareness) — currently only in `feedback_*`

## Key Insights From Discussion

- **Feedback memories refine; project memories replace.** Dated files (feedback) vs upsert
  (project) is the correct split — not "all files dated" or "all files upsert."
- **t-1461 complements this.** Session state is structured JSON → merge semantics. Memory
  files are unstructured markdown → dated append sidesteps merge entirely. Two tracks.
- **MEMORY.md auto-generation removes a model maintenance burden.** Model never touches
  the index — CLI regenerates it. Always current, always reflects latest dated file per slug.
- **Lock ≠ history.** A write lock prevents race conditions but still loses the earlier
  session's content (last write wins). Dated files preserve all versions.

## Risks and Mitigations

| Risk | Mitigation |
|------|-----------|
| Dated files accumulate without consolidation | Accept accumulation initially. Keep last 10 per slug until Lint+Heal (memory-consolidation-kairos.md) ships |
| MEMORY.md regeneration slow at session start | Shell script (`grep + sort`) first; Rust CLI when corpus grows. Benchmark at 100, 500, 1000 files |
| Type misclassification by model | PreToolUse hook validates `--type` arg; invalid type → block with error + hint |
| Migration of existing plain `feedback_slug.md` files | `brana memory migrate` command: convert plain slug → dated (use mtime as timestamp). One-time, idempotent |
| ruflo unstable for `pattern` type writes | Write to `~/.claude/memory/` file first (always), ruflo second (best-effort). Recall works even without ruflo |

## Engineering Disciplines

- **DDD:** ADR required before implementation — routing taxonomy, dated-file naming contract,
  MEMORY.md generation ownership, migration strategy
- **TDD:** Tests for dated file naming, routing logic per type+scope, `brana memory index`
  correctness, PreToolUse hook rejection of plain-slug writes to memory paths, migration
  idempotency
- **SDD:** Create `docs/architecture/memory.md`. Update skill procedures (close, retrospective,
  brainstorm PERSIST) to use `brana memory write`. Update global CLAUDE.md instruction.
- **Docs:** CLAUDE.md global: "Use `brana memory write` — never `Write` tool for memory paths."

## MCP Surface

Same pattern as `brana backlog` — expose the CLI as MCP tools so the model can call memory
operations directly without shelling out:

| MCP tool | CLI equivalent | Description |
|----------|---------------|-------------|
| `mcp__brana__memory_write` | `brana memory write` | Write a learning with type/scope/slug/content |
| `mcp__brana__memory_index` | `brana memory index` | Regenerate MEMORY.md from filesystem |
| `mcp__brana__memory_migrate` | `brana memory migrate` | Convert existing plain-slug files to dated |
| `mcp__brana__memory_list` | `brana memory list` | List memories by type/scope/slug |

MCP tools are registered in `system/brana-mcp/` alongside existing backlog MCP tools.
Skill procedures (close, retrospective, brainstorm PERSIST) call `mcp__brana__memory_write`
directly — no bash subshell required, faster, type-safe.

## Build Sequence (smallest valuable slice first)

1. **ADR** — routing taxonomy, dated-file contract, MEMORY.md generation ownership
2. **`brana memory write --type feedback`** — dated file + basic MEMORY.md update
3. **`brana memory index`** — regenerate MEMORY.md from filesystem
4. **PreToolUse hook** — block direct writes to `*/memory/*.md`
5. **`brana memory write --type project`** — upsert mode (simpler, validates the API shape)
6. **`brana memory migrate`** — convert existing files to dated format
7. **Remaining types** (`user`, `pattern`, `convention`, `field-note`, `adr`) — incrementally

## Relationship to Other Docs

- **t-1461** (`session-continuity-multi-session.md`): fixes session state JSON. This fixes
  memory files. Complements, doesn't replace. Shared ADR may be appropriate.
- **memory-consolidation-kairos.md** (Lint+Heal): L1 dedup becomes trivially simpler with
  dated files — "group by slug prefix, keep newest, archive rest." Ship Lint+Heal L1
  *after* this, not before.
- **resilient-pattern-store.md**: if ruflo stabilizes, `pattern` type routing here gets a
  reliable backend. Until then, file-first is the fallback.
