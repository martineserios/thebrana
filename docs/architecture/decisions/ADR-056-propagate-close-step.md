---
depends_on:
  - docs/architecture/decisions/ADR-052-close-queue-architecture.md
  - docs/architecture/decisions/ADR-053-close-oriented-modes.md
  - docs/architecture/decisions/ADR-030-maintenance-unification.md
informs:
  - docs/architecture/features/propagate-close-step.md
status: accepted
---

# ADR-056: PROPAGATE Close Step — Layered Propagation-Debt Audit

**Date:** 2026-06-12
**Status:** Accepted (2026-06-12, after premortem + second-pass challenger review)
**Tasks:** t-2003
**Source:** origin case proyecto_anita t-1306 (2026-06-12: 7 propagation gaps undetected by close) + premortem challenger review (verdict RECONSIDER — 4 CRITICAL findings, all resolved here)

## Context

Closing work leaves knowledge-propagation debt: spec Status fields that no longer match task state, Documentation-Plan checkboxes promised and never fulfilled, "al cerrar X" commitments in shapes/ADRs that never executed, project memories contradicted by current state, challenger findings routed "elsewhere" that never landed. The origin case (t-1306, a client repo, 18 commits) closed clean and a manual audit later found 7 such gaps.

The naive design — "new PROPAGATE step gated like Steps 3-8" — fails four ways (premortem, all repo-verified):

1. **Dead on the default path.** INSTANT is the default close since ADR-052; Steps 3-8 run in-session only on `--full`. The origin close itself was INSTANT — the feature would not have fired on its own motivating case.
2. **Untestable AC.** Six of the seven origin gaps need LLM prose judgment; only one (uncommitted tasks.json) is deterministically scriptable. One "procedure test" cannot cover both.
3. **Portability.** The origin case is a client repo: no `system/scripts/`, no reconcile, no spec-graph, different doc layout.
4. **Reconcile overlap.** `reconcile --scope propagation` (ADR-030) already covers doc fitness, spec-graph consistency, and errata cascade. The new value is unfulfilled-promise detection, state contradiction, and routed-finding loss — none of which reconcile checks.

## Decision

### 1. Three layers, all in v1 — cost tiered to close weight

| Layer | Runs on | Mechanism | Checks |
|-------|---------|-----------|--------|
| **L1 — deterministic** | every close except NANO and `--abort` | inline bash in the phase file (~1s, portable — no `system/scripts` dependency) | uncommitted tasks.json; unchecked `- [ ]` items in touched specs' Documentation Plans; spec `Status:` field vs task status (regex extract + known-vocabulary mismatch table); promise-pattern heuristic (`al cerrar`, `on close`) in touched shapes/ADRs — candidates surfaced, not judged |
| **L2 — session-bounded LLM audit** | orientation `--finish`, or weight FULL (`--full`) | instruction-context reading, bounded inputs (§3) | full categories (a)-(e): promise fulfillment, status semantics, cross-references, memory contradictions, challenger-finding routing |
| **L3 — deferred deep audit** | INSTANT/queued closes where L2 did not run | nightly cron propagation pass per queue entry; findings → **reminder store** (same v1 routing as extraction learnings — no new store) | L2-equivalent audit over the queued diff + repo state read at cron time |

L1 is near-universal because it is nearly free. L2 runs at the moment propagation debt matters most (the user is declaring work finished). L3 guarantees the default INSTANT path eventually pays its audit debt instead of never — inverting premortem CRITICAL-1.

**The Step 8b gate is orientation/weight-keyed, not Steps-4-8-gate-keyed.** Per ADR-053 §1, `--finish` forces weight INSTANT + cleanup — Steps 4-8 do not run in-session. PROPAGATE L2 runs on `--finish` anyway: Step 8b carries its own gate reading the announced `CLOSE_MODE`/`ORIENTATION`, independent of the Steps 4-8 weight gate. This is a deliberate amendment to ADR-053's "in-session audit only on FULL" expectation, scoped to Step 8b only — declaring work finished is exactly when unfulfilled promises must be checked, regardless of how light the rest of the close is.

NANO closes skip all layers (preserves the t-2003 AC; NANO also never queues, per ADR-052 §5, so L3 cannot apply). `--abort` skips all layers (clean abandon is the point, mirroring ADR-053 §4).

### 2. Insertion point: Step 8b — after DRIFT, before HANDOFF

"Post-HANDOFF, pre-REPORT" (the task's original placement) is not implementable: `next[]` is written exactly once, by `brana session write` in Step 9 (replace-not-merge). PROPAGATE therefore runs as **Step 8b**, owning its own phase file (`phases/propagate.md`), feeding gaps into the Step 9 payload via instruction context — the same hand-off pattern every Steps 3-8 finding uses. `doc-drift.md` (Step 8) already demonstrates the exact pattern: detection → `next[]` entry with `category: "maintenance"`.

Output contract: every detected gap ends as **either** an inline fix applied before HANDOFF (small edits, reported) **or** a `next[]` entry — zero silent drops (the existing close field-note rule, now load-bearing).

**Inline fixes are committed immediately** (2nd-pass challenger HIGH-3): after applying fixes, Step 8b runs `git add {fixed files} && git commit -m "fix(propagate): inline propagation gaps [close: {task_id}]"` before Step 9. Uncommitted fixes would be invisible to the already-taken Step 1b snapshot (L3 re-detects them), drift into the next session's working tree, and could spuriously re-trigger drift checks. The commit is not counted toward `COMMIT_COUNT` for audit purposes — the snapshot precedes it by design.

**L1 task resolution:** the task-status check uses the active task ID from the gate's Step 1 context. Task-less session → skip the status check, note "no active task". Multiple `in_progress` tasks → check the primary task only and emit a candidate note for L2. L1 "near-universal" never means erroring on sessions without a task.

### 3. Category bounds — no unbounded LLM sweeps

| Category | Bound |
|----------|-------|
| (a) committed artifacts | `- [ ]` items in Documentation Plans of specs **touched this session**; promise patterns in touched shapes/ADRs |
| (b) status fields | `Status:`-style fields of touched specs/shapes vs the session task's actual state |
| (c) cross-references | only docs **named** in touched specs' Documentation Plan "Existing docs to update" lines — the spec itself declares the propagation surface |
| (d) memories | current project's `.claude/memory/` files only |
| (e) challenger findings | **session-bounded**: verdicts/routings present in the current conversation context only |

Category (e) beyond the current session requires a persistent challenger-findings store, which does not exist — deferred (Non-Actions).

### 4. L3 contract — extend the existing queue and worker, minimally

- `brana close-queue append` gains an optional `--propagate` flag → `propagate: bool` field on the entry. **This field does not exist today** (verified against `brana-core/src/queue.rs`, `brana-cli/src/commands/close_queue.rs`, `brana-cli/src/cli.rs`, 2026-06-12) — adding it is v1 implementation scope, with AC: serde-optional, default `false`, round-trip-tested for backward compat with existing queue files.
- **Fail-safe queueing (2nd-pass challenger CRITICAL-2):** `close-snapshot.sh` passes `--propagate` on **every** queueing close. Step 1b runs seven steps before L2 and can only know whether L2 is *scheduled*, not whether it will *succeed* — inferring future success at queue time silently loses both L2 and L3 when L2 fails mid-flight. Instead, Step 8b clears the flag after L2 completes successfully via a new subcommand `brana close-queue mark-propagated --git-range {range}` (matches by dedup key). L2 failure, interruption, or mid-step compaction leaves the flag set → L3 covers the close. The ADR-053 §3 "never re-extract inline work" precedent is honored by the *clear*, not by declining to queue.
- **Step 8b re-entry guard (resume after compression):** before running L2, Step 8b checks whether propagation gap entries for this session were already announced (gaps list present in instruction context / a `fix(propagate):` commit exists at HEAD). If so, skip re-audit — L2 is LLM judgment, not deterministic; re-running is not a no-op.
- `close-extraction.sh` runs a second agy pass for entries with `propagate: true`: prompt = diff + targeted repo-state excerpts gathered at cron time (the entry carries `git_root`; the worker reads touched specs' Documentation Plans, task status, memory files **at cron time, not from the snapshot** — and runs `git log {git_range}..HEAD` to surface post-close commits, suppressing any gap the current state shows as already resolved; stale-audit false positives erode trust in the channel). Output contract: `{"gaps": [{"category": "a|b|c|d|e", "title": "...", "evidence": "...", "proposed_fix": "..."}]}` — validated like the learnings contract; unparseable → mark-failed, same retry budget. The prompt template is drafted in the feature spec (testability: the `AGY_BIN` stub must match the real contract).
- Gaps route to the reminder store (`--tags "propagation,{category}"`, dedup key `prop:{project}:{slug}`), surfacing at next session start. No new store, no new surfacing channel.

**Known risk:** the `close-extraction` job is failing as of 2026-06-12 (one entry repeatedly fails agy contract validation). L3 inherits agy reliability; the propagation pass uses the same validate-or-mark-failed discipline. Fixing the current failure is a separate task — L3 must not ship while the host job is red.

### 5. Portability — client repos are first-class

L1 is inline bash in the phase file: requires only git + grep + `brana backlog` (available everywhere the close skill runs). L2/L3-at-cron are LLM-judgment over whatever layout exists — layout-agnostic by nature; the phase file names *categories*, not thebrana-specific paths. The only thebrana-only feature is spec-graph-assisted file→spec mapping, which degrades to "specs touched in the session diff" when `docs/spec-graph.json` is absent (same fallback discipline as `doc-drift.md`).

### 6. Naming and reconcile relationship

The close step is named **PROPAGATE** (per t-2003 AC). The reconcile `propagation` scope is **unchanged** — PROPAGATE checks promise-fulfillment/state-contradiction debt at close time; reconcile propagation cascades errata and validates the spec graph on demand. The two are documented as siblings in both SKILL.mds to defuse the name collision. No standalone `/brana:reconcile --scope propagation` variant ships (the scope name already exists with settled semantics — premortem HIGH-4).

## Consequences

- Close SKILL.md gains Step 8b + PHASES row (`phases/propagate.md`) **and PROPAGATE in the step registry string between DRIFT and HANDOFF** (CC Task tracking + resume protocol depend on it); `cleanup.md` Step 12 report gains a propagation-gaps line (`{N found} ({M fixed inline + committed, K → next[]})`); `session-state.md` evidence list mentions PROPAGATE as a `next[]` feeder.
- `gate-and-evidence.md` picker description for `--finish` must state that an in-session L2 propagation audit now runs — `--finish` is no longer "INSTANT means zero in-session LLM work". This is the user-visible face of the ADR-053 amendment.
- ADR-052 §5 mode matrix and ADR-053 orientation table are amended **by this ADR** (not edited in place); ADR-053 frontmatter gains `amended_by: docs/architecture/decisions/ADR-056-propagate-close-step.md` so the chain is traversable.
- Rust CLI queue schema change (optional `propagate` field + `mark-propagated` subcommand) + `close-snapshot.sh` + `close-extraction.sh` changes — all backward compatible.
- Two-part test surface: `tests/procedures/test-close-propagate.sh` (deterministic L1 + gate matrix, CI-able) and `tests/procedures/test-close-propagate.md` (manual 7-gap re-simulation procedure grading L2 — LLM judgment is not CI-tested by design; first `.md` in that directory, marked `type: manual-procedure` to set the convention).
- `close-extraction.sh` per-field `python3 -c` loop pattern extends to the gaps loop — known O(4N) subprocess cost, acceptable in the nightly no-latency-budget context.
- New domain vocabulary: **propagation gap**, **knowledge debt** — added to `docs/domain/MODEL-001-brana-core.md`.

## Non-Actions

- **No persistent challenger-findings store** (category (e) stays session-bounded; revisit if gap data shows cross-session loss dominates).
- **No standalone `/brana:reconcile --scope propagation` variant** and no new reconcile scope — reconcile is untouched.
- **No `brana session write --append-next` CLI extension** — insertion before Step 9 makes it unnecessary.
- **No L3 backfill** for queue entries predating the `propagate` field (default `false`).
