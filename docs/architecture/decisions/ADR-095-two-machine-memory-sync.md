---
status: accepted
extends: docs/architecture/decisions/ADR-015-state-consolidation-plugin-first.md
informs: docs/architecture/decisions/ADR-038-memory-write-gateway.md
---

# ADR-095: One owner machine, a company tabz Mac, and how brana memory is kept

**Status:** Accepted (2026-10-05). Company question 4 (existing copies) still open; see *Open*.
**Date:** 2026-10-02 (proposed) · 2026-10-03 (revised, t-3436; challenged, t-3442) · 2026-10-05 (rewritten and accepted, t-3468) · 2026-10-06 (review fixes, t-3468)
**Deciders:** Martín Rios
**Tags:** memory, ruflo, backup, git, macos, security
**Extends:** [ADR-015](ADR-015-state-consolidation-plugin-first.md) (git is the source of truth) · **Respects:** [ADR-038](ADR-038-memory-write-gateway.md), [ADR-058](ADR-058-search-provider-hybrid-recall.md)

The earlier drafts designed a two-machine sync (per-entry ruflo sync, a filtered repo, a curated pack); their text is in this public repo's git history. This version records what was decided once the second machine turned out to be a company laptop. Device and credential specifics are kept out of this public file, in a private note in the owner's personal repo (not `brana-knowledge`, which the Mac clones).

## Context

- **There is one owner machine:** the Linux laptop. It holds everything and runs all knowledge work.
- **The Mac is company-managed** (enrolled in the employer's device management; the company can install, wipe and read it) and is used for one client, **tabz**, on the company's Claude account. The employer is in a regulated sector.
- **The 2026-10-02 restore over-collected:** every client's notes, the full ruflo DB and the whole private `brana-knowledge` repo landed on the Mac. The machines then diverged in `brana-knowledge` (t-3435), and the Mac pushed to it twice more (2026-10-03 and 2026-10-05).
- **The irreplaceable memory is files:** the notes in `~/.claude/memory`, per-project memory and the docs in `brana-knowledge`. The ruflo DB is a derived index plus telemetry: `knowledge` is rebuilt from docs, and 135 of 158 `pattern` rows are auto-generated error counters.
- **The exposure that matters runs outward:** tabz material sits in the owner's personal stores (the tabz repo on personal GitHub, its Linux clone, 19 tabz client files in `brana-knowledge`: 18 in tabz project folders plus a tabz sales-report reference under a general clients folder, and tabz session rows in its ruflo JSON exports).

## Decision

**Machines never converge through the database. The owner machine is the only intended writer of the owner's stores; the Mac's ability to write is being removed, not just discouraged. Nothing flows from the Mac to the owner's stores except text the owner carries by hand.**

1. **The Mac's role.** A company tabz machine on the company's Claude account, never a personal account. It is not a second brana workstation.
2. **Company terms** (relayed verbally by the owner, 2026-10-03; who and when to be recorded in t-3453): "pulls from the owner's personal repos are fine (public thebrana, the private pack repo)", over a repo-bound read-only deploy key; "the Mac must not push to the owner's personal private repo"; "tabz learnings stay on the Mac and in the tabz GitHub repo" (recorded in t-3454 as "only"). **Question 4**, what happens to the existing tabz copies in personal stores, is unanswered: nothing is purged until it is. Linux no longer adds tabz **project memory** (t-3475); its ruflo JSON exports still carry tabz session and flywheel rows until t-3466, and those rows are part of question 4.
3. **The Mac keeps its `brana-knowledge` clone**, an **accepted deviation**: neither the repo (all clients) nor the credential it is pulled with is covered by the terms above. Its write path is to be closed by git configuration, not by a file mode: disabling the clone's push URL was **requested** on 2026-10-06 and counts only once the Mac reports `git remote get-url --push origin` in t-3454; the in-script refusal and a read-only key follow there. The file-mode gate used first failed open (the 2026-10-05 push).
4. **The Mac's ruflo DB.** Its `session` and `metrics` rows are gone (an unrecorded step removed all 1,565; confirmed 2026-10-05). Knowledge, skills, pattern, episodes and reasoning patterns stay, including rows that name other clients (151 knowledge, 940 episode, 807 reasoning rows): a second accepted deviation. Knowledge extraction runs on Linux only (`knowledge-pipeline-tier1`, `export-patterns` disabled on the Mac).
5. **Linux to Mac: through the public harness.** Generic learnings reach the Mac as rules, skills and hooks in public thebrana (`main`, after `/brana:ship`). The hand-curated pack (t-3437, with t-3440 and t-3417) is **parked**: something the Mac misses is first promoted into thebrana; the pack is built only if that proves insufficient.
6. **Mac to Linux: by hand, generalised.** No automatic return path. A lesson learned on the Mac reaches Linux only as text the owner writes, free of tabz specifics.
7. **Backup: notes in git, the DB off git** (t-3466, planned). `brana-knowledge` keeps markdown notes under git with the t-3435 fetch-first guard and section-union export. The whole-store ruflo exports (`memory-entries.json`, `patterns.json`) and the vector files stop being committed — but only once an off-site DB copy is verified (t-3342, not done) or the spike of decision 8 rules the DB rebuildable. Until then the JSON in git is the only off-site copy and stays.
8. **ruflo's role is decided by a spike** (t-3467): ~20 real recall queries against notes-only search and against ruflo decide keep, demote to a rebuildable index, or drop. No ruflo entry is ever synced between machines.
9. **Patterns archive.** The live `~/.claude/memory/patterns.md` holds the most recent sections up to the cap in its own header (100); validate Check 31a prunes the oldest quarantine entries at that cap in code, and the always-loaded rule and the creation template state the same cap (t-3476). The `brana-knowledge` copy unions on export and is the grow-only archive; a deliberate delete is made in both by hand.
10. **This ADR is the short form.** The superseded drafts and their full threat analysis stay in git history.

## Threats that remain live

| Threat | State | Owner / task |
|---|---|---|
| **The code lane**: the Mac pulls public thebrana `main` and runs `bootstrap.sh` | The highest-impact channel to the Mac. Controls: protected `main`, PR-only merges, required CI, the ship gates. A promotion into thebrana is hand-written, generic and names no client | `/brana:ship` |
| **tabz in personal stores** (outbound) | Linux project-memory export stopped (t-3475); tabz rows still in the ruflo JSON exports (t-3466); 19 existing files held until question 4 | t-3453, then t-3454 (disclose before any purge) |
| **Other clients on the company Mac** (inbound) | Accepted deviations 3 and 4 | Owner; revisit if the company asks |
| **A write from the Mac into the owner's stores** (poisoning, clobbering) | Reduced, not closed: push-URL disable requested, unconfirmed; in-script refusal and read-only key pending; Linux's wrapper now warns when `backup.sh` loses its exec bit. Two pushes happened (2026-10-03, 2026-10-05); both were reviewed and reverted to the owner's state on Linux | t-3454 |
| **Device and credential hardening of both machines** | Open items, listed in the private note | t-3454, owner's call |
| **The employer as reader and claimant** of what is stored or authored on its machine | Inherent to a company device. The accepted clone (decision 3) makes everything in `brana-knowledge` readable there, so nothing that must stay from the employer goes into that repo | — |
| **Secrets in memory** | Secret-scan edit hook and validate check today; a publish-path lint only if the pack is revived | t-3417 (parked) |
| **Account or token compromise** (signing) | Not built | t-3419 (pending, P3) |

**Privacy boundary.** Memory content goes to private repos only; the public thebrana repo never receives it (`system/state/patterns-export.json` is gitignored there; audit t-3409). An export step that cannot reach a private repo does nothing and never falls back to the public one.

**Version guard.** `brana doctor` shows the installed ruflo version against one pin constant shared with the macOS setup guide (t-3407).

## Non-actions

- No sync of the ruflo DB or its entries, in either direction.
- No export, push or backup from the Mac to any owner repo.
- No automatic path from the Mac to Linux.
- No tunnel, VPN or remote link between the Mac and the owner's machines.
- No purge of existing tabz copies before the company answers question 4.

## History: the first live divergence (t-3435)

On 2026-10-02 both machines pushed whole-store snapshots to `brana-knowledge` master and diverged. The hand merge kept the Linux side; a key audit found the loss was 17 `patterns.md` sections and 1 `knowledge-staging.md` section, not ruflo rows. The fix shipped in `brana-knowledge`: a fetch-first guard (data-only fast-forward, review before merging anything else, refuse on divergence with a recipe), a section-union export, and `merge-snapshots.py` with identity keys `(namespace, key)` and `(task_type, approach, ts)` (the SQLite `AUTOINCREMENT` id collides across machines). The guard stopped the Mac's 2026-10-05 push for review because it changed `backup.sh`. Full record: [brana-knowledge-divergence-guard](../features/brana-knowledge-divergence-guard.md).

## Options rejected

| Option | Why not |
|---|---|
| Copy `memory.db` between machines | Two writers lose each other's learnings; 145 MB over GitHub's limit; carries every client. |
| Per-entry ruflo sync | The curated part is files already; the rest is counters and a derived index. |
| One repo filtered by a client allowlist | A token that reads the repo reads every blob; the boundary is which repo and key exist. |
| Tunnel or VPN from the Mac to Linux | Links an employer machine to personal infrastructure. |
| Automatic Mac-to-Linux path | Reopens poisoning and puts employer-adjacent text in personal stores; carrying text by hand already works. |

## Consequences

- No sync machinery to build or run. The only cross-machine channel is the public harness, so its gates carry the weight.
- The Mac builds its own tabz memory and sends nothing back automatically.
- `brana-knowledge` stops growing by a database dump per close once t-3466 lands, and not before the off-site copy exists.
- Two accepted deviations keep other clients' material on a company machine; the owner revisits them if the company raises it.

## Open

- **Company question 4** (t-3453): hand over or certify deletion of the existing tabz copies in personal stores; also record who gave the answers to questions 1 to 3 and when.

## Tasks (epic t-3372)

| Task | Status |
|---|---|
| t-3453 company answer (question 4) · t-3454 Mac write path, credentials and personal-store remediation | pending, P0 |
| t-3418 company-managed rules in the macOS guide | pending, P1 |
| t-3466 backup: notes in git, DB off git · t-3467 ruflo spike · t-3342 off-site DB copy | pending, P2 |
| t-3420 setup hygiene · t-3409 privacy audit · t-3407 ruflo pin | pending |
| t-3437 pack v0 · t-3440 Mac pack pull · t-3417 publish lint | pending, P3, tagged `parked` (decision 5) |
| t-3419 signing | pending, P3 |
| t-3435 divergence guard · t-3475 tabz backup exclusion · t-3476 patterns cap · t-3436 revision · t-3442 deep challenge · t-3455 promotion-hook fix · t-3403 first draft | completed |
| t-3404, t-3405, t-3406, t-3408, t-3410, t-3416, t-3438, t-3439 | cancelled |
