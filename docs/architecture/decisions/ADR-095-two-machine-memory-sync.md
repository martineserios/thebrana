---
status: proposed
extends: docs/architecture/decisions/ADR-015-state-consolidation-plugin-first.md
informs: docs/architecture/decisions/ADR-038-memory-write-gateway.md
---

# ADR-095: Keep brana memory current across two machines working in parallel

**Status:** Proposed (2026-10-02)
**Date:** 2026-10-02
**Deciders:** Martín Rios
**Tags:** memory, ruflo, sync, git, macos, harness
**Tasks:** t-3403 (this ADR) · implementation t-3404..t-3410 (see *Implementation*)
**Extends:** [ADR-015](ADR-015-state-consolidation-plugin-first.md) (cache-then-sync; git is the source of truth)
**Respects:** [ADR-038](ADR-038-memory-write-gateway.md) (dated, parallel-safe note files) and [ADR-058](ADR-058-search-provider-hybrid-recall.md) (ruflo never auto-indexes `~/.claude/memory/`)

---

## Context

Until 2026-10-02 brana ran on one machine. The macOS port (epic t-3372) added a second workstation, a Mac that sleeps, next to a Linux laptop that stays up. Restoring the Mac's memory by hand exposed what ADR-015 does not cover:

1. **The ruflo database cannot be shared.** `~/.swarm/memory.db` (150 MB, 7,150 entries, 384-dim embeddings) is gitignored because it exceeds GitHub's 100 MB limit (the push failure of 2026-09-10). Two machines cannot write one SQLite file, and a copy goes stale the moment either side learns something.
2. **`sync-state.sh push|pull` are unidirectional with no merge** (ADR-015: "no bidirectional newer-wins logic"). With two writers, whichever pushes last silently overwrites the other.
3. **Nothing restores notes.** `pull` restored 4 files. The 210 notes in `brana-knowledge/backup/memory` and the per-project memory had to be copied by hand, and project folders are named after the absolute path (`-home-martineserios-…` vs `-Users-martin-tabz-…`), so a copy needs a slug remap.
4. **Version drift is real.** Linux runs ruflo 3.34.0 (pinned, locally patched); the Mac's first install was 3.51.0.

What is in the ruflo DB decides what must be synced:

| Namespace | Entries | Nature |
|---|---|---|
| `knowledge` | 5,358 | **Derived** from `brana-knowledge/dimensions` by `index-knowledge.sh` |
| `session`, `metrics`, `default` | ~1,557 | Machine-local telemetry |
| `skills` | 69 | Derived from skill files |
| `pattern`, `field-notes`, `decisions`, `assumptions`, `verification`, `hive-memory` | ~166 | **Curated**, written by usage on either machine. The only part that is not reproducible. |

## Decision

**Each machine keeps its own database. Machines converge through entries and files in the private `brana-knowledge` repo, never through the database file.** Three data kinds get three rules.

### 1. Notes and docs: plain git, no new mechanism

`~/.claude/memory/*.md` and `~/.claude/projects/*/memory/` are mirrored to `brana-knowledge/backup/memory` and `backup/projects/` (the existing daily backup). Pull at session start, push at `/brana:close`.

- ADR-038's dated filenames already make concurrent writes land in different files.
- `MEMORY.md` is regenerated from the filesystem (`memory_index`), never merged.
- Append-only files (`event-log.md`, `override-log.md`) get `merge=union` in `.gitattributes`. Both machines only append, so a union merge is correct.
- **Project paths are stored host-neutral** (`clients/tabz`, resolved through `tasks-portfolio.json`), not as the path-derived slug. Pull maps each entry to the local slug and skips projects that do not exist on that machine.

### 2. Derived ruflo namespaces: rebuilt locally, never synced

`knowledge` and `skills` are re-indexed on each machine after a pull of the docs they derive from (`index-knowledge.sh` is incremental). `session`, `metrics`, `default` are local-only.

### 3. Curated ruflo entries: one file per entry, newest write wins

- **Export:** each curated entry becomes `brana-knowledge/backup/curated/<namespace>/<key-hash>.json` with `{namespace, key, content, tags, metadata, updated_at, origin_host}`. No embedding is exported; it is derived from `content` and recomputed on import (about 166 entries, cheap).
- **Why per-entry files:** two machines adding different entries produce different files, so the git merge is trivially clean. The current single 11 MB export would conflict on every parallel push.
- **Import:** upsert by `(namespace, key)`. If both sides hold the key, the larger `updated_at` wins; a tie breaks on `origin_host` order so both machines pick the same winner. The losing version stays in git history.
- **Deletes** are tombstone files (`deleted_at`), so a delete on one machine propagates instead of being re-created by the other.
- **Clock skew** between two laptops (seconds) only matters for two edits of the same key within that window; accepted.

### Triggers: inside existing commands (no new thing to remember)

| When | Action |
|---|---|
| Session start | `git pull --ff-only` on brana-knowledge, import changed curated entries, re-index changed docs. Time-boxed; offline or slow means skip silently, never block the session. |
| `/brana:close` | Export curated entries changed since the last sync, commit, push. A push failure queues, it does not fail the close. |
| New machine | `brana memory restore` performs what was done by hand on 2026-10-02: pin ruflo, copy or rebuild the DB, restore notes with slug mapping, reindex. |

A Mac that sleeps simply syncs when it next starts a session. There is no daemon and no schedule to miss.

### Version guard

brana-knowledge records the ruflo version and embedding model that wrote the curated entries (`backup/swarm/ruflo-version`). Import warns and skips when the local ruflo major/minor differs from it. `brana doctor` shows the pin on each machine.

### Privacy boundary

Everything above goes to the **private** `brana-knowledge` repo only. The public thebrana repo never receives memory content (consistent with t-3352; `system/state/patterns-export.json` is already gitignored there). An export step that cannot reach the private repo does nothing; it never falls back to the public one.

## Options considered

| Option | Why not |
|---|---|
| Copy `memory.db` between machines periodically | Two writers: last copy wins and loses the other side's learnings. 150 MB each time, over GitHub's file limit, and a copy of a live WAL database risks corruption (the recurring-corruption history). |
| One shared DB on a server or network share | New always-on infrastructure for ~166 entries; breaks offline use on a Mac that sleeps. |
| Keep ADR-015 unidirectional, "Linux is the master" | The Mac's learnings are lost, which defeats working on two devices. |
| CRDT / full-DB replication | Heavy for a curated set this small; the per-entry newest-wins rule gives the same result for this data. |

## Consequences

**Good.** Both machines accumulate knowledge. The only hard sync surface is ~166 entries plus text files. Merge conflicts are structurally rare. A new machine is one command.

**Costs and limits.**
- **Not real time.** A learning appears on the other machine at its next session start or manual sync.
- Same-key concurrent edits lose the older one (kept in git history).
- Both machines must run the pinned ruflo version.
- Session start gains a bounded pull and import step; it must stay inside the session-start hook's size and time budgets (`session-start.sh` is already near its 50 KB gate, so the new step lives in its own script).

**Residual risks.** Clock skew on same-key edits; a brana-knowledge push blocked by a large file (the memory DB stays gitignored; a size check belongs in export); the private repo as a single point of failure (it is also the backup).

## Open questions

1. **Delete semantics:** keep tombstones forever, or expire them after N days?
2. **`decisions` namespace:** about 1 entry today, but ADR-017's decision log is also files; is the namespace worth syncing separately?
3. **Per-project memory with no counterpart:** skip silently (proposed) or warn?
4. **The 5,358 `knowledge` entries:** re-indexing on each pull is incremental, but a first run on a new machine is slow (embeddings); `brana memory restore` may prefer one DB copy from a safe backup there.

## Implementation (filed under epic t-3372, all pending until this ADR is accepted)

1. **t-3404** — per-entry curated export/import with newest-wins and tombstones, with tests against two simulated homes.
2. **t-3405** — notes sync: pull restores `backup/memory` + per-project memory with slug mapping; `merge=union` for append-only logs.
3. **t-3406** — session-start pull and `/brana:close` push, in their own script and time-boxed.
4. **t-3407** — ruflo version guard and `brana doctor` line.
5. **t-3408** — `brana memory restore` for a new machine (replaces the manual runbook).
6. **t-3409** — privacy audit: prove no memory content can reach the public repo.
7. **t-3410** — concurrency test: two homes writing in parallel, then converging.
