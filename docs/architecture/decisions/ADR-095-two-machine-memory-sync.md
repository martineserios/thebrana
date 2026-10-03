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
**Tasks:** t-3403 (this ADR) · implementation t-3404..t-3410, security t-3416..t-3420 (see *Implementation*) · t-3415 (threat-model amendment)
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

Everything above goes to the **private** `brana-knowledge` repo only (the public-repo half of the threat model; the other threats are in the section above). The public thebrana repo never receives memory content (consistent with t-3352; `system/state/patterns-export.json` is already gitignored there). An export step that cannot reach the private repo does nothing; it never falls back to the public one.

## Threat model

The first draft covered only "memory must not reach the public repo". That is one of six threats. Memory is not inert data: it is loaded into Claude's context at session start, so what is synced becomes instructions on every machine that imports it, and the two machines are not equally trusted (the Mac is a work laptop that sleeps and may be company-managed; the Linux laptop is the owner's).

| # | Threat | How it happens | Mitigation (decision) | Task |
|---|---|---|---|---|
| T1 | **Memory poisoning** | Anything that can push to `brana-knowledge` (a compromised Mac, a stolen token, a bad import) plants an entry such as "ignore previous instructions" that persists on both machines | Every imported entry carries provenance (`origin_host`, source commit). Entries from a lower-trust host are quarantined: searchable, flagged, **not injected at session start** until approved from a one-screen import diff. Per-entry size and instruction-shape limits. | t-3416 |
| T2 | **Secrets in memory** | A note or pattern holds a token or password (precedent: the 2026-06-03 handoff with `ANITA_ADMIN_SECRET`); sync copies it to GitHub and to the other machine | Secret scan **in the export/push path** (not only a commit hook). A hit blocks that entry and reports file and key, never the value. | t-3417 |
| T3 | **Client confidentiality** | A machine receives clients it does not work on. The 2026-10-02 restore put all clients' notes and a 7,150-entry DB on a laptop used for one client | Each machine declares a **client allowlist**; export, pull and restore filter by it. Unscoped entries are general knowledge and sync. A one-off audit and remediation for the Mac's over-collection. | t-3418 |
| T4 | **Account or token compromise** | A stolen GitHub token pushes forged entries to both machines | **Signed commits per machine** (own SSH signing key), verified against an allowed-signers file before import; unsigned or unknown signers are refused. | t-3419 |
| T5 | **Excess credentials on the weaker machine** | `gh auth login` on the Mac granted access to every private repo | Fine-grained token or deploy keys limited to the repos that machine needs. | t-3420 |
| T6 | **Transfer leftovers** | Raw client data and the DB copied to a synced Desktop folder (iCloud), to unencrypted USB media, install scripts of npm packages run with `--allow-scripts` | Never stage transfer files in a synced folder; encrypt or wipe media; list allowed install scripts knowingly; check MDM/company management first. | t-3420 |

**Trust direction.** The rule is asymmetric on purpose: the owner's machine can push to the Mac freely, but entries flowing *from* the lower-trust machine back to the owner's pass through T1's quarantine until approved. If the Mac is company-managed, treat it as lower-trust by default.

**Residual risk accepted:** a compromised owner machine can still poison the Mac; both machines share one private repo as a single point of failure (it is also the backup). The T1 to T4 mitigations bound the damage; they do not remove it.

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

**Residual risks.** (Security: see *Threat model*.) Clock skew on same-key edits; a brana-knowledge push blocked by a large file (the memory DB stays gitignored; a size check belongs in export); the private repo as a single point of failure (it is also the backup).

## Amendment 2026-10-03: the first live divergence (t-3435)

The two machines diverged before any implementation task landed. On 2026-10-02 the Mac pushed four backup commits (`0c84f77d..b04be875`) while this machine held three unpushed ones (`ed5dc2cd..6a6f0211`); `backup.sh` kept committing on the stale base and its push failed at every close. A dry-run merge conflicted in exactly the whole-store snapshot files: `backup/swarm/memory-entries.json`, `backup/swarm/patterns.json`, `backup/memory/patterns.md`, `backup/memory/consolidation-log.md`.

**What happened.** The merge was resolved by hand as `9cf4055f` ("keep newest local snapshot"): both histories kept, conflicted files taken from the Linux side. A key-level audit against the Mac tip `b04be875` found that the real loss was in markdown, not in ruflo:

| Store | Audit result |
|---|---|
| `memory-entries.json` | 6 Mac-only keys: 2 `pattern` (`error-recurrence:*` tool-failure counters for Mac tools), 2 `session`, 2 `metrics`. 77 shared keys differed, 68 of them derived `skills`; the one key where the Mac was newer had identical content. |
| `patterns.json` | 0 Mac-only rows by content identity (11,643 ∪ 11,539 rows = 11,596 identities). |
| `patterns.md` | Four-way union of Linux snapshot (103 sections), Mac tip (110), Linux live file (104) and merged `HEAD` (103) = **121 sections**; the live Linux file lacked 17 of them. |
| `knowledge-staging.md` | 1 Mac-authored section missing from the live Linux file. |
| `consolidation-log.md`, per-project memories | 0 lost; all 624 Mac project files survived the merge. |

**Rule applied (user decision 2026-10-03: keep as much as possible, no duplicates).**

| File | Identity | Rule |
|---|---|---|
| `memory-entries.json` | `(namespace, key)` | union; same key, larger `updated_at` wins |
| `patterns.json` | `(task_type, approach, ts)`, **not** `id` | union; `id` is a per-machine SQLite `AUTOINCREMENT` and collides across machines; identical rows collapse, larger `uses` wins |
| `patterns.md`, `knowledge-staging.md` | `## ` section heading | union by section: ours' order first, the other side's new sections appended; shared heading keeps ours' body |
| `session`, `metrics` rows; `error-recurrence:*` counters | — | not merged: machine-local telemetry (§2); they stay in git history (`b04be875`) |
| deletes | — | not propagated in this one-time pass (all 5 Mac deletions were `session`/`metrics`); tombstone semantics stay a question for acceptance |

**What was done.** The rule ships as `brana-knowledge/merge-snapshots.py` (`tests/test-merge-snapshots.sh`). The live Linux `patterns.md` and `knowledge-staging.md` were unioned from all sides (pre-union copies in `~/.claude/memory/archive/*_2026-10-03-pre-union.md`) and exported, so the repo copy holds the 121 sections. The live file does not: its header caps it at 100 and an auto-pruner trimmed it to 99 the same hour. Decision (user, 2026-10-03): keep the cap; the repo copy is the archive, grow-only because export unions, and the live file holds the most recent hundred. The Mac's step is only `git pull --ff-only` in brana-knowledge, so its next export runs the new `backup.sh` and unions instead of clobbering. The union is **not** copied onto the Mac's live files: under the trust profile of the ADR-095 revision (t-3436) the Mac is a company-managed, single-client machine, and Linux-authored sections reach it only through the client allowlist (T3, t-3418). The other direction did happen here: 17 Mac-authored sections entered the owner machine's live `patterns.md` on the user's approval of the heading list, without the T1 import review (t-3416, not built yet); the pre-union copy is in `~/.claude/memory/archive/`, so `diff` shows exactly what came in.

**Interim guard (until the ADR-095 revision's sync lands).** `backup.sh` and `daily-push.sh` now source `lib/remote-guard.sh` and fetch before anything else. Behind-only (the other machine pushed, nothing local to lose) fast-forwards **only when the incoming commits touch `backup/` data and add no symlink** — a pulled script would run at that very close, and the other machine is lower-trust (T1/T4), so anything else stops for review; true divergence refuses to commit, exits 2 and prints a recipe that unions only the four stores with an identity rule (`memory-entries.json`, `patterns.json`, `patterns.md`, `knowledge-staging.md`) and lists the rest for a by-hand merge keeping both sides; an offline fetch warns and continues so a local backup is never lost to a missing network (`tests/test-backup-guard.sh`). On export, `patterns.md` and `knowledge-staging.md` (section-keyed, written on both machines) are unioned by heading with the tracked copy instead of copied over it, and a union that cannot run keeps the tracked copy rather than falling back to the copy (`tests/test-backup-union.sh`); `portfolio.md` stays a plain copy because its sections are containers of rows, where heading-union would drop the other machine's rows (row merge belongs to t-3405). `merge-snapshots.py` refuses markdown without headings and JSON keyed only by a per-machine id instead of silently keeping ours. `restore.sh` lost its swallowed `git pull --rebase` for the same guard. A sibling sweep found the remaining copies of the pattern already tracked: the pull direction and the line logs (t-3405), `restore.sh` paths (t-3367), and the per-machine task-id counter (class C, see spec). This surfaces a divergence at the first close instead of the third.

**Known limit.** The two ruflo exports are still whole-store snapshots: each machine's export replaces the repo copy with its own database, so ruflo entries do not converge through the backup; `merge-snapshots.py` gives the one-time rule when they conflict. The ADR-095 revision (t-3436) decides there is no ruflo entry sync at all — the `pattern` rows are auto-generated telemetry, machine-local — and the per-entry export t-3404 is cancelled; the memory worth syncing is files, which is t-3405. The pull direction (repo copy into the live files) and the date/line logs (`event-log.md`, `override-log.md`, `consolidation-log.md`, where heading-union is wrong) belong to t-3405.

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
8. **t-3416** — provenance and quarantine for imported entries (T1).
9. **t-3417** — secret scan on export (T2).
10. **t-3418** — per-machine client allowlist and audit of the Mac's over-collection (T3).
11. **t-3419** — signed commits per machine, verified before import (T4).
12. **t-3420** — macOS setup security hygiene: scoped token, transfer media, synced folders (T5, T6).
13. **t-3435** — one-time divergence merge of 2026-10-02/03 and the interim fetch-first guard in `backup.sh` (done; see *Amendment 2026-10-03*).

Tasks 8 to 11 gate task 3 (session-start pull): importing without them would ship the sync with the poisoning path open.
