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

**Where we stopped.** `/brana:brainstorm` Phase 3 (Discuss), after Round 5. The owner was asked to
confirm an order of work and answered "check my last message", which was: *"check our memory
layers and architecture to better understand what we are trying to build."* That check is **done**
(Appendix A: memory-layer inventory; Appendix B: what the architecture is trying to build) and it
reframed the project (see Round 5): the real gap is recall for **unattended workers**, plus a
measured feedback loop, plus supersession and relatedness at recall time. The order of work is
still unconfirmed, and the pre-mortem and shape phases have not run.

**Paste this to start the new session** (from `~/enter_thebrana/thebrana`, then work in a
worktree for this branch, `git worktree add ../thebrana-docs-ruvector docs/ruvector-integration-options`
if it does not exist):

```
Resume the brainstorm in docs/ideas/ruvector-integration-options.md (branch
docs/ruvector-integration-options). Read the whole doc first, including both appendices. Continue
at "Discussion log > Open question". Do not re-derive measurements or re-run the architecture
reads; they are recorded. Round 5 reframed the project: the real gap is recall for unattended
Beat and Epic workers, a measured feedback loop (a usage log of recalled notes versus notes the
task cited), and supersession and relatedness at recall time, not engine choice. First task:
restate in 6 lines what brana is trying to build and where recall fits, test that against the
owner's goals (precision first, speed second, related concepts across notes, all four cross-concept
needs), and propose the first-week scope. Then ask me to confirm the order of work, run the
pre-mortem round, shape the idea (Phase 4), and offer the backlog plan (Phase 5). Constraints: no
API key, no GPU, about 3 GB free RAM.
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

**Round 5 (owner: check our memory layers and architecture to understand what we are trying to
build).** Two read-only passes ran (Appendix A: 12 memory layers; Appendix B: purpose, rings,
principles). Their joint conclusion **reframes the project**:

- Memory is documented as "a fourth dimension" orthogonal to the rings: every ring should recall on
  entry and write back on exit. Recall today serves only the interactive `/brana:build` LOAD and
  SessionStart. **The unattended Beat and Epic path has no recall step at all**, which is exactly the
  owner's goal ("leave workers working"): workers read the task `context` field and `CONTEXT.md` only.
- The documented unmet needs are not scoring quality: (a) a read-on-entry recall for Beat and Epic
  workers, (b) a Knowledge-ring gauge that measures whether recall hits change outcomes ("nothing
  yet measures whether accumulated knowledge is any good"), (c) supersession, staleness and
  relatedness handled at recall time (no step resolves contradictions at recall; the recall-hit
  log that staleness rules depend on is written by nothing).
- Structural problems in the stores (duplicate pattern stores, indexes stale or unscheduled, writers
  without readers, 41% dangling links, canonical docs and dimension docs unindexed) matter more to
  precision and relatedness than the engine choice.
- Design principles that bound any solution: derived indexes rebuildable; pointer not paste with one
  home of record; single writer; fail-open; evidence over assertion and a context budget (cost per
  beat is about context size, so a bundle must be small).

Implication for the plan: the "context bundle" should be designed first as **the recall a
fresh-context worker gets at pull time**, with a size budget, typed sections, supersession-aware
ranking and a usage log that closes the loop (which recalled notes did the task cite). That log
becomes both the benchmark source and the staleness signal.

**Open question (where we stopped).** The owner replied "check my last message" to the order
question; the last message asked to **understand the memory layers and architecture first**. So the
order is unconfirmed. Still to do in the discussion: confirm the order after the architecture
read, run the pre-mortem round, then Phase 4 (shape) and Phase 5 (output, backlog plan).
*(Resolved in Round 6, session 2026-10-14 resume.)*

**Round 6 (resume: restate the purpose, test it against the goals, confirm the order).**

What brana is building and where recall fits, in six lines:

1. Brana turns intent into shipped work through four rings (Micro, Beat, Epic, Knowledge). The
   rings forget; memory is the only thing that crosses between them.
2. Each ring should recall on entry and write back on exit. That is the Knowledge ring, which is
   still mostly design.
3. The proven ring is Beat: a fresh-context worker pulls a task, does it and reports. It reads only
   the task `context` field and `CONTEXT.md`. It has no recall step.
4. Recall today serves only interactive `/brana:build` LOAD and SessionStart. Nothing measures
   whether recalled notes helped, and nothing resolves supersession at recall time.
5. Pocock tie-break: the ticket body, `CONTEXT.md` and ADRs stay the worker's main instruction (his
   "the issue is a complete instruction"). Recall adds only what his single-session scope lacks
   (cross-session learnings) and delivers them as pointers (a slug plus a one-line gist), never
   pasted text. The bundle is computed at pull time and is not stored into `context`: derive, do not
   store a parallel signal (ADR-086 §7, ADR-078).
6. The product is a small, typed context bundle given to each worker when it pulls a task, plus a
   usage log comparing the notes recalled with the notes the task cited. That log becomes the
   benchmark, the staleness signal and the Knowledge-ring gauge.

Test against the owner's goals:

| Goal | Fit | Note |
|---|---|---|
| Precision first | strong | measurable as cited ÷ recalled: on the 103 mined pairs now, and live through the usage log later |
| Speed second | partial | the real lever is the in-process embedder (~700 ms → tens of ms); HNSW makes no visible difference at 7.7k vectors; this is week 2 |
| Context bundle | week 1 | the core deliverable |
| Conflict and staleness | partial in week 1 | a supersession filter at recall time is cheap; the non-use staleness rule needs log data, so week 2+ |
| Multi-hop A → B | 1-hop slice only | 1-hop over links that already resolve, behind a flag, kept only if it lifts the benchmark; full multi-hop needs the 41% dangling links repaired first |
| Same pattern, other domain | deferred | rare, no gold set; **the honest gap against "all four"** |
| No API key, no GPU, 3 GB RAM | fits | the ONNX MiniLM model is about 90 MB |

**Decision (owner, 2026-10-14): tracer bullet first** (Pocock's slicing preferred over the Round 4
benchmark-first order, applying the tie-break rule). Week 1:

- Days 1–2: build a thin end-to-end path. A bundle verb (task id → typed pointers) runs on today's
  `brana recall`, is wired into Beat and Epic worker pull (`drain-loop.md`, `epic-drain.md`), and
  writes a usage log (bundle note ids at pull; notes the task cited at close).
- Days 3–5: mine the benchmark from history and pre-register keep/kill gates, then improve ranking
  against it: per-type quotas, MMR diversity, a ~1.5K-token budget, a supersession filter, and 1-hop
  link expansion behind a flag. Each change is kept only if it passes the gates.
- Week 2: the embedder parity spike (speed), the staleness rule from usage-log data, link repair,
  and the t-3510/t-3511 merge decision.

**Round 6b (owner: "did you already check our memory structure, layers, format and nature?").**
Structure and layers: yes (Appendix A). Per-note format: no, so a read-only frontmatter census ran on
2026-10-14 (script: session scratchpad `fm_census.py`; scope: `~/.claude/memory/*.md` plus
`~/.claude/projects/*/memory/*.md` top level, test-tmp dirs and MEMORY.md excluded):

| Fact | Value | Consequence for the bundle |
|---|---|---|
| Notes in scope | 1,107 | matches embed-memory's count |
| No frontmatter at all | **315 (28%)** | type must fall back to the filename prefix (`pattern_`, `feedback_`...) |
| `description` present | 789 (71%) | the one-line gist for pointer output exists for most notes; fallback: first body line |
| `type` (top-level 386 + nested `metadata.type` 562) | feedback 306, project 215, pattern 202, reference 44, user 11, field-note 10 | two schemas coexist (old flat, newer `metadata:` block); the reader must accept both |
| `modified` / `created` | 241 / 132 | dates mostly come from the filename (dated files) or mtime, not frontmatter |
| `status` | **1** (quarantine) | ADR-057's `status: superseded` vocabulary is unused in practice |
| `supersedes` as a field | **0**; 42 files mention "supersed*" in prose | **no structured supersession data exists**: week 1 must derive it (newest dated file per slug, per ADR-038, plus a prose regex for "superseded by [[x]]"); a backfill or a write-path field is a separate decision |
| `transferable` / `confidence` / `source_task` | 117 / 117 / 114 | `transferable` is a ready filter for "same pattern, other domain"; `source_task` is extra gold data (note → task) for the benchmark |
| Note size | p50 1.6 KB, p90 7.7 KB, max 2.5 MB (`sessions.md`-type logs) | pointers, not pastes, are the only way to fit a ~1.5K-token budget; outsized logs need excluding from recall |
| Citation form in tasks | slugs cited bare (`project_ruflo-memory-corruption-recurring` ×9) and as prefixes | the cited-notes extractor must match slugs with and without date suffixes |

Nature: notes are atomic-ish markdown cards written mostly by the model, with two frontmatter
generations, sparse dates and no lifecycle state. Supersession and staleness therefore have to be
**derived at recall time**, which is consistent with principle 2 (derive signals, never store
parallel ones).

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

## Challenger review (Phase 5, 2026-10-14)

Three `brana:challenger` workers reviewed the shaped idea, each with a different lens: convergent,
systems and critical (evaluation design). **All three returned RECONSIDER (narrow).** Their
calibration notes are in `~/.claude/agent-memory/brana-challenger/`.

**Verification run by the main session after the reviews:**

- `~/.claude/run-state/t-*.jsonl` holds 28 build runs. 25 of them record a `LOAD` checkpoint, so
  `/brana:build` LOAD, which runs `brana recall`, does happen in practice.
- `~/.claude/scheduler/beats.jsonl` has **8 lines in total**. The last one is wave-29, 2026-09-07.
  The headless runner is close to unused.

### HIGH confidence (two or more workers)

**H1. Premise correction: supervised drain workers already get recall; only the headless runner
does not.**
- *Raised by:* convergent #1, verified above; systems #3 (three pull paths) points the same way.
- *Evidence:* each task pulled by a supervised drain runs the full `/brana:build`
  (`docs/guide/workflows/drain-loop.md:120-121`, `epic-drain.md:174-179`), and build LOAD calls
  `brana recall` (`system/skills/build/phases/load.md:98`). Only the headless runner prompt has no
  recall (`system/scripts/autonomous-runner.sh:376-383`).
- *Correction:* Round 5's "Beat and Epic have no recall step" was too broad. The real gaps are:
  - LOAD's recall is untyped, not budgeted, and blind to supersession;
  - nothing records which recalled notes were used;
  - the headless runner has no recall, but at 8 beats ever it is low volume.
- *Fix:* the integration point becomes **build LOAD**, where the bundle replaces or extends the
  recall step, and **build CLOSE**, which writes the used/ignored data. The runner gets its own
  later decision.

**H2. The used/ignored field has nowhere to live as currently written.**
- *Raised by:* systems #1, convergent #3, critical #5.
- *Evidence:*
  - Beat records are written once per beat, from a single-sourced schema that may not be forked
    (`loops-library.md:100-157`).
  - The runner throws away worker stdout except the `NEEDSHUMAN` grep (`autonomous-runner.sh:387-393`).
  - ADR-057:25 notes that a schema field without a blocking mechanism "does not get adopted".
  - The field is also LLM self-report, which only means something once the bundle is shown.
- *Fix:*
  - Write it from **build CLOSE as one row per task**, through a single `brana` verb (single writer).
  - CLOSE refuses to finish without it. "Field absent" is recorded separately from "used nothing".
  - Add an observable second signal: which pointed note files the transcript actually opened.

**H3. Shadow mode can kill the bundle but cannot justify keeping it, and its token gate is zero by
construction.**
- *Raised by:* critical #3, convergent #2, systems #6.
- *Evidence:*
  - Nothing is injected in shadow mode, so the token change per run is 0.
  - The real cost is cache reads (87% of ruflo's extra tokens) plus Reads of the notes a pointer
    leads to (p50 1.6 KB). Neither is counted in a bundle budget.
- *Fix:*
  - Shadow gates are **kill-only**. Offline, the bundle must beat two baselines: current
    `brana recall` on subject+tags, and the pointers already written in the ticket.
  - Keep decisions come from a **canary or alternating A/B** in the injection phase, comparing tokens
    per run, retries and AC pass rate.
  - Pre-register a minimum n. Below it, the verdict is INCONCLUSIVE, not keep.

**H4. Pointers are unreadable in the runner's sandbox, and the bundle has no project-scope rule.**
- *Raised by:* systems #4, convergent #5.
- *Evidence:*
  - The bwrap jail does not mount `~/.claude/memory` or `~/.claude/projects`
    (`sandbox-claude.sh:57,85-91`; `autonomous-runner.sh:474`).
  - Recall spans about 100 project dirs, including client projects. Cross-client walls are still an
    open question (ADR-095).
- *Fix:*
  - The ADR fixes the scope as current project plus global, with other clients excluded, enforced by
    a must-fire test.
  - The runner either gets inline gists (fenced, length-capped, injected host-side, never copied into
    the worktree) or waits.

### Single-worker findings (strong evidence, adopted)

**C1 (critical #1). The mined gold mixes several meanings of "cited".**
- *Evidence:* `scripts/mine_pairs.py:26` matches slug substrings across description, context and
  notes, with no field split and no time order. Seven hits for one slug turned out to be three
  different kinds:
  - plan-time pointers already present in the ticket;
  - write targets ("findings written back to X");
  - completion notes.
- *Fix:*
  - Hand-label about 30 hits as pointed, wrote or read. Keep only "read" hits whose note predates the
    task's `started`.
  - **Commit the frozen gold file.** The miner reads a job-tmp export that is deleted with the job.

**C2 (critical #2). `source_task` records which task *wrote* a note, so as gold it is circular.**
- *Evidence:* of the 114 notes with `source_task`, about 62 are `close-YYYY-MM-DD` labels and about
  40 name a task. A note written by task T did not exist when T was pulled.
- *Fix:* drop it from the hit-rate gold. Use it only as a leakage control, against an index filtered
  to notes dated before the task's `started`.
- *Correction:* the Round 7 mitigation "gold adds `source_task`" is withdrawn.

**C3 (critical #4). Precision is capped by the gold, and the doc's caveat was inverted.**
- *Evidence:*
  - An incomplete gold set understates *precision*, not recall.
  - At about 1.22 cited notes per task, maximum precision at K=8 is about 15%.
  - The gold is also biased toward what interactive recall already surfaced.
- *Fix:* gate on hit@K and MRR against the baselines, and report precision only relative to a
  baseline.

**C4 (convergent #4). Deriving supersession from recency misreads ADR-038 and duplicates ADR-057.**
- *Evidence:*
  - Dated files exist so that parallel writes are safe (ADR-038:29-31). "Newest per slug" only
    decides which line MEMORY.md shows, so treating recency as supersession would hide valid parallel
    notes.
  - ADR-057 already defines `status: superseded` and `supersedes`, and ADR-078 forbids a second
    signal for the same state.
- *Fix:*
  - Read the ADR-057 fields first.
  - Down-weight derived supersession hits; never drop them.
  - Measure the prose regex's precision on the 42 candidate files, then backfill the confirmed pairs
    into the ADR-057 fields.

**C5 (systems #5). The usage log is canonical, not rebuildable.**
- *Evidence:* a bundle is ranker output at a moment in time, and it cannot be re-derived later from
  beat records.
- *Fix:*
  - Treat the log as a canonical store: one writer, backed up.
  - Key rows by (task, claimant, ts). Record per-leg status, because the 500 ms keyword deadline
    degrades silently.
  - *Correction:* this overrides "derived, rebuildable" in the Shape's ADR line.

**C6 (systems #2). A hung bundle call can strand leased tasks.**
- *Evidence:* a bundle call made under the runner's `RUN_LOCK` after leasing would block every task
  in the lease.
- *Fix:* call it per task, with a wall-clock timeout (`timeout 10`), and fail open to an empty
  bundle.

**C7 (critical #6). The ~1.5K-token budget does not bind.**
- *Evidence:* a pointer is about 40-50 tokens, so 1.5K tokens is about 30 pointers.
- *Fix:* cap the bundle at 8 pointers or fewer. Take the gist from `description` only. Gate cost on
  measured tokens per run, not on bundle size.

**C8 (convergent #6). Citation fixes needed before the ADR is drafted.**
- The procedures live in `docs/guide/workflows/{drain-loop,epic-drain}.md`. The `system/loops/*`
  files are catalog pointers only.
- `memory-decay-by-non-use.md:12-13` counts recall *exposure*, not use, so shadow rows must not
  count.
- ADR-086 §7 allows pointer appends to `context`, so it cannot justify "not stored". Cite
  retrieval-routing rule 4 instead.

**Surface the plan missed:**
- `system/skills/build/phases/load.md` and the build CLOSE phase
- `loops-library.md` §Beat record schema
- `autonomous-runner.sh` and `lib/sandbox-claude.sh`
- the `beats.jsonl` consumers (`pipeline-digest.sh`, `brana-scheduler-digest.sh` and their tests)
- `docs/architecture/features/autonomous-runner.md`
- `memory-decay-by-non-use.md`
- `scripts/mine_pairs.py` and the frozen gold file

## Open decisions for the owner

> **Resolved 2026-10-14 (Rounds 6 and Phase 5):** order = tracer bullet first (Round 6); archive
> notes stay **out** of recall scope; **merge t-3510 before day 1** (it blocks the tracer bullet;
> t-3511 follows); governance tasks (ADR → tests → implementation → spec and docs) are **included**
> in the backlog plan. Still open: whether the ruflo memory server is removed in this project or
> separately (default: separately, after exporting its 739 `knowledge:url` rows).

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

### Pre-mortem (run 2026-10-14, Round 7)

"Six months on, this failed." The two most credible causes, and the owner's choice (**both
mitigations**):

- **(A) The usage log measured citation habit, not usefulness.** Only 103 of 1,965 completed tasks
  (5%) ever cited a note by slug. If workers keep not citing, cited ÷ recalled stays near 0 and the
  gates can never decide anything. **Mitigation:** the beat report gets a required structured field
  listing the note slugs used and ignored, so the log does not depend on free-text citations; the
  gold set adds `source_task` (114 notes) as a second note → task signal.
- **(B) The tracer bullet fed unproven, partly stale bundles to unattended workers.** That means a
  token and noise tax on every beat (the ruflo +105% story again), unnoticed because nobody watches
  drains. **Mitigation: shadow mode.** The tracer bullet computes and logs the bundle at pull but does
  not give it to the worker until it passes the pre-registered gates, one of which is a per-beat token
  change.
- **How the two fit:** in shadow mode the worker never sees the bundle, so it cannot report
  used/ignored. Shadow mode is scored offline (mined benchmark plus `source_task` gold). The
  used/ignored field starts counting once the bundle is injected, and from then on it grows the gold
  set every day, which ends the saturated-benchmark problem.
- Lesser causes considered, not selected: a rich-get-richer staleness loop (see Second-order effects);
  scope creep across the four needs; a second recall code path drifting from `brana recall`.

## Shape (Phase 4, 2026-10-14)

**Idea: Knowledge-ring ORIENT for unattended workers, measured.**

- **Problem:** Beat and Epic workers start each task with no cross-session memory, and nothing
  measures whether recall helps anyone.
- **Solution:** at pull time, compute a small typed bundle of pointers from existing recall and log
  it; inject it only once it passes pre-registered gates, then learn from a structured used/ignored
  field in the beat report.
- **Audience:** unattended Beat and Epic workers first; interactive `/brana:build` LOAD can reuse the
  same verb later.
- **Scale:** small project, 1 to 2 weeks (effort M).
- **Success metric (to be pre-registered on day 3 with numbers):** on the mined gold set, the bundle
  contains at least one cited note for a stated share of tasks (hit rate), with bundle precision above
  a stated floor; the token change per beat stays under a stated ceiling; recall latency does not
  regress; zero failed pulls caused by recall (fail-open).

**Key insights carried from the discussion:**

- Engine choice (RuVector or not) is close to irrelevant to precision at 7.7k vectors; data shape and
  fusion matter more. RuVector's best candidate stays the in-process embedder, for speed, in week 2.
- Supersession has no structured data (Round 6b); derive it at recall time.
- Pocock tie-break: the ticket, `CONTEXT.md` and ADRs remain the worker's instruction; the bundle is
  pointers only, computed and not stored into `context`; tracer-bullet slicing.

**Architecture of the tracer bullet:**

```
pull(task) ──> bundle(task_id) ──> recall legs (FTS5, vectors, knowledge) ──> fuse (RRF)
                    │                                                             │
                    │      derive: type (frontmatter, else filename prefix),      │
                    │      supersession (newest dated per slug + prose regex),    │
                    │      quotas per type, MMR, ~1.5K-token budget, pointers     │
                    ▼                                                             ▼
             usage log (append-only, derived from pull + report)        shadow: log only
             {task, bundle ids, ranks, ts}  +  at report: {used, ignored}   gated: inject into worker prompt
                    │
                    └──> offline scorer (mined gold + source_task) ──> keep/kill gates
```

**Risks and mitigations:** see Pre-mortem above, plus the earlier candidate list.

**Engineering disciplines:**

- **DDD / decision (ADR):** yes. A new ADR: "Knowledge-ring ORIENT at pull: shadow-gated recall
  bundle with a usage log." It decides the pull-time recall step, pointer-only output, shadow-then-gate
  rollout, where the usage log lives (derived, append-only, rebuildable from beat receipts), and the
  derived supersession rule. It also records that ADR-057's `status`/`supersedes` vocabulary is unused
  in practice.
- **TDD:** tests before code for: type derivation (both frontmatter schemas plus filename fallback),
  supersession derivation (dated variants of one slug; prose "superseded by"), quotas and token
  budget, pointer format, fail-open when a recall leg fails or times out, usage-log write at pull and
  report, the cited-slug extractor (with and without date suffixes), and the offline scorer on a fixed
  fixture.
- **SDD / spec:** a feature spec `docs/architecture/features/worker-recall-bundle.md` before any
  `system/` write (M-effort gate). Update `drain-loop.md` and `epic-drain.md` (the new ORIENT step),
  `the-brana.md` and the guide's Knowledge-ring row (from design to partial), and
  `retrieval-routing.md`.
- **Docs (`/brana:docs`, feature strategy):** tech doc = the feature spec; user guide = a short
  section on reading the usage log and gate report; CLI reference for the new verb; spec-graph routing
  over files whose `impl_files` touch recall (`load.md`, `recall-memory-file-vectors.md`,
  `local-vector-recall.md`).

**Possible next steps:**

1. ADR plus feature spec (half a day).
2. Tracer bullet in shadow mode: bundle verb, pull-time call, usage log (days 1–2).
3. Mine gold (cited slugs plus `source_task`), pre-register gates, offline scorer (day 3).
4. Ranking improvements, each kept only if it passes the gates: quotas, MMR, supersession, 1-hop
   behind a flag (days 4–5).
5. Gate review, then inject plus the used/ignored report field (end of week 1 or week 2).
6. Week 2: embedder parity spike; staleness from log data; link repair; same-pattern-other-domain
   via the `transferable` filter.

### Second-order effects

- **Inject the bundle → workers use notes → used/ignored becomes a recall-hit signal → the non-use
  staleness rule (`memory-decay-by-non-use.md`) finally has data → a demotion loop becomes possible.**
  Surprise (risk): rich get richer. Notes the ranker never surfaces are never "used", so a non-use rule
  would demote them for being unranked, not for being useless. Mitigation: staleness must count
  *exposure* (eligible and shown) separately from use, or reserve one exploration slot per bundle.
- **Structured used/ignored field → the gold set grows with every beat →** the benchmark stops being
  saturated and keeps tracking real work. Surprise (opportunity): this is also the Knowledge-ring gauge
  the guide says is missing ("nothing yet measures whether accumulated knowledge is any good"). One
  mechanism closes three documented gaps: (a) worker recall, (b) the gauge, (c) the staleness input.

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

Source: read-only pass, 2026-10-14 (the `~/.swarm` databases were not opened; only file names and
sizes come from them). C = canonical (source of record), D = derived and rebuildable.

| # | Layer | Location, size | Content | Writer | Reader | Indexed by | Sync / backup | Known problems | Source |
|---|---|---|---|---|---|---|---|---|---|
| 1 | Native auto-memory (C) | `~/.claude/projects/*/memory/*.md` + MEMORY.md; about 1,010 .md in about 100 real project dirs (`-enter-thebrana-clients-bemol` alone has 72) | feedback, project facts, per-project patterns, `sessions.md` (1.3M), event-log | the Claude model writes directly (ADR-038 exempts it from the gateway); `memory-index-sync.sh` appends MEMORY.md lines; `brana memory write` for feedback and project | Claude Code auto-loads MEMORY.md; recall (FTS) | layers 3 and 4 | not in git; only `pre-lint-heal-*` snapshots (2.4G + 2.5G inside `~/.claude/memory/`); export stopped for tabz (t-3475) | 809 `*-test-tmp-*` dirs are test pollution (`projects/` is 2.0G); per-worktree dirs split memory (`bemol-rails` vs `-t-125`; `prof-man` vs `prof_man`; 3 praia-* dirs) | ADR-038, 095 |
| 2 | Global memory files (C) | `~/.claude/memory/`: 213 .md; 184 `pattern_*`, 18 `feedback_*`, MEMORY.md (191 of 200 lines), `patterns.md` (46K, 99 sections, cap 100), `knowledge-staging.md` (cap 30), `portfolio.md` (28.6K), event-log (+265K archive) | patterns, feedback, staging claims, client portfolio | `brana memory write`, `/brana:retrospective`, `/brana:close`, `session-end-pattern-promotion.sh`, scheduler `memory-consolidation` (Mon-Sat 15:30), `lint-heal` (Sun) | `build/phases/load.md`, session-start, `brana recall` | layers 3 and 4 | `brana-knowledge/backup.sh` at close; pattern union on export (ADR-095) | two pattern stores (`patterns.md` and `pattern_*.md`); ADR-039 (per-file, no cap) still "proposed"; `consolidation-log.md` reads "0 debrief flags consumed" on every run; MEMORY.md last modified Sep 15 while newer files exist | ADR-038/039/095 |
| 3 | FTS5 `index.db` (D) | `~/.claude/memory/index.db`, 17.5M | keyword index over memory files | `brana memory reindex` (scheduler `reindex-patterns`, Sunday 03:00); drop-and-rebuild | `brana recall` (FTS5Provider) | n/a | rebuildable | `patterns.md` modified Oct 14, after the last index build on Oct 13; top level of each dir only, so `archive*/` excluded; only `*.md` indexed | ADR-058, memory.rs |
| 4 | Vector store `knowledge.db` (D) | `~/.claude/memory/knowledge.db`, 24.3M | 384-d f32 BLOB per row: knowledge, link and feed rows (about 6,600+) plus `memory-file:` rows | `brana knowledge vector-sync` (every 4h, +20m), `embed-memory` (manual) | `brana recall` / MCP recall (VectorProvider) | brute-force cosine, no index | not backed up; rebuild needs ruflo rows | `embed-memory` not scheduled (t-3511); first full run about 1 h; ruflo still needed as the query embedder | local-vector-recall.md, recall-memory-file-vectors.md |
| 5 | ruflo `~/.swarm/memory.db` (mixed) | 148.5M; 14 `.corrupt-*` copies (about 0.5G); `hnsw.index` last built Aug 13; `memory.rvf`; `agentdb-memory.db` 54M; stray 152K `memory.db` copies in `~/.claude/` and `thebrana/.claude/` | namespaces `knowledge`, `pattern`, `session`, `metrics`, `skills`, `field-notes`, `decisions` | `session-end-persist.sh` (`session`, `metrics`), `close` (`session`, `field-notes`), `post-tool-use-failure.sh` (`pattern` counters), `index-knowledge.sh` (Sun), `feed-ruflo-index`, `process-url` (`knowledge`) | session-start (queries `pattern`), `/brana:research` (`field-notes`, `decisions`), `flywheel-insight.sh` (`metrics`) | HNSW (retired as broken, t-2620) | daily binary backup, weekly JSON export; close pushes JSON to private `brana-knowledge`; raw DB off-site only after t-3342 | silent-success defects; repeated corruption (14 copies); ADR-095 reports 135 of 158 `pattern` rows are error counters; `session` and `metrics` have no recall reader | memory-backup.md, ADR-095, `ruflo-stub-guard.md` |
| 6 | Knowledge pipeline (C to D) | `~/.swarm/knowledge-pipeline-state.json` (1.3M), `~/.claude/knowledge-pipeline-report.md`, `brana-knowledge/{drafts,inbox,dimensions}` (85 dimension docs; repo is 1.5G) | link/feed to tier1, tier2, tier3 drafts, dimensions | scheduler `knowledge-pipeline-tier1` (03:00), `drain-links` (4h), `feed-*` | `/brana:research`, reindex into ruflo and `knowledge.db` | `index-knowledge.sh` (ruflo), vector-sync | git (`brana-knowledge`) | `brana-knowledge/inbox/` is empty; Mac clone of the repo is a deviation (ADR-095) | ADR-042/087/093 |
| 7 | docs/ (C) | 97 ADR files, 68 drained ideas, 41 research docs, 1 field-notes file, reflections | decisions, specs | humans and skills | grep, Read, `spec-graph` | `docs/spec-graph.json` (D, 625K, built 2026-10-06, 657 nodes, 2,598 edges, 148 orphans) | git | ADR-038 and 039 still "proposed" although the CLI ships; ADR-057 says ADR-038 is "unimplemented"; neither `brana recall` nor the FTS index covers docs/ or `brana-knowledge` dimensions | ADR-057 |
| 8 | graphify-out (D) | `thebrana/graphify-out/graph.json` 14.1M, built from commit `cfd7ef79` | code and doc structure | `graphify update .` (manual) | retrieval rule 2 | itself | untracked | stale unless rebuilt; doc-edge overlay is wiped on rebuild | ADR-064 |
| 9 | Backlog ledger (C) | `thebrana/.claude/tasks.json` 5.7M (global `~/.claude/tasks.json` is a 12-byte stub), `tasks-archive.json`, `~/.claude/tasks-json-backups` (276M, hourly) | tasks with context, notes, AC | `brana backlog` | `brana backlog get`, `/brana:build` | none (scan only) | hourly backup; per project | not covered by recall; rule 0 routes to the CLI | retrieval-routing.md |
| 10 | Session state (C, short-lived) | `projects/*/memory/session-state.json`, `session-history.jsonl`; `~/.claude/state/*.jsonl`, `close-queue.json`, `run-state/pipeline-digest/` | handoff, goals, digest | `brana session write` (close Step 9), the session-end hook | `/brana:sitrep`, session-start | none | none | hook-written files say "auto-captured" with only metrics | close/phases/session-state.md |
| 11 | Scheduler and digest outputs | `~/.claude/scheduler/` (25M; `feed-log.jsonl` 18M), `intelligence-feed-digest.md`, `lint-heal-report.md` | logs, reports | cron | humans; `/morning` | `feed-*` goes to ruflo | local | digest and report writers mostly lack a programmatic reader | pipeline-digest.md |
| 12 | Link-capture queue | `personal/` repo (`inbox/`, `deploy/drain-links.sh`, event-log 92K); link tasks in the backlog | raw URLs | Telegram bot, `brana log`, scheduler `personal-repo-pull` (15 min) | `drain-links` | to rows 4 and 5 | personal git | entries keyed `knowledge:url:` in ruflo, and the ruflo copy is rebuilt from nothing | ADR-093 |

### (a) Write and read paths

```
WRITE                                              READ
CC model --Write--> projects/*/memory/*.md ─┐     SessionStart ─┬─ ruflo `pattern` search
close/retro --brana memory write--> memory/ ─┼─FTS reindex (weekly)─> index.db ──┐
links/feeds -> ruflo `knowledge` --vector-sync(4h)--> knowledge.db ──────────────┼─> brana recall (RRF)
embed-memory (manual) ─────────────────────────────────> knowledge.db ───────────┘      (+ SessionStart hybrid-recall, top 5)
hooks -> ruflo session/metrics/pattern    (no recall reader)
docs/ & brana-knowledge --index-knowledge.sh (Sun)--> ruflo knowledge ; spec-graph/graphify : separate queries
tasks.json, session-state, portfolio.md : direct read only
```

### (b) Five structural problems (with evidence)

1. **Duplicate pattern stores.** `patterns.md` has 99 sections and a cap of 100; there are also 184
   `pattern_*.md` files and ruflo `pattern` rows. ADR-039 (per-file, no cap) is still "proposed"; the
   cap is enforced in code (ADR-095 §9).
2. **Stale or unscheduled indexes.** FTS is rebuilt weekly and was already stale against
   `patterns.md`; `embed-memory` is manual (t-3511); the HNSW index dates from Aug 13, was retired in
   t-2620, and ADR-058 is still unrevised; the session-start hook still queries ruflo `pattern`
   (`session-start.sh:234`) though `retrieval-routing.md` calls that namespace noise.
3. **Writers with no reader.** `session`, `metrics`, scheduler and feed output, and the
   memory-consolidation "debrief flags" (0 consumed on every run) have no recall reader. `~/.swarm`
   holds 14 corrupt DB copies; the pre-lint-heal copies add 4.9G.
4. **Readers with no writer, or a missing feature.** The UserPromptSubmit auto-recall hook is not
   built (`local-vector-recall.md:224`; `context-inject.sh` only injects task IDs and files). The
   rules in `memory-decay-by-non-use.md` rely on a recall-hit log that nothing writes.
5. **Unindexed canonical text.** docs/ ADRs and the 85 dimension docs reach recall only through ruflo
   (the Sunday `index-knowledge.sh` run). ADR-095 §8 demotes ruflo to a rebuildable index, yet its DB
   is still the only copy of the link-research insights and about 13 challenge and spike notes
   (t-3478). 809 test-tmp project dirs and split per-worktree dirs pollute layer 1.

### (c) Recall coverage

- **Covered:** top-level `*.md` in global and project memory (FTS5, and vectors once embedded), and
  `knowledge.db` rows (links, feeds, doc chunks from ruflo).
- **Ignored:** `archive*/` subdirs (4 of 20 eval questions), docs/ ADRs and specs as files,
  `tasks.json`, session state, ruflo `session`/`metrics`/`pattern`, spec-graph, graphify, and
  `sessions.md`/event-log (which FTS does index as plain markdown).

## Appendix B: what the architecture is trying to build

Source: read-only pass over the project docs, 2026-10-14. Paths are relative to the repo root.

### 1. Purpose, in the docs' own terms

- `docs/architecture/the-brana.md` Cover: "The Brana is how brana turns intent into shipped work...
  Nothing crosses between [branes] except memory, carried by loops that return... Gates sit where
  that motion turns irreversible. And the human lives inside it, an inhabitant not an operator...
  sensing the rest only through what memory brings across."
- `docs/reviews/architecture-review-2026-06-10.md` §1, the founding bet: agent work products "can be
  captured, persisted, and recalled so that the agent compounds in capability across sessions
  instead of starting from zero." It calls the aim a "self-improving exocortex."
- `docs/reflections/ARCHITECTURE.md`: "Single Brain, All Projects": identity, intelligence (memory)
  and context layers. Principles include "Cross-pollinate" and "Confidence-weighted recall."

### 2. Ring model (the-brana.md §Scale; `docs/ideas/the-brana-guide.md` L3.1)

- **Memory is a "fourth dimension," orthogonal to the rings.** Every ring recalls on entry (ORIENT)
  and writes back on exit (ASSIMILATE). The rings "cycle and forget; memory accumulates —
  write-back is what turns each circle into a spiral."
- **Micro (seconds):** red-green-refactor inside one task. Reads the task context on entry.
- **Beat (minutes):** pull, work, report. The only fully proven ring. Reads "task context + wave
  state on entry"; writes "learnings + receipt on exit." Proof: "beat 2 read its build map from the
  task's `context` field, not from the conversation."
- **Epic (days):** waves, gates, valves. Reads wave state and the epic plan. The epic-level
  learnings write is design-only: "no step writes epic-level learnings today."
- **Knowledge (weeks):** "memory → recall → work → learnings → memory. No command — the harness
  itself." Entire row is design-only; the guide says its gauge is weak: "nothing yet measures
  whether accumulated knowledge is any good."
- **Recall today serves two places:** `/brana:build` LOAD (`system/skills/build/phases/load.md`: `brana
  recall` plus ruflo knowledge and pattern search, then a 1-hop `docs/spec-graph.json` traversal), and
  SessionStart and sitrep. **It does not serve the unattended Beat or Epic path.** Workers read the
  task `context` field and the CONTEXT.md glossary instead.
- **Should serve:** Knowledge-ring ORIENT for every beat (a fresh-context worker at pull time), and
  the missing Knowledge-ring MEASURE and JUDGE steps. The "Knowledge band, instrumented (design, not
  yet built)" pipeline is: capture, then `knowledge-staging` queue, then distiller pump (t-2851),
  curation valve (t-2852), reservoir, hygiene gauges (t-2853).

### 3. Problems memory is documented to solve, with the strongest evidence

- **Context loss between sessions.** ADR-004: "Most sessions end without any of them."
  `docs/ideas/drained/session-continuity-multi-session.md`: four close-to-sitrep leaks, e.g.
  "Follow-ups offered, user skips, items evaporate."
- **Concurrent sessions.** "`brana session write` always replaces `session-state.json`
  unconditionally... the second close overwrites the first's `accomplished`, `next`, and
  `learnings`." ADR-038 and `dated-memory-files.md`: "Two CC sessions closing... Last write wins; the
  earlier session's learning is lost." ADR-088: shared active-epic state is bad.
- **Write-only memory.** Architecture review: "The system writes everything and reads almost
  nothing"; 6,259 rows with `access_count = 0`; "Even the decision log is write-only." ADR-021: a
  schema "announced without a blocking enforcement mechanism does not get adopted."
- **Retrieval silently failing.** `docs/architecture/features/local-vector-recall.md`: 4,441 rows,
  HNSW "Vectors: 2", and "`knowledge:url:` entries ever returned by semantic search: 0." The review:
  session recall returned `[]` by design because of a hidden 0.55 threshold. t-3510: the right file
  ranked 1st among memory files but 42nd overall, never reaching the pool of 20.
- **Convention and quality drift.** ADR-039: garbage patterns such as "`tracy-catalog-id-not-articleid`
  ... useless outside proyecto_anita." `memory-pattern-learning-redesign.md`: recall similarity of
  "0.43–0.45, generic patterns."
- **Cross-client learning.** `ARCHITECTURE.md` "Compound Learning Effect": "Day 30: Start gamma... 30%
  of problems already solved by alpha." No incident-level evidence it works; it is aspirational.
  ADR-095 limits it: the company Mac gets "no automatic return path."
- **Unattended loops.** ADR-079 §Pull: a wave pull ignored `blocked_by` (t-2919 pulled ahead of
  t-2920, wave-11), recorded as memory `pattern_wave-pull-ignores-blocked-by-ordering`. the-brana.md
  law 2: dead-letter exists because of t-2587, a "160-day-stale root cause."
- **Persistence loss.** The 2026-03-31 ruflo corruption wiped all patterns (`resilient-pattern-store.md`).

### 4. Unattended loops: needs and supply

- **Needs:** ADR-086 §1 "Task = one fresh context window"; fresh context per pull is the default
  (guide L3.6). `epic-drain.md`: "a task is one fresh context window."
- **Supply today:** the task `context` field (ADR-086 §7: it "makes 'do t-NNN' complete"), the
  `acceptance_criteria` field, `CONTEXT.md`, wave state re-read each beat ("each beat re-reads it and
  trusts nothing from prior beats"), and fresh-context judge workers.
- **Gaps:** `drain-loop.md` and `epic-drain.md` contain **no recall step**; their only memory contact
  is the "task-context write" at ASSIMILATE. "Nothing reads beat records structurally today"
  (loops-library.md). The handoff packet's `spec`, `log` and `refs` are 0 or near-0 populated (guide
  L2.4). The Epic exit-write is missing.

### 5. Explicit statements and explicit gaps

- **Cross-project transfer, stated:** ADR-039 filter "Would this pattern apply... a completely
  different codebase with a different client?"; `/brana:memory pollinate`; "transferable" patterns
  and tags; ADR-038 routes cross-project scope to `pattern`.
- **Cross-project transfer, open:** `ARCHITECTURE.md` open questions (should SessionStart inject
  cross-client patterns, "walls" for competitive clients, sensitive-pattern filtering; "Cross-project
  DNA matching... Deferred."); ADR-095: tabz material must not flow out.
- **Staleness, stated:** `system/rules/memory-decay-by-non-use.md`: "staleness signal is 'never
  recalled since written,' not 'written N days ago'," driven by recall-hit counts;
  `system/rules/memory-consolidation-scheduled.md` and ADR-048 (lint-heal, consolidation); ADR-057
  `review_due`, `status`, and claim/pattern confidence from quarantine to proven; retrieval-routing
  rule 4: "Recall may return a stale snapshot — re-verify against the live accessor."
- **Staleness, gap:** ADR-021's temporal metadata was "never implemented." The recall-hit log is the
  only signal and there is no demotion implementation.
- **Supersession and conflict, stated:** the `supersedes` relation and `status: superseded`
  vocabulary (ADR-057); debrief contradiction flags that archive files (ADR-048); `/brana:memory
  review --audit` for cross-doc contradiction (learn.md); dated feedback files with the newest per
  slug winning the index (ADR-038).
- **Supersession and conflict, gap:** ADR-058's own changelog says it "should be revisited or
  superseded." **Nothing resolves contradictions at recall time.**
- **Associative or related-concept retrieval, stated:** tag-based `pollinate`; the spec-graph 1-hop
  `depends_on`/`informs` traversal in LOAD 2b; ADR-057: "graph is irreplaceable for structural
  queries, vectors for fuzzy discovery," and "atomic notes beat long docs 30–50%."
- **Associative or related-concept retrieval, gap:** memory files are not graph-scanned (the
  knowledge-base redesign says only 9% have wiki-links, about 30% of those broken; our own count on
  2026-10-14 was 36% with links and 41% dangling); ADR-064 forbids graphify plain-language query for
  open-ended questions; sitrep targeted recall (domain, problem-type, risk queries) is P2 and
  unbuilt; recall counts, recurrence counts and promotion are P1 and unbuilt.
- **Recall eval status:** 16/16 in scope, but 4 of 20 questions target archived files no leg indexes.

### 6. Five constraining design principles

1. **Derived indexes must be rebuildable; git or files are the source of truth.** ADR-015; ADR-095
   decision 8 ("ruflo is demoted to a rebuildable index"); ADR-039. Disaster test: wipe the DB,
   re-index, recover 100%.
2. **Pointer, not paste. Single home of record; derive signals, never store parallel ones.** ADR-086
   §7 (and §3 via ADR-078). `CONTEXT.md` is generated, not hand-edited.
3. **Single writer and gateway.** ADR-038 (`brana memory write` classifies and routes; MEMORY.md is
   generated; dated files for parallel safety); ADR-058 §7 (store independence); the-brana.md law 1
   ("a message may carry a pointer, never state").
4. **Fail-open with graceful degradation.** ADR-058 §5 (FTS5-only or vector-only fallback, 500 ms and
   2 s deadlines); ADR-038 ("Recall works even without ruflo"); "convert silent failures to loud
   ones" (architecture review).
5. **Evidence over assertion, and a context budget.** ADR-076 (executed evidence beats notes); recall
   results are frozen assertions, re-verified (retrieval-routing rule 0); law 5 "Cost per beat ≈
   context size"; ADR-058 caps LOAD calls and snippets (200 chars); `context-budget.md` 55/70/85%
   thresholds; quality gate before storage (ADR-039); human valve on irreversible promotion.

### 7. Pointer for the brainstorm (the reframing)

The docs' unmet need is **not** better keyword-versus-vector scoring. It is:

- **(a) a read-on-entry hook for Beat and Epic workers.** Unattended loops currently have no recall
  step, which is the owner's stated goal ("leave workers working").
- **(b) a Knowledge-ring gauge** that measures whether recall hits change outcomes.
- **(c) supersession, staleness and relatedness handled at recall time.**

The in-flight t-3510 and t-3511 work only fixes the memory-file semantic leg.
