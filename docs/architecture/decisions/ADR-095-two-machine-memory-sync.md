---
status: proposed
extends: docs/architecture/decisions/ADR-015-state-consolidation-plugin-first.md
informs: docs/architecture/decisions/ADR-038-memory-write-gateway.md
---

# ADR-095: Keep brana memory current across machines, with trust profiles

**Status:** Proposed (2026-10-02, revised 2026-10-03, corrected after the t-3442 review 2026-10-03)
**Date:** 2026-10-02
**Deciders:** Martín Rios
**Tags:** memory, ruflo, sync, git, macos, security, harness
**Tasks:** t-3403 (first draft, closed) · t-3415 (threat model) · t-3436 (this revision) · t-3442 (deep challenge) · implementation and security tasks in *Implementation*
**Extends:** [ADR-015](ADR-015-state-consolidation-plugin-first.md) (cache-then-sync; git is the source of truth)
**Respects:** [ADR-038](ADR-038-memory-write-gateway.md) (dated, parallel-safe note files) and [ADR-058](ADR-058-search-provider-hybrid-recall.md) (ruflo never auto-indexes `~/.claude/memory/`)

**Revision note (2026-10-03).** The first draft proposed per-entry sync of "curated" ruflo entries and one repo filtered by a client allowlist. Three findings changed that: (1) the ruflo `pattern` namespace is mostly auto-generated error-recurrence counters (135 of 158 rows); the 15 hand-curated rows all have file echoes; (2) the second machine is **company-managed** (Apple Business Manager / DEP, Rippling MDM), so it cannot be trusted with other clients' data; (3) a filter inside one repo is not a boundary against a machine whose token can read the whole repo. Decisions below replace the earlier ones; the history is in git.

**Correction note (2026-10-03, t-3442).** A three-lens challenge (security and compliance, code correctness, simplicity) re-derived every number in this ADR from the live stores and found the design pointed at the wrong direction of risk. The live exposure is employer data flowing *out* into personal stores, not personal data flowing *in* to the Mac. Decisions 1, 3, 4 and 5 and the threat model were narrowed accordingly; the *Review* section at the end lists what was overstated. Nothing in this ADR has been implemented yet except the t-3435 divergence guard.

---

## Context

Until 2026-10-02 brana ran on one machine. The macOS port (epic t-3372) added a second workstation: a Mac that sleeps, used for client **tabz**, next to the owner's Linux laptop that stays up. Restoring the Mac's memory by hand exposed what ADR-015 does not cover:

1. **The ruflo database cannot be shared.** `~/.swarm/memory.db` (145 MB, ~7,190 entries, 384-dim embeddings) is gitignored because it exceeds GitHub's 100 MB limit. Two machines cannot write one SQLite file, and a copy is stale the moment either side learns something.
2. **`sync-state.sh push|pull` are unidirectional with no merge** (ADR-015). With two writers, whichever pushes last silently overwrites the other.
3. **Nothing restores notes.** `pull` restored 4 files. The ~210 notes in `brana-knowledge/backup/memory` and the per-project memory had to be copied by hand, and project folders are named after the absolute path (`-home-martineserios-…` vs `-Users-martin-tabz-…`).
4. **The restore over-collected.** It put every client's notes, a full DB and the whole private repo on a laptop used for one client. Measured on the Mac: 46 of 206 notes and, in ruflo, 566 of 855 `session` and 431 of 712 `metrics` entries mention other clients; the clone held about 70 client project folders. (Re-derived 2026-10-03 on Linux: 46 of 206 notes, 576 of 860 `session`, 438 of 717 `metrics`. The 46 holds only when the client list includes names absent from `tasks-portfolio.json`: cosmos-trading, acrelec, dgrx, tracy, chess. From portfolio slugs alone the count is 29. **The portfolio file is a project registry, not a client census, and must never be the only source of a confidentiality list.**)
5. **The Mac is company-managed.** Inventory (2026-10-03): DEP-enrolled, MDM user-approved, vendor Rippling; profiles for MDM, FileVault, PPPC, managed login items and Device Trust CAs; FileVault company key unconfirmed; iCloud Desktop & Documents sync was on. The company can install and wipe, and plausibly holds the disk key.
6. **tabz already lives in personal stores.** Verified 2026-10-03: the tabz repo is a private repo on the owner's personal GitHub with a 42 MB clone on the Linux laptop's unencrypted ext4 disk; `brana-knowledge` (the owner's all-clients backup repo) tracks 632 paths under Mac-derived project directories, including tabz project memory from both machines, which the t-3435 merge kept on purpose; the Mac's transfer folder was uploaded to iCloud before it was deleted. The tabz glossary describes a pharmacy payments schema with patient and prescription tables (vocabulary derived from table names, no rows). This is the exposure that matters to a HIPAA-compliant employer, and it exists today.

What is in the ruflo DB decides what is worth moving (audited 2026-10-03, all namespaces):

| Namespace | Entries | Nature | Worth syncing? |
|---|---|---|---|
| `knowledge` | 5,380 | **Derived** from `brana-knowledge/dimensions` by `index-knowledge.sh`; 83 mention another client | No: rebuild from docs |
| `session`, `metrics`, `default` | 1,579 | Machine-local telemetry, more than half name other clients | Never |
| `skills` | 69 | Derived from skill files; the plugin installs them | No |
| `pattern` | 158 | 135 `error-recurrence:*` counters written by `post-tool-use-failure.sh`; 23 hand-curated `pattern:`/`spike:`/`challenge:` rows, of which 15 hold real content and all 15 have file echoes; 20 rows are key-only stubs written by `session-end-pattern-promotion.sh` when a read timed out (t-3455) | No |
| `field-notes`, `decisions`, `assumptions`, `verification`, `hive-memory` | 9 | Hand-written but negligible | No (the same facts live in files) |

**The valuable, irreplaceable memory is already files**: the 206 top-level notes in `~/.claude/memory` (48,034 files in total once archive snapshots are counted; only the top level is memory), per-project memory, and the docs in `brana-knowledge`. The ruflo DB is a rebuildable index plus telemetry.

## Decision

**Machines converge through files in git, never through the database. The boundary between a trusted and a restricted machine is which repositories and keys exist, never a filter inside one repository. Nothing flows from the company-managed machine to the owner's stores automatically, and employer data does not enter the owner's personal stores.**

### 1. Notes and project memory: backup only, no owner-to-owner sync

`~/.claude/memory/*.md` and `~/.claude/projects/*/memory/` keep their daily backup to the private `brana-knowledge` repo, with the fetch-first guard and the section-union export from t-3435. There is only one owner machine, so the session-start pull and close push of the first revision are **not built** (t-3405, t-3406, t-3408, t-3410 cancelled 2026-10-03). The host-neutral project path and `merge=union` for append-only logs stay on record for the day a second owner-controlled machine appears.

### 2. Derived ruflo namespaces: rebuilt locally, never synced

`knowledge` is re-indexed on each machine from the docs that machine is allowed to hold. `session`, `metrics`, `default` are local-only. **No ruflo entry is synced** (t-3404 cancelled). The 15 curated `pattern` rows with real content are not a reason to revisit: their substance is in files.

### 3. Trust profiles, by what exists on the machine

| Profile | Machines | Holds | Never |
|---|---|---|---|
| **owner** | the owner's Linux laptop | everything, full DB | tabz data beyond what the company sanctions (decision 6) |
| **company-managed** | the Mac (Rippling MDM) | the tabz repo and the Mac's own tabz memory, the harness (public thebrana), and the pack of decision 4 | other clients' notes, memory or backups; the full DB; a `brana-knowledge` clone; a credential that reaches any repo other than the ones it needs; any tunnel, VPN or link to personal infrastructure |

**Rules for a company-managed machine:** tabz-only; ordinary developer traffic only (HTTPS to GitHub, package registries, APIs); no tunnel, VPN or remote-access path to the owner's machines; the owner reads the company's acceptable-use and AI-tools policy; the backup script refuses to run under this profile (t-3454). Nothing in this design is chosen to avoid the employer's visibility, and absence of concealment is not disclosure: the company's written answer (t-3453) gates every pack task.

There is no runtime profile filter. A machine that cannot be trusted with a data class is simply not given the repository or key that holds it.

### 4. Shared docs repo: a hand-curated bundle (v0)

A **separate** private repo holds only files the owner has hand-picked. A company-managed machine clones it with a repo-bound read-only deploy key and has no access to `brana-knowledge`. A sparse or filtered clone of the main repo was rejected: a token that can read the repo can fetch every blob.

v0 is a bundle, not a pipeline: an allowlist file naming each approved path with its content hash, a copy script that publishes exactly those files and fails closed on a client-name or secret lint, run by hand from `/brana:close`. No scope tags (none exist today: 0 of 206 notes carry one; the gateway's `--scope` chooses a directory, it does not tag), no hold queue, no builder, no timers, no manifest and no signing in v0. Default is **exclude**: none of the 177 notes that name no client ships until picked; 32 of 85 `dimensions/` files name a client and stay out unless redacted by hand. A pre-registered kill rule decides whether the bundle earns a v1. Flow and kill rule: [mac-knowledge-pack](../features/mac-knowledge-pack.md); task t-3437 (absorbs t-3438, t-3439), Mac side t-3440.

### 5. Remote query between owner-controlled machines: dropped

There is no second owner-controlled machine. The SSH forced-command idea stays in git history; it is not an option for the company-managed Mac.

### 6. tabz data stays in company-sanctioned stores

Where the tabz repo and its project memory may live is the company's decision (t-3453). Until it is answered the owner adds no new tabz copies to personal stores, and t-3454 removes the ones that exist (brana-knowledge history included) or hands them over, after the owner decides how to disclose. Silent deletion can look like evasion, so disclosure comes before purge.

### Triggers: inside existing commands

| When | Action |
|---|---|
| `/brana:close` (owner machine) | existing backup to `brana-knowledge` (fetch-first guard); optional `brana pack publish` from the allowlist, never automatic. |
| Session start (company-managed) | fetch the pack repo over the deploy key, 3 s budget, fast-forward only; offline or slow means keep the last pack. Then the tabz repo. |
| New owner machine | none planned; the manual runbook is the reference until one exists. |

### Version guard

`brana doctor` shows the installed ruflo version against one pin constant (3.34.0, locally patched) that the macOS setup guide also reads (t-3407). Relevant even without DB sync: the Mac first installed 3.51.0 from an unpinned install line.

### Privacy boundary

Everything goes to **private** repos only. The public thebrana repo never receives memory content (t-3352; `system/state/patterns-export.json` is gitignored there). An export step that cannot reach a private repo does nothing and never falls back to the public one.

## Threat model

Memory is not inert data: it is loaded into Claude's context at session start, so what is synced becomes instructions on every machine that imports it, and machines are not equally trusted. The 2026-10-03 review re-aimed the table: the rows that are live today are T3, T5, T6, T7 and the new T8 and T9; T1 and T4 are theoretical while no automatic Mac-to-Linux path exists.

| # | Threat | How it happens | Mitigation (decision) | Task |
|---|---|---|---|---|
| T1 | **Memory poisoning** | Anything that can push to a synced repo plants a note such as "ignore previous instructions" that persists on every importer | Remove the path: the Mac never pushes to any owner repo, its backup script refuses under the company-managed profile, and nothing on Linux imports from the Mac. Lessons from the Mac travel as text the owner reads. Provenance/quarantine (t-3416) **cancelled**: it guarded a channel that no longer exists. | t-3454 |
| T2 | **Secrets in memory** | A note holds a token or password (precedent: the 2026-06-03 handoff with `ANITA_ADMIN_SECRET`) | Secret lint in the publish path, veto only. A hit blocks that file and reports file and key, never the value. | t-3417 |
| T3 | **Client confidentiality, both directions** | A machine receives clients it does not work on (happened 2026-10-02); **and** employer data lands in personal stores (happening now: context 6) | The repo-and-key boundary (section 3, 4) for the inbound side; t-3454 for the outbound side, ordered: credentials, iCloud verification, disclosure decision, then purge. | t-3454, t-3437 |
| T4 | **Account or token compromise** | A stolen GitHub token pushes forged notes to the pack repo | **Deferred past v1.** Signing had no allowed-signers location, installer or rotation; its unattended key would sit beside the push token on an unencrypted disk; git already hashes objects; the public code lane is unsigned and higher impact. If revived, verify both the pack and the thebrana pull or neither. | t-3419 (P3) |
| T5 | **Excess credentials on the weaker machine** | `gh auth login` on the Mac granted access to every private repo; the Linux token carries `admin:org`, `repo`, `workflow` | Revoke; one read-only deploy key per repo the Mac needs. Step zero of remediation. | t-3454 |
| T6 | **Transfer leftovers** | Raw client data and the DB copied to a synced Desktop folder (iCloud), unencrypted USB media, npm install scripts run with `--allow-scripts` | Verified purge (Recently Deleted), Apple ID type recorded, never stage transfer files in a synced folder; documented afterwards. | t-3454, t-3420 |
| T7 | **Company-device policy** | Personal infrastructure linked to an employer machine, personal-client data on it, or an unapproved AI account reading company data | The company's written answer gates every pack task; tabz-only, ordinary traffic, no link to personal machines. | t-3453, t-3418 |
| T8 | **Employer as reader and claimant** | The company can read, image or wipe the Mac, may hold the FileVault key, and its IP-assignment clauses can reach what is authored on it; a personal Claude account on it sends company data to a vendor without the company's agreement | Nothing personal of value is authored or stored on the Mac beyond the bundle; which Claude account runs there is the company's call. | t-3453 |
| T9 | **The Linux laptop is the weakest link** | Plain ext4, always on, 11 GB in swap, every client's data, and every credential | Full-disk encryption is the owner's decision, recorded in t-3454; no pack is published from an unencrypted disk that also holds tabz data. | t-3454 |

**Trust direction.** Owner machine to company-managed machine: hand-picked files only. Company-managed machine to owner: text carried by a person.

**Residual risk accepted:** a compromised owner machine can still publish a bad bundle; the private repos are also the backup. T2, T3 and T5 bound the damage; they do not remove it.

## Options considered

| Option | Why not |
|---|---|
| Copy `memory.db` between machines | Two writers lose each other's learnings; 145 MB over GitHub's file limit; a live WAL copy risks corruption; and it carries every client's data. |
| Per-entry sync of ruflo entries (first draft) | 135 of 158 `pattern` rows are error counters and the 15 curated ones live in files. Not worth building. |
| One repo, filtered by a client allowlist (first draft) | A machine whose token reads the repo can fetch everything, a sparse clone included. The boundary must be a repository and its key. |
| Scope tags, hold queue, builder with triggers, signed manifest (second draft) | Over-built for one owner and a few dozen files: no scope tags exist, a hold queue shows only the detector's hits, the triggers could add nothing the spec admits, and signing was unspecified. Replaced by the v0 bundle with a kill rule. |
| SSH tunnel or VPN from the company Mac to the owner's Linux | Links an employer machine to personal infrastructure; the traffic pattern is what security tools and policies flag. |
| One shared DB on a server | New always-on infrastructure; breaks offline use on a Mac that sleeps. |
| Mac learns something back automatically | Any automatic return path reopens T1 and puts employer-adjacent text in personal stores. Manual promotion is proven: every Mac finding so far (t-3390, t-3405, t-3420) arrived as text carried by hand. |

## Consequences

**Good.** The surface is a handful of files in one extra private repo. No database copying, no tunnel, no daemon, no new write path. The company-managed machine holds exactly what the owner picked.

**Costs and limits.**
- **Not fresh.** The bundle changes when the owner publishes it. The Mac learns of it at its next session start.
- The Mac builds its own tabz memory and sends nothing back.
- The owner spends one session picking the first bundle and minutes per refresh.
- If the kill rule fires, the bundle is deleted and the Mac runs on the harness alone.

**Residual risks.** See *Threat model*; the private repos as a single point of failure (they are also the backup).

## Amendment 2026-10-03: the first live divergence (t-3435)

*Added from the t-3435 branch (another session); the live evidence it records is the reason the company-managed profile must not hold write access to the main repo: the Mac pushed four backup commits (631 files, including its project memories) straight into `brana-knowledge`, a repo that holds every client.*

The two machines diverged before any implementation task landed. On 2026-10-02 the Mac pushed four backup commits (0c84f77d..b04be875) while this machine held three unpushed ones (ed5dc2cd..6a6f0211); `backup.sh` kept committing on the stale base and its push failed at every close. A dry-run merge conflicted in exactly the whole-store snapshot files: `backup/swarm/memory-entries.json`, `backup/swarm/patterns.json`, `backup/memory/patterns.md`, `backup/memory/consolidation-log.md`.

**What happened.** The merge was resolved by hand as `9cf4055f` ("keep newest local snapshot"): both histories kept, conflicted files taken from the Linux side. A key-level audit against the Mac tip found the real loss: 14 sections of `patterns.md`, 2 curated `pattern` entries (error-recurrence counters), and 4 machine-local rows (2 `session`, 2 `metrics`). `patterns.json` lost nothing by content and the Mac's 624 per-project memory files all survived. **Correction (t-3442):** those 624 files include tabz project memory under `backup/projects/-Users-martin-tabz-*`; keeping them in the owner's all-clients repo contradicts the tabz-only rule and is the outbound half of T3. t-3454 decides their fate after the company answers.

**Rule applied, retroactively.**

| File | Merge key | Rule |
|---|---|---|
| `memory-entries.json` | `(namespace, key)` | union; same key, larger `updated_at` wins |
| `patterns.json` | `approach` content, **not** `id` | union; `id` is a per-machine autoincrement and collides across machines |
| `patterns.md`, `consolidation-log.md` | `## ` section heading | union by section |
| `session`, `metrics` rows | — | not merged: machine-local (§2); they stay in git history |

A union commit restored the 14 sections and 2 curated entries from `b04be875`. Counts per key after the merge are at least each side's; no duplicate keys.

**Guard.** `backup.sh` now fetches before it exports. Behind-only fast-forwards; true divergence refuses to commit and prints the resolution command; an offline fetch warns and continues so a local backup is never lost to a missing network. The section-union export covers `patterns.md` and `knowledge-staging.md`.

**Known limit.** The export is still a whole-store snapshot from one machine. With decision 1 narrowed to one owner machine and the Mac's backup disabled under its profile (t-3454), there is no longer a second writer, and the snapshot shape is acceptable.

## Open questions

Answered 2026-10-03 after the t-3442 review:

1. **Generic notes on the company-managed machine:** start clean; the owner hand-picks each note into the bundle.
2. **Docs that name a client:** exclude; redaction only by hand, per file.
3. **Remote query between owner machines:** no; dropped (decision 5).

Still open, and the owner's alone: the three company questions in t-3453.

## Review 2026-10-03 (t-3442)

Three challengers (security and compliance, code correctness, simplicity) plus a live re-derivation of every number. Outcome: the design was sound engineering aimed at the wrong direction of risk. Overstated or wrong in the previous text of this ADR:

- "pattern is auto-generated telemetry": 85 percent right by count, wrong for 15 curated rows.
- "46 of 206 notes": right, but only because regex false positives offset clients missing from the portfolio file.
- "tabz stays on the company side" and "a restricted machine holds only what it should": false today (context 6).
- "scope tag exists": false.
- "nothing hidden, nothing evaded": true, and not the same as the company knowing.
- "T1 to T4 bound the damage": they bounded poisoning, not the confidentiality failure that was live.

Task changes applied the same day: t-3405, t-3406, t-3408, t-3410, t-3416, t-3438, t-3439 cancelled; t-3437, t-3440, t-3418, t-3420, t-3407, t-3411, t-3419 re-scoped; t-3403 closed; t-3453 (company answer), t-3454 (remediation), t-3455 (stub-writing hook) added.

## Implementation (filed under epic t-3372)

1. **t-3453** — company answer in writing; blocks every pack task.
2. **t-3454** — credential and personal-store remediation, owner-run, in the order of T3.
3. **t-3437** — pack v0 bundle: allowlist with hashes, veto lint, scoped repo, `brana pack publish`, kill rule (absorbs t-3438, t-3439).
4. **t-3440** — Mac pull on a deploy key, fast-forward only, reindex, pack age.
5. **t-3417** — secret and client lint, veto only.
6. **t-3418**, **t-3420** — docs: company-managed rules and setup hygiene, written after t-3454 so they describe what was done.
7. **t-3407** — ruflo pin constant plus doctor line.
8. **t-3409** — privacy audit: prove no memory content can reach the public repo.
9. **t-3435** — divergence merge and fetch-first guard (done; see *Amendment*).
10. Cancelled: t-3404, t-3405, t-3406, t-3408, t-3410, t-3416, t-3438, t-3439. Deferred: t-3419 (P3).
