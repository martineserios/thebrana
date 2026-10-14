---
status: implemented
task: t-3510
created: 2026-10-14
relates: ADR-058, ADR-095, docs/architecture/features/local-vector-recall.md
---

# Semantic leg for curated memory files in `brana recall`

## Problem

`brana recall` fused two legs: FTS5 keyword search over the curated memory files, and
exact-cosine vector search over `~/.claude/memory/knowledge.db`. The vector store is fed only
by `brana knowledge vector-sync`, which copies rows from ruflo's `memory_entries`. The curated
memory files (`~/.claude/projects/*/memory/*.md` and `~/.claude/memory/*.md`) were never
embedded, so they were found by keyword only.

## Decision

Embed the memory files with the existing `Embedder` seam (ruflo ONNX MiniLM, 384d) into
`knowledge.db`, and fuse them into recall as their own ranked list.

- **Identity.** A memory file has one identity regardless of which leg found it:
  `(path, slug, mtype, scope)`, derived by `memory::memory_file_identity`, the rule the FTS
  index also uses. Equal `DocRef` values accumulate RRF score (ADR-058 §6).
- **Storage.** One row per file in the existing `knowledge` table: key
  `memory-file:<absolute path>`, `source = 'memory-file'`, `tags = memory-file,scope:<scope>`,
  `content` = file text, `vec` = embedding of the first 1500 characters. No schema change.
- **Three-way fusion.** `vector::recall_provider` (used by both `brana recall` and the MCP
  `recall` tool) fuses FTS, a knowledge-rows leg, and a memory-files leg
  (`MemoryScope::Only`). A separate list is required: measured on the live store, the right
  file ranked 1st among memory files but 42nd among all rows, behind ~6,600 knowledge entries,
  and never reached the shared candidate pool of 20. `VectorProvider` defaults to
  `MemoryScope::Exclude`, so `brana knowledge search` stays knowledge-only as documented.
- **One query embedding.** `CachedEmbedder` lets both semantic legs share a single embedding of
  the query instead of starting the external embedder twice.
- **Incremental.** A file whose stored `content` equals the file on disk is skipped. Rows whose
  file no longer exists are pruned (never on an empty scan, never rows of other sources). A file
  the embedder cannot embed is counted as `failed`; an older row for it is kept.
- **Command.** `brana knowledge embed-memory [--json] [--dest PATH]`. Re-runnable. Recall itself
  never embeds.
- **Fail-soft.** With nothing embedded, the memory leg is empty and recall is identical to
  before (measured: 15/20 before and after). If the embedder is unavailable at query time the
  vector legs return nothing and recall degrades to FTS-only.
- **Embedder fix found on the way.** ruflo's CLI reads a `-t` value starting with `-` as a flag
  and crashes (`text.substring is not a function`). 791 of 1,106 memory files open with a `---`
  frontmatter fence, so 72% failed to embed at first. `RufloEmbedder` now prefixes a space
  (`argv_safe_text`); this also fixes any recall query that starts with a dash.

## Scope decision (needs confirmation)

Recall indexes only the top level of each memory directory, as the FTS index always did.
Archived notes under `memory/archive-2026-06/` are out of scope for both legs. This was chosen
for parity with the FTS leg and because archived notes are retired, but it is an assumption:
four of the twenty evaluation questions target archived files, which no leg can return.

## Measurements

Question set: 20 file-derived paraphrases (kept outside the repo; it is built from private
memory files). Run with `system/scripts/recall-eval.sh`, release build, 2026-10-14.

| Build and store | hits@5 | in scope |
|---|---|---|
| Installed build (before) | 15/20 | 15/16 |
| New build, live store, nothing embedded | 15/20 | 15/16 |
| New build, all memory files embedded | 16/20 | 16/16 |

The four remaining misses are the archived files. The single in-scope improvement is the
question whose answer was crowded out of the shared pool. Median latency is unchanged (~0.6 to
0.9 s). The first full `embed-memory` run over 1,106 files takes about an hour because every
text starts a Node process; later runs only touch changed files.

## Out of scope

Replacing the ruflo embedder, removing ruflo from `.mcp.json`, changing the RRF constant, and
scheduling `embed-memory` (follow-up t-3511).

## Acceptance

See task t-3510. The original target (>= 18/20) assumed all twenty answers were reachable;
four are archived, so the achievable maximum under the current scope is 16/20 and the result is
16/16 in scope.
