---
status: proposed
---
# Mac knowledge pack v0: a hand-curated bundle for a company-managed machine (t-3436, epic macos-portability t-3372)

> **Parked (2026-10-05).** [ADR-095](../decisions/ADR-095-two-machine-memory-sync.md) decision 5: generic learnings reach the Mac through public thebrana; this pack is built only if that proves insufficient (t-3437, t-3440, t-3417 parked). The spec below is kept for that case.

Written against the access model of an earlier ADR-095 revision; the accepted ADR-095 supersedes it where they differ. This spec is the step-by-step flow; the ADR holds the decision and the threat model. Narrowed on 2026-10-03 after the t-3442 review: the builder, scope tags, hold queue, triggers, manifest and signing of the first version were removed. The reasons are in ADR-095 §Options considered and §Review.

## Problem

The owner works on a Linux laptop that is always on and accumulates knowledge (notes, research docs, a ruflo database, patterns) for many clients. A second machine, a Mac, is **company-managed** (enrolled in the employer's device management) at a company that is regulated, and is used for one client, tabz. The Mac may benefit from a small set of the owner's general harness lessons. It must not receive other clients' data, nothing may link it to the owner's machines or services in a way the company has not sanctioned, and nothing may flow from it into the owner's personal stores.

Nobody has measured how much a Mac session working on tabz would actually recall from generic harness notes. The bundle therefore ships with a kill rule.

## Decision

**Publish a hand-picked bundle; do not connect machines.** The owner keeps an allowlist of approved files with their content hashes. A copy script publishes exactly those files to a small private repo, failing closed on any client-name or secret hit. The Mac pulls that repo over a repo-bound read-only deploy key at session start. Nothing flows back. No background process exists on either side.

Not legal advice. Safeguards in plain terms: minimum necessary (an allowlist, never a filter after the fact); approved channels only (the company's written answer, t-3453, comes first); employer data stays in company-sanctioned stores (t-3454); access control and audit (deploy key, git history); transmission security (TLS). Which Claude account runs on the Mac is the company's call.

## Gate

Nothing below is built until **t-3453** records the company's written answer to: the Claude account on the Mac, a read-only pull from a personal private repo, where tabz and its memory must live, and what happens to the existing copies. A written no ends this spec: the Mac runs the harness and the tabz repo, nothing more.

## The lanes

```
 LINUX (owner, always on)          INTERNET (ordinary HTTPS)        COMPANY MAC
 ────────────────────────          ─────────────────────────        ──────────────────
 A  harness code ─────── push ───▶ GitHub: thebrana (public) ─pull─▶ thebrana + hooks   [exists]
 B  bundle (hand-picked) ─ push ─▶ GitHub: pack repo (private) ─pull▶ pack notes dir    [build]
 C  tabz repo + memory             (where the company says, t-3453)  tabz repo + work   [t-3454]
 D  owner reads reports  ◀──────── owner carries text by hand ◀──── Mac-Claude reports [exists]
 E  other clients, full DB,   ✗✗✗ never crosses, no path exists ✗✗✗  Mac's own tabz memory
    session/metrics, backups                                          stays on the Mac
```

- **A** code is public and flows one way: ship `dev` to `main`, the Mac runs `git pull` and `./bootstrap.sh`. This lane is unsigned and higher impact than any note; signing the bundle without signing this lane would be theatre (this lane is the code-lane row of the accepted ADR-095's threat table).
- **B** is the new lane, one-way and read-only for the Mac.
- **C** is not "company side today": tabz is on the owner's personal GitHub with a clone on Linux and its project memory in `brana-knowledge`. t-3454 moves or removes those per the company's answer. Until then no new tabz copy enters a personal store.
- **D** is the only Mac-to-Linux path: a person pasting text. Every Mac finding so far arrived this way.
- **E** is where the safety lives: no connection exists for it to leak through.

## Lane B, Linux side

```
 P1  Owner picks a file            ~/.claude/memory/<note>.md or brana-knowledge/dimensions/<doc>.md
      ▼
 P2  `brana pack approve <path>`   appends {path, sha256} to the allowlist file  [build, t-3437]
      │   the lint runs here and REFUSES the approval on a hit (client name, secret shape)
      │   the lint can only remove; it never admits a file by itself
      ▼
 P3  `brana pack publish`          run by the owner, offered at /brana:close     [build, t-3437]
      · re-hashes every allowlisted file; a changed file is skipped and reported until re-approved
      · runs the lint again on the exact bytes it will copy; any hit aborts the whole publish
      · copies only the listed files into the pack repo clone, commits, pushes
      · appends one audit line: date, files, hashes
```

No timers, no debounce, no job hooks. A publish happens when the owner runs it. Nothing automatic can add a file.

**Client lint list.** A committed file, not derived from `tasks-portfolio.json` alone: the portfolio misses cosmos-trading, acrelec, dgrx, tracy and chess, and venture names reveal outside work. Generic words (crea, unlock, somos, linkedin) stay out of the lint and are caught by the owner's eyes at P1, which is why the allowlist is per file and by hand.

## Lane B, Mac side

```
 M1  Owner starts a Claude Code session on the Mac
      ▼
 M2  session-start step in its OWN script (session-start.sh is at its 50 KB gate)   [build, t-3440]
      git fetch over the repo-bound read-only deploy key, 3 s budget
        │ offline / slow ─▶ keep the last pack
        ▼
 M3  fast-forward only; a non-fast-forward or a changed remote URL refuses the update and warns
        ▼
 M4  pack files sit in a FLAT directory the FTS5 note indexer reads (verify the indexer's
     directory handling before choosing the path; the current reader is non-recursive)
        ▼
 M5  `brana memory reindex` (local, fast); no ruflo required on the Mac
        ▼
 M6  statusline shows "pack: 2 d old"
```

The Mac never pushes to the pack repo and holds no credential that could.

## Freshness

The bundle is as fresh as the owner's last `brana pack publish`. The Mac sees it at its next session start. No freshness target was ever stated by the owner; none is invented here.

**Not built, on purpose:** push or webhook links into the Mac; a background sync agent; a builder on timers; scope tags at the memory gateway (none exist: 0 of 206 notes carry one); a hold queue; a signed manifest; anything flowing back from the Mac.

## Kill rule

Pre-registered before the repo is created (memory pattern: a kill rule needs a threshold, an owner mechanism and a date):

- **Measure:** distinct pack files surfaced by `brana recall` in Mac sessions, read from the Mac's recall log.
- **Threshold:** fewer than 3 distinct pack files recalled across 5 Mac sessions within 14 days of the first pull.
- **Owner mechanism:** a dated reminder created together with the repo (t-3437 AC).
- **Action on firing:** delete the pack repo and the Mac's pack directory; the Mac runs on the harness alone. Record the outcome in t-3437.

## What lives where

| Node | Holds | Written by | Read by |
|---|---|---|---|
| Linux notes and ruflo DB (full) | everything, all clients | owner, gateway, jobs | Linux only |
| `brana-knowledge` (owner repo) | backups; existing tabz project memory **until t-3454 resolves it** (no longer added, t-3475) | `backup.sh` (Linux only; disabling the Mac clone's push URL is requested, ADR-095 decision 3) | Linux writes; the Mac keeps a read-only clone (accepted deviation) |
| Allowlist file + lint list | approved paths with hashes; client names to veto | owner, by hand | `brana pack publish` |
| Pack repo (private, deploy key read-only on the Mac) | the hand-picked files | `brana pack publish` on Linux | Mac |
| Mac pack directory | the bundle | the Mac's pull step | Mac-Claude via FTS5 recall |
| Mac own memory (tabz) | tabz lessons | Mac-Claude | Mac only |
| tabz repo, its memory and `inbox/` | company data | owner and Mac-Claude | where the company says (t-3453, t-3454) |

## Failure behaviour

| Failure | Result |
|---|---|
| Mac offline, or GitHub down | Uses the last pack and shows its age. |
| Non-fast-forward, or the remote URL changed | The update is refused, nothing is applied, a warning shows. |
| Lint hit on approve | The file is not added to the allowlist; the hit (file and rule, never the matched text) is printed. |
| Lint hit on publish | The whole publish aborts; nothing is pushed. |
| An approved file changed on disk | It is skipped and reported; the rest publishes; re-approve to include it. |
| Something wrongly approved | It publishes. Git history shows what and when; remove it from the allowlist and publish again. |
| Deploy key leaked | It reads one small repo of files the owner already chose to share. Rotate it. |

## Open decisions

1. **The three company questions and the existing copies**: t-3453, owner-run, gates everything.
2. **Which docs and notes enter the bundle**: by hand, one at a time; default exclude. Answered: start clean.
3. ~~Staleness tolerance~~: no target; publish is manual.
4. ~~Where the tabz repo lives / which Claude account / whether a scoped token is acceptable~~: folded into t-3453.

## Out of scope

Live access between machines for the company-managed Mac; syncing ruflo entries (ADR-095 decision 8, no ruflo entry is synced: the `pattern` namespace is 135 error counters plus 15 curated rows that live in files); anything flowing from the Mac to Linux automatically; signing (deferred, t-3419 P3); a second owner machine.

## Implementation

| Task | Scope | Blocked by |
|---|---|---|
| t-3453 | company answer in writing | — |
| t-3454 | credential and personal-store remediation (owner-run) | t-3453 for the purge step only |
| t-3437 | allowlist with hashes, lint list, `brana pack approve` / `brana pack publish`, scoped repo, kill rule | t-3453 |
| t-3440 | Mac pull on a deploy key, fast-forward only, flat dir, reindex, pack age | t-3453, t-3437 |
| t-3417 | secret and client lint, veto only | — |
| t-3418, t-3420 | docs: company-managed rules, setup hygiene | t-3453 / t-3454 |
| cancelled | t-3438 (scope, scan, hold queue), t-3439 (builder, manifest, signing, triggers), t-3416 (quarantine) | |
| deferred | t-3419 signing (P3) | |

## Testing

Per task, test first. Must-fire tests: a client name in an approved file blocks the approval and, if planted afterwards, the publish; a token-shaped string blocks the publish; a changed approved file is skipped and reported; a non-fast-forward pack repo is refused on the Mac within the 3 s budget; after a good pull a bundle note is found by `brana recall` on the Mac; the lint list test fails if any of the five names missing from the portfolio is absent from it.
