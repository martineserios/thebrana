---
status: specified
task: t-3514
epic: t-3513
created: 2026-10-14
decision: docs/architecture/decisions/ADR-099-recall-bundle-and-usage-log.md
relates: ADR-038, ADR-057, ADR-058, ADR-069, ADR-095, docs/architecture/features/recall-memory-file-vectors.md, docs/architecture/features/local-vector-recall.md
---

# Feature: Recall bundle at build LOAD, usage log at CLOSE

**Date:** 2026-10-14
**Status:** specified — design accepted 2026-10-14; implementation in t-3516, t-3517 (shadow), t-3521 (canary)
**Task:** t-3514 (spec) → implementation t-3516, t-3517, t-3518; gates t-3515; ranking t-3519;
canary t-3521
**Decision:** [ADR-099](../decisions/ADR-099-recall-bundle-and-usage-log.md). This spec holds the
contract and the details; the ADR holds the decision and its reasons.
**Evaluation data:** [docs/research/recall-bundle/](../../research/recall-bundle/README.md): frozen gold set, pre-registered gates v1, measured baseline (t-3515).
**Shaping:** idea doc `docs/ideas/ruvector-integration-options.md` §Shape v2 (on branch
`docs/ruvector-integration-options`).

## Problem

`/brana:build` LOAD calls `brana recall` and gets about five untyped snippets. They have no
budget, no project scope and no supersession handling. Nothing records which recalled notes the
work used, so recall quality cannot be measured, the Knowledge-ring gauge does not exist, and the
staleness rule has no input.

## Decision Record

See [ADR-099](../decisions/ADR-099-recall-bundle-and-usage-log.md). It covers:
- the bundle at LOAD;
- scope (project + global, through `find_session_root`);
- supersession (ADR-057 first, derived only down-weights);
- fail-open behaviour with per-leg status;
- the per-project, ids-only, canonical usage log;
- outcomes asked only for shown bundles, checked by a command exit code;
- the shadow-then-canary rollout with kill-only shadow gates;
- exposure as an extra staleness input.

## Constraints

- No API key, no GPU, about 3 GB free RAM. Everything runs locally.
- `brana recall '<query>'` keeps its current behaviour and output byte for byte.
- No new store besides the usage log. The notes remain the source of record.
- Pointer, not paste. No note body enters the worker's prompt.
- Fail-open. A recall failure never blocks a build.
- The usage log never carries free text, and it never crosses the ADR-095 export boundary.

## Scope

- **Shadow (t-3516, t-3517, t-3518):**
  - `brana recall --bundle <task-id>`;
  - per-leg status in HybridProvider;
  - the usage log with offered rows, and `brana memory usage` (writer, `--report`, `--check`);
  - the LOAD shadow call;
  - the offline scorer.
- **Canary (t-3521):**
  - showing the bundle to some builds;
  - running `brana memory usage --check` at the build's exit step (CLOSE, ANSWER, REPORT);
  - outcome rows.
- **Out of scope:**
  - the headless autonomous runner (t-3525);
  - the in-process embedder (t-3522);
  - the ADR-057 backfill (t-3523);
  - the staleness rule's implementation (t-3524);
  - link repair; same-pattern-other-domain.

## Glossary

These terms are added to `docs/domain/MODEL-001-brana-core.md` §Ubiquitous Language (context
"Recall"); `CONTEXT.md` is regenerated from it.

| Term | Meaning | Avoid |
|---|---|---|
| **Recall bundle** | The at-most-8 typed pointers computed for one task at LOAD | context pack, recall results |
| **Pointer** | A note slug (or ADR reference) plus its `description` line; never the body | snippet, excerpt |
| **Offered row** | A usage-log record of the bundle computed for a task, with `shown` true or false | hit, impression |
| **Outcome row** | A usage-log record of which offered notes the work used and ignored; only for shown bundles | feedback, citation |
| **Exposure** | A note appearing in a bundle that was shown to the worker (`shown: true`) | recall hit |
| **Shadow mode** | Computing and logging the bundle without showing it | dry run |
| **Derived supersession** | A supersession signal inferred from a dated twin or prose, which only down-weights a note | superseded |

## Behavior

### Shadow (week 1)

1. A build with a task id starts. LOAD runs `brana recall '<query>'` as today, and also runs
   `brana recall --bundle <task-id> --shadow`.
2. The bundle command builds a query from the task (subject + tags + AC keywords). It runs the
   two legs (FTS5, vectors), fuses them, applies scope, type, supersession, quota and cut, and
   appends one `offered` row with `shown: false`. In shadow mode it prints nothing to the model.
3. Today's recall output is used unchanged. No outcome is asked at CLOSE.
4. `brana memory usage --report` prints offered-row counts, bundle sizes and per-leg degradation
   counts. The offline scorer (t-3518) reads the offered rows and the frozen gold set.

### Canary (week 2, t-3521)

5. For canary builds, LOAD runs `brana recall --bundle <task-id>` (shown), and the typed pointer
   list is added to the LOAD context. The offered row has `shown: true`.
6. At the build's exit step (CLOSE for feature, fix, refactor and migration; ANSWER for spike;
   REPORT for investigation), the worker runs
   `brana memory usage <task-id> --used <refs> --ignored <refs>`, or `--no-answer`. The CLI binds
   the row to the latest unresolved offered row for the task, and derives `opened` from the
   transcript path captured at LOAD (or records `unavailable`).
7. The exit step then runs `brana memory usage <task-id> --check`. It exits 2 when a shown,
   unresolved offered row exists, and the step stops and names the command to run.

### Bundle output (`--json`, printed to stdout, not stored)

```json
{
  "task": "t-NNN",
  "scope": {"project": "-home-…-thebrana", "global": true},
  "shown": true,
  "legs": {"fts": "ok", "vector": "timeout"},
  "pointers": [
    {"type": "pattern", "ref": "pattern_wave-pull-ignores-blocked-by-ordering",
     "gist": "wave pull selected t-2919 ahead of its blocker t-2920; …", "rank": 1, "flags": []},
    {"type": "decision", "ref": "ADR-079 §Pull", "gist": "frontier = ready ∧ unblocked ∧ unclaimed",
     "rank": 2, "flags": []},
    {"type": "pattern", "ref": "pattern_wave-pull-ordering-v1", "gist": null, "rank": 7,
     "flags": ["derived-superseded:pattern_wave-pull-ignores-blocked-by-ordering"]}
  ]
}
```

The human format is the typed list from the idea doc's solution overview: one line per pointer,
grouped by type, with flagged notes marked.

### Usage-log rows (`~/.claude/projects/<main-checkout>/brana/recall-usage.jsonl`)

Ids only. No query text, no gists, no note bodies.

```json
{"v":1,"kind":"offered","id":"o-<ulid>","task":"t-NNN","ts":"2026-10-20T10:02:11Z",
 "shown":false,"legs":{"fts":"ok","vector":"ok"},"elapsed_ms":740,
 "pointers":[{"ref":"pattern_…","type":"pattern","rank":1,"flags":[]}]}
{"v":1,"kind":"outcome","offered":"o-<ulid>","task":"t-NNN","ts":"2026-10-20T11:40:02Z",
 "answer":"given","used":["pattern_…"],"ignored":["feedback_…"],"opened":["pattern_…"]}
```

- `answer` is `given` or `no-answer`. A `given` answer with an empty `used` means "used none".
- `opened` holds refs, or the string `unavailable`.
- An outcome names its offered row by `id`. A re-pulled task gets a new offered row, and nothing
  is overwritten.

## Design

```
 task t-NNN ─> query (subject + tags + AC keywords), sanitised as brana recall does (t-2293)
                 │
                 ▼  HybridProvider: FTS5 leg (500 ms) + vector leg (2 s), RRF (ADR-058)
            ~40 candidates  +  per-leg status {ok | timeout | error}
                 │
   1 scope      keep main-checkout project dir + global; drop other projects, archive*/
   2 type       metadata.type → top-level type → filename prefix → "note"
   3 supersede  ADR-057: drop status:superseded and supersedes-targets
                derived: older dated twin, prose "superseded by [[x]]" → ×0.5 weight + flag
   4 quota      ≤3 per type (v1); MMR in t-3519 if gated
   5 cut        ≤8 pointers; gist = description or null
                 │
                 ▼
          usage_log::append(offered)  →  print (shown) | silent (shadow)
   any error: empty or partial bundle, offered row with legs marked, exit 0
```

- **Code locations:**
  - `brana-core/src/search.rs`: HybridProvider returns per-leg status alongside results, instead
    of `unwrap_or_default` discarding a timed-out leg (search.rs:252-254). The legs and the
    deadlines are injectable for tests. Today's `query()` output is unchanged; status is a new,
    additive accessor.
  - New `brana-core/src/recall_bundle.rs`: stages 1–5 as pure functions over candidates.
  - New `brana-core/src/usage_log.rs`: the only writer. It reuses the lock-sidecar and
    single-`write_all` append pattern from `brana time` (time.rs:171-200).
  - `brana-cli/src/commands/recall.rs`: the `--bundle` and `--shadow` flags.
  - `brana-cli`, memory command: `memory usage` (outcome writer, `--report`, `--check`).
  - `brana-mcp/src/tools/recall.rs`: an optional `bundle_task` parameter calling the same core
    function, with no shell-out (ADR-058 §8).
- **Main-checkout resolution:** reuse `brana_core::util::find_session_root` (util.rs:298, ADR-069
  D0b) and the dual project-dir encoding in `brana time` (`encode_project_path` and
  `encode_project_path_legacy`, time.rs:80-92). Claude Code currently maps `/` and `_` to `-`,
  the legacy encoding maps only `/`, and both exist on disk. Move the encoders to `brana-core` if
  they need to be shared; do not write a third.
- **Transcript path for `opened`:** captured at LOAD the same way `brana time start` captures it
  (time.rs:65-74, newest-mtime `.jsonl` in the project's transcript dir), and stored on the
  offered row as a local path. Concurrent sessions can make this pick the wrong file, so `opened`
  is advisory and never used as gold. Subagent reads are not counted.
- **Skill wiring (canary only):** LOAD step 2 shows the bundle; the exit steps in `close.md` and
  `strategies.md` (spike ANSWER, investigation REPORT) run the outcome and `--check` commands.
  In shadow mode, only LOAD step 2 gains a silent call.

## Edge Cases

- **No task id** (freeform build): no bundle and no row. LOAD proceeds as today.
- **Task with no tags and a one-word subject:** the bundle may be empty. Log the row anyway, since
  an empty bundle is data.
- **Both legs time out:** empty bundle, row with both legs `timeout`, exit 0.
- **Concurrent sessions on one machine:** the lock serialises appends, and rows are independent
  lines.
- **Same task pulled twice** (lease expiry, retry, resume in a new session): two offered rows. The
  outcome binds to the latest unresolved one.
- **Note deleted or renamed** between offer and outcome: the outcome keeps the ref as text. The
  scorer treats unknown refs as "used, unresolvable" and does not drop them silently.
- **Note from another client named explicitly by the ticket:** still excluded from the bundle. The
  ticket's own pointer stands on its own.
- **Spike and investigation builds:** shadow rows have no outcome by design. In the canary, ANSWER
  and REPORT run the outcome step. Builds that end without any exit step are counted as
  `no-exit` and kept out of the use-rate denominator.
- **Client project (tabz) on the owner machine:** its log sits in its own project folder and is
  excluded from export by the existing folder glob. On the company Mac, the log is local and
  nothing syncs it (ADR-095).
- **Project path containing `_`:** resolved by the dual encoder. A fixture covers it.
- **Transcript scanners:** `brana time`'s newest-`*.jsonl` picker (time.rs:126) and
  `brana skills usage` (skills.rs:445-475) read the top level of every project folder, which is
  where Claude Code writes transcripts. The log lives in the `brana/` subfolder so neither scanner
  sees it. A test asserts the picker still returns the transcript after a log append.
- **Other skills with a LOAD step** (`/brana:fix`, brainstorm, research, review): they keep plain
  `brana recall` in v1. Only `/brana:build` LOAD calls `--bundle`, so these skills write no offered
  rows and need no outcome step. Extending the bundle to them is a separate decision after the
  canary.

## Boundaries

| Always | Ask first | Never |
|---|---|---|
| Write an offered row for every bundle, including empty and failed ones | Changing the bundle cap (8) or the per-type quota | Paste note bodies into a prompt |
| Fail open with exit 0 | Showing the bundle to the worker (that is t-3521's canary) | Put query text or gists in the log |
| Keep `brana recall '<query>'` output unchanged | Adding a new leg or engine | Include other projects' or clients' notes |
| Go through `usage_log::append` | Syncing or backing up the log outside the per-folder exclusions | Ask for an outcome on a bundle that was not shown |

## Testing Strategy

Tests are written first in t-3516 and t-3517. Fixtures are small synthetic memory dirs and a
fake `$HOME`, not the live store.

- **Unit (bundle stages, pure):**
  - type derivation from flat frontmatter, from the `metadata:` block, and from the filename
    prefix when frontmatter is missing;
  - ADR-057 `status: superseded` dropped; `relations` supersedes-target dropped; an older dated
    twin down-weighted and flagged, not dropped; prose "superseded by [[x]]" flagged;
  - quota ≤3 per type; cut ≤8; gist null when `description` is missing;
  - scope: a note in another project dir is excluded (**must-fire**: the test fails if the filter
    is removed); `archive*/` excluded; a worktree path resolves to the main-checkout project dir,
    including a fixture root whose path contains `_` (both encodings).
- **Unit (HybridProvider status):** with injected legs and deadlines, a leg that sleeps past its
  deadline reports `timeout`, and the results equal today's `query()` output. Runs in
  milliseconds through an injected short deadline, not by waiting out real deadlines.
- **Unit (usage log):**
  - row shapes (`v`, `kind`, the `answer` enum, `opened` = refs or `unavailable`);
  - no field contains query text (an assertion over a row built from a query with a known
    sentinel string);
  - two concurrent appends produce two parseable lines;
  - after a log append, `brana time`'s transcript picker still returns the transcript, not the
    log (fixture project folder with one transcript `.jsonl` and the `brana/` subfolder);
  - an outcome binds to the latest unresolved offered row.
- **Integration:**
  - `brana recall --bundle --shadow` against a fixture gives one offered row, nothing on stdout,
    exit 0;
  - with one leg forced to time out, `legs` is marked and exit is 0;
  - `brana recall '<query>'` output is unchanged (snapshot);
  - `brana memory usage --check` exits 0 with no shown rows, exits 2 with a shown unresolved row,
    and exits 0 after an outcome is written.
- **Scorer (t-3518):** reproducible numbers on a fixed fixture gold file (same input gives the
  same hit@K and MRR); INCONCLUSIVE below minimum n.
- **Mock policy:** use real SQLite FTS on fixture dirs. Fake only the embedder (a fixed-vector
  stub at the process boundary) and the leg timing (injected).

## Documentation Plan

- [ ] **Tech doc:** this spec, moved to `status: implemented` with the shipped flags (t-3520).
- [ ] **User guide:** a short section in `docs/guide/workflows/memory.md` on
      `brana memory usage --report` and, in the canary, what the exit step asks (t-3520).
- [ ] **Existing docs to update** (t-3520, plus t-3521 for the canary wiring):
  - `system/skills/build/phases/load.md` step 2;
  - `system/skills/build/phases/close.md` and `system/skills/build/phases/strategies.md` (the
    exit-step outcome and `--check`, canary only);
  - `docs/guide/workflows/drain-loop.md` and `docs/guide/workflows/epic-drain.md`, where the
    procedure lives (`system/loops/*` are catalog pointers);
  - `docs/architecture/the-brana.md` and the guide's Knowledge-ring row (from design to partial);
  - `system/rules/memory-decay-by-non-use.md` (exposure added as an input, not a replacement);
  - the `brana recall` / `brana memory` CLI reference (regenerated);
  - `docs/architecture/decisions/ADR-058` changelog (the per-leg status amendment).
- [ ] **Backup:** the log is never backed up (ADR-099 §5). t-3517 adds a test in the
      `brana-knowledge` repo asserting `backup.sh` never copies it.
- [ ] **Gold set and miner:** t-3515 commits the frozen gold file and documents
      `docs/ideas/ruvector-integration-options/scripts/mine_pairs.py`'s limits (no field split,
      no time order).

## Surface (files this work touches)

| File | Task | Change |
|---|---|---|
| `system/cli/rust/crates/brana-core/src/search.rs` | t-3516 | per-leg status, injectable legs and deadlines |
| `system/cli/rust/crates/brana-core/src/recall_bundle.rs` (new) | t-3516 | bundle stages |
| `system/cli/rust/crates/brana-core/src/usage_log.rs` (new) | t-3517 | single writer |
| `system/cli/rust/crates/brana-core/src/util.rs` | t-3516 | reuse `find_session_root`; host shared encoders if moved |
| `system/cli/rust/crates/brana-cli/src/commands/time.rs` | t-3516 | encoders moved to core (if shared) |
| `system/cli/rust/crates/brana-cli/src/commands/recall.rs`, `cli.rs`, `main.rs` | t-3516 | `--bundle`, `--shadow` |
| `brana-cli` memory command module | t-3517 | `memory usage` (writer, `--report`, `--check`) |
| `system/cli/rust/crates/brana-mcp/src/tools/recall.rs` | t-3521 | optional bundle parameter (canary only; MCP has no shadow mode) |
| `system/skills/build/phases/load.md` | t-3517 / t-3521 | shadow call, then shown call |
| `system/skills/build/phases/close.md`, `strategies.md` | t-3521 | outcome + `--check` at exit steps |
| `system/rules/memory-decay-by-non-use.md` | t-3520 | exposure as an added input |
| `docs/guide/workflows/{drain-loop,epic-drain}.md` | t-3520 | mention recall at LOAD |
| `docs/domain/MODEL-001-brana-core.md`, `CONTEXT.md` | t-3514 | glossary |
| `brana-knowledge/backup.sh` (other repo) | t-3517 | test: never copies `recall-usage.jsonl` |
| `system/cli/rust/crates/brana-core/src/vector.rs` | t-3516 | status-returning query (`error` on missing DB or embedder) |
| `system/cli/rust/crates/brana-cli/src/commands/handoff.rs`, `brana-core/src/session.rs` | t-3516 | encoder copies consolidated into core |
| `system/hooks/session-start.sh` (Job 1c recall) | none | out of scope in v1: keeps plain `brana recall` |
| `docs/ideas/ruvector-integration-options/scripts/mine_pairs.py`, gold file | t-3515 | frozen gold |
| Not touched | none | `autonomous-runner.sh`, `lib/sandbox-claude.sh`, beat-record schema, `beats.jsonl` consumers |

## Assumptions

- **Log location:** chose one file per project at `~/.claude/projects/<main-checkout>/brana/recall-usage.jsonl`
  because client rows then stay inside the folder that `backup-exclude.txt` already excludes, and
  no memory tool globs outside `memory/`. Needs confirmation.
- **Gist:** `description` only, else null. A first body line was rejected as too noisy (challenger
  C7).
- **Quota v1:** ≤3 per type before any gated tuning. t-3519 may change it, but only through the
  gates.
- **`opened` is advisory.** It is best-effort from the newest transcript and is never used as gold.

## Gate-2 amendments (normative)

Applied after the BUILD-exit challenger gate (PROCEED WITH CHANGES). Where earlier sections of this
spec conflict, this section and ADR-099 win.

- **Per-leg status** is `ok`, `empty`, `timeout` or `error`. `SearchProvider` gains a
  status-returning method implemented by FTS5 and `vector.rs`. A missing index or embedder is
  `error`. The scorer keeps degraded bundles apart.
- **Knowledge-store rows** (no path, no scope) are left out of the bundle in v1. t-3510 blocks
  t-3516.
- **Log:** mode 0600; never synced or backed up; transcript reference stored as the session-file
  stem.
- **Outcome refs** must appear in the bound offered row's pointers; anything else is rejected. The
  no-free-text sentinel test covers outcome rows too.
- **`--check`** looks only at the latest shown offered row for the task. Older unresolved rows are
  reported as orphans and never block.
- **MCP bundle parameter** moves to t-3521 (canary), because MCP output is always shown.
- **Canary arms** are assigned by a hash of the task id. Tokens per run, retries and AC pass rate
  are compared across arms. Use rate is measured in the shown arm only, reported with `no-answer`
  and `no-exit` counts and never with them dropped.
- **Staleness:** zero exposure means unmeasured, not a candidate. A candidate needs exposure ≥ N
  (pre-registered) and zero use.
- **Gist** is capped at 160 characters.
- **Encoders:** the copies in `brana time`, `handoff.rs` and `session.rs` are consolidated into
  `brana-core`. The log is written under the current encoding, and `--check` reads both encodings.

## Slice A delivered (t-3535, 2026-10-15)

t-3516 is built in three slices: t-3535 (this foundation), t-3536 (index freshness), t-3537
(the bundle). Slice A landed these interfaces for the bundle to use:

- **Per-leg status:** `SearchProvider::try_query` returns `Err` when a leg cannot search
  (missing index or store, no query embedding, store read error).
  `HybridProvider::query_with_status` returns the hits plus
  `HybridStatus { keyword, semantic, extras }` of `LegStatus` (`ok | empty | timeout | error`).
  A leg whose thread dies is `error` and does not wait out the deadline. `query()` is unchanged.
- **Scope is a provider parameter:** `recall_provider(fts, knowledge, embedder, RecallScope)`.
  The bundle passes `RecallScope::current_project()`; plain `brana recall` and MCP pass `All`
  (decision 2026-10-15: no change to plain recall's default; `brana recall --scope project`
  opts in). The keyword leg filters in SQL and the memory-vector leg filters before scoring,
  so out-of-scope notes never take top-k slots. An unresolvable project narrows to global only.
- **Encoders:** `brana_core::util::encode_project_dir` / `encode_project_dir_legacy` are the
  only copies; `session.rs`, `handoff.rs` and `brana time` call them. They fold `/` and `_`
  and keep `.`, which matches the folder names on disk (checked 2026-10-15: `.` and `_` are the
  only characters other than letters, digits and `-` in `~/.claude/projects`).
- **Boundary — worktree-keyed folders:** Claude Code also keys folders by a session's own cwd,
  so a session started inside a worktree writes to `<main-checkout-encoding>-<suffix>/memory`.
  These are out of `Project` scope. Checked 2026-10-15: 161 such folders exist for this repo and
  none holds a note (only `MEMORY.md` indexes, which recall skips). Revisit if notes appear there.
- **Failure semantics:** the vector leg skips a row it cannot read and is `error` only when no
  row can be read; the keyword leg opens the index read-only, so a missing index is `error` and
  is never created by a search.

## Index freshness (amendment 2026-10-14, ADR-099 §4a)

- **Gap:** `index.db` is rebuilt weekly (scheduler `reindex-patterns`, Sunday) as a full
  drop-and-rebuild, and memory-file vectors exist only after `embed-memory`. Notes written since
  are missing from the bundle.
- **Check** (superseded by §Index freshness — design below: per-file state, not build time):
  before querying, compare the newest in-scope `*.md` mtime with the index build time
  (stored in `index.db` metadata). Upsert only the newer files into FTS (a new incremental path in
  `brana-core/src/memory.rs`; today's reindex only rebuilds everything). The check counts toward
  the fail-open budget; on timeout the bundle proceeds on the stale index and says so.
- **Deletions:** the same check drops index entries whose file no longer exists, so a deleted or
  renamed note never reaches the bundle. The weekly full rebuild stays as a safety net, not as
  the freshness mechanism; more frequent rebuilds only shrink the window and would still miss
  notes written in the current session.
- **Row fields:** offered rows add `index_age_s`, `stale_notes`, `unembedded`.
- **Tests (t-3516):** a note written after the index build is found by the bundle (must-fire:
  fails if the check is removed); `stale_notes` counts it; a forced-slow upsert falls back to the
  stale index with exit 0.
- **Surface:** `brana-core/src/memory.rs` (incremental upsert, build-time metadata).

## Index freshness — design (t-3536, 2026-10-15)

- **Change tracking, per file:** `index.db` gains `memory_files(path, mtime_ns, size)` and
  `memory_meta(key, value)` (`refreshed_at`, unix seconds). A full rebuild rewrites both in the
  same transaction as `memory_fts`. Tracking each file's own mtime and size, not "newer than the
  build", also catches edits and files copied in with an old mtime.
- **Refresh (`memory::refresh_fts_dirs(dirs, db, budget) -> FreshnessReport`):** lists the in-scope
  folders; a note whose stat differs from `memory_files` (or is absent there) is stale and is
  re-indexed (delete by path, insert); an indexed row under a folder that listed completely whose
  file is gone is dropped. A folder that is missing or could not be listed changes nothing.
  One transaction; nothing is written when nothing is stale.
- **Unreadable note (decision 2026-10-15):** skipped; its previous row stays as it was and it is
  counted in `unreadable`. Every other change still lands.
- **Budget and locks:** the stale count is always taken (stats only, no write lock). Then, in one
  transaction, notes are read and written one by one while the budget lasts; the lock wait is
  the remaining budget. Over budget: what was written commits and the rest waits for the next
  call (`outcome: stale/timeout`, `refreshed_notes` < `stale_notes`). The first note always goes
  through, so a backlog larger than one budget converges over calls instead of rolling back
  forever; each note is written whole, so partial progress leaves a consistent index. A zero
  budget checks and writes nothing. Locked longer than the budget, or any write error: roll back,
  keep the stale index, report the reason. It never returns an error.
- **Measured 2026-10-15** (copy of the live index, 402 in-scope notes, release build): first
  refresh of an index from the deployed binary 224 ms (1.33 s before deleting FTS rows by rowid:
  `path` is UNINDEXED, so a delete by path scans the table); a fresh check ~7 ms;
  `unembedded_count` ~215 ms.
- **Who calls it (decision 2026-10-15):** the bundle only (t-3537). Plain recall and MCP stay
  read-only.
- **Report fields** (as the check found the index, before any refresh): `index_age_s` (since
  `refreshed_at`; absent for an index built before this change), `stale_notes`, `deleted_notes`,
  `unreadable`, `refreshed_notes`, `outcome` (`fresh | refreshed | stale`
  plus a reason: `timeout | busy | unreadable | error`). `unembedded` comes from
  `memory_vectors::unembedded_count` (below).
- **Deleted** means the full rebuild's rule: an indexed note directly inside a folder that
  listed completely whose path is no longer a listed note (gone, renamed, or taken over by
  something that is not a note). Only files are notes; a folder named `x.md` is not one.
- **Racily clean:** a note modified within 2 s of the moment its state is recorded is recorded
  as suspect and re-read once on the next check, so a same-size rewrite inside one filesystem
  clock tick is not missed (git's approach).
- **Lock waits are re-armed from the remaining budget before every statement**; the commit alone
  gets a fixed 200 ms grace so written notes are not thrown away while a reader finishes. That
  grace is the most a refresh can overrun its budget.
- **Unreadable notes are found before the write lock**, so a note that stays unreadable never
  makes a refresh lock the index for nothing; the progress guarantee counts the first *readable*
  note.
- **`index_age_s`** is the time since the last write to the index by any scope (a refresh for
  another project, or a partial commit, resets it). `stale_notes` is the signal for "this scope
  was out of date".
- **Folder spelling:** `dirs` must be spelled exactly as the indexer spells them
  (`memory::memory_dirs_in` / `RecallScope::project_in` both derive from `home()`); a differently
  spelled folder (a symlinked home) would see every note as new.
- **Symlinked notes** are followed, as in the rebuild and `embed-memory`; the refresh only makes
  their text reach the bundle sooner (per call, not per week). Changing that is a policy
  decision, not part of this slice.
- **`unembedded_count`** uses the embedder's own rule (same text and current `EMBED_VERSION`;
  shared function), not mtime, and takes the caller's lock wait.
- **Indexes from older binaries** have no `memory_files`: the first refresh treats every in-scope
  note as stale and re-indexes it once. Deleted-note detection reads `memory_fts` paths, so it
  works on old indexes too.
- **Lock waits elsewhere:** the full rebuild and the keyword search keep rusqlite's default 5 s
  lock wait (a refresh holds the lock for milliseconds; the search leg's 500 ms deadline already
  bounds what recall waits). Only the refresh shortens its wait, to the remaining budget, because
  the default would overrun it.

## Challenger findings

**Shaping review (idea doc, 2026-10-14):** three lenses, H1–H4 and C1–C8, all incorporated before
this spec was written.

**Spec review (2026-10-14, one challenger, verdict RECONSIDER (narrow)).** The main session
checked each claim against the code before any fix was applied.

| # | Finding | Severity | Resolution |
|---|---|---|---|
| 1 | "CLOSE refuses" was prose with no enforcement, and in shadow mode it asked about notes the worker never saw | CRITICAL | No outcome in shadow mode. In the canary, the exit step runs `brana memory usage --check` (exit 2). ADR-099 §6 |
| 2 | A global log with query text, backed up by `backup.sh`, would bypass the per-folder ADR-095 export exclusions | CRITICAL | Log is per project folder, ids only (no query, no gist); any backup reuses `backup-exclude.txt`. ADR-099 §5 |
| 3 | No reliable session id (`BRANA_SESSION_ID` not exported); model-typed `opened` | WARNING | Outcome binds to the latest unresolved offered row; `opened` derived by the CLI from the transcript path captured at LOAD, or `unavailable`; advisory only |
| 4 | Main-checkout resolution omitted the dual encoding (`_` → `-`) | WARNING | Reuse `find_session_root` and the `brana time` encoders; fixture with `_` |
| 5 | "search.rs unchanged" contradicted per-leg status; three legs named where production has two; no timeout seam; 10 s budget untestable | WARNING | search.rs gains additive per-leg status and injectable legs/deadlines; two legs; 10 s budget dropped in favour of the ADR-058 deadlines |
| 6 | Spike and investigation have no CLOSE; ADR §8 narrowed the decay rule | WARNING | Outcome step also at ANSWER and REPORT; builds without an exit step counted as `no-exit`; exposure is an added input, not a replacement |
| 7 | (gate, second-variant finder) A top-level `.jsonl` in the project folder collides with `brana time`'s transcript picker and `brana skills usage` | 4 | Log moved to the `brana/` subfolder; picker test added; rule stated: brana-owned files never sit at the top level of a Claude Code project folder |
| 8 | (gate, second-variant finder) `/brana:fix`, brainstorm, research and review share build's LOAD pattern | 2 | Stated as v1 non-scope: only build LOAD calls `--bundle`, so they write no offered rows |
| 9 | (gate 2) Per-leg `error` unproducible; MCP shows bundles in shadow; canary arms and metrics undefined; outcome refs free text; backup self-contradiction; zero-exposure demotion | 3 each | See Gate-2 amendments above and ADR-099 §4–8 |
| — | No Non-actions section; evidence link not on this branch | OBSERVATION | Non-actions added; the evidence link is marked to merge before acceptance |
