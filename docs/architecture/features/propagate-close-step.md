---
depends_on:
  - docs/architecture/decisions/ADR-056-propagate-close-step.md
  - docs/architecture/decisions/ADR-052-close-queue-architecture.md
  - docs/architecture/decisions/ADR-053-close-oriented-modes.md
status: shipped
---

# Feature: PROPAGATE Close Step — Layered Propagation-Debt Audit

**Date:** 2026-06-12
**Status:** shipped
**Task:** t-2003

## Problem

Every close leaves knowledge-propagation debt the pipeline never checks: stale spec Status fields, unfulfilled Documentation-Plan checkboxes, "al cerrar X" promises never executed, contradicted project memories, challenger findings routed and lost. Origin case t-1306 (proyecto_anita, 18 commits): a clean close, then a manual audit found 7 gaps. Undetected knowledge debt compounds — the docs claim a state the system is no longer in.

## Decision Record (frozen 2026-06-12)

> Do not modify after acceptance. Full decision: [ADR-056](../decisions/ADR-056-propagate-close-step.md).

**Context:** INSTANT is the default close; a step gated like Steps 3-8 would never run on real closes. Six of seven origin gaps need LLM judgment. The origin repo is a client repo without thebrana infrastructure.
**Decision:** Three layers in v1 — L1 deterministic inline bash (all closes except NANO/`--abort`), L2 session-bounded LLM audit (`--finish`/`--full`), L3 nightly cron deep audit for queued INSTANT closes (findings → reminder store). Step 8b insertion (post-DRIFT, pre-HANDOFF) so gaps feed the single Step 9 `next[]` write. Portable inline checks; bounded category inputs; reconcile untouched.
**Consequences:** Queue schema + snapshot script + extraction worker extended (backward compatible); split test surface (deterministic `.sh` CI test + manual `.md` 7-gap procedure); PROPAGATE/propagation naming documented as siblings.

## Constraints

- `next[]` is written once, in Step 9, replace-not-merge — PROPAGATE must complete before HANDOFF.
- Mode/orientation crosses phase files only as instruction context (ADR-053) — no env vars; gate reads the announced `CLOSE_MODE` / `ORIENTATION`.
- L1 must stay ~1s and dependency-free beyond git/grep/`brana backlog` (client-repo portable).
- L3 rides the existing extraction worker; `close-extraction` job is currently red — L3 lands behind its repair (blocked subtask).
- NANO closes skip everything (AC); `--abort` skips everything; `--patterns` precedent: inline-audited closes are not re-audited by cron.

## Scope (v1)

- New phase file `system/skills/close/phases/propagate.md` (Step 8b) + SKILL.md registry row + step-table updates.
- L1 inline checks: dirty tasks.json; `- [ ]` count in touched specs' Documentation Plans; `Status:` field vs task status mismatch table; promise-pattern heuristic (`al cerrar` / `on close`) surfacing candidates for L2.
- L2 audit instructions: categories (a)-(e) with the ADR-056 §3 bounds; each gap → inline fix or `next[]` (`category: "maintenance"`), zero silent drops.
- L3: `--propagate` queue flag + `mark-propagated` subcommand (Rust CLI), `close-snapshot.sh` always-queue passthrough, `close-extraction.sh` propagation pass with post-close-resolution suppression, gaps → reminder store.
- Step 12 report line: `**Propagation gaps:** {N found} ({M fixed inline + committed, K → next[])}`.
- `gate-and-evidence.md` picker: `--finish` description updated to disclose the in-session L2 audit.
- ADR-053 frontmatter: `amended_by` pointer to ADR-056.
- Domain vocabulary: "propagation gap", "knowledge debt" → MODEL-001.

Out of scope (ADR-056 Non-Actions): persistent challenger-findings store, reconcile changes, `--append-next` CLI, queue backfill.

## Research

- Close mechanics (phase files, scout 2026-06-12): evidence reaches Step 9 via instruction context; `doc-drift.md` Step 8 is the detection→`next[]` precedent; Step 12 already enforces "skipped follow-ups still land in next[]".
- `close-classify.sh` is the single mode source of truth; PROPAGATE needs **no classify change** — its gate derives from the already-announced mode + orientation.
- Extraction worker routes findings to the reminder store with dedup keys; the propagation pass reuses contract-validation + mark-failed discipline verbatim.
- Reconcile `propagation` scope = verify-docs + spec-graph + errata cascade — zero overlap with categories (a)-(e) (gap table in premortem; ADR-030).
- Premortem (challenger, RECONSIDER): 4 CRITICALs — each resolved by a numbered ADR-056 decision (§1 gating, §2 insertion, §3 bounds/testability split, §5 portability, §6 naming).

## Assumptions

- `Status:`-field extraction can rely on a small known vocabulary (`pending`, `specifying`, `live run pending`, `in progress`, …) for the L1 mismatch table; unknown values are L2's job. — chose regex+vocabulary because full semantics is L2 anyway — needs confirmation at first L1 implementation review.
- The reminder store is an acceptable L3 landing zone (no per-repo `next[]` injection from cron). — chose it because it is the established extraction routing and surfaces at session start.
- "Touched specs" = `.md` files under docs/spec/shape directories appearing in the session diff; spec-graph refines this in thebrana, absence degrades gracefully.

## Design

```
Step 8 DRIFT ──► Step 8b PROPAGATE ──► Step 9 HANDOFF (single next[] write)
                 │
                 ├─ Gate (from announced CLOSE_MODE/ORIENTATION):
                 │    NANO or --abort ........ skip entirely
                 │    --finish or FULL ....... L1 + L2
                 │    other non-NANO ......... L1 only (+ queue --propagate for L3)
                 │
                 ├─ L1 (bash, inline): dirty tasks.json · [ ] counts · Status vs task · promise heuristic
                 │     task resolution: active task from gate Step 1 context; task-less → skip status
                 │     check; multi-task → primary task only + candidate note for L2
                 ├─ L2 (LLM, bounded): categories a–e over touched specs, named docs, project memory,
                 │     session challenger verdicts. Re-entry guard: skip if gaps already announced /
                 │     fix(propagate) commit at HEAD (resume-after-compression is not a no-op for LLM work)
                 ├─ Inline fixes: applied → committed IMMEDIATELY (`fix(propagate): ...`) before Step 9
                 └─ Output: gaps[] → fix inline (commit + report) | next[] maintenance entry — never dropped
                       L2 success → `brana close-queue mark-propagated --git-range {range}` (clears L3 flag)

Step 1b (earlier): close-snapshot.sh queues EVERY close with --propagate (fail-safe: L2 failure,
interruption, or compaction leaves the flag set → L3 covers; the clear happens only on L2 success)

Nightly (L3): close-extraction.sh → entries with propagate:true → agy propagation pass
              (diff + repo state read at CRON time + git log {range}..HEAD post-close suppression)
              → {"gaps":[...]} → reminder store (tags: propagation,{cat})
```

L3 prompt template (draft — the `AGY_BIN` test stub must match this contract):

```
You are auditing knowledge-propagation debt for project '{project}' (branch {branch}, commits {range}).
Below: (1) the session diff, (2) CURRENT content of touched specs' Documentation Plan sections,
(3) current task status for {task_id}, (4) current project memory files, (5) post-close commits ({range}..HEAD).
Detect gaps in categories: (a) unfulfilled committed artifacts ('- [ ]' items, 'al cerrar'/'on close' promises),
(b) Status fields contradicting task state, (c) docs named in 'Existing docs to update' lines not updated,
(d) memory claims contradicted by current state. Suppress any gap the current state or post-close commits
show as already resolved. Return ONLY JSON, no markdown fences, matching exactly:
{"gaps": [{"category": "a|b|c|d", "title": "...", "evidence": "...", "proposed_fix": "..."}]}
Empty array if no gaps.
```

(Category (e) is absent from L3 by design — challenger findings are session-bounded and unavailable at cron time.)

Key files: `system/skills/close/phases/propagate.md` (new), `system/skills/close/SKILL.md` (PHASES row + **step registry string: PROPAGATE between DRIFT and HANDOFF**), `system/skills/close/phases/gate-and-evidence.md` (picker `--finish` description discloses L2), `system/skills/close/phases/cleanup.md`, `system/skills/close/phases/session-state.md` (one-line evidence mention), `system/scripts/close-snapshot.sh`, `system/cron/close-extraction.sh`, `system/cli/rust/crates/brana-core/src/queue.rs` + `brana-cli/src/commands/close_queue.rs` (`propagate` field + `mark-propagated` subcommand), `docs/architecture/decisions/ADR-053-close-oriented-modes.md` (frontmatter `amended_by` only), `docs/domain/MODEL-001-brana-core.md`.

## Boundaries

| Always | Ask First | Never |
|--------|-----------|-------|
| Report every gap (inline fix or next[]) | Applying inline fixes that touch >3 files or any non-doc file | Silently drop a detected gap |
| Skip on NANO and --abort | Changing task status as a "fix" | Modify reconcile's propagation scope |
| Degrade gracefully (no spec-graph, no brana binary) | — | Block a close on PROPAGATE failure |
| Validate L3 agy output or mark-failed | — | Re-audit closes that ran L2 inline |

## Testing Strategy

- **Unit (70%):** `tests/procedures/test-close-propagate.sh` — fixture repo simulating origin gaps #1/#3/#7 (status mismatch, unchecked `[ ]`, dirty tasks.json) asserting L1 detects 3/3; gate matrix (NANO skip, --abort skip, --finish L1+L2 announce, bare-INSTANT L1+queue-flag); `cargo test` for the queue field round-trip.
- **Integration (25%):** `close-snapshot.sh --propagate` → queue entry assertion; `close-extraction.sh` propagation pass against a fixture entry with stubbed `AGY_BIN` (contract validation, mark-failed path, reminder write).
- **E2E / manual (5%):** `tests/procedures/test-close-propagate.md` — the 7-gap re-simulation: fixture state mirroring t-1306, run `/brana:close --finish`, human-graded checklist of expected detections per gap and per layer. **LLM-judgment checks are deliberately not CI-gated** (ADR-056 Consequences). First `.md` in `tests/procedures/` — carries a `<!-- type: manual-procedure — not CI-automated -->` marker to set the convention.
- **Rust:** `cargo test` round-trip for the `propagate` field (serde default on legacy entries) and `mark-propagated` matching by git_range/dedup key.
- **Mock policy:** real git fixture repos; stub only `agy` (external binary) and time-dependent paths.

## Documentation Plan

- [x] **User guide** — `docs/guide/features/propagate-close-step.md`: what closes now check, how to read the gaps report, the layered gate table, how L3 findings surface as reminders.
- [x] **Tech doc** — this file, promoted to `implemented` with final file map.
- [x] **Existing docs to update** — `system/skills/close/SKILL.md` (step table + weight matrix row), `system/skills/reconcile/SKILL.md` (sibling note, §6 naming), `docs/domain/MODEL-001-brana-core.md` (vocabulary).

## Challenger findings

Premortem (pre-spec, verdict RECONSIDER) — resolutions:
- CRITICAL-1 dead gating → §1 layered gate, L1 near-universal, L3 for INSTANT.
- CRITICAL-2 untestable AC → split test surface (deterministic .sh / manual .md), ADR-056 Consequences.
- CRITICAL-3 client-repo portability → §5 inline portable L1, layout-agnostic L2/L3.
- CRITICAL-4 reconcile overlap → §6 siblings, reconcile untouched, gap table confirms categories a-e are net-new.
- HIGH-1/2 insertion seam → §2 Step 8b before the single Step 9 write.
- HIGH-3 latency → L1-only on default closes; LLM cost moved to --finish/--full/cron.
- HIGH-4 standalone variant → dropped (Non-Action).
- MEDIUM-1 no findings store → (e) session-bounded.
- MEDIUM-3 spec mapping → spec-graph with diff-based fallback.
- LOW-1 Spanish-only promise regex → pattern covers `al cerrar` + `on close`, documented as extensible list.
- LOW-2 naming collision → §6.

Post-spec challenger review (2026-06-12, verdict PROCEED-WITH-CHANGES) — all findings resolved in this revision:
- CRITICAL-1 (ADR `proposed` while Rust schema in scope) → ADR-056 flipped to `accepted` at spec approval, before any Rust code.
- CRITICAL-2 (Step 1b cannot know L2's future outcome; L2 failure silently loses L3 too) → fail-safe inversion: always queue `--propagate`; Step 8b clears via `mark-propagated` only on L2 success.
- CRITICAL-3 (picker description, resume double-audit, missing step-registry entry) → gate-and-evidence.md picker in Key Files; Step 8b re-entry guard; PROPAGATE added to registry string.
- HIGH-1 (task-id on multi-task/task-less sessions) → resolution rule in Design.
- HIGH-2 (L3 stale-audit false positives) → cron-time state read + `{range}..HEAD` suppression in the L3 prompt.
- HIGH-3 (inline fixes uncommitted after snapshot) → immediate `fix(propagate):` commit before Step 9.
- MEDIUM-1 (.md test convention) → `type: manual-procedure` marker. MEDIUM-2 (undrafted L3 prompt) → template in Design. MEDIUM-3 (python3 loop cost) → noted acceptable for nightly. LOW-1 (ADR-053 pointer) → `amended_by` in Key Files. LOW-2 (registry string) → folded into CRITICAL-3 fix.
