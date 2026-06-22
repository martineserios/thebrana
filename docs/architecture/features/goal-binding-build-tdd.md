# Feature: /goal binding — /brana:build TDD loop (ADR-061 Stage 2)

**Date:** 2026-06-21
**Status:** specifying
**Task:** t-2205
**ADR:** [ADR-061](../decisions/ADR-061-goal-integration-three-primitive.md) (Accepted) — this feature is its Stage 2 deliverable.

## Problem

ADR-061 defines `/goal` as the ITERATE primitive that owns one gate-free span and
stops at the gate. Stage 2 is the **first concrete binding**: anchor `/brana:build`'s
red→green TDD span to `/goal` so the task auto-completes when its acceptance criteria
go green. Two gaps block this today:

1. The build LOAD phase writes `active-goal.json` **without `base_ref`**, but the
   hardened `goal-completion.sh` (t-2204) *requires* `base_ref` to run its grader-path
   immutability interlock. Without it, auto-complete never fires.
2. The presence interlock reads `~/.claude/run-state/presence-{session_id}` (must be
   fresher than 15 min) but no interactive-only hook *writes* that token.

ADR-061 also left one decision open ("name this before Stage 2"): is `/goal` a true
iterate loop or a one-shot anchor?

## Decision Record (frozen 2026-06-21)
> Do not modify after acceptance. Full record: ADR-061 §Open (Attack 4 resolution).

**Context:** `/goal` today is a one-shot session anchor — `goal-completion.sh` fires once
at Stop and does not re-enter on non-green. The "ITERATE" verb is design intent.

**Decision:** **Option (b) — keep `/goal` a one-shot session anchor for Stage 2.** The
binding is (1) the `active-goal.json` declaration (span = build red→green, done-signal =
all `AC:` exit codes == 0) plus (2) `goal-completion.sh` auto-completion at Stop.
Iteration is driven by the session's natural Stop → "goal blocked: {criterion}" → continue
cycle, not by the hook re-injecting a continuation. A hard re-entry loop is deferred to
Stage 4 if evidence justifies it.

**Consequences:** C2 (gate-free span) holds **by construction** — no auto-iterating span
exists to contain the per-subtask TDD gate, so the binding never auto-advances *through*
the gate. Auto-complete fires only at full green, behind the presence + base_ref
immutability interlocks. Smallest change that produces the soak evidence Stage 2 exists to
collect.

## Constraints

- `goal-completion.sh` is security-critical (anti-gaming suite G1–G6, t-2210). Any change
  must keep all interlocks intact; new code is additive (audit emission), never relaxing.
- The presence-token writer must be **interactive-only** — a headless runner must not be
  able to forge presence. Gate on `/dev/tty` availability.
- `base_ref` must be pinned at `/goal` *start* (build LOAD), captured as `git rev-parse HEAD`
  before any implementation edits, so the grader-immutability diff is meaningful.

## Scope (v1)

- **A.** LOAD phase (`system/skills/build/phases/load.md`) writes `base_ref` into
  `active-goal.json`.
- **B.** Interactive-only presence-token refresh hook (UserPromptSubmit, `/dev/tty`-gated)
  that touches `~/.claude/run-state/presence-{session_id}`.
- **C.** `goal-completion.sh` emits **structured audit output** — for each criterion: the
  heuristic that judged it + the evidence (commit SHA / file path).
- **D.** Tests in `system/hooks/tests/test-goal-completion.sh` for the audit output and the
  base_ref-present path.
- **E.** ADR-061 Open item resolved (done).

**Out of scope:** hard hook-driven re-entry loop (Stage 4); the `/brana:fix` and
`/brana:reconcile` bindings (Stage 3, t-2206).

## Assumptions
- `BRANA_SESSION_ID` is the branch name and is available to both the LOAD phase and the
  presence hook — *needs confirmation in BUILD* (grep current hooks for how session_id is
  resolved; goal-completion.sh already uses it for presence lookup).
- No presence-token writer exists yet — *verify in DECOMPOSE* (grep for `presence-` writers).

## Behavior
- When a code task with AC: lines starts via `/brana:backlog start`, build LOAD anchors the
  session with `/goal` and writes `active-goal.json` including `base_ref`.
- While the human interacts, each prompt refreshes the presence token.
- At Stop, `goal-completion.sh` checks each criterion, emits an audit line per criterion, and
  auto-completes the task **only** when all are green and both interlocks pass.

## Edge Cases
- Headless / no `/dev/tty`: presence token not refreshed → auto-complete correctly refuses
  (fail-closed, matches G5).
- `base_ref` missing from an old active-goal.json: hook already blocks auto-advance (no
  regression — we only add the writer).
- Grader-path changed since base_ref (e.g. a test file edited): immutability gate blocks
  (existing G1–G4 behavior); audit output should still emit, marking the block reason.

## Design

| Component | File | Change |
|-----------|------|--------|
| Goal declaration | `system/skills/build/phases/load.md` §Step 0 | add `"base_ref": "$(git rev-parse HEAD)"` to the active-goal.json write |
| Presence writer | `system/hooks/<presence-refresh>.sh` + settings wiring | new UserPromptSubmit hook, `/dev/tty`-gated, `touch ~/.claude/run-state/presence-$SESSION_ID` |
| Audit emission | `system/hooks/goal-completion.sh` | after each criterion verdict, append `{criterion, heuristic, evidence, verdict}` to audit (additionalContext + `~/.claude/run-state/{task_id}-audit.jsonl`) |
| Tests | `system/hooks/tests/test-goal-completion.sh` | base_ref-present pass; audit-output assertions |

## Boundaries
| Always | Ask First | Never |
|--------|-----------|-------|
| Emit audit per criterion; pin base_ref at goal start | Changing any G1–G6 interlock logic | Relax presence/immutability gates; add hook-driven re-entry |

## Testing Strategy
- **Unit:** audit-emission shape per criterion; base_ref capture (shell, via test harness).
- **Integration:** `test-goal-completion.sh` end-to-end with a base_ref-pinned active-goal.json
  (clean pass auto-completes + audit emitted; grader-path mutation blocks + audit notes it).
- **Mock policy:** real git repo fixtures (the existing test harness already builds temp repos).

## Documentation Plan
- [ ] Tech doc — this file (design rationale, key files).
- [ ] Update `docs/guide/workflows/` Operating-the-Orbit guide if it describes goal auto-complete.
- [ ] ADR-061 Open item — done.

## Challenger findings
{auto-populated after challenger review}
