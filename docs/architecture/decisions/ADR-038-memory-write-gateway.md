---
status: proposed
produced_by: docs/ideas/dated-memory-files.md
depends_on:
  - docs/architecture/decisions/ADR-037-memory-enforcement-and-migration.md
  - docs/architecture/features/memory-taxonomy-sdd.md
---
# ADR-038: Unified Memory Write Gateway — Dated Files, Routing Taxonomy, CLI Gateway, MEMORY.md Ownership

**Status:** Proposed
**Date:** 2026-05-19
**Task:** t-1465 (t-1463 phase)
**Depends on:** ADR-037 (enforcement waves), memory-taxonomy-sdd.md (classify() interface)

---

## Context

ADR-037 defines *when* to block direct `feedback_*.md` writes (advisory → blocking waves).
It does not define *where* a learning should go instead, nor does it define a CLI gateway
that makes routing deterministic.

Three compounding failures motivate this ADR:

1. **Routing is ad-hoc.** The model decides the destination per session. Same class of
   learning lands in different buckets across sessions (e.g. `feedback_*` vs CLAUDE.md
   vs ruflo) depending on the skill invoked and how much context is loaded.

2. **Parallel writes clobber each other.** Two CC sessions closing on the same project
   both write `feedback_slug.md`. Last write wins; the earlier session's learning is lost.
   Dated files sidestep merge entirely by making every write an independent append.

3. **MEMORY.md is a maintenance burden.** The model currently writes the index directly
   during `close` and `retrospective`. This is fragile (index gets stale, entries truncated,
   cross-session overwrites). The index should be generated from the filesystem.

This ADR defines the contract that closes these gaps. The enforcement wave
(blocking hook) defined in ADR-037 Wave 2 enforces this contract operationally.

---

## Decision

### A. 7-Type Routing Taxonomy

Replace the 6-type `classify()` taxonomy from memory-taxonomy-sdd.md with a 7-type
table keyed on `type + scope`. The model classifies type and scope; the CLI routes deterministically.

| Type | Scope | Destination | Write mode |
|------|-------|-------------|------------|
| `feedback` | project | `~/.claude/projects/{p}/memory/feedback_{slug}_{ts}.md` | **dated** |
| `feedback` | global | `~/.claude/memory/feedback_{slug}_{ts}.md` | **dated** |
| `project` | project | `~/.claude/projects/{p}/memory/project_{slug}.md` | **upsert** |
| `user` | global | `~/.claude/memory/user_{slug}.md` | **upsert** |
| `pattern` | cross-project | ruflo `pattern:*` + `~/.claude/memory/pattern_{slug}.md` | **versioned** |
| `convention` | project | `.claude/CLAUDE.md` conventions section | **append** |
| `field-note` | project | relevant dimension doc `## Field Notes` section | **append** |
| `adr` | project | `docs/architecture/decisions/draft-{slug}.md` | **create** |

**Classification decision tree (model uses this):**

1. Does this constrain **how I should behave** in future sessions? → `feedback`
2. Is this a **current project state fact** (will become outdated, last-write-wins)? → `project`
3. Is this about **who the user is** (stable profile, not project-specific)? → `user` (global)
4. Would this help **other clients** facing the same problem? → `pattern` (cross-project)
5. Is this about **how this project's workflow operates** (not model behavior)? → `convention`
6. Is this a **technical surprise** — unexpected behavior of a tool, platform, or dependency? → `field-note`
7. Was an **architectural decision** made or implied? → `adr`

When two types are plausible, prefer the more specific one. If still ambiguous, prefer
`feedback` over `convention` (behavioral over workflow) and `field-note` over `knowledge`
(practical surprise over general dimension update).

### B. Dated File Naming Contract

`feedback` type memories use a dated naming convention to support parallel-safe writes:

```
feedback_{slug}_{timestamp}.md
```

- `{slug}`: kebab-case identifier for the topic (stable across sessions, user-meaningful)
- `{timestamp}`: ISO 8601 UTC, colons replaced with hyphens — `YYYY-MM-DDTHH-MM-SS`

Examples:
```
feedback_tdd-no-exceptions_2026-05-19T14-23-01.md
feedback_deploy-merge-to-main_2026-05-19T09-11-45.md
```

**All other types** (`project`, `user`, `pattern`) use plain-slug filenames (upsert semantics):
```
project_batrade-broker-role.md
user_lexia-bonnie-alias.md
pattern_memory-routing-taxonomy.md
```

### C. `brana memory write` CLI Gateway

All memory writes go through a single CLI command:

```bash
brana memory write \
  --type feedback \      # from the 7-type table above
  --scope project \      # project | global | cross-project
  --slug "slug-name" \
  --content "..."
```

**Model classifies. CLI routes.** The CLI is the single authority on destination resolution:
- Validates `--type` is one of the 7 canonical types (invalid type → error + hint)
- Resolves destination path from `type + scope`
- For `feedback` type: generates the ISO timestamp and writes dated file
- For `project`/`user` type: upserts (creates or overwrites)
- For `pattern` type: writes to local file first, then ruflo best-effort
- For `convention`/`field-note`: appends to target section (errors if section not found)
- For `adr`: creates draft file in `docs/architecture/decisions/`

MCP surface (same pattern as `brana backlog`):

| MCP tool | CLI equivalent |
|----------|---------------|
| `mcp__brana__memory_write` | `brana memory write` |
| `mcp__brana__memory_index` | `brana memory index` |
| `mcp__brana__memory_migrate` | `brana memory migrate` |
| `mcp__brana__memory_list` | `brana memory list` |

Skill procedures (close, retrospective, brainstorm PERSIST) call `mcp__brana__memory_write`
directly — no bash subshell required.

### D. MEMORY.md Ownership — Auto-Generated by CLI

`MEMORY.md` is generated from the filesystem. The model **never writes MEMORY.md directly**.

`brana memory index` scans `~/.claude/projects/{p}/memory/` for all `*_*.md` files, groups
by slug prefix, picks the newest file per slug (by timestamp in filename), and writes the
index. Session-start hook triggers regeneration.

**Rationale:** MEMORY.md written by the model is fragile — entries drift, get truncated,
or conflict across sessions. Generated from the filesystem, it is always current and
consistent with the actual files on disk.

**Implementation order:**
1. Shell script first (`grep + sort + head`) — fast, no Rust required
2. Rust CLI when corpus grows or shell becomes a bottleneck

### E. Migration Strategy for Existing Plain-Slug Files

Existing `feedback_slug.md` files (plain slug, no timestamp) are migrated to the dated
format by `brana memory migrate`:

```bash
brana memory migrate [--dry-run] [--scope project|global]
```

**Algorithm:**
1. Find all `feedback_*.md` files WITHOUT a timestamp suffix (pattern: `feedback_[^_]+.md`)
2. Read each file's mtime
3. Rename: `feedback_slug.md` → `feedback_slug_{mtime_as_ts}.md`
4. Operation is idempotent — re-running on an already-migrated file is a no-op (already
   has timestamp suffix)

**Sequencing with ADR-037 migration:**
- ADR-037 on-encounter rule: when a skill reads `feedback_*.md`, classify and write to
  canonical destination; rename original to `feedback_*.md.migrated`
- This ADR's `brana memory migrate`: converts plain-slug to dated before the on-encounter
  rule runs, so the on-encounter rule processes dated files going forward
- Run `brana memory migrate` once before enabling ADR-037 Wave 2 blocking

---

## Consequences

- Memory routing becomes deterministic and inspectable. The CLI is the single routing
  authority — session behavior is consistent regardless of which skill triggered the write.
- Parallel sessions writing `feedback_*` no longer clobber each other. Each session writes
  to its own timestamped file; no merge required.
- MEMORY.md is always current. Generated at session-start from actual files on disk;
  model maintenance burden eliminated.
- Existing plain-slug `feedback_*.md` files are migrated once via `brana memory migrate`
  before Wave 2 blocking is enabled.
- Skill procedures (close, retrospective, brainstorm) must be updated to call
  `mcp__brana__memory_write` instead of the `Write` tool directly.

## Non-Actions

- **No immediate bulk migration of pattern or project memories.** Only `feedback_*` files
  need dated naming; `project_*` and `user_*` retain upsert semantics.
- **No ruflo dependency for feedback type.** File-first always; ruflo is best-effort for
  `pattern` type only. Recall works even without ruflo.
- **No MEMORY.md auto-generation before CLI is built.** Until `brana memory index` ships,
  the model continues writing MEMORY.md manually. This ADR is the spec; enforcement starts
  when the CLI is available.
- **No reclassification of existing `feedback_*.md` content in bulk.** That is ADR-037's
  on-encounter migration. This ADR only renames the files to dated format.
