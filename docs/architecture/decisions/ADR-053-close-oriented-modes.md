---
depends_on:
  - docs/architecture/decisions/ADR-052-close-queue-architecture.md
  - docs/ideas/close-oriented-modes.md
informs:
  - docs/architecture/features/close-oriented-modes.md
status: proposed
---

# ADR-053: Oriented Close Modes — Orientation Forces Weight, Flag Wins Over Classification

**Date:** 2026-06-11
**Status:** Proposed
**Tasks:** t-1980
**Source:** docs/ideas/close-oriented-modes.md (brainstorm 2026-06-11) + premortem challenger review same day (verdict: RECONSIDER — 3 CRITICAL, 4 HIGH findings, all resolved here)

## Context

ADR-052 made close fast (INSTANT default: snapshot + queue + handoff, extraction deferred to nightly cron) but kept it monolithic: one pipeline, weight auto-classified from git state, invoked at session end. In practice closes happen for different *reasons* — pausing to resume, finishing for good, capturing a discovery, abandoning an approach — and each reason needs a different subset of the pipeline and a different final task state. The brainstorm (t-1980) settled the mode vocabulary; the premortem killed the original dispatch architecture (env vars across phase files — not implementable in an LLM skill where each bash snippet runs in an isolated shell) and the pre-compact countdown picker (CC hooks cannot show UI or block on input).

## Decision

### 1. Orientation forces weight — one axis, not two

Orientation (why you're closing) and weight (how much pipeline runs) are NOT orthogonal axes layered on the same pipeline. Each orientation flag maps to a forced weight; auto-classification runs only on bare invocation:

| Flag | Forced weight | Task state target | Queues? |
|------|--------------|-------------------|---------|
| `--continue` | INSTANT | `in_progress` (unchanged) | yes |
| `--finish` | INSTANT + cleanup | `completed` | yes |
| `--patterns` | LIGHT-inline | unchanged | **no** (§3) |
| `--abort` | NANO | `pending` + reason | no |
| *(bare)* | auto via close-classify.sh | per detected mode | per ADR-052 §5 |

v1 ships these four. `--block`, `--handoff`, `--eod` are deferred — premortem found seven modes collapse to two in practice; defer until usage data justifies them.

### 2. `close-classify.sh --mode-override` — no new dispatch mechanism

The orientation flag reaches the pipeline through `close-classify.sh`, which gains a `--mode-override <orientation>` argument resolved at the **top** of its flag-parsing block (above `--light/--full/--nano`, mirroring that escape-hatch pattern). The script remains the single source of truth for all mode/weight decisions (t-1978 contract); `tests/procedures/test-close-weight-adaptive.sh` asserts the orientation→weight matrix.

**Rejected mechanism (premortem C1):** a new `phases/mode-dispatch.md` setting `CLOSE_MODE_OVERRIDE`/`TASK_STATE_TARGET` env vars for later phases to read. Close phases are separate `.md` files read by the LLM at step boundaries; each bash snippet runs in an isolated shell invocation — env vars do not survive phase-file boundaries. The failure mode is a silent no-op (mode ignored, task state never updated). The existing `CLOSE_MODE` variable in `gate-and-evidence.md` demonstrates the correct pattern: computed and consumed within one bash block, carried across phases as instruction context via the gate announcement.

Task-state targets are derived in `session-state.md` from the announced orientation via a mapping table in its own bash block — never from a cross-phase env var.

### 3. `--patterns` does not queue — documented exception to ADR-052 §5

ADR-052 §5 says LIGHT queues ("cheap to queue; cron decides extraction value"). `--patterns` runs LIGHT-*inline* extraction and does **not** append to the close queue: the user explicitly chose extract-now, so a nightly re-extraction of the same session is a wasted LLM pass and a duplicate-learnings source. This is the single exception to the §5 matrix; any future orientation that runs inline extraction inherits it.

### 4. `--abort` is a tested script, not inline phase logic

`system/scripts/close-abort.sh` owns the abort sequence (premortem H4 — three work-loss failure modes when done inline):

1. Reason required (arg or prompt) → appended to task context
2. Dirty tree: always ask — stash with note / hard reset (confirm + loss summary) / leave dirty with warning
3. Tag with timestamp suffix: `aborted/{task-id}-{slug}-{YYYYMMDD}` (bare slugs collide on re-abort)
4. Push the tag; on failure warn loudly that the archive is local-only
5. Checkout main **before** `git branch -D` (deleting the current branch fails)
6. Task → `pending`

No pattern extraction by default — clean abort is the point; `--patterns` runs first only on explicit request.

### 5. Pre-compact: two layers — ask in the agent loop, snapshot in the hook

**Rejected (premortem C2):** countdown picker inside `pre-compact.sh`. CC hooks are synchronous stdin→stdout processes — no UI, no blocking input, no AskUserQuestion access.

- **Layer 1 (interactive):** when context crosses the orange-zone threshold with a task in flight, Claude offers `/brana:close --continue` via AskUserQuestion in normal conversation — before compaction pressure.
- **Layer 2 (safety net):** `pre-compact.sh` calls `close-snapshot.sh` silently — idempotency guard (skip when a snapshot for the current HEAD already exists), notice via `additionalContext`, always exit 0. Never blocks compaction.

### 6. Detection and picker contract (bare invocation)

- Bash signals (git state, task status, context %) compute a **candidate set**; Claude selects the recommended candidate from conversation context; AskUserQuestion always shown, recommended first, options labeled with flag names (progressive disclosure — the picker teaches the flags)
- Conflicting hard signals (e.g. task `in_progress` + branch merged) → no recommendation, candidates equally weighted — conflicts indicate stale state, not a tie-breaking problem
- `--patterns` is **never** an auto-detected candidate (git state cannot signal "discoveries happened"); it surfaces via explicit flag or Claude's conversation-level inference only
- Flag given → no detection, no picker, immediate execution

### 7. Queue accumulation semantics for `--continue`

Successive `--continue` closes at different HEADs produce different `git_range` values → different `dedup_key` (ADR-052 §3) → each appends. Same-HEAD repeats are dedup no-ops. Accumulate-not-dedup is therefore free; the nightly cron extracts from the full arc. Covered by a regression test on `brana close-queue append`.

## Alternatives considered

**`phases/mode-dispatch.md` + cross-phase env vars** — rejected (§2): mechanism does not exist in LLM-skill execution; silent no-op failure.

**Keeping `close-classify.sh` untouched** — rejected: orientation must force weight (`--patterns` at INSTANT weight skips the extraction it exists for). "Untouched" was self-contradictory; extending its escape-hatch block keeps single-source-of-truth intact.

**Countdown picker in pre-compact hook** — rejected (§5): not implementable in the CC hook protocol.

**Seven modes at launch** — deferred: `--block`/`--handoff`/`--eod` lack distinct detectable outcomes today; revisit with usage data. `--eod` additionally operates on the queue store (not live session state) — separate task when picked up.

**Picker that auto-executes on high-confidence detection** — rejected (user decision, brainstorm): bare invocation never picks silently; the picker is the learning mechanism.

## Consequences

- `/brana:close --continue` becomes the standard mid-session persistence primitive (context relief, task switching) — closes stop being end-of-session-only
- `close-classify.sh` grows one argument but remains the single decision point; the weight matrix and the orientation matrix live in one tested file
- One documented exception to ADR-052 §5 (`--patterns` no-queue) — future inline-extraction modes inherit it
- Abort becomes safe enough to use: archived work is pushed, collisions impossible, current-branch deletion handled
- The deferred modes have a designed slot (orientation table row + forced weight) — adding one is additive, not architectural
