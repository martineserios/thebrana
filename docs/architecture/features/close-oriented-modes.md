# Feature: Oriented Close Modes

**Date:** 2026-06-11
**Status:** specifying
**Task:** t-1980
**Decision record:** [ADR-053](../decisions/ADR-053-close-oriented-modes.md) — orientation forces weight, flag wins over classification, `--patterns` no-queue exception, abort script contract, two-layer pre-compact

## Problem

`/brana:close` runs one monolithic pipeline regardless of why the user is closing. Pausing mid-session, finishing for good, capturing a discovery, and abandoning an approach all cost the same and leave task state wrong as often as right. Closes are also end-of-session-only — there is no cheap primitive for mid-session persistence (context relief, task switching, blockers).

## Constraints

- `close-classify.sh` remains the single source of truth for mode/weight decisions (t-1978) — extended, never bypassed or replicated
- No cross-phase env vars — close phases are LLM-read `.md` files; bash state lives within single blocks (premortem C1)
- CC hooks cannot prompt or block on input (premortem C2)
- ADR-052 queue contract untouched except the documented `--patterns` exception
- Bare invocation never executes silently — picker always shown (user decision)
- INSTANT model preserved: extraction stays nightly for `--continue`/`--finish`

## Scope (v1)

Four modes: `--continue`, `--finish`, `--patterns`, `--abort`. Detection + picker on bare invocation. Pre-compact Layer 2 wiring. Deferred: `--block`, `--handoff`, `--eod`, `--ship`, `--review`.

## Design

See ADR-053 for the contracts. Component changes:

| File | Change |
|---|---|
| `system/scripts/close-classify.sh` | `--mode-override <orientation>` at top of escape-hatch block; prints orientation + forced weight |
| `system/scripts/close-abort.sh` | NEW — 6-step abort sequence (ADR-053 §4) |
| `system/skills/close/SKILL.md` | argument-hint + flag table; PHASES registry note (no new phase file) |
| `system/skills/close/phases/gate-and-evidence.md` | Step 1: parse `$ARGUMENTS` for orientation flag → pass `--mode-override`; bare → detection (candidate set via bash signals) + picker |
| `system/skills/close/phases/session-state.md` | orientation → task-state mapping table (own bash block) |
| `system/skills/close/phases/errata-and-patterns.md` | `--patterns` triggers inline LIGHT extraction; no queue |
| `system/skills/close/phases/cleanup.md` | cleanup runs only for `--finish` (and FULL) |
| `system/hooks/pre-compact.sh` | call `close-snapshot.sh` with idempotency guard, notice via additionalContext, exit 0 always |
| `docs/domain/MODEL-001-brana-core.md` | `CloseOrientation` concept added to domain model |

## Assumptions

- `$ARGUMENTS` reliably carries the flag into the close skill (existing `--light/--full/--nano` already depend on this) — verified by current behavior
- Context % is readable by the gate for detection (session state file); if unavailable, detection degrades to git+task signals only — confirmed acceptable
- `git push` of abort tags may fail offline — warn-and-continue, never block the abort

## Boundaries

| Always | Ask First | Never |
|--------|-----------|-------|
| Flag → immediate execution | Bare invocation → picker | Silent mode selection on bare invocation |
| `--patterns` extracts inline, skips queue | `--abort` dirty-tree disposal (stash/reset/leave) | `--abort` without a reason |
| Pre-compact hook exits 0 | `--abort` hard reset (confirm + loss summary) | Hook blocking compaction |
| Orientation forces weight | | Cross-phase env vars |
| | | jq/direct writes to close-queue.json (ADR-052 §2) |

## Testing Strategy

- **Unit (70%):** `test-close-weight-adaptive.sh` extended — orientation→weight matrix (4 modes × override-wins-over-auto cases, bare-invocation fallthrough unchanged); `test-close-abort.sh` NEW — tag timestamp suffix, collision on re-abort, current-branch checkout-first, push-failure warning path, reason-required gate (mock git via PATH shim, per validate-sh test conventions)
- **Integration (25%):** `brana close-queue append` accumulate-not-dedup regression (same branch, advancing HEAD → N entries; same HEAD twice → 1 entry); pre-compact idempotency (two invocations same HEAD → one snapshot)
- **E2E (5%):** one scripted `/brana:close --continue` smoke against a fixture repo (existing close test harness pattern)
- **Mock policy:** real git repos in temp dirs (existing test convention); mock only `git push` (network) and the brana binary where the suite already does

## Documentation Plan

- [ ] **User guide** — `docs/guide/features/close-oriented-modes.md`: the four modes, when to use which, picker behavior, flag learning path
- [ ] **Tech doc** — this file, updated to `shipped` with final design
- [ ] **Existing docs to update** — `docs/guide/commands/index.md` (close entry), `docs/architecture/hooks.md` (pre-compact field note)

## Challenger findings

Premortem run 2026-06-11 (context-isolated challenger, verdict RECONSIDER → resolved):
- **C1 (CRITICAL):** cross-phase env vars don't exist in LLM-skill execution → architecture revised to `--mode-override` + same-block derivation (ADR-053 §2)
- **C2 (CRITICAL):** hook countdown picker not implementable → two-layer design (ADR-053 §5)
- **C3 (CRITICAL):** "close-classify.sh untouched" self-contradictory → orientation forces weight via the script itself (ADR-053 §1)
- **H4:** abort work-loss modes (unpushed tags, current-branch delete, tag collision) → close-abort.sh contract (ADR-053 §4)
- **H5:** 7 modes collapse to 2 in practice → v1 ships 4
- **H6:** `--patterns` undetectable from git state → excluded from auto-candidates (ADR-053 §6)
- **H7:** ADR-052 §5 contradiction → documented exception (ADR-053 §3)
- **M9/M10:** dedup edge covered by ADR-052 §3 semantics + regression test; no PHASES registry renumbering (no new phase file)
