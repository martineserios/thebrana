# ADR-015: State Consolidation and Plugin-First Architecture

**Date:** 2026-03-10
**Status:** accepted
**Related:** ADR-005 (AgentDB v3), ADR-006 (merge enter into thebrana), ADR-014 (plugin management skill), t-326 (investigation), t-291 (plugin suite research), t-292 (plugin suite architecture)

## Context

An audit of `~/.claude/` revealed that brana-created knowledge and operational state is accumulating outside any git repo. If the machine dies, all learned patterns, session history, event logs, and semantic indexes are lost.

### Current state inventory

```
~/.claude/                              NOT in git
├── CLAUDE.md                           ← bootstrap copy (source: system/CLAUDE.md)
├── CLAUDE.md.backup.* (108 files)      ← garbage from early bootstrap
├── rules/*.md (12 files)               ← bootstrap copy (source: system/rules/)
├── hooks/*.sh (10 files)               ← bootstrap copy (source: system/hooks/)
├── scripts/*.sh (6 files)              ← bootstrap copy (source: system/scripts/)
├── statusline.sh                       ← bootstrap copy
├── scheduler/                          ← bootstrap copy (source: system/scheduler/)
├── memory/
│   ├── event-log.md                    ← /brana:log writes here (cross-client events)
│   ├── portfolio.md                    ← cross-client routing index
│   ├── meta-whatsapp-templates.md      ← domain knowledge (escaped dimension doc)
│   └── pending-learnings.md            ← stale, no longer produced
├── tasks-portfolio.json                ← cross-client project registry
├── tasks-config.json                   ← display theme config
├── projects/*/memory/
│   ├── MEMORY.md                       ← CC native auto-memory + brana fallback writes
│   ├── sessions.md                     ← session-end.sh writes per-session stats
│   ├── session-handoff.md              ← /brana:close writes session handoff
│   └── .needs-backprop                 ← drift flag (session-end.sh)
└── ...                                 ← CC internals (debug, history, file-history, etc.)

~/.swarm/                               NOT in git
└── memory.db                           ← claude-flow/AgentDB semantic store (SQLite + embeddings)

~/.claude-flow/                         NOT in git
└── embeddings.json                     ← embedding model config (384-dim ONNX)
```

### The two memory systems

Brana uses two independent memory systems that serve different purposes:

```
┌─────────────────────────────────────────────────────────────┐
│                    BRANA MEMORY STACK                         │
├──────────────────────────────┬──────────────────────────────┤
│   OPERATIONAL STATE          │    SEMANTIC MEMORY            │
│   (this ADR's scope)         │    (claude-flow/AgentDB/RVF)  │
│                              │                               │
│   event-log.md               │    patterns namespace         │
│   portfolio.md               │    knowledge namespace        │
│   sessions.md                │    decisions namespace        │
│   session-handoff.md         │    metrics namespace          │
│   tasks-portfolio.json       │    business namespace         │
│   tasks-config.json          │    scheduler-runs namespace   │
│   MEMORY.md snapshots        │    research-leads namespace   │
│                              │                               │
│   Format: markdown/JSON      │    Format: 384-dim vectors    │
│   Store: flat files           │    Store: SQLite (~/.swarm/)  │
│   Path: ~/.claude/*          │    Path: ~/.swarm/memory.db   │
│   Recovery: git sync         │    Recovery: rebuildable      │
└──────────────────────────────┴──────────────────────────────┘
```

No hook writes to both systems for the same data. Operational state and semantic memory are written independently, by different triggers, with different access patterns. This ADR addresses operational state. Semantic memory is addressed in the compatibility section below.

### The memory stack today (7 layers)

| Layer | Content | Path | In git? | Written by |
|-------|---------|------|---------|------------|
| L1 | Global identity (CLAUDE.md) | `~/.claude/CLAUDE.md` | Source only | bootstrap.sh |
| L2 | Behavioral rules | `~/.claude/rules/*.md` | Source only | bootstrap.sh |
| L3 | Project identity | `thebrana/.claude/CLAUDE.md` | Yes | Human + Claude |
| L4 | Project auto-memory | `~/.claude/projects/*/memory/MEMORY.md` | No | CC native + brana fallback |
| L5 | Session companion files | `~/.claude/projects/*/memory/{sessions,handoff}.md` | No | brana hooks + skills |
| L6 | Global memory | `~/.claude/memory/*.md` | No | brana skills |
| L7 | Semantic vector store | `~/.swarm/memory.db` | No | claude-flow, index-knowledge.sh |

**Layers 4–7 (all learned knowledge) are outside git.** This is the problem.

### What writes to `~/.claude/memory/` today

| Writer | Trigger | Target | Content |
|--------|---------|--------|---------|
| `/brana:log` | User invocation | `event-log.md` | Cross-client events (meetings, DNS fixes, client comms) |
| `/brana:client-retire` + archiver agent | Client retirement | `portfolio.md` | Portfolio index updates |
| `/brana:close` | Session end | `portfolio.md` | Pointer updates |
| `/brana:meta-template` | Read-only | `meta-whatsapp-templates.md` | (never writes, only reads) |
| `session-end.sh` | SessionEnd hook | `pending-learnings.md` | Fallback when claude-flow unavailable |

### Why bootstrap.sh exists

CC's plugin system (v2.1.x) has a known bug (#24529): PostToolUse and PostToolUseFailure hooks don't fire from plugin `hooks.json`. Only PreToolUse, SessionStart, and SessionEnd work from plugins. Bootstrap.sh exists to install PostToolUse hooks to `~/.claude/settings.json` with absolute paths — a workaround for this CC limitation.

### Strategic direction

The user's stated goals:

1. **All brana state in git repos.** Three repos, three concerns: thebrana (system), clients/* (per-client), brana-knowledge (vault).
2. **Kill bootstrap.sh.** Everything loads as a pure plugin — no deployment step.
3. **Claude Marketplace distribution.** `install brana` and it works. Zero `~/.claude/` manipulation.

## Decision

### Principle: cache-then-sync — local paths are hot cache, git repos are source of truth

A pre-mortem challenge (Opus, 2026-03-10) identified two critical blockers in the original "direct write to repos" approach:

1. **CC's `@` directive may not support plugin-relative paths.** Writing `portfolio.md` directly to repo and referencing via `@system/state/portfolio.md` in CLAUDE.md is untested. If `@` only resolves `~/.claude/` paths, the portfolio routing breaks.
2. **`session-end.sh` runs in a background fork.** It CDs to `/tmp` and has no reliable `$PROJECT_DIR` variable. Writing companion files directly to `{project-repo}/.claude/memory/` requires knowing the project path, which the hook doesn't have.

**Resolution: cache-then-sync pattern.** Skills and hooks continue writing to `~/.claude/` (fast, reliable, CC-native paths). A sync mechanism copies state to git repos for recovery and portability.

```
┌──────────────────────────────────────────────────────────────────┐
│                         RUNTIME LAYER                            │
│                                                                  │
│  Skills/Hooks write to fast, reliable local paths                │
│                                                                  │
│  ┌──────────────────────┐         ┌───────────────────────┐     │
│  │  ~/.claude/           │         │  ~/.swarm/memory.db    │     │
│  │  (operational cache)  │         │  (semantic store)      │     │
│  │                       │         │                        │     │
│  │  memory/              │         │  6 namespaces          │     │
│  │   event-log.md        │         │  384-dim ONNX vectors  │     │
│  │   portfolio.md        │         │  BM25 hybrid search    │     │
│  │  projects/*/memory/   │         │  AgentDB v3 backend    │     │
│  │   MEMORY.md           │         │                        │     │
│  │   sessions.md         │         │  ┌──────────────────┐  │     │
│  │   session-handoff.md  │         │  │ Future: .rvf      │  │     │
│  │   .needs-backprop     │         │  │ (Phase 3 target)  │  │     │
│  └──────────┬────────────┘         │  └──────────────────┘  │     │
│             │                      └──────────┬─────────────┘     │
└─────────────┼─────────────────────────────────┼──────────────────┘
              │                                 │
              │  SYNC LAYER                     │  REBUILD LAYER
              │  (new — this ADR)               │  (existing)
              ▼                                 ▼
┌──────────────────────────┐    ┌──────────────────────────────────┐
│  GIT REPOS               │    │  REBUILDABLE FROM GIT            │
│  (source of truth)       │    │                                  │
│                          │    │  index-knowledge.sh              │
│  thebrana/               │    │    brana-knowledge/dimensions/   │
│   system/state/          │    │    → knowledge namespace (315+)  │
│    event-log.md     ◄────┤    │                                  │
│    portfolio.md     ◄────┤    │  session hooks (organic)         │
│    tasks-*.json     ◄────┤    │    → patterns, metrics ns        │
│    patterns-export  ◄────┤    │                                  │
│                          │    │  export-patterns.sh              │
│  clients/*/              │    │    patterns + decisions ns        │
│   .claude/memory/        │    │    → system/state/patterns.json  │
│    sessions.md      ◄────┤    │                                  │
│    handoff.md       ◄────┤    │  RVF Phase 3: single .rvf file  │
│    MEMORY-snapshot  ◄────┤    │    exportable, git-trackable     │
│                          │    │                                  │
│  brana-knowledge/        │    │                                  │
│   dimensions/       ◄───┤    │                                  │
│    meta-whatsapp.md      │    │                                  │
└──────────────────────────┘    └──────────────────────────────────┘
```

### 1. Operational state: cache at `~/.claude/`, sync to `system/state/`

Writers continue targeting `~/.claude/` paths. A sync step copies to git:

| File | Runtime path (cache) | Git path (source of truth) | Sync trigger |
|------|---------------------|---------------------------|-------------|
| `event-log.md` | `~/.claude/memory/` | `thebrana/system/state/event-log.md` | session-start.sh (reverse sync) |
| `portfolio.md` | `~/.claude/memory/` | `thebrana/system/state/portfolio.md` | session-start.sh (reverse sync) |
| `tasks-portfolio.json` | `~/.claude/` | `thebrana/system/state/tasks-portfolio.json` | session-start.sh |
| `tasks-config.json` | `~/.claude/` | `thebrana/system/state/tasks-config.json` | session-start.sh |
| `meta-whatsapp-templates.md` | `~/.claude/memory/` | `brana-knowledge/dimensions/meta-whatsapp-templates.md` | One-time move |

Create `thebrana/system/state/` directory for cross-client operational state.

**Sync direction:** Bidirectional. On session start, the sync script:
1. Copies `~/.claude/memory/{file}` → `thebrana/system/state/{file}` (if cache is newer)
2. Copies `thebrana/system/state/{file}` → `~/.claude/memory/{file}` (if repo is newer — new machine scenario)

This avoids modifying any skill or hook write paths while ensuring git recovery.

### 2. CC auto-memory: snapshot to project repos

CC auto-memory (`~/.claude/projects/*/memory/MEMORY.md`) cannot be relocated — CC owns that path. Brana syncs it:

- `session-end.sh` copies `MEMORY.md` to `{project-repo}/.claude/memory/MEMORY-snapshot.md`
- On new machine: `bootstrap.sh --restore-memory` copies snapshots back to CC's paths
- Frequency: every session end (incremental, small file)

**Note:** `session-end.sh` runs in a background fork without `$PROJECT_DIR`. Resolution: the hook already receives the project path via CC's hook environment (`$CLAUDE_PROJECT_DIR` or inferred from `$PWD` before fork). If unreliable, fall back to writing a snapshot alongside the session companion files at `~/.claude/projects/*/memory/` and let the session-start sync pick it up.

### 3. Companion files: write to cache, sync to project repos

| File | Runtime path (cache) | Git path (source of truth) | Sync trigger |
|------|---------------------|---------------------------|-------------|
| `sessions.md` | `~/.claude/projects/*/memory/` | `{project-repo}/.claude/memory/sessions.md` | session-start.sh |
| `session-handoff.md` | `~/.claude/projects/*/memory/` | `{project-repo}/.claude/memory/session-handoff.md` | session-start.sh |
| `.needs-backprop` | `~/.claude/projects/*/memory/` | `{project-repo}/.claude/memory/.needs-backprop` | session-start.sh |

Hooks and skills continue writing to `~/.claude/projects/*/memory/` (no code changes needed). Session-start sync copies to the project repo.

### 4. Semantic memory: export/import for patterns and decisions

claude-flow's semantic store (`~/.swarm/memory.db`) has 6 namespaces with different recovery profiles:

| Namespace | Content | Entries | Recovery method |
|-----------|---------|---------|----------------|
| `knowledge` | Dimension doc sections | 315+ | **Rebuildable** from `brana-knowledge/dimensions/` via `index-knowledge.sh` |
| `patterns` | Corrections, session summaries | ~50+ | **Export needed** — learned over time, not derivable |
| `decisions` | Architectural decisions | ~20+ | **Export needed** — curated by skills |
| `metrics` | Flywheel metrics | ~30+ | **Derivable** — session hooks regenerate organically |
| `business` | Pipeline deal snapshots | ~10+ | **Derivable** — pipeline events regenerate |
| `scheduler-runs` | Job execution summaries | ~20+ | **Ephemeral** — no recovery needed |

Only `patterns` and `decisions` namespaces need explicit backup:

- `system/scripts/export-patterns.sh` — dump patterns + decisions to `thebrana/system/state/patterns-export.json`
- `system/scripts/import-patterns.sh` — restore from export on new machine
- Scheduler job: weekly export (alongside the existing weekly reindex)

**RVF Phase 3 compatibility:** When AgentDB migrates to a single `.rvf` container (per ADR-005 Phase 3), the entire semantic store becomes a single binary file. The export/import dance simplifies to `cp memory.rvf → repo` (possibly via git-lfs). The cache-then-sync pattern is the bridge to that future.

### 5. Sync triggers: hooks + scheduler (belt and suspenders)

Session hooks are the primary sync mechanism (real-time, best-effort). The brana scheduler (systemd timers, `Persistent=true`) is the **safety net** — if a hook fails or the machine was off, the scheduler catches up within 24h.

```
              SESSION HOOKS                    SCHEDULER (safety net)
              (real-time, best-effort)         (guaranteed, catches up)

session-start  ─→ sync operational state
                  (cache ↔ repo, bidirectional)

session-end    ─→ MEMORY.md snapshot
                  sessions.md update

                                               sync-state        daily 9am
                                               ─→ same logic as session-start
                                               ─→ catches missed syncs
                                               ─→ auto-commit if changed

                                               export-patterns   Sunday 3am
                                               ─→ dump patterns+decisions ns
                                               ─→ write to system/state/
                                               ─→ auto-commit if changed

                                               reindex-knowledge Sunday 3am
                                               ─→ ALREADY EXISTS
                                               ─→ rebuild knowledge ns
```

**Why both?** Both `session-start.sh` and `session-end.sh` perform push (belt and suspenders). But both run in background forks and may fail silently. The scheduler guarantees no sync gap exceeds 24h. `Persistent=true` means if the machine was asleep at 9am, the job runs as soon as it wakes.

#### Sync trigger matrix

```
TRIGGER              WHAT SYNCS                     DIRECTION        FREQUENCY
─────────────────   ───────────────────────────    ──────────       ─────────
session-start.sh    event-log.md, portfolio.md     cache ↔ repo     every session
                    tasks-portfolio.json            cache ↔ repo     every session
                    tasks-config.json               cache ↔ repo     every session
                    sessions.md, handoff.md         cache → repo     every session
                    MEMORY-snapshot.md              cache → repo     every session

session-end.sh      MEMORY.md snapshot             CC path → cache  every session
                    event-log.md, portfolio.md     cache → repo     every session
                    tasks-portfolio.json            cache → repo     every session
                    sessions.md, handoff.md         cache → repo     every session

sync-state (sched)  same as session-start           cache ↔ repo     daily 9am

export-patterns     patterns + decisions ns         cf → repo        Sunday 3am
(scheduler)

reindex-knowledge   dimension docs → knowledge ns   repo → cf        Sunday 3am
(scheduler)

post-commit hook    changed dimension docs          repo → cf        on commit
(brana-knowledge)
```

The sync is **bidirectional** across the two memory systems:
- Operational state: `~/.claude/` → git repos (this ADR, hooks + scheduler)
- Semantic knowledge: git repos → `~/.swarm/` (existing: `index-knowledge.sh` + post-commit hook)

#### New scheduler job definitions

Add to `scheduler.json`:

```json
{
  "sync-state": {
    "type": "command",
    "command": "./system/scripts/sync-state.sh --auto-commit",
    "project": "~/enter_thebrana/thebrana",
    "schedule": "*-*-* 09:00:00",
    "enabled": true,
    "timeoutSeconds": 60,
    "captureOutput": true
  },
  "export-patterns": {
    "type": "command",
    "command": "./system/scripts/export-patterns.sh --auto-commit",
    "project": "~/enter_thebrana/thebrana",
    "schedule": "Sun *-*-* 03:05:00",
    "enabled": true,
    "timeoutSeconds": 120,
    "captureOutput": true
  }
}
```

`sync-state` runs at 9am daily (5 min after any morning-check). `export-patterns` runs Sunday 3:05am (5 min after `reindex-knowledge` to avoid lock contention on the same project).

### 6. Plugin-first migration path

| Phase | What | Blocker |
|-------|------|---------|
| **Now** | Cache-then-sync for all brana state (decisions 1–4) | None |
| **Now** | Sync scripts in `session-start.sh` + `session-end.sh` | None |
| **When CC fixes #24529** | Move PostToolUse hooks from `settings.json` to `plugin.json` | CC bug fix |
| **When CC supports plugin rules** | Move `rules/*.md` into plugin manifest | CC feature |
| **When CC supports plugin identity** | Move `CLAUDE.md` into plugin manifest (or CC-supported equivalent) | CC feature |
| **Final state** | `bootstrap.sh` retired. Plugin is self-contained. Marketplace install works. | All CC features landed |

Until CC ships the missing plugin capabilities, bootstrap.sh remains as a **shrinking shim** — each CC release may eliminate one more reason for it to exist.

### 7. Immediate cleanup

- Delete 108 `CLAUDE.md.backup.*` files (bootstrap garbage)
- Delete `pending-learnings.md` (stale)
- Move `meta-whatsapp-templates.md` to brana-knowledge

### 8. New machine recovery procedure

```
# 1. Clone repos
git clone thebrana && git clone brana-knowledge && git clone clients/*

# 2. Install identity layer
cd thebrana && ./bootstrap.sh

# 3. Restore operational state (session-start sync handles this automatically)
#    First session start detects repo is newer → copies to ~/.claude/

# 4. Restore auto-memory snapshots
./bootstrap.sh --restore-memory

# 5. Rebuild semantic knowledge (315+ sections)
./system/scripts/index-knowledge.sh

# 6. Restore patterns and decisions
./system/scripts/import-patterns.sh

# 7. Metrics, business, scheduler-runs rebuild organically from new sessions
```

## Consequences

### Positive

- **Portable.** Clone three repos on a new machine → all brana knowledge recoverable. 8-step setup, mostly automated.
- **Recoverable.** Git history preserves every state change. No more silent knowledge loss.
- **Non-breaking.** No skill or hook code changes needed for operational state — sync layer handles the mapping.
- **Marketplace-ready.** Each decision moves closer to a self-contained plugin with no external state.
- **Auditable.** Event log, portfolio, patterns — all visible in git diffs and PRs.
- **RVF-compatible.** Cache-then-sync is the bridge to Phase 3's single `.rvf` container.

### Negative

- **Git noise.** `event-log.md` and `sessions.md` change frequently. Mitigate: `.gitattributes` to mark as generated, or `state/` directory commits separate from feature work.
- **Concurrent writes.** Multiple sessions writing to the same cache file (event-log.md) could conflict on sync. Mitigate: append-only format, last-write-wins for portfolio, per-session temp files merged by sync.
- **CC auto-memory is still external.** MEMORY.md snapshots are backups, not the live copy. RPO: one session of work between snapshot and machine failure. Acceptable tradeoff.
- **bootstrap.sh can't die yet.** CC plugin system needs three features (PostToolUse hooks, plugin rules, plugin identity) before bootstrap is fully eliminated. This is a phased migration, not a single cutover.
- **Sync adds latency to session start.** File comparison + copy adds a few hundred ms. Acceptable — session-start already takes 2-5s for pattern recall.

### Challenge findings addressed

| Finding | Severity | Resolution |
|---------|----------|-----------|
| `@` directive may not support plugin-relative paths | CRITICAL | Avoided — `portfolio.md` stays at `~/.claude/memory/`, sync copies to repo. `@` reference unchanged. |
| `session-end.sh` can't find project repo path | CRITICAL | Avoided — hooks write to `~/.claude/` (cache). Session-start sync copies to repo. |
| Concurrent write conflicts on `event-log.md` | WARNING | Append-only format + last-write-wins sync. |
| Git noise from frequent state changes | WARNING | `.gitattributes` + separate `state/` commits. |
| Migration touches 23+ files | WARNING | Eliminated — no write path changes. Only sync scripts added. |
| MEMORY.md snapshot RPO | OBSERVATION | Documented as acceptable (one session). |
| claude-flow export is point-in-time | OBSERVATION | Weekly export + event-driven export on high-value stores (future). |
| bootstrap.sh retirement has no CC timeline | OBSERVATION | Accepted — phased migration, monitor CC releases. |

### Migration order

1. Create `system/state/` directory
2. Build `system/scripts/sync-state.sh` (bidirectional file sync with newer-wins logic)
3. Add sync-to-repo call to `session-start.sh`
4. Add MEMORY.md snapshot step to `session-end.sh`
5. Build `system/scripts/export-patterns.sh` / `import-patterns.sh`
6. Add `sync-state` + `export-patterns` jobs to `scheduler.template.json`
7. Deploy scheduler: `brana-scheduler deploy` (generates systemd timers)
8. Clean up garbage (108 backups, pending-learnings.md, move meta-whatsapp)
9. Test new machine recovery procedure end-to-end
10. Monitor CC plugin releases for #24529 fix and new capabilities
