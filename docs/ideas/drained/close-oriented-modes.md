# Oriented Close Modes (`/brana:close --<mode>`)

> Brainstormed 2026-06-11. Revised same day after premortem challenger review (verdict: RECONSIDER → all findings resolved). Status: specified — see [ADR-053](../architecture/decisions/ADR-053-close-oriented-modes.md) and the [feature spec](../architecture/features/close-oriented-modes.md). Task: t-1980.

## Problem

`/brana:close` is a monolith invoked only at session end. Every close runs the same pipeline regardless of *why* you're closing — burning time and friction on the wrong stages. A mid-session context snapshot before `/compact` costs the same as a full end-of-project debrief. A "I'm stuck" close runs the same flow as a "I shipped something" close.

## Proposed solution

Mode flags that map each scenario to exactly the stages it needs. Bare `/brana:close` detects the current context and presents a picker (options labeled with their flags), so the user learns the flags through repetition and eventually skips the picker entirely by typing the flag directly.

## Success metrics

1. Faster closes for `--continue` and `--patterns` — seconds, not minutes
2. Nothing lost between sessions — every mid-session state change, blocker, or discovery lands in the right place

## Mode map — v1 launches 4 modes

Premortem finding #5: seven modes at launch collapse to two in practice. v1 ships the four with distinct, detectable outcomes; `--block`, `--handoff`, `--eod` are deferred (see Deferred below).

| Mode | Forced weight | Snapshot | Queue | Handoff | Task state | Extract | Cleanup |
|---|---|---|---|---|---|---|---|
| `--continue` | INSTANT | ✓ | ✓ | ✓ | stays `in_progress` | ✗ (nightly) | ✗ |
| `--finish` | INSTANT | ✓ | ✓ | ✓ | → `completed` | ⟳ nightly | ✓ |
| `--patterns` | LIGHT-inline | ✗ | ✗ | ✗ | no change | ✓ now | ✗ |
| `--abort` | NANO | ✗ | ✗ | minimal (reason) | → `pending` + reason | ✗ | via close-abort.sh |

Notes:
- **Orientation forces weight.** The two axes (orientation × weight) are NOT orthogonal — `--patterns` is meaningless at INSTANT weight (extraction is the whole point), `--continue` is meaningless at NANO (nothing to snapshot). The orientation flag wins; auto-classification runs only on bare invocation. (Premortem finding #3.)
- `--continue` is also the right mode for pre-compact context snapshots; successive `--continue` closes at different HEADs produce different `git_range` values → different `dedup_key` → each appends (ADR-052 §3 dedup semantics give accumulate-not-dedup for free). Same-HEAD repeats are no-ops.
- `--finish` is the current INSTANT behavior plus cleanup + task completion.
- `--patterns` does NOT queue — a documented exception to ADR-052 §5 ("LIGHT → queues"). Recorded in ADR-053. (Premortem finding #7.)

## Detection: bash narrows, Claude picks

1. **Bash signals** (fast, testable): git state (commits since branch, dirty tree, merged-to-main), task status from backlog, context % → outputs candidate set
2. **Claude** reads conversation context → selects recommended from candidates → picker shows recommended first
3. **Conflict rule:** hard signals disagreeing (e.g. task `in_progress` + branch merged — likely stale task state) → no recommendation, all candidates equal weight
4. **`--patterns` is never an auto-detected candidate** — "discoveries happened" is not a git-state signal. It surfaces only via explicit flag, or when Claude's conversation-level inference notices pattern-worthy material. (Premortem finding #6.)
5. **Flag given:** no picker, no detection, immediate execution
6. **Picker UX:** each option labeled with its flag name (e.g. "Continue (`--continue`)") — the picker is the learning mechanism, not an escape hatch

## Architecture — revised after premortem

**Original design (REJECTED):** new `phases/mode-dispatch.md` setting `CLOSE_MODE_OVERRIDE`/`TASK_STATE_TARGET` env vars read by later phases. Premortem finding #1 (CRITICAL): close phases are separate `.md` files read by the LLM; each bash snippet runs in an isolated shell — env vars do not survive phase boundaries. Silent no-op.

**Revised design:**
- `close-classify.sh` gains `--mode-override <mode>` — mirrors the existing `--light/--full/--nano` escape-hatch block. Orientation maps to forced weight at the top of flag parsing. The script stays the single source of truth for ALL mode/weight decisions; `test-close-weight-adaptive.sh` is the natural home for mode→weight assertions.
- No new phase file. Flag parsing happens at the top of `gate-and-evidence.md` Step 1 — the existing `CLOSE_MODE` variable carries orientation+weight through the gate *within the same bash block* (the pattern that already works).
- The orientation is persisted for later phases via the gate's existing announcement (`Close mode: $CLOSE_MODE`) — later phase files receive it as instruction context, and `session-state.md` derives the task-state action from a mapping table in its own bash block (orientation → `completed`/`in_progress`/`pending`), not from a cross-phase env var.

## Mode designs

### `--abort` — implemented as a tested script (`close-abort.sh`)

Premortem finding #4: inline phase logic loses work. The script owns the sequence:

1. Reason required — prompt if not given as arg (`/brana:close --abort "reason"`)
2. Dirty tree: always ask — stash with note / hard reset (confirm + summary of what's lost) / leave dirty with warning
3. Tag with **timestamp suffix**: `git tag aborted/t-NNN-slug-YYYYMMDD HEAD` (re-abort of the same task would collide on a bare slug)
4. **Push the tag** (`git push origin <tag>`); on failure warn loudly: "archive is LOCAL ONLY until pushed"
5. **Checkout main first**, then `git branch -D` (deleting the current branch fails otherwise)
6. Task → `pending`, reason appended to context

Pattern extraction is NOT offered by default — a clean abort is the point. The user can run `--patterns` first explicitly if there were learnings.

### Pre-compact — two-layer design

Premortem finding #2 (CRITICAL): CC hooks are synchronous stdin→stdout processes — no UI, no blocking on input, no AskUserQuestion. A countdown picker inside the hook is not implementable. Interactivity moves up a layer:

- **Layer 1 — interactive, in the agent loop:** when context crosses the orange-zone threshold AND a task is in flight, Claude proactively offers `--continue` via AskUserQuestion in normal conversation — before compaction pressure. This is where "ask first" lives.
- **Layer 2 — silent safety net, in the hook:** `pre-compact.sh` calls `close-snapshot.sh` silently with an idempotency guard (skip if a snapshot for the same HEAD exists), writes a notice to `additionalContext`. Never blocks compaction; failure → exit 0.

## Deferred (post-v1)

- `--block` — record blocker, set `blocked_by`; v1 workaround: set task state before closing
- `--handoff` — machine-safe handoff doc; v1: `--continue` covers most of it
- `--eod` — manual queue-flush ("run the nightly extraction now, scoped to today"); separate task — operates on the queue store, not live session state; nightly cron stays as safety net
- `--ship` / `--review` — close + pipeline entry; revisit after v1 usage data

## Engineering disciplines

- **DDD:** "Close Orientation" added to domain model (docs/domain/MODEL-001) alongside ADR
- **SDD:** [ADR-053](../architecture/decisions/ADR-053-close-oriented-modes.md) — mode contract, weight forcing, ADR-052 §5 exception
- **TDD:** extend `test-close-weight-adaptive.sh` (mode→weight assertions) + new `test-close-abort.sh` — both before implementation
- **Docs:** `docs/guide/commands/index.md` close entry, feature tech doc

## Scope (complete file list — premortem surface audit)

| File | Change |
|---|---|
| `system/scripts/close-classify.sh` | `--mode-override` argument |
| `system/scripts/close-abort.sh` | NEW — abort sequence |
| `system/skills/close/SKILL.md` | flag docs, argument-hint |
| `system/skills/close/phases/gate-and-evidence.md` | flag parsing + detection + picker |
| `system/skills/close/phases/session-state.md` | task-state mapping table |
| `system/skills/close/phases/errata-and-patterns.md` | `--patterns` inline trigger |
| `system/skills/close/phases/cleanup.md` | mode-conditional cleanup |
| `system/hooks/pre-compact.sh` | silent snapshot + notice |
| `tests/procedures/test-close-weight-adaptive.sh` | mode→weight cases |
| `tests/procedures/test-close-abort.sh` | NEW |
| `docs/architecture/decisions/ADR-053-close-oriented-modes.md` | NEW |
| `docs/domain/MODEL-001-brana-core.md` | Close Orientation concept |
| `docs/guide/commands/index.md` | close modes documentation |
