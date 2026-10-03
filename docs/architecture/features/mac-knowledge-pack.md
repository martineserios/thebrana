---
status: proposed
---
# Mac knowledge pack: one-way knowledge flow to a company-managed machine (t-3436, epic macos-portability t-3372)

Implements the access model of [ADR-095](../decisions/ADR-095-two-machine-memory-sync.md) (trust profiles, shared docs repo). This spec is the step-by-step flow; the ADR holds the decision and the threat model.

## Problem

The owner works on a Linux laptop that is always on and accumulates knowledge (notes, research docs, a ruflo database, patterns) for many clients. A second machine, a Mac, is **company-managed** (Apple Business Manager / DEP, Rippling MDM) at a company that is HIPAA-compliant, and is used for one client, tabz. The Mac needs the owner's general knowledge. It must not receive other clients' data, and nothing may link the Mac to the owner's machines or services in a way the company has not sanctioned. The knowledge should stay as fresh as the owner's work on Linux allows.

## Decision

**Publish a package; do not connect machines.** Linux builds a signed, read-only "pack" from an allowlist (scope-tagged, scanned, reviewed items only) and publishes it to a private repo. The Mac pulls it over ordinary HTTPS at session start. Nothing flows back automatically. Live access (SSH, VPN) between the two machines is rejected for the company-managed Mac (ADR-095, option A is for owner-controlled machines only).

Safeguards applied (not legal advice): minimum necessary (allowlist, never a filter after the fact), approved channels only, data stays in its zone, access control and audit (scoped token, signed manifest, git history), integrity and transmission security (signatures, checksums, TLS), vendor review (which Claude account runs on the Mac is the company's call).

## The five lanes

```
 LINUX (owner, always on)          INTERNET (ordinary HTTPS)        COMPANY MAC
 ────────────────────────          ─────────────────────────        ──────────────────
 A  harness code ─────── push ───▶ GitHub: thebrana (public) ─pull─▶ thebrana + hooks   [exists]
 B  knowledge pack ───── push ───▶ GitHub: pack repo (private) ─pull▶ notes+docs index  [build]
 C  (nothing)                      (company's choice)               tabz repo + work   [exists]
 D  owner reads bug reports ◀───── owner carries text by hand ◀──── Mac-Claude reports [exists]
 E  other clients, full DB,   ✗✗✗ never crosses, no path exists ✗✗✗  Mac's own tabz memory
    session/metrics, backups                                          stays on the Mac
```

- **A** code is public and flows one way: ship `dev` to `main`, the Mac runs `git pull` and `./bootstrap.sh`.
- **B** is the new lane, all of it one-way and read-only for the Mac.
- **C, D** tabz stays on the company side; the only Mac-to-Linux path is a person pasting text.
- **E** is where the safety lives: no connection exists for it to leak through.

## Lane B, Linux side

```
 L1  Owner works in a Claude session on Linux
      │  writes a lesson / ingests a link / session closes
      ▼
 L2  memory gateway  `brana memory write --type … --scope …`        [exists]
      │  S1  every item has a scope tag:  project | global | cross-project
      │      default = project  → NEVER a candidate, stays in L3/L4 only
      ▼
 L3 notes ~/.claude/memory/*.md      L4 ruflo DB ~/.swarm/memory.db   [exist, full]
      │                                  ▲
      │            ┌─────────────────────┴───────────────────────────────┐
      │            │ other writers feeding L2/L4 (existing scheduled jobs)│
      │            │  link-research-extraction  every 4 h                 │
      │            │  knowledge-pipeline-tier1  daily 03:00               │
      │            │  close-extraction          nightly 02:00             │
      │            │  knowledge-vector-sync     every 4 h                 │
      │            └──────────────────────────────────────────────────────┘
      ▼
 S2  TRIGGER  (any of)                                               [build]
      · a gateway write (debounced 60 s)
      · any of the jobs above finishing
      · 30-minute fallback timer
      ▼
 L8  PACK BUILDER
      S3  select      items with scope = global | cross-project
      S4  scan        client deny-list + secret scan + size limits
           │ pass                      │ fail
           ▼                           ▼
      S5  candidate set        L9  HOLD QUEUE
                                    S6  owner reviews at /brana:close or
                                        `brana pack review`
                                        approve → candidate · reject → excluded
      S7  build       manifest {path, sha256, scope, source commit}; delta vs last pack
      S8  sign        Linux signing key
      S9  publish     git push to the pack repo (a tiny commit) + audit log line
```

After S9 nothing more happens on Linux. No connection to the Mac is open.

## Lane B, Mac side

```
 M1  Owner starts a Claude Code session on the Mac
      ▼
 S10 session-start hook (own script)                                  [build]
      git fetch of the pack repo, 3 s budget
        │ offline / slow ─▶ skip silently, use the last pack
        ▼
 S11 VERIFY   signature valid? signer on the allowed list?
              every file matches its manifest sha256?
        │ fail ─▶ refuse the whole update, warn in the statusline
        ▼
 S12 APPLY    changed files → ~/.claude/memory/<pack dir>/
        ▼
 S13 INDEX    notes: `brana memory reindex`  (fast, local)
              docs:  ruflo indexes the approved text locally
                     (v1 ships text and the Mac re-embeds; the set is small.
                      Shipping prebuilt vectors ties the pack to the exact ruflo
                      DB layout and is a later optimization.)
        ▼
 M5  local stores:  pack notes + docs index  +  the Mac's OWN tabz memory
        ▼
 M7  statusline shows  "pack: 2 h old"
```

## Freshness

Limits come from the existing Linux jobs, not from the sync.

| Source on Linux | Time to reach the pack |
|---|---|
| A lesson or note written in a session | about a minute (gateway write triggers the builder) |
| Links and research (`link-research-extraction`) | up to about 4 h |
| Knowledge pipeline docs (daily 03:00) | next morning |
| Learnings extracted at close (`close-extraction`, 02:00) | next morning |
| Vector index updates (`knowledge-vector-sync`) | up to about 4 h |

The builder also runs right after each job finishes, so nothing waits for the 30-minute fallback. On the Mac, staleness is bounded by the time since the last session start, plus a manual `brana pack update`. Open question: whether extracted learnings need to arrive within the hour (would add on-demand extraction at close for global-scope items, at the cost of more model calls on Linux).

**Not built, on purpose:** push or webhook links into the Mac (need a listener on a company machine); a background sync agent (Dropbox, Syncthing and the like, visible to MDM); anything flowing back from the Mac.

## What lives where

| Node | Holds | Written by | Read by |
|---|---|---|---|
| Linux notes and ruflo DB (full) | everything, all clients | owner, gateway, jobs | Linux only |
| `brana-knowledge` (owner repo) | backups, all clients | `backup.sh` | Linux only; the Mac never touches it |
| Pack builder and hold queue | scope-tagged items | Linux | Linux, then publishes |
| Pack repo (private, scoped read-only token) | approved notes and docs, signed | Linux only | Mac |
| Mac pack notes and docs index | the pack | the Mac's pull step | Mac-Claude |
| Mac own memory (tabz) | tabz lessons | Mac-Claude | Mac only |
| Mac tabz repo and `inbox/` | company data | owner and Mac-Claude | Mac only |

## Failure behaviour

| Failure | Result |
|---|---|
| Mac offline, or GitHub down | Uses the last pack and shows its age. |
| Signature or manifest check fails | The whole update is refused, nothing is applied, a warning shows. |
| Scan flags an item | It goes to the hold queue; nothing publishes until approved. |
| Linux overloaded | The builder is slow; the Mac keeps its last pack. |
| Something wrongly approved | It publishes. The audit log and git history show what and when; pull it back with a new signed delta. |

## Open decisions (owner)

1. **Where the tabz repo lives.** It is on the owner's personal GitHub today; a compliant company would likely want it on its own account.
2. **Which Claude account runs on the Mac**, and whether the company approves it (everything Claude reads there goes to Anthropic).
3. **Whether a private repo and a scoped token are acceptable** to the company (ordinary developer traffic, but their rules decide).
4. **Which existing docs and notes may enter the pack.** 31 of 85 docs name a client; the default is exclude (t-3437).
5. **Staleness tolerance** (see Freshness).

## Out of scope

Live access between machines for the company-managed Mac; syncing ruflo entries (ADR-095 cancelled t-3404: `pattern` rows are auto-generated error-recurrence telemetry); anything flowing from the Mac to Linux automatically.

## Implementation

| Task | Scope |
|---|---|
| t-3438 | scope default, scan and hold queue at the gateway (S1, S3-S6) |
| t-3439 | builder, manifest, delta, signing, publish, triggers (S2, S7-S9) |
| t-3440 | Mac pull, verify, apply, index, pack-age indicator (S10-S13) |
| t-3437 | review of existing docs and notes for the pack; create the scoped pack repo |
| t-3416, t-3417, t-3419 | provenance and quarantine, secret scan, signed commits (security tasks in ADR-095) |
| t-3418, t-3420 | company-managed profile rules, Mac remediation, setup hygiene |

## Testing

Per task, test first: project-scope items never selected; flagged items held; a tampered file or bad signature refused; offline session start within budget; a new approved note found by `brana recall` on the Mac after a pull; mutation checks on the scan (a client name in an approved item must block the publish).
