# Feature: Time Tracking — Metric 1 (Active Effort)

**Date:** 2026-08-17
**Status:** shipped
**Task:** t-2921 (tests, this spec) · t-2922 (implementation)

## Problem

ADR-083 decided the design for active-effort time tracking (turn-delta summation with a
15-min idle cap, many-sub-spans bracket model, `brana/time/` storage). This spec covers
*how* to implement it in the Rust codebase — module layout, which existing helpers to
reuse vs. what's genuinely new, and the test plan (t-2921, blocks t-2922).

## Decision Record (frozen 2026-08-17)

> Do not modify after acceptance.

**Context:** ADR-083 is accepted and settles the architecture. `system/cli/rust/crates/brana-core/` already has two close precedents — `receipt.rs` (atomic writes, git-common-dir storage, H2 git-env scrub, pure/I/O split) and `queue.rs` (locked read-modify-write, concurrent-write stress tests, lightweight versioned JSONL schema) — that this feature composes from rather than reinventing.

**Decision:**
1. **Module:** `brana-core/src/time_tracking.rs` — pure turn-delta/idle-cap algorithm, inline `#[cfg(test)] mod tests` (receipt.rs's split). I/O (locking, atomic write, git-common-dir resolution, H2 scrub) lives in `brana-cli/src/commands/time.rs` (or the equivalent LOAD/CLOSE hook entry point), tested by a new `brana-cli/tests/time_smoke.rs` integration crate.
2. **Two different write shapes for two different files — corrected during BUILD (rung-2 judge panel, 2026-08-17).** The original draft applied `write_json_atomic` + `lock_sidecar` uniformly to both files. That's wrong for the data store: a bracket line, once written, is never modified — writing a new `Start`/`Close` line is a pure append, not a read-modify-write, so `queue.rs`'s locked whole-document-rewrite pattern is the wrong model for it. `brana-cli/src/commands/decisions.rs`'s append-only JSONL log (`OpenOptions::new().create(true).append(true)` + `writeln!`) is the closer precedent, and POSIX guarantees small (`&lt;PIPE_BUF`) `O_APPEND` writes are atomic without any explicit lock — concurrent appends to the *same* file, or writes to *different* `&lt;task_id&gt;.jsonl` files, never corrupt each other.
   - **Data store** (`brana/time/&lt;task_id&gt;.jsonl`): blind atomic append, `decisions.rs`-shaped. No `lock_sidecar`.
   - **Per-worktree open-bracket lock** (`brana-time-open-bracket.json`): genuinely read-modify-write ("is a bracket already open? if not, write") — this is the one file that needs `brana_core::util::write_json_atomic` + `brana_core::util::lock_sidecar`'s race protection, matching `queue.rs`'s pattern. **Not** `brana-cli/src/commands/receipt.rs`'s local `write_atomic` helper (unlocked, single-shot receipt.rs-only pattern) and **not** a blind-append pattern (no check-then-act protection at all) — this file specifically needs the full locked read-modify-write `queue.rs` already proves out under concurrent writers.
3. **Git-env scrub (H2):** reuse `brana_core::util::scrub_git_env` (`util.rs:13-30`) — already the single shared copy in Rust (`brana-cli/src/commands/receipt.rs` already migrated off its own local copy, per t-2617). No new copy needed in Rust; the "4 duplicated denylists" ADR-083 flags are all shell scripts, not Rust, and out of scope here.
4. **Git-common-dir resolution:** replicate `brana-cli/src/commands/receipt.rs`'s scrubbed inline pattern (`store_dir`/`tasks_file`) — run `git rev-parse --git-common-dir` through a scrubbed `Command`, then join if relative. Do **not** use `brana_core::util::find_tasks_file`/`git_common_root` — those resolve via an *unscrubbed* `git rev-parse`, which `receipt.rs` deliberately avoids (a leaked `GIT_DIR` would follow it to a foreign repo; the general defect is filed separately as t-2617). The per-worktree open-bracket lock (Assumptions, below) resolves `git rev-parse --git-dir` instead — same scrubbing requirement applies to that call too.
5. **Schema:** follow `queue.rs`'s lightweight convention — a bare integer `version` field in the JSONL line/envelope, lenient forward-compatible serde (`#[serde(default)]` on new fields, no `deny_unknown_fields`) — rather than `receipt.rs`'s heavier versioned-schema-string + domain-separated-hash attestation convention. Each bracket line is a discrete, independently-evolvable event record, not a signed attestation document; the heavier convention is overkill here. Declare struct fields alphabetically (receipt.rs's free canonical-JSON-key-ordering trick) if byte-stable output ever matters for a bracket line — cheap, worth keeping even though nothing here needs tamper-evidence.
6. **Session-transcript parsing is new code.** No existing brana-core module reads the Claude Code session transcript (`~/.claude/projects/{hash}/{session}.jsonl`, `message.usage`, per-turn timestamps) — `session.rs` is a false-friend name match; it only reads/writes brana's own session-handoff files. This spec adds a minimal parser: read the transcript JSONL, extract each line's `timestamp` field (ISO8601 UTC, millisecond precision — confirmed present on every entry per `docs/ideas/task-time-tracking.md`'s live-transcript research), compute turn-to-turn deltas, cap each delta at 15 minutes, sum.

**Consequences:**
- Reusing `write_json_atomic`/`lock_sidecar`/`scrub_git_env` means this feature adds zero new atomic-write or git-env-scrub logic to audit — only the bracket-specific read-modify-write shape and the turn-delta algorithm are genuinely new.
- The session-transcript parser is the one piece with no existing precedent in this codebase — highest-risk surface, gets the most test coverage (see Testing Strategy).
- Diverging from `receipt.rs`'s schema convention (lighter version field vs. schema-string + hash) means this feature is not byte-for-byte consistent with the *other* `git-common-dir`-family feature — acceptable per ADR-083's own reasoning (bracket lines are events, not attestations), but worth a one-line comment in the code pointing here so a future reader doesn't assume the two should match.

## Constraints

- Must not touch `~/.claude/run-state/{task_id}.jsonl` (the resume-checkpoint mechanism) — separate file, separate lifecycle, per ADR-083.
- Must work for all effort sizes (no M+ gate), per ADR-083's M+-gate decoupling decision.
- Marker-writing is invoked from `build.md`'s LOAD/CLOSE steps (markdown procedure, not Rust) — the Rust side exposes a CLI subcommand (or a library function called by a thin CLI wrapper) that LOAD/CLOSE shell out to. **Correction (challenger-caught, 2026-08-17):** there is no existing "how `receipt mint`/`validate` are invoked from `close.md`" precedent to match — a repo-wide check found zero wiring of `receipt mint`/`validate` into any skill procedure; ADR-083 and `build-receipts.md` both correctly describe this as designed-but-not-yet-wired. This spec's CLI-subcommand-invoked-from-markdown-step shape is a new pattern for this repo, not a copy of an existing one — t-2922 should design the actual invocation (argv, error handling, what LOAD/CLOSE do on a non-zero exit) without assuming a template exists elsewhere to follow.

## Scope (v1)

- Turn-delta summation with 15-minute idle cap — pure function, exhaustively unit-tested.
- Many-sub-spans-per-task_id bracket model — sum all `(start_ts, end_ts)` pairs recorded for a `task_id` across files/sessions.
- Serialized one-open-bracket-per-worktree enforcement (redesigned from per-session during SPECIFY — see Assumptions).
- Atomic, locked writes to `$(git rev-parse --git-common-dir)/brana/time/<task_id>.jsonl`.
- Coverage-annotation output shape (task/bracket counts, `coverage: partial` flag for excluded subagent/fork fan-out).
- **Out of scope for this spec:** the actual `build.md` LOAD/CLOSE wiring (t-2922 does the Rust side; wiring the markdown procedure to call it is part of t-2922's AC too — `system/skills/build/phases/load.md`/`close.md` must contain `"brana/time"`), Metric 2 (separate milestone, t-2923/t-2924), the query/aggregation command (t-2925+, blocked_by this).

## Research

Full precedent research (this session, 2026-08-17): `receipt.rs`/`receipt_smoke.rs` (atomic write, H2 scrub, pure/IO split, schema versioning), `queue.rs` (locking, concurrent-write stress tests, lightweight schema), `util.rs` (shared `write_json_atomic`, `lock_sidecar`, `scrub_git_env` — all reused here, none newly duplicated). No existing session-transcript parser found anywhere in `brana-core` — confirmed via targeted grep across all `.rs` files for `transcript`, `.claude/projects`, `message.usage`, `"usage"`.

**Additional precedents found during the rung-2 BUILD-gate judge panel (2026-08-17), previously uncited:** `brana-cli/src/commands/decisions.rs` (true `O_APPEND` JSONL, no lock — the actual model for the data store, see Decision #2 above); `brana-core/src/remind.rs` (ADR-051 — a second module already proving out the identical `lock_sidecar` + `write_json_atomic` + lenient-schema combo previously attributed only to `queue.rs`); `brana-core/src/session_initiative.rs::write_initiative_marker` (a fourth, independent hand-rolled atomic-write implementation, unlocked, structurally close to the open-bracket lock file). Four distinct atomic-write strategies now exist in brana-core; this design uses two of them (the `decisions.rs` append shape for the data store, the `queue.rs`/`remind.rs` locked-rewrite shape for the lock file) — not a fifth.

## Assumptions

- **Transcript path reconstruction — RESOLVED during SPECIFY (challenger-caught, 2026-08-17).** The original hypothesis (`project_hash = md5(cwd)`, carried over unverified from t-648) is **factually wrong**. The real scheme, confirmed by reading `brana-core/src/session.rs::encode_path()` and independently cross-checked against this very session's own live memory path (`~/.claude/projects/-home-martineserios-enter-thebrana-thebrana/` for cwd `/home/martineserios/enter_thebrana/thebrana` — exact match, not a 32-hex MD5 digest): `project_hash = cwd.to_string().replace('/', "-").replace('_', "-")`. The remaining open question ("which cwd, for a worktree build?") is resolved the same way `brana-core::util::find_project_root()` already resolves it elsewhere in this codebase: `CLAUDE_PROJECT_DIR` env var first (CC-injected since v2.1.139), falling back to `git rev-parse --show-toplevel`, falling back to process cwd — reuse that existing resolution order rather than inventing a new one. t-2921's tests must assert against `encode_path()`'s actual algorithm, not the old `md5` hypothesis.
- **One-open-bracket-per-session enforcement — REDESIGNED during SPECIFY (challenger-caught, 2026-08-17).** The original design scoped this by `$BRANA_SESSION_ID`. That env var's propagation to a Bash-tool-invoked CLI subprocess (as opposed to a hook process, which is what `session-start.sh` writes it for) is **unverified and contradictory**: `session-start.sh` only writes it to `$CLAUDE_ENV_FILE` (a hook-only channel), yet it was observed set in this live session's own Bash tool environment despite `$CLAUDE_ENV_FILE`/`$CLAUDE_PROJECT_DIR` both being empty at the same time — meaning some other, untraced mechanism sets it, and neither its presence nor its absence can be relied on with confidence. **Redesign: scope the enforcement per git-worktree, not per session-id.** This repo's hard rule (git-discipline.md) is one worktree per concurrent session — worktree identity is therefore a *more* reliable proxy for "this session" than an unverified env var, and needs no env var at all: `git rev-parse --git-dir` (unlike `--git-common-dir`, this resolves to a path unique per worktree — `<common-dir>/worktrees/<name>/` — not shared across worktrees). The open-bracket marker lives at `$(git rev-parse --git-dir)/brana-time-open-bracket.json` (per-worktree, ephemeral, not git-tracked); the aggregated bracket *data* (START/CLOSE timestamps per `task_id`) still lives in the shared, `git-common-dir`-scoped `brana/time/<task_id>.jsonl` exactly as ADR-083 specifies — only the *serialization lock*, not the durable data, moves to a per-worktree path. `$BRANA_SESSION_ID`, if present, may still be recorded as a label/annotation on bracket lines for human debugging — just not relied on for the correctness invariant.
- **One session, one transcript file**: assumes the running session's own transcript is the only file `time_tracking.rs` reads *while that session is live* (later, CLOSE reads it for the just-completed bracket). Cross-session aggregation (summing multiple *different* sessions' transcripts for the same `task_id`) is a *later* aggregation-command concern (t-2925+), not this spec's — this spec only closes brackets against the current session's own transcript.
- **Which transcript file, among possibly many — RESOLVED during BUILD (rung-2 verify stage, 2026-08-17).** Ruling out `$BRANA_SESSION_ID` for the worktree-lock question (above) left a separate, previously-unanswered question: a project's `~/.claude/projects/{encode_path(project_root)}/` directory can hold one `.jsonl` per session ever run against that project — CLOSE needs to read specifically *this* session's file, and nothing in this design names a session identifier to pick it out. **Resolution: snapshot, don't re-resolve.** At `START`, resolve the transcript file via the newest-mtime `.jsonl` in the project directory (the only session actively writing to its transcript at that instant is the current one — a heuristic, not a guarantee, but the same class of best-effort resolution `find_project_root()` already uses elsewhere in this codebase) and record its path in the per-worktree open-bracket lock file (`brana-time-open-bracket.json`) alongside `task_id`/`opened_at`. `CLOSE` reads that recorded path back directly — it never re-resolves "newest mtime" itself, so a second session becoming newest-mtime between START and CLOSE (e.g. the human switches to a different terminal mid-bracket) cannot silently redirect CLOSE onto the wrong transcript. If the recorded path no longer exists at CLOSE time (deleted, rotated), fail closed per the Boundaries table — never silently substitute a different file.

## Behavior

- At LOAD (a `time start <task_id>` call, or equivalent), if no bracket is currently open for this worktree (per the `--git-dir`-scoped lock file): append a `START` marker with the current timestamp to `brana/time/<task_id>.jsonl` and write the lock file. If one is already open (for any task_id, in this worktree): refuse — LOAD must CLOSE the current task's bracket first.
- At CLOSE (a `time close <task_id>` call), read the transcript from the matching `START` timestamp forward, compute turn-delta-summed active time (15-min cap), append a `CLOSE` marker with the computed duration and a coverage annotation, then remove the worktree's open-bracket lock file.
- A query surface (later task) sums all brackets for a `task_id` across every `brana/time/<task_id>.jsonl` line ever written.

## Edge Cases

- **Crash / session death mid-bracket**: an orphaned `START` with no matching `CLOSE`. Per ADR-083, the fallback is "the old session's bracket end is its last real turn's timestamp" — t-2921 must test this orphaned-bracket recovery path explicitly (a synthetic transcript with a `START` and no `CLOSE`, asserting the computed duration uses the last turn's timestamp, not "now" and not an error).
- **Overnight / multi-day idle gap**: the exact scenario ADR-083's re-validation covered — a gap far exceeding 15 minutes must cap at 15 minutes per occurrence, not per-gap-uncapped.
- **`BRANA_SESSION_ID` unset**: no longer a correctness dependency (see Assumptions redesign) — the env var, if present, is recorded as a debugging label only; its absence must not block a bracket from opening or closing.
- **Concurrent DIFFERENT worktrees, DIFFERENT `task_id`s** (the normal case — this repo's hard rule): each worktree's own `git rev-parse --git-dir` open-bracket lock is independent, so two sessions in two worktrees must never block each other. The shared `brana/time/` data store is `git-common-dir`-scoped, so their concurrent writers must never corrupt each other's lines either: covered by the `queue.rs`-shaped concurrency test.
- **Same worktree, second START before CLOSE**: must be rejected — this is the actual "one open bracket" invariant, now enforced via the per-worktree lock file rather than a session-id.
- **Corrupt/partial existing store file** (e.g. a truncated write from a prior crash): must not be silently overwritten — `queue.rs`'s `parse_before_write_never_clobbers_corrupt_store` shape applies.

## Design

```
brana-core/src/time_tracking.rs   — pure: turn-delta+idle-cap algorithm, bracket-sum,
                                     orphaned-bracket fallback. #[cfg(test)] mod tests.
brana-cli/src/commands/time.rs    — I/O: git-common-dir resolution (scrubbed), lock_sidecar,
                                     write_json_atomic, transcript file read, CLI subcommands
                                     (`brana time start <id>`, `brana time close <id>`).
brana-cli/tests/time_smoke.rs     — integration: real tempdir repos, real transcript fixture
                                     files, CLI exit codes, concurrent-writer stress test.
```

**Bracket-line schema (`brana/time/<task_id>.jsonl`, one JSON object per line, `queue.rs`-style lenient versioning):**

```jsonc
// START line
{"version": 1, "kind": "start", "task_id": "t-NNNN", "ts": "2026-08-17T14:03:11.000Z", "session_label": "<$BRANA_SESSION_ID if present, else null — debug-only, not load-bearing>"}
// CLOSE line
{"version": 1, "kind": "close", "task_id": "t-NNNN", "ts": "2026-08-17T14:47:52.000Z", "duration_capped_secs": 1847, "turn_count": 63, "gaps_capped": 2, "coverage": "full"}
// CLOSE line, delegation-heavy task
{"version": 1, "kind": "close", "task_id": "t-NNNN", "ts": "...", "duration_capped_secs": 620, "turn_count": 12, "gaps_capped": 0, "coverage": "partial"}
```

`coverage` is `"full"` or `"partial"` (the flag ADR-083 requires for subagent/fork-fan-out exclusion) — not a boolean, so a future v2 coverage state (e.g. `"estimated"`) doesn't require a schema break, matching `queue.rs`'s `#[serde(default)]` evolution rule.

**Append atomicity — corrected during BUILD (rung-2 verify stage, 2026-08-17).** `decisions.rs`'s `writeln!(file, "{}", entry)` (the cited precedent for this file's write shape) serializes via `Display`, which is multiple `write()` syscalls, not one — POSIX's `O_APPEND` atomicity guarantee is per-syscall, so a multi-syscall write can interleave with a concurrent writer's own multi-syscall write and corrupt the file. This precedent has never itself been concurrency-tested (`decisions.rs`'s own test module is single-threaded) — filed as its own follow-up (t-2971) independent of this feature. **Mandate for t-2922: serialize the full line to a `String`/`Vec<u8>` first (`serde_json::to_string` + `"\n"`), then issue exactly one `write_all` call** with that complete buffer — never an incremental/`Display`-driven write. This is cheap (one extra allocation) and closes the gap without reintroducing `queue.rs`'s locked-rewrite model.

**Per-worktree open-bracket lock (`$(git rev-parse --git-dir)/brana-time-open-bracket.json`, not git-tracked, not the durable data store):**

```jsonc
{"task_id": "t-NNNN", "opened_at": "2026-08-17T14:03:11.000Z", "transcript_path": "/home/user/.claude/projects/-encoded-project-path/abc123.jsonl"}
```

Presence of this file = a bracket is open in this worktree; absence = none open. Written/removed under the same `lock_sidecar`-protected read-modify-write critical section that guards the check-then-write invariant (the file itself is a plain locked-rewrite, `queue.rs`/`remind.rs`-shaped — not the blind-append shape used for the data store). `transcript_path` is resolved once at `START` (newest-mtime `.jsonl` in the project directory) and read back verbatim at `CLOSE` — see the "which transcript file" Assumption above.

**Worktree resolution fallback (t-3044, 2026-08-24):** CC keys a transcript directory by the *session's* cwd — the main checkout (cwd-discipline) — but builds run `time start` inside a linked worktree, whose `--show-toplevel` encodes to a project directory that never exists on disk. Resolution therefore tries the invoking root first (covers sessions genuinely started inside a worktree, e.g. ADR-060 runners), then falls back to the main-checkout root (`--git-common-dir`'s parent; identical to the invoking root in a plain checkout). Before this fallback, every worktree-based build silently recorded no transcript and lost its bracket at CLOSE (4/4 reproduction, t-3038/t-3097/t-3096/t-3168).

**Scoped out (t-3191):** the same worktree-blind `find_project_root()` keying exists in `commands/handoff.rs::resolve_handoff_path` and `brana_core::session.rs`'s path helpers (consumed by log.rs, memory.rs, session_initiative.rs). Deliberately not fixed here — some of those consumers may *want* worktree-scoped paths, so each needs a per-call-site decision (tracked as t-3191, challenger S4 finding on t-3044).

## Boundaries

| Always | Ask First | Never |
|--------|-----------|-------|
| Atomic writes: single `write_all` append to `brana/time/`, locked read-modify-write to the per-worktree lock file | Changing the 15-min idle-cap constant (ADR-083 locked it) | Write to `~/.claude/run-state/{task_id}.jsonl` (resume-checkpoint's file) |
| **CLOSE only**: fail closed when the recorded `transcript_path` existed but no longer resolves (evidence that vanished stays a refusal — `time_smoke.rs::d3`). When START recorded *no* transcript at all (`transcript_path` absent), CLOSE instead falls back to wall-clock between the Start marker and now, annotated `coverage: partial` with `turn_count: 0` (the wall-clock signature) — t-3044: better an honest upper bound than losing the bracket. START warns loudly on stderr when resolution fails, but still opens the bracket | Adding a new git-common-dir resolution helper (reuse `receipt.rs`'s pattern) | Use `util::find_tasks_file`/`git_common_root` for this path (unscrubbed), depend on `$BRANA_SESSION_ID` for correctness, or re-resolve "newest mtime" at CLOSE instead of reading the path START recorded |
| **START does NOT require a resolvable transcript** — clarified during BUILD verify (2026-08-17, iteration-2 catch): the row above previously read ambiguously as "no `.jsonl` found at START" also failing closed, but 6 of 9 tests already assumed START succeeds unconditionally (it only needs to record a `transcript_path`, best-effort — a `null`/absent value there is CLOSE's problem to fail on, not START's). Avoids a chicken-and-egg bootstrap case (a brand-new project's very first session has no prior transcript yet at the moment LOAD fires). | — | Block bracket-open on transcript resolvability |

## Testing Strategy

- **Unit (70%+, brana-core inline):** turn-delta summation with idle-gap capping (incl. synthetic overnight-gap case, per `docs/ideas/task-time-tracking.md`'s own live-transcript numbers as a regression fixture — 63.5h naive → 0.51h capped); many-sub-spans rollup across multiple synthetic transcript files for one `task_id`; orphaned-bracket-uses-last-turn-timestamp fallback; coverage-annotation output shape (task/bracket counts, `coverage: partial` flag).
- **Integration (25%, brana-cli smoke test):** serialized-bracket rejection scoped per-worktree — **both** a sequential re-entry check (second START in the same worktree after the first succeeds → rejected) **and** a genuinely concurrent race (two `time start` calls fired at the same worktree with no serialization between them, via a `std::sync::Barrier` so both processes' actual syscalls overlap — assert exactly one succeeds). The sequential-only version was caught by the rung-2 concurrency-lock finder (2026-08-17) as insufficient: it can't distinguish a real TOCTOU-safe lock from a naive unlocked check-then-write, since there's no possible interleaving in a sequential test. A second START in a *different* tempdir-repo worktree for a different `task_id`, concurrently → both succeed independently, real CLI invocations against real tempdir repos with real `git worktree add` setups; atomic concurrent-write stress test, `decisions.rs`-shaped blind-append with a **single pre-serialized `write_all` per line** (N threads/processes writing brackets for distinct `task_id`s to the same `brana/time/` directory, assert no corruption/loss, synchronized with a `Barrier` so `git worktree add`'s own internal locking doesn't stagger the writers enough to mask a real race) **plus a same-`task_id` variant** (multiple concurrent writers appending to the *same* `<task_id>.jsonl`, asserting every line survives intact and well-formed — the rung-2 verify stage flagged this as the scenario the many-sub-spans bracket model actually needs and the distinct-`task_id` version can't exercise, since it's trivially safe regardless of write strategy); stale/orphaned open-bracket lock file test (a lock file left behind by a simulated crash — no matching CLOSE — must produce a clean, named-cause outcome on the next `time start`/`close` in that worktree, not silent corruption or a hang); H2 git-env-leak test (real `GIT_DIR` set to a foreign repo, assert the write lands in the correct repo, mirroring `receipt_smoke.rs`'s H2 test, covering both the `--git-common-dir` data-store resolution and the `--git-dir` lock-file resolution); corrupt-store-not-clobbered test; **transcript-path fail-closed test** (a `time close` with no resolvable transcript — no `.jsonl` in the `HOME`-scoped fake project directory, or a recorded `transcript_path` pointing at a now-deleted file — must fail per the Boundaries table, not silently succeed).
- **E2E (5%):** none planned for this task — end-to-end `build.md` LOAD/CLOSE wiring is t-2922's scope.
- **Mock policy:** real filesystem via `tempfile::TempDir` (matches both `receipt_smoke.rs` and `queue.rs`'s own test style) — no mocking of git or the filesystem. Synthetic transcript fixture files (real JSONL, hand-authored timestamps) for the turn-delta tests, not live session data. **Every integration test whose `time close` call is meant to succeed must run with `HOME` overridden to a tempdir** (never the real `~/.claude/projects/`) containing a fabricated `{encoded-project-path}/{fake-session}.jsonl` with a handful of turn timestamps — the rung-2 verify stage caught that tests asserting `close` succeeds with no transcript fixture anywhere silently contradicted this same spec's own "fail closed on unresolvable path" boundary.

## Documentation Plan

- [x] **Tech doc** — this file, `docs/architecture/features/time-tracking-metric-1.md`
- [ ] **User guide** — deferred to t-2925+ (the query/aggregation command); this task has no user-facing surface yet (LOAD/CLOSE markers are internal)
- [x] **Existing docs to update** — `docs/ideas/task-time-tracking.md` Next Steps #3/#4 status, marked DONE (2026-08-18)

## Changelog

- 2026-08-24: worktree transcript resolution fixed (main-checkout fallback via `--git-common-dir` parent), START warns loudly on unresolvable transcript, CLOSE falls back to wall-clock (`coverage: partial`, `turn_count: 0`) when no transcript was recorded; recorded-but-deleted still fails closed (t-3044, 467b62a6). Sibling worktree-blind helpers scoped out to t-3191; close idempotence + coverage cells to t-3193.

## Challenger findings

**Iteration 1 (2026-08-18), RECONSIDER, 2 sev-4 — both fixed:**
1. CLOSE marker fired at `close.md` step 1.5 (right after AC validation), truncating the
   measured window before steps 2-14 (docs, merge, ship, etc.) ran, with no
   `coverage:partial` flag to signal the gap. Fixed: moved to step 13.5 (after Report,
   before the periodic/human-gated Ship-to-main step).
2. `time.rs::encode_project_path` was a 3rd hand-rolled copy of the CC path-encoding
   scheme, missing the legacy-encoding fallback `commands/handoff.rs` already proved
   necessary. Fixed: added `encode_project_path_legacy` + dual-try resolution, mirroring
   `handoff.rs::resolve_handoff_path`; covered by a dedicated test (`e1_...`) after a
   sev-3 iteration-2 follow-up flagged the fallback branch itself as untested.

**Iteration 2 (2026-08-18): PROCEED WITH CHANGES.**

**Correction to Decision #4 above (2026-08-18, post-freeze addendum — the Decision
Record itself is not edited per its own "do not modify after acceptance" rule):**
its claim that `brana_core::util::find_tasks_file`/`git_common_root` "resolve via an
*unscrubbed* `git rev-parse`" is now stale — a second-variant finder during this task's
Challenger gate confirmed `util.rs`'s `git_common_root_in`/`git_toplevel_in` both already
call `scrub_git_env` (the t-2617 fix landed repo-wide since this spec was drafted).
Decision #4's actual conclusion (replicate `receipt.rs`'s scrubbed inline pattern rather
than reuse those helpers) still stands for an unrelated reason worth restating precisely:
`find_tasks_file`/`find_project_root` prioritize the `CLAUDE_PROJECT_DIR` env-var hint
over the scrubbed git resolution, which is a different (and separately real) way a
caller-controlled environment variable could redirect resolution — not the "unscrubbed
git rev-parse" mechanism originally cited. A future reader should not treat
`find_tasks_file`/`git_common_root` as unsafe for the reason this doc originally gave.
