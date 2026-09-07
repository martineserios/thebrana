---
title: Project Descriptor Vectors — one curated line per project, embedded once
status: built
created: 2026-09-06
tasks: [t-3307]
depends_on:
  - docs/architecture/features/local-vector-recall.md
  - docs/architecture/features/tasks-portfolio.md
---

# Project Descriptor Vectors

> One curated line per portfolio project, embedded once, in a table the link
> scoring pass can read. Curated because the cheap alternative mistags.

## Problem

The link-signal enrichment pipeline needs to answer "which project is this
link about?". The obvious implementation — cosine between the link's vector and
each repo's `CLAUDE.md` — fails on this portfolio specifically: sibling client
repos are scaffolded from the same template and describe themselves with the
same stack vocabulary (Next.js, Supabase, FastAPI). Six repos say the same
words, so they cross-tag each other, and the project with the most boilerplate
wins.

The differentiator is not in the repo. `batrade` is *grain brokerage*, `bemol`
is *a home-visit music school*, `truper` is *barter without money* — and none
of those phrases appear in either repo's scaffolding. That signal has to be
written down by a human once, not derived.

## Decision

1. **The descriptor is curated, not generated.** One line per project on the
   portfolio record (`tasks-portfolio.json` → `clients[].projects[].descriptor`),
   naming domain, customer and problem. No stack words — the thing that
   cross-tags siblings is exactly the vocabulary they share.
2. **thebrana is not a portfolio record.** It is the workshop, so its vector is
   composed from the repo's own docs: the curated line, the `## Cover`
   paragraph of [the-brana.md](../the-brana.md), and the titles of the accepted
   ADRs — a decision vocabulary no client repo shares.
3. **Embed through the existing seam.** `RufloEmbedder::embed()`
   (`vector.rs`) — the one ruflo layer [local-vector-recall.md](local-vector-recall.md)
   keeps. No second embedding path.
4. **Embed once per descriptor.** A project is re-embedded only when its
   descriptor text changes, detected by SHA-256 of the exact embedded text.
   `--force` covers the case the hash cannot see (a changed embedding model).
5. **One store.** The table lives in `~/.claude/memory/knowledge.db`, beside
   the `knowledge` table, so the scoring pass opens one file.

## Schema

```sql
CREATE TABLE project_vectors (
    slug            TEXT PRIMARY KEY,  -- portfolio project slug, or "thebrana"
    descriptor      TEXT NOT NULL,     -- the exact text that was embedded
    descriptor_hash TEXT NOT NULL,     -- SHA-256 of descriptor — the re-embed trigger
    source          TEXT NOT NULL,     -- "portfolio" | "the-brana"
    updated_at      INTEGER NOT NULL,
    vec             BLOB NOT NULL      -- 384 little-endian f32, same encoding as `knowledge`
);
```

## Surface

```bash
brana knowledge project-vectors                      # embed what changed
brana knowledge project-vectors --force              # re-embed everything
brana knowledge project-vectors --list               # show the stored table
brana knowledge project-vectors --json               # stats for a caller
```

| Flag | Default | Description |
|------|---------|-------------|
| `--portfolio <path>` | `~/.claude/tasks-portfolio.json` | Portfolio registry to read descriptors from. |
| `--dest <path>` | `~/.claude/memory/knowledge.db` | Store holding the `project_vectors` table. |
| `--docs <path>` | `<repo>/docs` | Docs root thebrana's own vector is composed from. |
| `--force` | off | Re-embed every project, changed or not. |
| `--list` | off | Print the stored table instead of embedding. |
| `--json` | off | Emit stats as JSON. |

Reading side: `ProjectVectorStore::all()` returns every row, slug-ordered —
what the scoring pass consumes.

## Failure behaviour

- A project with no `descriptor` gets **no vector**. An uncurated project is
  better absent than represented by boilerplate — that is the whole point.
- An embedding failure leaves the previously stored vector in place rather than
  replacing it with nothing; the slug is reported under `failed`.
- If nothing could be embedded *and* nothing was already current, the command
  exits non-zero — that is ruflo being unreachable, not a per-project quirk.
- Missing `the-brana.md` or decisions directory: thebrana falls back to its
  curated line alone. Never blocks a sync.

## Constraints

- thebrana's composed text is capped at 1,200 chars. The embedding model
  (all-MiniLM-L6-v2) truncates around 256 tokens, so all ~80 accepted ADR
  titles would not fit anyway; the cap makes that explicit instead of pretending
  the tail counts.
- Accepted ADRs are read in filename order — an unstable order would change the
  composed text and re-embed on every run.

## Operating notes

- Descriptors live in the repo copy (`system/state/tasks-portfolio.json`) and
  reach `~/.claude/tasks-portfolio.json` via `sync-state.sh pull`. Editing the
  cache copy directly and then running `sync-state.sh push` is the other
  direction — do not do both in one session or one will overwrite the other.
- Re-run the command after editing any descriptor; nothing watches the file.

## Open

- **Cross-tagging fallback (challenger alt, 2026-09-06):** if curated
  descriptors still cross-tag siblings once t-3311's scoring pass runs, enrich
  each project vector with that project's own backlog task subjects and tags —
  a differentiated, already-maintained signal — before reaching for anything
  heavier. Decide on evidence from real scoring runs, not up front.
- Two descriptors are written from the portfolio index alone because their
  repos were not reachable: `curso-papa-derecho-ia` and `unlock`. Worth an
  owner pass.
