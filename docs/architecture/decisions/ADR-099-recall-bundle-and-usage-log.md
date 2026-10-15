---
status: proposed
amends: docs/architecture/decisions/ADR-058-search-provider-hybrid-recall.md
respects: docs/architecture/decisions/ADR-038-memory-write-gateway.md, docs/architecture/decisions/ADR-057-unit-of-knowledge.md, docs/architecture/decisions/ADR-078-stale-task-park-via-tag.md, docs/architecture/decisions/ADR-086-wave-as-human-unit-pocock-ticket-shape.md, docs/architecture/decisions/ADR-095-two-machine-memory-sync.md
---

# ADR-099: Recall bundle at build LOAD, usage log at CLOSE

**Status:** Proposed (2026-10-14). Design only; implementation is t-3516 (bundle flag),
t-3517 (usage log), t-3518 (scorer), t-3521 (canary).
**Date:** 2026-10-14
**Deciders:** Martín Rios
**Tags:** recall, memory, knowledge-ring, measurement, pocock-tie-break
**Task:** t-3514 (epic t-3513 `recall-bundle`)
**Evidence:** idea doc `docs/ideas/ruvector-integration-options.md` (on branch
`docs/ruvector-integration-options`, to be merged before this ADR is accepted): Appendix A (memory layers), Appendix B (architecture
read), Round 6b (frontmatter census), Challenger review H1–H4 and C1–C8, Shape v2.
**Spec:** [recall-bundle.md](../features/recall-bundle.md)

---

## Context

Every `/brana:build` run, interactive or pulled by a supervised drain, starts with LOAD, which
calls `brana recall` (`system/skills/build/phases/load.md` step 2; a LOAD checkpoint is recorded
in 25 of 28 run-state files). What LOAD gets back is an untyped list of snippets with no budget,
no project scope and no notion of supersession. Nothing records which recalled notes the work
used, so nothing can tell whether recall helps (the guide's Knowledge-ring gauge: "nothing yet
measures whether accumulated knowledge is any good"). The staleness rule
(`system/rules/memory-decay-by-non-use.md`) depends on a recall-hit log that nothing writes.

Measured facts that shape the decision (2026-10-14): 1,107 in-scope memory notes; 28% have no
frontmatter; `status` appears once and `supersedes` never; 71% carry a `description` line;
recall runs about 0.6–0.9 s, of which the vector scan is about 0.5%. Engine choice (RuVector HNSW
and similar) does not move precision at this scale.

Pocock tie-break (2026-10-07): the ticket body, `CONTEXT.md` and ADRs remain the worker's
instruction. Recall adds only what his single-session scope lacks, which is knowledge from earlier
sessions, and adds it as pointers.

## Decision

1. **A recall bundle at LOAD.** A new flag, `brana recall --bundle <task-id>`, returns at most
   8 pointers grouped by type (pattern, feedback, decision, project, reference). A pointer is a
   slug or ADR reference plus the note's `description` line; a note without `description` is
   shown as its slug alone. Note bodies are never pasted.
   - It builds on the existing HybridProvider and RRF fusion (ADR-058): two legs, FTS5 keyword
     and local vectors, with knowledge rows inside the vector store. Steps run after fusion; no
     new engine.
   - It is a flag, not a subcommand, because `brana recall` takes a positional query and a
     `bundle` subcommand would capture queries that begin with that word.
2. **Scope is the current project plus global.**
   - "Current project" is the memory directory of the repository's main checkout plus
     `~/.claude/memory/`. It is resolved with the existing `find_session_root` (ADR-069 D0b) and
     the dual project-dir encoding already used by `brana time`. No new encoder is added.
   - Other projects' and clients' notes never appear, and archived notes (`archive*/`) stay out.
     A must-fire test proves an other-client note is excluded.
   - This scope is the bundle's. Plain `brana recall` and MCP `recall` keep every project by
     default; the scope is a `recall_provider` parameter and `brana recall --scope project`
     opts in (decision 2026-10-15, t-3535).
   - Candidates without a file path and scope (knowledge-store rows from links and feeds) are left
     out of the bundle in v1, because their project cannot be checked. They still reach LOAD
     through plain `brana recall`. The memory-file vector leg comes from t-3510, which blocks
     t-3516.
3. **Supersession is read first and derived second.**
   - ADR-057's fields are authoritative where present: a note with `status: superseded`, or the
     target of a `relations: supersedes` edge, is dropped.
   - Derived signals only down-weight and flag a note, never drop it. These are an older dated
     twin of the same slug, and a prose "superseded by [[x]]" line. Dated files exist for
     parallel-write safety (ADR-038 §A), so recency alone is not supersession.
4. **The bundle fails open and says which legs failed.**
   - The per-leg deadlines of ADR-058 §9 bound the call. Per-leg status is `ok`, `empty`,
     `timeout` or `error`. HybridProvider can see only a timeout, so `SearchProvider` gains a
     status-returning method that FTS5 and the vector provider implement: a missing index, a
     missing embedder or an open failure is `error`, not `ok` with zero hits. A degraded bundle is
     then visible, and the scorer can keep degraded bundles apart.
   - Any failure yields an empty or partial bundle and exit 0, and the build continues.
4a. **The bundle checks index freshness before it queries.** (Amendment 2026-10-14.)
   - The keyword index (`index.db`) is rebuilt weekly and the memory-file vectors only when
     `embed-memory` runs, so notes written since then are invisible, and those are often the most
     relevant ones. A write-path trigger cannot close this, because the model writes auto-memory
     files directly (ADR-038 exempts them from the gateway).
   - At bundle time, any in-scope `*.md` whose modification time is newer than the index build is
     upserted into the FTS index first (incremental, bounded to those files, inside the same
     fail-open budget). Notes without vectors stay keyword-only until `embed-memory` runs (t-3511).
   - The same check drops index entries whose file is gone. The weekly full rebuild remains a safety
     net; rebuilding more often would only shrink the blind window, not close it.
   - Every offered row records `index_age_s`, `stale_notes` (count reindexed) and `unembedded`
     (in-scope notes without vectors), so the scorer separates "index was stale" misses from
     ranking misses.
5. **The usage log is canonical, local and free of free text.**
   - Rows live at `~/.claude/projects/<main-checkout>/brana/recall-usage.jsonl`, one file per
     project. The top level of a project folder belongs to Claude Code's session transcripts, and
     brana's own scanners (`brana time`'s transcript picker, `brana skills usage`) read every
     `*.jsonl` there, so brana-owned files live in the `brana/` subfolder and never at the top
     level. The file is also outside `memory/`, so no memory tool reads it. A client project's log sits in
     that client's folder, so the export exclusions of ADR-095 (`backup-exclude.txt`, which
     works per folder) apply unchanged.
   - Rows carry ids only: task id, note refs, ranks, leg status, timestamps. They never carry
     query text or gists.
   - The log is append-only through one writer module in `brana-core`, serialised with the
     existing lock-sidecar pattern. Its callers are the bundle function and `brana memory usage`.
     The MCP recall tool gains a bundle parameter only with the canary (t-3521), because MCP
     output is always shown and has no shadow mode.
   - A bundle is ranker output at one moment and cannot be rebuilt later, so the log is a record
     of events. It is per machine, created with mode 0600, and **never synced or backed up**: the
     `brana-knowledge` backup goes to a repository the company Mac clones (ADR-095), and a test
     asserts `backup.sh` never copies `recall-usage.jsonl`. Losing the log loses measurement
     history only, never knowledge.
   - The transcript reference on an offered row is the session file's stem, not an absolute path.
6. **The worker is asked only about what it was shown.**
   - In shadow mode, no outcome is asked and none is required. Shadow is scored offline.
   - Once the bundle is shown (canary, t-3521), build CLOSE runs
     `brana memory usage <task-id> --check`. That command exits non-zero when a shown bundle has
     no outcome row, so the refusal is a command's exit code rather than prose. "Did not answer"
     is recorded as a value distinct from "used none".
   - The outcome binds to the latest unresolved **shown** offered row for the task, not to a
     session id, because builds resume across sessions. `--check` looks only at that row; older
     unresolved rows from re-pulls are reported as orphans and never block.
   - `--used` and `--ignored` accept only refs that appear in that offered row's pointers. Anything
     else is rejected, so outcome rows stay ids-only and a typo cannot be credited as use.
   - `opened` is derived by the CLI from the transcript path captured at LOAD (the `brana time`
     pattern) or recorded as unavailable. It is never typed in by the model.
   - Spike and investigation builds, which have no CLOSE, get the same step at ANSWER and REPORT.
7. **Rollout goes shadow, then canary.**
   - In shadow mode, LOAD keeps today's recall, and the bundle is only computed and logged with
     `shown: false`.
   - Shadow results are scored offline against a hand-labelled, frozen gold set and against two
     baselines: today's `brana recall` on subject+tags, and the pointers already in the ticket.
     Shadow gates can **only kill** the bundle. Below the pre-registered minimum n, the verdict is
     INCONCLUSIVE.
   - **Keep** is decided only by a canary in which the bundle is shown to some builds.
     - Arm assignment is deterministic per task (a hash of the task id), so a re-pulled task stays
       in its arm.
     - Compared across arms: tokens per run, retries, and AC pass rate. Both arms log offered rows,
       so both have the same denominator.
     - Measured in the shown arm only: use rate (used ÷ shown pointers), reported together with
       the `no-answer` and `no-exit` counts, never with them dropped from the denominator.
     - Thresholds over these measures are pre-registered before any scored run (t-3515).
8. **Exposure is recorded separately from use, and is one input among others.**
   - `shown: true` rows record exposure. A note with zero exposure is **unmeasured**, never a
     demotion candidate. A candidate needs exposure of at least a pre-registered N and zero use, so
     a note is never demoted for having been unranked or for appearing only in shadow rows.
   - This adds to `memory-decay-by-non-use.md`'s recall-hit signal and does not narrow it. A
     plain `brana recall` hit counter, if one is built, stays a separate input.

## Considered options

- **Reindex on `brana memory write` only.** Rejected for freshness: it misses every note the model
  writes directly with the Write tool. The bundle-time check covers all writers.

- **Write the bundle into the task's `context`.** Rejected. ADR-086 §7 allows pointer appends,
  but a bundle is ranker output that goes stale as notes change; frozen in the ticket it becomes
  an outdated assertion (retrieval-routing rule 4). It is computed at pull time instead.
- **A used/ignored field on the beat record.** Rejected. The beat record is per beat and its
  schema is single-sourced (`loops-library.md` §Beat record). The headless runner discards worker
  stdout, and supervised beat records are never persisted. The build's exit step (CLOSE, ANSWER
  or REPORT) runs once per task.
- **One global log under `~/.claude/memory/`.** Rejected after the spec review. It would mix
  client rows into the owner's stores and bypass the per-folder export exclusions.
- **Ask for used/ignored in shadow mode.** Rejected. The worker never saw the bundle, so every
  answer would be "no answer" or made up from plain-recall overlap.
- **Derive supersession from the newest dated file per slug.** Rejected. This misreads ADR-038,
  where newest-per-slug only picks the MEMORY.md line, and it would add a second signal for state
  that ADR-057 already models (ADR-078 rejects parallel signals).
- **Inject the bundle immediately.** Rejected. An unmeasured bundle is a token and noise cost on
  every build. This is the ruflo trial lesson: +105% to +137% tokens with zero learning.
- **A faster engine first (persisted RuVector HNSW).** Deferred. The scan is about 0.5% of a
  recall call at 7.7k vectors. Revisit near 50k–100k vectors. The in-process embedder is a
  separate speed spike (t-3522).

## Non-actions

- The beat-record schema, `beats.jsonl` consumers, the headless autonomous runner and its sandbox
  are not touched. Recall for the runner is decided separately (t-3525).
- No note is rewritten. The ADR-057 backfill is a separate task (t-3523).
- `brana recall '<query>'` keeps its output byte for byte.
- No cross-machine sync of the usage log.
- Only `/brana:build` LOAD calls `--bundle`. `/brana:fix`, brainstorm, research and review keep
  plain `brana recall` in v1, so they write no offered rows and need no outcome step.

## Consequences

- LOAD gains one call. In the canary, the build's exit step gains one checked command.
- The usage log becomes the benchmark source, the Knowledge-ring gauge and an exposure input to
  staleness. These were three documented gaps, and one mechanism now closes them.
- ADR-058 is amended: HybridProvider reports per-leg status, and recall gains a post-fusion
  bundle stage and a per-call usage record. Its provider and deadline sections stand.
- `brana-knowledge/backup.sh` must never copy the log (a test asserts it).
- Three copies of the project-dir encoder already exist (`brana time`, `handoff.rs`,
  `session.rs`); t-3516 consolidates them into `brana-core` rather than adding a fourth.
- ADR-057's `status`/`supersedes` vocabulary is recorded as unused in practice. The backfill is
  t-3523.
