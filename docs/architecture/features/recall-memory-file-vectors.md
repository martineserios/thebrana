---
status: draft
task: t-3510
created: 2026-10-14
relates: ADR-058, ADR-095, docs/architecture/features/local-vector-recall.md
---

# Semantic leg for curated memory files in `brana recall`

## Problem

`brana recall` fuses two legs: FTS5 keyword search over the curated memory files, and
exact-cosine vector search over `~/.claude/memory/knowledge.db`. The vector store is fed only by
`brana knowledge vector-sync`, which copies rows from ruflo's `memory_entries`. The curated
memory files (`~/.claude/projects/*/memory/*.md` and `~/.claude/memory/*.md`) are never
embedded, so they are found by keyword only.

Evidence (clean-room trial, 2026-10-13): on 20 questions written as paraphrases of 20 memory
files, ruflo semantic search over the files scored 20/20 hits@5; `brana recall` scored 15/20.
Two of the five misses returned no memory file at all.

## Decision

Embed the memory files with the existing `Embedder` seam (ruflo ONNX MiniLM, 384d) into
`knowledge.db`, and let `VectorProvider` return them as `DocRef::MemoryFile`, so the RRF merge
in `HybridProvider` fuses FTS and semantic signals for the same document.

- **Identity.** A memory file has one identity regardless of which leg found it:
  `(path, slug, mtype, scope)`, derived by the same function the FTS index uses
  (`memory::memory_file_identity`). Equal `DocRef` values accumulate RRF score, which is the
  "dual-backend confirmation" ADR-058 §6 relies on.
- **Storage.** One row per file in the existing `knowledge` table: key
  `memory-file:<absolute path>`, `source = 'memory-file'`, `tags` = `memory-file,scope:<scope>`,
  `content` = file text, `vec` = embedding of the first 1500 characters. No schema change. Slug
  and type are re-derived from the path on read, so they cannot drift from the FTS leg.
- **Opt-in provider.** `VectorProvider::with_memory_files(true)` includes these rows; the
  default excludes them. `brana recall` and the MCP `recall` tool opt in. `brana knowledge
  search` does not, because it documents that the vector store holds only `knowledge:` entries.
- **Other passes.** `vector-sync` only upserts, and the relevance scoring pass reads only
  link and feed rows, so neither touches `memory-file` rows.
- **Incremental.** A file whose stored `content` equals the file on disk is skipped. Rows whose
  file no longer exists are pruned. A file the embedder cannot embed is counted as failed and
  leaves no row (recall falls back to keyword for it).
- **Command.** `brana knowledge embed-memory` (re-runnable, prints scanned / embedded /
  unchanged / pruned / failed). Recall itself stays read-only and never embeds.
- **Fail-open.** Embedder unavailable at query time returns no vector hits, so recall degrades
  to FTS-only, exactly as today.

## Out of scope

Replacing the ruflo embedder, removing ruflo from `.mcp.json`, changing the RRF constant,
scheduling `embed-memory` (follow-up: chain it after `vector-sync`), the MCP `recall` tool
(it shares `HybridProvider` and inherits the change).

## Acceptance

See task t-3510. Measured by `system/scripts/recall-eval.sh <questions.json>`: hits@5 of
`brana recall` on the 20-question set must be >= 18/20 (baseline 15/20).
