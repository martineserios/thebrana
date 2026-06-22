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
- **Stage-2 gap (accepted):** the `tests_required[]` registration in `build-loop.md` does **not**
  verify the test was *red* — a developer can register a trivially-passing test. Acceptable for
  Stage 2 (the presence interlock ensures a human reviews every green); red-verification is a
  Stage-3 prerequisite (a pre-commit hook, filed separately, blocking t-2206).

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

## Design (Option C — deep challenge 2026-06-21, 3 lenses converged)

The naive "pin base_ref at goal start + plain immutability" is fatally broken for TDD (the
loop's first step writes the test the grader reads). **Option C** keeps a single goal-start
pin and distinguishes **Modified** (pre-existing → always blocked) from **Added** (new → exempt
only if registered in `tests_required[]`). Full rationale: [t-2205 deep-challenge report] and
ADR-061 §4 "Invariant 2 refinement".

| Component | File | Lines | Change |
|-----------|------|-------|--------|
| Goal declaration | `system/skills/build/phases/load.md` | Step 0 (39-43) | add `"base_ref": "$(git rev-parse HEAD)"` (single pin) + init `"tests_required": []` in the active-goal.json write |
| Test registration | `system/skills/build/phases/build-loop.md` | step 3d (~113) | after the failing test file is created, `jq` append its path to `active-goal.json.tests_required[]` (durable on disk → survives compaction) |
| Grader split | `system/hooks/goal-completion.sh` | 237-242 | replace single CHANGED block: (a) `--diff-filter=M` + grader regex → BLOCK; (b) `--diff-filter=A` + grader regex, unregistered → BLOCK; (c) `ls-files --others` + grader regex, unregistered → BLOCK |
| Audit emission | `system/hooks/goal-completion.sh` | new | per criterion: `{criterion, heuristic, evidence (commit/file), verdict}`; per registered file: `registered_as_red: bool` → `~/.claude/run-state/{task_id}-audit.jsonl` + additionalContext |
| Presence writer | `system/hooks/<presence-refresh>.sh` + settings wiring | new | UserPromptSubmit hook, `/dev/tty`-gated, `touch ~/.claude/run-state/presence-$SESSION_ID` |
| Tests | `system/hooks/tests/test-goal-completion.sh` | new G7/G8 | G7: registered new test exempted → auto-completes; G8: unregistered new fixture still blocked (G2-class preservation). Verify G1-G6 unchanged. |

**Deferred to Stage 3 (NOT this task):** red-verification pre-commit hook (registers a test in
`tests_required[]` only if it exits non-zero). Filed as its own task; `t-2206 blocked_by` it.

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

**Round 1 (single challenger, 2026-06-21):** 2 BLOCKERs. #2 session_id mismatch — **REFUTED by
probe** (`$BRANA_SESSION_ID` is present in Bash tool calls and equals the CC session UUID).
#4 base_ref self-sabotage — **CONFIRMED**: base_ref-at-goal-start trips the immutability gate on
every TDD run (new test file matches grader regex).

**Round 2 (deep challenge, 3 lenses — security / TDD-correctness / simplicity, 2026-06-21):**
UNANIMOUS verdict **Option C with `tests_required[]`** (above). Rejected: (A) re-pin base_ref —
clears the window retroactively, fragile across resume, fails build-loop step 3g; (B)
`--diff-filter=M` alone — no-op for untracked (pre-commit) state, regresses G2 if channel 2
dropped. The G2/TDD indistinguishability problem (a new test vs an injected fixture are
structurally identical on the untracked channel) is what forces the `tests_required[]`
registration. Two-phase split: Phase 1 (forensic trail) = this task; Phase 2 (red-verification
hook, hard enforcement) = Stage-3-blocking task. Full report: `/tmp/t-2205-deep-challenge-report.md`.
