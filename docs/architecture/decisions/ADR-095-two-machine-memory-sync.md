---
status: proposed
extends: docs/architecture/decisions/ADR-015-state-consolidation-plugin-first.md
informs: docs/architecture/decisions/ADR-038-memory-write-gateway.md
---

# ADR-095: Keep brana memory current across machines, with trust profiles

**Status:** Proposed (2026-10-02, revised 2026-10-03)
**Date:** 2026-10-02
**Deciders:** Martín Rios
**Tags:** memory, ruflo, sync, git, macos, security, harness
**Tasks:** t-3403 (first draft) · t-3415 (threat model) · t-3436 (this revision) · implementation and security tasks in *Implementation*
**Extends:** [ADR-015](ADR-015-state-consolidation-plugin-first.md) (cache-then-sync; git is the source of truth)
**Respects:** [ADR-038](ADR-038-memory-write-gateway.md) (dated, parallel-safe note files) and [ADR-058](ADR-058-search-provider-hybrid-recall.md) (ruflo never auto-indexes `~/.claude/memory/`)

**Revision note (2026-10-03).** The first draft proposed per-entry sync of "curated" ruflo entries and one repo filtered by a client allowlist. Three findings changed that: (1) the ruflo `pattern` namespace is auto-generated error-recurrence records, not curated lessons; (2) the second machine is **company-managed** (Apple Business Manager / DEP, Rippling MDM), so it cannot be trusted with other clients' data; (3) a filter inside one repo is not a boundary against a machine whose token can read the whole repo. Decisions below replace the earlier ones; the history is in git.

---

## Context

Until 2026-10-02 brana ran on one machine. The macOS port (epic t-3372) added a second workstation: a Mac that sleeps, used for client **tabz**, next to the owner's Linux laptop that stays up. Restoring the Mac's memory by hand exposed what ADR-015 does not cover:

1. **The ruflo database cannot be shared.** `~/.swarm/memory.db` (150 MB, ~7,190 entries, 384-dim embeddings) is gitignored because it exceeds GitHub's 100 MB limit. Two machines cannot write one SQLite file, and a copy is stale the moment either side learns something.
2. **`sync-state.sh push|pull` are unidirectional with no merge** (ADR-015). With two writers, whichever pushes last silently overwrites the other.
3. **Nothing restores notes.** `pull` restored 4 files. The ~210 notes in `brana-knowledge/backup/memory` and the per-project memory had to be copied by hand, and project folders are named after the absolute path (`-home-martineserios-…` vs `-Users-martin-tabz-…`).
4. **The restore over-collected.** It put every client's notes, a full DB and the whole private repo on a laptop used for one client. Measured on the Mac: 46 of 206 notes and, in ruflo, 566 of 855 `session` and 431 of 712 `metrics` entries mention other clients; the clone held about 70 client project folders.
5. **The Mac is company-managed.** Inventory (2026-10-03): DEP-enrolled, MDM user-approved, vendor Rippling; profiles for MDM, FileVault, PPPC, managed login items and Device Trust CAs; FileVault company key unconfirmed; iCloud Desktop & Documents sync was on. The company can install and wipe, and plausibly holds the disk key.

What is in the ruflo DB decides what is worth moving:

| Namespace | Entries | Nature | Worth syncing? |
|---|---|---|---|
| `knowledge` | ~5,360 | **Derived** from `brana-knowledge/dimensions` by `index-knowledge.sh` | No: rebuild from docs |
| `session`, `metrics`, `default` | ~1,560 | Machine-local telemetry, more than half name other clients | Never |
| `skills` | 69 | Derived from skill files; the plugin installs them | No |
| `pattern` | 157 | **Auto-generated error-recurrence records** (~190 chars, tags `type:error-recurrence`, keys like `spike:<project>:…`, provenance unknown), many client-specific | No |
| `field-notes`, `decisions`, `assumptions`, `verification`, `hive-memory` | ~9 | Hand-written but negligible | No (the same facts live in files) |

**The valuable, irreplaceable memory is already files**: the ~206 notes in `~/.claude/memory`, per-project memory, and the docs in `brana-knowledge`. The ruflo DB is a rebuildable index plus telemetry.

## Decision

**Machines converge through files in git, never through the database. Each machine has a trust profile that decides which files it may receive. The boundary between profiles is a repository and its token, never a filter inside one repository.**

### 1. Notes and project memory: plain git, filtered by profile

`~/.claude/memory/*.md` and `~/.claude/projects/*/memory/` are mirrored to the private `brana-knowledge` repo (the existing daily backup). Owner machines pull at session start and push at `/brana:close`.

- ADR-038's dated filenames already make concurrent writes land in different files.
- `MEMORY.md` is regenerated from the filesystem (`memory_index`), never merged.
- Append-only files (`event-log.md`, `override-log.md`) get `merge=union` in `.gitattributes`.
- **Project paths are stored host-neutral** (`clients/tabz`, resolved through `tasks-portfolio.json`), not as the path-derived slug. Pull maps each entry to the local slug and skips projects that do not exist on that machine.

### 2. Derived ruflo namespaces: rebuilt locally, never synced

`knowledge` is re-indexed on each machine from the docs that machine is allowed to hold. `session`, `metrics`, `default` are local-only. **No ruflo entry is synced** (the per-entry export/import of the first draft is dropped, t-3404). If hand-curated ruflo entries ever appear in volume, revisit.

### 3. Trust profiles

| Profile | Machines | Receives | Never |
|---|---|---|---|
| **owner** | the owner's Linux laptop | everything, full DB | n/a |
| **company-managed** | the Mac (Rippling MDM) | the work the machine exists for (tabz repo and its memory), the harness (thebrana), generic notes that name no other client, and **approved** shared docs | other clients' notes, memory or backups; the full DB; the `brana-knowledge` clone; any tunnel, VPN or link to personal infrastructure |

**Rules for a company-managed machine:** tabz-only; ordinary developer traffic only (HTTPS to GitHub, package registries, APIs); no tunnel, VPN or remote-access path to the owner's machines; the owner reads the company's acceptable-use and AI-tools policy. Nothing in this design is chosen to avoid the employer's visibility. A machine that cannot be trusted with a data class is simply not given it.

### 4. Shared docs repo: the knowledge a restricted machine may read

A **separate** private repo (`brana-knowledge-shared`) holds only docs the owner has approved. A company-managed machine clones that repo with a fine-grained token scoped to it, and has no access to `brana-knowledge`. A sparse or filtered clone of the main repo was rejected: a token that can read the repo can fetch every blob. 31 of 85 files in `dimensions/` name a client, so the default is **exclude**; redaction only by explicit owner approval per file (t-3437).

### 5. Remote query between owner-controlled machines: optional, later

An SSH forced-command read-only wrapper over a mesh VPN (Tailscale, as used in the nexeye deployments) or a reverse tunnel can give one owner machine live access to another's index without copying it. Out of scope for the company-managed Mac. Not built until needed.

### Triggers: inside existing commands

| When | Action |
|---|---|
| Session start (owner machines) | `git pull --ff-only` on the profile's repo, re-index changed docs. Time-boxed; offline or slow means skip silently, never block the session. |
| Session start (company-managed) | Pull the shared docs repo and the tabz repo only. |
| `/brana:close` | Export notes changed since the last sync for this profile, secret-scan, commit, push. A push failure queues, it does not fail the close. |
| New machine | `brana memory restore --profile <name>` builds exactly that profile's set: pin ruflo, restore notes with slug mapping, index, doctor. |

### Version guard

`brana doctor` shows the installed ruflo version against the pinned one (3.34.0, locally patched). Relevant even without DB sync: the Mac first installed 3.51.0.

### Privacy boundary

Everything goes to **private** repos only. The public thebrana repo never receives memory content (t-3352; `system/state/patterns-export.json` is gitignored there). An export step that cannot reach a private repo does nothing and never falls back to the public one.

## Threat model

Memory is not inert data: it is loaded into Claude's context at session start, so what is synced becomes instructions on every machine that imports it, and machines are not equally trusted.

| # | Threat | How it happens | Mitigation (decision) | Task |
|---|---|---|---|---|
| T1 | **Memory poisoning** | Anything that can push to a synced repo (a compromised machine, a stolen token) plants a note such as "ignore previous instructions" that persists on every importer | Imported notes carry provenance (origin host, source commit). Notes from a lower-trust host are quarantined: searchable, flagged, **not injected at session start** until approved from a one-screen diff. Size and instruction-shape limits. | t-3416 |
| T2 | **Secrets in memory** | A note holds a token or password (precedent: the 2026-06-03 handoff with `ANITA_ADMIN_SECRET`) | Secret scan **in the export/push path**. A hit blocks that file and reports file and key, never the value. | t-3417 |
| T3 | **Client confidentiality** | A machine receives clients it does not work on (happened on 2026-10-02) | Trust profiles and the **repo boundary** (section 3, 4). A company-managed machine never receives the main repo. One-off remediation of the Mac's over-collection. | t-3418, t-3437 |
| T4 | **Account or token compromise** | A stolen GitHub token pushes forged notes | Signed commits per machine (own SSH signing key), verified against an allowed-signers file before import. | t-3419 |
| T5 | **Excess credentials on the weaker machine** | `gh auth login` on the Mac granted access to every private repo | Fine-grained token or deploy key limited to the repos that machine needs. | t-3420 |
| T6 | **Transfer leftovers** | Raw client data and the DB copied to a synced Desktop folder (iCloud), unencrypted USB media, npm install scripts run with `--allow-scripts` | Never stage transfer files in a synced folder; encrypt or wipe media; list allowed install scripts knowingly; check MDM/company management first. | t-3420 |
| T7 | **Company-device policy** | Personal infrastructure linked to an employer machine (VPN, tunnel, remote access), or personal-client data on it | Company-managed profile (section 3): tabz-only, ordinary traffic only, no link to personal machines; read the acceptable-use policy. Not hidden, not evaded. | t-3418, t-3420 |

**Trust direction.** The owner's machine can push to a company-managed machine freely (within the profile); anything flowing back from it passes T1's quarantine until approved.

**Residual risk accepted:** a compromised owner machine can still poison the Mac; both machines depend on private repos that are also the backup. The T1 to T4 mitigations bound the damage; they do not remove it.

## Options considered

| Option | Why not |
|---|---|
| Copy `memory.db` between machines | Two writers lose each other's learnings; 150 MB over GitHub's file limit; a live WAL copy risks corruption; and it carries every client's data. |
| Per-entry sync of ruflo entries (first draft) | The entries are mostly auto-generated error records, not curated lessons; the lessons are files. Not worth building. |
| One repo, filtered by a client allowlist (first draft) | A machine whose token reads the repo can fetch everything, a sparse clone included. The boundary must be a repository and its token. |
| SSH tunnel or VPN from the company Mac to the owner's Linux | Links an employer machine to personal infrastructure; the traffic pattern is what security tools and policies flag. Fine between owner-controlled machines (section 5), not for the company Mac. |
| One shared DB on a server | New always-on infrastructure; breaks offline use on a Mac that sleeps. |
| "Linux is the master", Mac learns nothing back | Loses the Mac's learnings, which defeats working on two devices (notes flow back through T1's quarantine). |

## Consequences

**Good.** The sync surface is plain files. Merge conflicts are structurally rare. A restricted machine holds only what it should. No database copying, no tunnel.

**Costs and limits.**
- **Not real time.** A learning appears on the other machine at its next session start or manual sync.
- The company-managed machine does not get the owner's older client-specific lessons; it builds its own tabz memory.
- Docs reach the restricted machine only after a one-time review (t-3437).
- Session start gains a bounded pull step in its own script (`session-start.sh` is near its 50 KB gate).

**Residual risks.** See *Threat model*; a brana-knowledge push blocked by a large file (the DB stays gitignored; a size check belongs in export); the private repos as a single point of failure (they are also the backup).

## Amendment 2026-10-03: the first live divergence (t-3435)

*Added from the t-3435 branch (another session) and adapted to this revision; the live evidence it records is the reason the company-managed profile must not hold write access to the main repo: the Mac pushed four backup commits (631 files, including its project memories) straight into `brana-knowledge`, a repo that holds every client.*

The two machines diverged before any implementation task landed. On 2026-10-02 the Mac pushed four backup commits (0c84f77d..b04be875) while this machine held three unpushed ones (ed5dc2cd..6a6f0211); `backup.sh` kept committing on the stale base and its push failed at every close. A dry-run merge conflicted in exactly the whole-store snapshot files: `backup/swarm/memory-entries.json`, `backup/swarm/patterns.json`, `backup/memory/patterns.md`, `backup/memory/consolidation-log.md`.

**What happened.** The merge was resolved by hand as `9cf4055f` ("keep newest local snapshot"): both histories kept, conflicted files taken from the Linux side. A key-level audit against the Mac tip found the real loss: 14 sections of `patterns.md`, 2 curated `pattern` entries (error-recurrence counters), and 4 machine-local rows (2 `session`, 2 `metrics`). `patterns.json` lost nothing by content and the Mac's 624 per-project memory files all survived.

**Rule applied, retroactively, as this ADR prescribes.**

| File | Merge key | Rule |
|---|---|---|
| `memory-entries.json` | `(namespace, key)` | union; same key, larger `updated_at` wins |
| `patterns.json` | `approach` content, **not** `id` | union; `id` is a per-machine autoincrement and collides across machines |
| `patterns.md`, `consolidation-log.md` | `## ` section heading | union by section |
| `session`, `metrics` rows | — | not merged: machine-local (§2); they stay in git history |

A union commit restored the 14 sections and 2 curated entries from `b04be875`. Counts per key after the merge are at least each side's; no duplicate keys.

**Interim guard (until t-3405 supersedes the snapshot export).** `backup.sh` now fetches before it exports. Behind-only (the other machine pushed, nothing local to lose) fast-forwards; true divergence (commits on both sides) refuses to commit and prints the resolution command; an offline fetch warns and continues so a local backup is never lost to a missing network. This surfaces a divergence at the first close instead of the third, which is all a whole-store snapshot can do.

**Known limit.** The export is still a whole-store snapshot: the next export from either machine overwrites the repo copy with that machine's local store. The union is durable only once the notes sync (t-3405) lands (the per-entry ruflo export, t-3404, was cancelled by the 2026-10-03 revision above: the curated entries involved were error-recurrence counters), and until then the Linux local `patterns.md` also received the 14 sections so this machine's next export does not drop them again.

## Open questions

1. **Generic notes on the company-managed machine:** keep the ~177 notes that name no client (mostly harness lessons), or start completely clean? (Owner to decide.)
2. **Docs that name a client:** exclude (default) or redact individually? (Per file, owner approves.)
3. **Remote query between owner machines:** build it, or leave until a real need appears?

## Implementation (filed under epic t-3372; all pending until this ADR is accepted)

1. ~~t-3404~~ — per-entry ruflo export/import: **cancelled** (decision 2).
2. **t-3405** — notes sync: pull restores `backup/memory` and per-project memory with slug mapping and profile filter; `merge=union` for append-only logs.
3. **t-3406** — session-start pull and `/brana:close` push, own script, time-boxed, profile-aware.
4. **t-3407** — ruflo version guard as a `brana doctor` line (down-scoped).
5. **t-3408** — `brana memory restore --profile` for a new machine (replaces the manual runbook).
6. **t-3409** — privacy audit: prove no memory content can reach the public repo.
7. **t-3410** — convergence test: two homes writing notes in parallel, then converging (notes only).
8. **t-3416** — provenance and quarantine for imported notes (T1).
9. **t-3417** — secret scan on export (T2).
10. **t-3418** — trust profiles and the company-managed rules; audit and remediation of the Mac (T3, T7).
11. **t-3419** — signed commits per machine, verified before import (T4).
12. **t-3420** — macOS setup security hygiene: scoped token, transfer media, synced folders, policy check (T5, T6, T7).
13. **t-3437** — shared docs repo: review and publish only approved docs (T3).
14. **t-3435** — one-time divergence merge of 2026-10-02/03 and the interim fetch-first guard in `backup.sh` (done by another session; see *Amendment 2026-10-03*).

Tasks 8 to 11 gate task 3 (session-start pull): importing without them would ship the sync with the poisoning path open.
