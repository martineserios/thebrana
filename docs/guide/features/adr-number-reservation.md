# ADR Reservation — collision-safe ADR numbering

`brana adr reserve <slug>` picks the next ADR number and creates the placeholder file for
you, safely — even if another session on this machine (in a different `git worktree`) does
the exact same thing at the exact same moment.

## Quick Start

```bash
brana adr reserve backfill-retry-policy
# Reserved ADR-093 -> docs/architecture/decisions/ADR-093-backfill-retry-policy.md
```

Open the file it printed and write the ADR as usual — the command only reserves the number
and scaffolds the headers, it doesn't write the decision content for you.

## How It Works

Before this existed, picking an ADR number meant `ls docs/architecture/decisions/ | tail`
and eyeballing the next one — fine with one session, unsafe with two. `brana adr reserve`
replaces that with a real lock: it's safe to run from two sessions at once, even in
separate worktrees of the same repo, and no two calls will ever get the same number.

It only reserves a number and writes a stub — it does not open an editor, does not commit
anything, and does not touch any other ADR file.

## Examples

Fresh ADR after the current highest (`ADR-092` in this repo):

```bash
$ brana adr reserve worktree-lock-registry
Reserved ADR-093 -> docs/architecture/decisions/ADR-093-worktree-lock-registry.md

$ cat docs/architecture/decisions/ADR-093-worktree-lock-registry.md
# ADR-093: worktree-lock-registry

Status: draft

## Context

## Decision

## Consequences
```

Two sessions running it at once — no collision, no manual coordination needed:

```bash
# session A (worktree ../thebrana-t-100)
$ brana adr reserve session-a-topic
Reserved ADR-094 -> ...

# session B (worktree ../thebrana-t-200), run moments later
$ brana adr reserve session-b-topic
Reserved ADR-095 -> ...
```

## Scope

Works across every session and worktree **on the same machine**. It does not coordinate
across two different physical machines working on the same repo — that's a separate,
not-yet-built check tracked against a pre-push validation gate.
