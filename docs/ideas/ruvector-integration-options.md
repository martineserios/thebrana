---
title: Which RuVector and ruflo components belong inside brana (and what recall is for)
status: idea
created: 2026-10-14
tasks: [t-3510, t-3511, t-3498]
---
# Which RuVector and ruflo components belong inside brana (and what recall is for)

> Brainstormed 2026-10-14 in session 8e7be6c0. **Paused mid-discussion at the owner's request
> because the session ran out of context.** This document is the full handoff: nothing from the
> session should need to be re-derived. Read "Resume here" first.

## Resume here (for a fresh session)

**Where we stopped.** `/brana:brainstorm` Phase 3 (Discuss), after Round 4. The owner was asked to
confirm an order of work and answered "check my last message", which was: *"check our memory
layers and architecture to better understand what we are trying to build."* So the next step is
**not** to pick an engine; it is to ground the choice in the memory architecture. Two read-only
passes were launched to do that (results are in Appendix A and B below if they finished before
this commit; otherwise re-run them, briefs are in "Open work").

**Paste this to start the new session** (from `~/enter_thebrana/thebrana`, then work in a
worktree for this branch, `git worktree add ../thebrana-docs-ruvector docs/ruvector-integration-options`
if it does not exist):

```
Resume the brainstorm in docs/ideas/ruvector-integration-options.md (branch
docs/ruvector-integration-options). Read the whole doc first, including the appendices. Continue
at "Discussion log > Open question". Do not re-derive measurements; they are recorded. First task:
read the memory-layer inventory and architecture appendix, restate in 6 lines what brana is trying
to build and where recall fits, and check it against the owner's goals (precision first, speed
second, related concepts across notes). Then ask me to confirm the order of work, run the
pre-mortem round, and shape the idea. Constraints: no API key, no GPU, ~3 GB free RAM.
```

## Seed

Decide which parts of the RuVector and ruflo family deserve a place inside brana, and what each
would actually buy. Raised on 2026-10-14 after the harness audit, two ruflo clean-room trials,
the t-3510 semantic-memory build, and a RuVector prototype. Original words: *"integrating
ruvector to brana. is also ruflo or another component eligible and useful?"* Earlier the owner
said: *"brana recall needs to wrap an available ruvector full power"* and *"we have a db with
patterns and memories, isn't that using ruvector?"* (answer: no, see below).

## What happened in the session (chronological, with outcomes)

1. **Harness audit** (4 read-only scouts + a 5-lens hive-mind, verdict RESTRUCTURE). Kept: backlog
   ledger and CLI, worktree rule, build/close/backlog/sitrep/ship/challenge, about 6 hard gates.
   Found dead: 11 hooks emit `additionalContext` in a JSON shape Claude Code 2.1.293 ignores, so
   session-start context never reached the model. Saved in memory note
   `project_harness-audit-2026-10-07`.
2. **Pocock tie-break rule** (owner, 2026-10-07): *where brana and Pocock cover the same ground,
   take his version and retire brana's.* Brana keeps only what his single-repo scope lacks (the
   persisted ledger, atomic pull across sessions, portfolio). Recorded on t-3489.
3. **Ruflo evaluation.** Trial 1 (full stack incl. mods, console, swarm) and trial 2 (classic
   hooks, zero plugins), both in clean rooms: `~/ruflo-clean/REPORT.md`,
   `~/ruflo-clean-v2/REPORT.md` (not in the repo; keep them). Results: K-cost FAIL (+104.6% then
   +136.6% tokens vs plain Claude Code; limit +15%), K-learning FAIL (all learning counters 0 after
   15 sessions, 33 edit hooks confirmed firing, route and predict outputs constant on 5/5 tasks).
   About 23.4K tokens of generated project config are injected before the first turn; 87% of the
   extra tokens are cache reads. Disposition: hooks, mods, console, swarm, daemon, autopilot and
   learning are closed.
4. **Corrections made during the session** (so a reader does not repeat them): the "88% ruflo
   memory search failure" was test-fixture contamination (real sessions fail about 7%); the
   "ruflo 20/20 vs brana recall 15/20" memory comparison was inflated because 4 of 20 answer files
   live in `memory/archive-2026-06/`, which the trial indexed recursively and brana's indexes do not
   (in scope, recall was already 15/16).
5. **t-3510 built and pushed** (branch `ruflo-integration/feat/t-3510-semantic-memory-recall`,
   3 commits, NOT merged): `brana knowledge embed-memory` (incremental), a dedicated memory-file
   vector leg fused three ways with keyword and knowledge legs (`vector::recall_provider`, one
   factory for CLI and MCP), `MemoryScope`, `HybridProvider::with_extra`, `CachedEmbedder`, a fix for
   ruflo's CLI crashing on `-t` text that starts with `-` (791 of 1,106 memory files start with
   `---`), and `system/scripts/recall-eval.sh`. Spec: `docs/architecture/features/recall-memory-file-vectors.md`
   (on that branch). Result: 15/20 to 16/20, 15/16 to 16/16 in scope. Not yet run on the live store
   (deploy the new binary first, then run embed-memory once; first run about 1 hour).
6. **RuVector spike** (this doc's spike/ folder): measured below.
7. **Brainstorm** (this document).

## Measurements (inputs, not opinions)

### Where the data really lives

| Question | Finding | How verified |
|---|---|---|
| Is the pattern and memory DB using RuVector? | **No.** `~/.swarm/memory.db` (155 MB SQLite; namespaces knowledge 5,488, session 918, metrics 775, pattern 171, skills 69) plus ruflo's **own JavaScript HNSW** (`@claude-flow/memory/dist/hnsw-index.js`, `class HNSWIndex extends EventEmitter`); `ruflo memory stats` reports "sql.js + HNSW, active, 5,862 entries" | source read, `memory stats` |
| RuVector in ruflo | `@claude-flow/memory` and `agentdb` import `@ruvector/{attention,gnn,rvf,rvf-wasm,ruvllm,graph-node,core,sona,router,rvf-solver}` only as optional dynamic imports | grep of dist |
| Brana's Rust code | zero references to ruvector | grep |
| What brana borrows from ruflo | only the embedding command `ruflo embeddings generate -t <text> -o json` (Transformers.js MiniLM-L6-v2, 384d), and `vector-sync` copies rows from ruflo's `memory_entries` | source |
| `~/ruvector.db`, `agentdb.rvf` | 1.5 MB and 162 B; not SQLite ("file is not a database"); written by ruflo packages, not read by brana | sqlite3 |

### RuVector core on the real vectors (spike, 7,732 vectors, dim 384, 20 query embeddings)

Crate `ruvector-core` 2.4.0 (MIT), release build in about 75 s. Features used: simd, hnsw, storage, parallel.

| Search | Build | Query p50 | Top-5 overlap with exact | Top-10 overlap |
|---|---|---|---|---|
| Exact scan (brana today, naive Rust loop) | none | 3,275 us | 1.000 | 1.000 |
| RuVector flat (no HNSW) | 0.1 s | 2,091 us | 1.000 | 1.000 |
| RuVector HNSW efSearch 50 | 0.4 s | 114 us | 0.960 | 0.945 |
| RuVector HNSW efSearch 100 | 0.4 s | 151 us | 0.980 | 0.970 |
| RuVector HNSW efSearch 200 | 0.4 s | 230 us | 1.000 | 0.990 |
| RuVector HNSW + Turbo4 (4-bit) | 1.0 s | 364 us | 1.000 | 0.990 |

Reading: faithful, 10 to 30 times faster per scan, but the scan is about 0.5% of a ~700 ms recall
call (the rest is the Node process that embeds the query), and a fresh `brana recall` process
would pay the 0.4 s build unless the index is persisted (redb storage exists). The crate's own
types mark Scalar, Product and Binary quantization "not yet applied" (the README advertises 4x to
32x); only Turbo4 is applied. The standalone `rabitq` crate (kemingy) is **AGPL-3.0**, a licence
risk if ever pulled in directly.

### Other RuVector crates seen on crates.io (not tested)

`ruvector-onnx-embeddings` 0.1.0 (pure-Rust ONNX embeddings via `ort`; features download-models,
coreml, cuda, gpu...), `ruvector-gnn` 2.3.0 (graph neural layer on HNSW), `ruvector-attention`,
`ruvector-graph-transformer`, `ruvector-mincut`, `ruvector-solver`, `ruvector-verified`,
`ruvector-router-cli`, `ruvector-cli` (CLI and MCP server), `ruvector-postgres`. About 200 crates.

### Recall quality and speed

| Build and store | Hits in top 5 | In scope | Median latency |
|---|---|---|---|
| Installed brana (before) | 15/20 | 15/16 | 0.77 s |
| New build, live store, nothing embedded | 15/20 | 15/16 | 0.89 s |
| New build, all memory files embedded (scratch copy) | 16/20 | 16/16 | 0.59 s |

Gotcha: **measure with a release build.** A debug build runs SQLite unoptimized, the keyword
search blows its 500 ms deadline, and recall silently becomes vector-only.

### Failure found on the way (embedder)

Ruflo's CLI reads a `-t` value that starts with `-` as a flag and crashes (`text.substring is not
a function`). A leading space fixes it. This also silently broke any recall query that began with
a dash. Fixed in t-3510 (`argv_safe_text`).

### Data facts for the benchmark and the graph

- Memory notes: 1,107 (1,106 scanned by embed-memory). Types: pattern 480, feedback 233, project
  172, untyped 123, field-note 41, reference 27, topic 17, user 10. Archived notes live in
  `memory/archive-2026-06/` and are **out of recall scope** for both the keyword and semantic legs.
- Explicit concept graph in the notes: 397 files (36%) carry at least one `[[link]]`; 1,276 links
  in total, 752 (59%) resolve to an existing note, **41% dangle**. Outgoing links per file
  (0,1,2,3,4,5,6+): 710, 209, 101, 35, 17, 6, 29.
- Gold data from history: of 1,965 completed tasks, **103 cite at least one memory note by slug**
  (126 citations), 16 cite two or more. By kind: fix 20, research 15, feature 12, untyped 10,
  design 7, refactor 7. Usable as a benchmark: query = task subject plus tags (what the build LOAD
  step sends), gold = cited notes. Caveat: a citation shows a note mattered, not that it was the
  only one, so recall is understated.
- The only benchmark used so far (20 questions written as paraphrases of the notes) is **saturated**
  and favors semantic search, so it cannot show improvement.

## Component inventory and first-read verdicts

| Component | What it would give brana | Evidence | First read |
|---|---|---|---|
| RuVector HNSW (core) | faster vector scan | faithful, invisible at 7.7k vectors | not yet; revisit near 50k to 100k vectors |
| RuVector in-process ONNX embedder | query embed about 700 ms to tens of ms; first full embed hour to minutes; no Node or ruflo in recall; ends the flag-parsing bug class | untested; vectors must match the 7.7k stored (cosine at least 0.99 on 50 stored texts, else re-embed) | **best candidate** |
| 4-bit (Turbo4) | memory at scale | works | no, data is small |
| Graph, neural rerank, self-learning | smarter recall | unproven; nothing moved in the trials | no |
| ruflo embedding command | today's embedder | works, about 4 s per file cold | keep until replaced |
| ruflo memory server and MCP | a second memory store | duplicates recall, about 3k tokens a turn (estimate), corruption history, 739 unique `knowledge:url` rows to export first | drop after export |
| ruflo hooks, mods, daemon, learning | orchestration | +105% to +137% tokens, zero learning | closed |
| ruflo prompt-injection scan | safety | listed as stub in the repo's own stub guard | no |
| MetaHarness, Dream Machine | pre-registered gates, accept/reject discipline | worth copying as method, not code | copy ideas only |

## Decisions so far (owner, 2026-10-14)

- **Outcomes:** faster recall and better recall quality. Then refined: **precision first, speed
  second, aiming both very high**, plus **related concepts across notes**.
- **Scale:** small project, 1 to 2 weeks.
- **Non-negotiable:** no API key, no GPU. *Not* ticked: "stay minimal", "no re-embedding of the
  7.7k vectors", "keep ruflo as fallback".
- **Evaluate for real:** RuVector in-process embedder, a persisted RuVector HNSW index, and
  MetaHarness-style pre-registered keep/kill gates as method.
- **Cross-concept needs: all four** (context bundle for a task; multi-hop A leads to B; same
  pattern in a different domain; conflict and staleness check).
- The owner said the 16 in-scope test cases are "very easy" and that real work is "much more
  complex", so a harder benchmark must be built.

## Discussion log

**Round 1 (challenge: is speed worth it?).** A recall call is about 700 ms and a session makes a
handful, against multi-second model turns, so a 0.6 s saving is invisible day to day. Owner:
precision first, speed second.

**Round 2 (devil's advocate: the benchmark is saturated).** Recall scores 16/16 in scope on 20
file-derived paraphrases. Owner: precision **and related concepts**, retrieval **across concepts**,
measure and evaluate, and the 16 cases are not representative of real, more complex work.

**Round 3 (which cross-concept retrieval?).** Owner chose all four. They are different
mechanisms, not one engine:

| Need | Mechanism that fits | Where RuVector fits |
|---|---|---|
| Context bundle for a task | hybrid retrieval with per-type quotas and diversity (MMR) across pattern, feedback, project, decision | MMR and filtering exist in the core crate; brana already has RRF |
| Multi-hop A to B | deterministic traversal of explicit `[[links]]`, spec-graph and ADR edges | graph and neural-rerank features unproven; explicit edges are not |
| Same pattern, other domain | semantic search restricted to `pattern` notes marked transferable, across scopes | embeddings already in place |
| Conflict and staleness | metadata: supersedes links, dates, `modified`; contradiction judged by a model | not a retrieval problem |

Working hypothesis: engine choice is mostly orthogonal to these needs. The work is data quality
(41% dangling links, untyped notes, no supersession), fusion logic, and a benchmark.

**Round 4 (help me decide: which first?).** Recommended order, with reasons: (1) context bundle
(used at every build and brainstorm start, measurable now from 103 mined pairs), with cheap 1-hop
link expansion over links that already resolve, kept only if the benchmark shows a lift; (2)
conflict and staleness (stale notes poison bundles); (3) same-pattern-other-domain last (rare, no
gold set). Multi-hop full version after link repair.

**Open question (where we stopped).** The owner replied "check my last message" to the order
question; the last message asked to **understand the memory layers and architecture first**. So the
order is unconfirmed. Still to do in the discussion: confirm the order after the architecture
read, run the pre-mortem round, then Phase 4 (shape) and Phase 5 (output, backlog plan).

## Proposed plan (unconfirmed, pending the architecture check)

1. Mine the benchmark from history and **pre-register** keep/kill thresholds before running
   anything (MetaHarness-style): hit rate and bundle-recall of cited notes, per-type coverage,
   latency, with a stated decision rule.
2. Typed context bundle: fuse legs with per-type quotas and diversity; optional 1-hop expansion
   over resolved links; keep expansion only if it lifts the benchmark.
3. In parallel, the embedder parity spike (hours): embed 50 stored texts in-process with
   `ruvector-onnx-embeddings`, require cosine at least 0.99 against stored vectors; also measure
   query latency and build complexity (`ort`, model download, 3 GB RAM ceiling).
4. Data repair as a side effect: map the 41% dangling `[[links]]` (renamed or archived notes),
   type the 123 untyped notes, decide the archive-search question.
5. Later: staleness via supersession metadata; HNSW persisted index only if vectors exceed about
   50k; drop the ruflo memory server after exporting its 739 unique `knowledge:url` rows.

## Open decisions for the owner

- Order of work (above), after the architecture check.
- Should notes under `memory/archive-2026-06/` be searchable in recall? Assumed no (parity with
  the keyword index); four benchmark answers live there.
- Whether to merge t-3510 now (it is correct and fail-soft) or fold it into this project.
- Whether the ruflo memory server is removed in this project or separately.

## Risks (pre-mortem not yet run; candidates so far)

- Building engines against a saturated benchmark proves nothing (mitigation: benchmark first).
- Mined gold set is small (103 pairs, 16 multi-note) and biased to cited notes.
- In-process embedder vectors differ from the 7.7k stored ones (re-embedding cost, or a silent
  quality drop if mixed). Mitigation: parity gate before adoption.
- Scope creep: four cross-concept needs in 1 to 2 weeks.
- Persisted HNSW adds a second store to keep consistent with `knowledge.db` (the repo has a long
  corruption and drift history with ruflo's stores).

## Open work (briefs for the two read-only passes, if re-running)

- **Memory-layer inventory:** every store (auto-memory files and MEMORY.md, `~/.claude/memory/`
  including patterns.md, index.db FTS5, knowledge.db vectors; ruflo `memory.db` namespaces;
  knowledge pipeline and `brana-knowledge/dimensions`; docs/ADRs/specs/ideas/research;
  `docs/spec-graph.json`; graphify; the backlog ledger; session state; scheduler digests; the
  link-capture queue in the personal repo): location, content, writers, readers, indexing, sync,
  problems, source ADR. End with write/read path diagram, five structural problems, and which
  layers recall covers versus ignores.
- **What the architecture is trying to build:** read `docs/architecture/the-brana.md`,
  `docs/reflections/ARCHITECTURE.md`, `docs/architecture/idea-to-ship.md`, ADR-004, 021, 076, 079,
  080, 086, 087, 092, 096, `docs/ideas/the-brana-guide.md` (Micro, Beat, Epic, Knowledge rings).
  State the purpose, which ring recall serves, what memory is documented to solve, what unattended
  loops need from memory, any stated goals about cross-project transfer, staleness, supersession or
  associative retrieval, and the design principles that constrain new retrieval work.

## Artifacts and where things live

| What | Where |
|---|---|
| This idea doc | branch `docs/ruvector-integration-options`, worktree `../thebrana-docs-ruvector` |
| Spike source | `docs/ideas/ruvector-integration-options/spike/` (standalone Cargo project; paths inside point at the old scratch HOME and must be repointed) |
| Measurement scripts | `docs/ideas/ruvector-integration-options/scripts/` (embedding-rank diagnosis, dash-crash diagnosis, missing-embedding diagnosis, link density, gold-pair mining, query-vector generation) |
| t-3510 build | branch `ruflo-integration/feat/t-3510-semantic-memory-recall`, worktree `../thebrana-t-3510`; tasks t-3510 (this feature), t-3511 (schedule embed-memory, speed up first run) |
| Ruflo trial tasks | t-3498 (verdicts recorded), t-3488 (setup phase), t-3489 (Pocock band, tie-break rule recorded) |
| Ruflo trial reports | `~/ruflo-clean/REPORT.md`, `~/ruflo-clean-v2/REPORT.md`; question set `~/ruflo-clean/questions.json` (private, derived from memory notes; **not committed**) |
| Memory notes | `project_harness-audit-2026-10-07` (full chronology with corrections), `project_pocock-adoption-ideas-2026-08-18` (tie-break rule) |
| Eval script | `system/scripts/recall-eval.sh <questions.json> [top]` on the t-3510 branch; `BRANA_BIN` selects the binary |
| Not durable | the scratch HOME and job folder `~/.claude/jobs/8e7be6c0/tmp` (copies of the stores, query vectors, builds) are deleted with the job |

## Gotchas learned (save the next session an hour)

- Measure with `cargo build --release`; debug builds time out the 500 ms keyword deadline.
- In a worktree-isolated session the Bash hook refuses commands that use shell variables, inline
  Python heredocs, `HOME=...` prefixes or `cd` chains. Write scripts to files and run them with
  literal absolute paths. `git worktree add ... -b <literal-branch>` with nothing after it passes
  the branch-name guard; a trailing redirect or `dev` argument is parsed as the branch name.
- A worktree created with `-b <name>` from a feature branch inherits its commits; cut from
  `origin/dev` for docs. The docs branch tracks `origin/dev`; push it explicitly:
  `git push -u origin docs/ruvector-integration-options`.
- The system `sqlite3` CLI has no FTS5 module; query the FTS index through brana, not sqlite3.
- Do not run `embed-memory` on the live store before the new binary is deployed: the old binary
  would show `memory-file` rows as knowledge entries.
- Commit messages in this repo must not carry attribution trailers (hook rejects them).
- ruflo's `memory store` exits 0 even when it fails on text starting with `---`.
- No API key ever, no local model or GPU on this machine, about 3 GB free RAM.

## Appendix A: memory-layer inventory

*(Filled from the read-only pass if it finished before this commit; see "Open work" otherwise.)*

## Appendix B: what the architecture is trying to build

*(Filled from the read-only pass if it finished before this commit; see "Open work" otherwise.)*
