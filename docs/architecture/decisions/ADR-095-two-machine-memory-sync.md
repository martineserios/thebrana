---
status: accepted
extends: docs/architecture/decisions/ADR-015-state-consolidation-plugin-first.md
informs: docs/architecture/decisions/ADR-038-memory-write-gateway.md
---

# ADR-095: One owner machine, a company tabz Mac, and how brana memory is kept

**Status:** Accepted (2026-10-05). Company question 4 (existing copies) still open; see *Open*.
**Date:** 2026-10-02 (proposed) · 2026-10-03 (revised, t-3436; challenged, t-3442) · 2026-10-05 (rewritten and accepted, t-3468)
**Deciders:** Martín Rios
**Tags:** memory, ruflo, backup, git, macos, security
**Extends:** [ADR-015](ADR-015-state-consolidation-plugin-first.md) (git is the source of truth) · **Respects:** [ADR-038](ADR-038-memory-write-gateway.md), [ADR-058](ADR-058-search-provider-hybrid-recall.md)

The earlier drafts designed a two-machine sync (per-entry ruflo sync, a filtered repo, a curated pack). Their full text, evidence and threat analysis are in git history. This version records what was decided once the second machine turned out to be a company laptop.

## Context

- **There is one owner machine:** the Linux laptop. It holds everything and runs all knowledge work.
- **The Mac is company-managed** (Apple Business Manager / DEP, Rippling MDM; the company can install, wipe and plausibly holds the disk key) and is used for one client, **tabz**, on the company's Claude Team account.
- **The 2026-10-02 restore over-collected:** every client's notes, the full ruflo DB and the whole private `brana-knowledge` repo landed on the Mac. The two machines then diverged in `brana-knowledge` (t-3435).
- **The irreplaceable memory is files:** the notes in `~/.claude/memory`, per-project memory, and the docs in `brana-knowledge`. The ruflo DB is a derived index plus telemetry: `knowledge` is rebuilt from docs, and 135 of 158 `pattern` rows are auto-generated error counters.
- **The live exposure runs outward:** tabz material already sits in the owner's personal stores (the tabz repo on personal GitHub, its Linux clone, 632 tabz paths in `brana-knowledge`). For a HIPAA-compliant employer this matters more than what the Mac holds.

## Decision

**Machines never converge through the database. The owner machine is the only writer of the owner's stores. The Mac is a company work machine that runs the public harness; nothing flows from it to the owner's stores except text the owner carries by hand.**

1. **The Mac's role.** A company tabz machine on the company's Claude Team account, never a personal account. It is not a second brana workstation.
2. **Company terms** (relayed verbally by the owner, 2026-10-03; who and when to be recorded in t-3453). Pulls from the owner's repos are fine. The Mac never pushes to the owner's private repos. tabz learnings live on the Mac and in the tabz GitHub repo. **Question 4**, what happens to the existing tabz copies in personal stores, is unanswered; until it is, no new tabz material enters personal stores and nothing is purged.
3. **The Mac's `brana-knowledge` clone stays, with `backup.sh` non-executable.** This is an **accepted deviation**: the clone holds every client, and pulling it is a pull from a personal private repo, which question 2 did not name. The owner accepts it; the Mac never exports.
4. **The Mac's ruflo DB.** `session` and `metrics` rows are gone (an earlier, unrecorded step removed all 1,565; confirmed 2026-10-05). Knowledge, skills, pattern, episodes and reasoning patterns stay, including rows that name other clients (another accepted deviation). Knowledge extraction runs on Linux only: `knowledge-pipeline-tier1` and `export-patterns` are disabled on the Mac.
5. **Linux to Mac: through the public harness.** Generic learnings reach the Mac as rules, skills and hooks in public thebrana (`main`, after `/brana:ship`). The hand-curated pack (t-3437, with t-3440 and t-3417) is **parked**: something the Mac misses is first promoted into thebrana; the pack is built only if that proves insufficient.
6. **Mac to Linux: by hand, generalised.** No automatic return path. A lesson learned on the Mac reaches Linux only as text the owner carries and strips of tabz context.
7. **Backup: notes in git, the DB off git** (t-3466). `brana-knowledge` keeps markdown notes under git with the t-3435 fetch-first guard and section-union export. The ~12 MB whole-store JSON exports of the ruflo DB stop being committed; the DB keeps its daily local rotation plus an off-site file copy (t-3342), unless decision 8 makes it a rebuildable index.
8. **ruflo's role is decided by a spike** (t-3467): ~20 real recall queries against notes-only search and against ruflo decide keep, demote to a rebuildable index, or drop. No ruflo entry is ever synced between machines.
9. **Patterns archive.** The live `~/.claude/memory/patterns.md` keeps the most recent 100 sections (auto-pruned); the `brana-knowledge` copy unions on export and is the grow-only archive. A deliberate delete is made in both by hand.
10. **This ADR is the short form.** Superseded drafts and the full threat analysis stay in git history.

## Threats that remain live

| Threat | State | Owner / task |
|---|---|---|
| **tabz in personal stores** (outbound confidentiality) | Exists today; frozen | t-3453 question 4, then t-3454 (disclose before any purge) |
| **Other clients on the company Mac** (inbound confidentiality) | Accepted deviations 3 and 4 | Owner; revisit if the company asks |
| **Excess credentials on the Mac** (`gh` token reaches every repo) | Open | t-3454: revoke, repo-bound read-only deploy keys |
| **Transfer leftovers** (iCloud Recently Deleted, Apple ID type) | Partly verified | t-3454 |
| **Unencrypted Linux disk** holding every client and every credential | Open | t-3454, owner's call |
| **Memory poisoning from the Mac** | Closed by design: no Mac write path. The one push (`092e401d`, 2026-10-03) predates the chmod; Linux re-exported after it | — |
| **Account or token compromise** (signing) | Deferred | t-3419 (P3) |

**Privacy boundary.** Memory content goes to private repos only; the public thebrana repo never receives it (`system/state/patterns-export.json` is gitignored there; audit t-3409).

**Version guard.** `brana doctor` shows the installed ruflo version against one pin constant shared with the macOS setup guide (t-3407).

## History: the first live divergence (t-3435)

On 2026-10-02 both machines pushed whole-store snapshots to `brana-knowledge` master and diverged. The hand merge kept the Linux side; a key audit found the loss was 17 `patterns.md` sections and 1 `knowledge-staging.md` section, not ruflo rows. The fix shipped in `brana-knowledge`: a fetch-first guard (data-only fast-forward, review before merging anything else, refuse on divergence with a recipe), a section-union export for the two section-keyed note files, and `merge-snapshots.py` with identity keys `(namespace, key)` and `(task_type, approach, ts)` (the SQLite `AUTOINCREMENT` id collides across machines). Full record: [brana-knowledge-divergence-guard](../features/brana-knowledge-divergence-guard.md).

## Options rejected

| Option | Why not |
|---|---|
| Copy `memory.db` between machines | Two writers lose each other's learnings; 145 MB over GitHub's limit; carries every client. |
| Per-entry ruflo sync | The curated part is files already; the rest is counters and a derived index. |
| One repo filtered by a client allowlist | A token that reads the repo reads every blob; the boundary is which repo and key exist. |
| Tunnel or VPN from the Mac to Linux | Links an employer machine to personal infrastructure. |
| Automatic Mac-to-Linux path | Reopens poisoning and puts employer-adjacent text in personal stores; carrying text by hand already works. |

## Consequences

- No sync machinery to build or run. The only cross-machine channel is the public harness.
- The Mac builds its own tabz memory and sends nothing back automatically.
- `brana-knowledge` stops growing by a database dump per close once t-3466 lands.
- Two accepted deviations (clone, ruflo rows) keep other clients' material on a company machine; they are the first thing to revisit if the company's answer to question 4 asks for it.

## Open

- **Company question 4** (t-3453): hand over or certify deletion of the existing tabz copies in personal stores; also record who gave the answers to questions 1 to 3 and when.

## Tasks (epic t-3372)

| Task | Status |
|---|---|
| t-3453 company answer (question 4) · t-3454 credentials and personal-store remediation | pending, P0 |
| t-3466 backup: notes in git, DB off git · t-3467 ruflo spike | pending, P2 |
| t-3418 company-managed rules in the macOS guide · t-3420 setup hygiene · t-3409 privacy audit · t-3407 ruflo pin | pending |
| t-3437 pack v0 · t-3440 Mac pack pull · t-3417 publish lint | parked with the pack (decision 5) |
| t-3419 signing | deferred, P3 |
| t-3435 divergence guard · t-3436 revision · t-3442 deep challenge · t-3455 promotion-hook fix · t-3403 first draft | completed |
| t-3404, t-3405, t-3406, t-3408, t-3410, t-3416, t-3438, t-3439 | cancelled |
