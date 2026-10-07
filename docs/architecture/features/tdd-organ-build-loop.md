# Feature: `tdd` organ — vendored Pocock `tdd`, called from the build loop and `/brana:fix`

**Date:** 2026-10-07
**Status:** specced — awaits ADR-097 acceptance; implementation is t-2981 (M, AC approved)
**Task:** t-2981 · ADR-097 D3 · ADR-085 D4/D6 · ADR-061 §4

## Problem

brana's TDD discipline is real but diffused: `system/rules/sdd-tdd.md` states it,
`system/skills/build/phases/build-loop.md` narrates it, `system/hooks/red-verification.sh`
registers a red test into `tests_required[]`, and the PreToolUse spec gate checks that *a
spec or test file exists* — not that a red actually ran. Pocock's `tdd` skill is a single
artifact that forces the sequence (one failing test → prove the red is real → smallest green
→ refactor) and, since PR #1209, adds "if you forced the red by mutating code or a fixture,
`diff` against a pristine copy to prove the mutation landed before you trust it."

ADR-085 D4 admits exactly one extraction from build: a phase that has ≥2 callers *and* must
run headless. The TDD step has both (build + fix; runner).

## Decision Record (frozen 2026-10-07, pending ADR-097)

**Context:** vendor+wrap is the proven pattern (three live adapters). His skill has no
termination engine and no grader-immutability rule; his check is human code review.
**Decision:** vendor `tdd` verbatim at the band pin; a ≤15-line adapter maps brana's inputs
(task packet, worktree, `/goal` span) to its expectations and **cuts his loop at green**.
Refactor runs in brana's existing post-green step, outside the `/goal` predicate.
**Consequences:** ADR-061 invariants 2 (done-signal immutability) and 3 (span boundary) are
re-asserted in the adapter, not inherited from upstream. The #1209 "prove the mutation
landed" step is kept as-is — it strengthens inv. 2's spirit (a red that was never really red
cannot register).

## Design

### Vendored organ

```
.agents/skills/tdd/            verbatim upstream, pinnedRef = band pin (v1.3.1)
  SKILL.md
  agents/openai.yaml           (if shipped)
.claude/skills/tdd  →  symlink
skills-lock.json               entry: source, skillPath, pinnedRef, computedHash, files[]
```

Hash via `system/scripts/skills-lock-hash.sh .agents/skills/tdd` (ADR-084 §7a: the script,
never by hand). `test-skills-lock-hash.sh` already loops every entry — no new test for the
lock.

### Adapter — `system/skills/tdd-organ/SKILL.md`

Name avoids collision with any built-in `tdd`. Model-invocation off (`disable-model-invocation:
true`); callers are build-loop and fix, explicitly, via `Call the Skill tool with "tdd-organ"`.

```
┌──────────────── tdd-organ (adapter, ≤15 lines) ────────────────────────┐
│ 1  Read the vendored skill: Skill("tdd") — .claude/skills/tdd/SKILL.md │
│ 2  Remap while following it:                                           │
│    "ticket" / "issue"          → the task packet (t-NNN subject + AC)  │
│    "the repo"                  → this worktree (never the main checkout)│
│    GLOSSARY.md                 → docs/domain/ (ADR-097 D7)             │
│    "write the failing test"    → write it, run it, let                 │
│                                  red-verification.sh register it      │
│                                  (tests_required[], ADR-061 inv. 2)   │
│    "make it pass"              → smallest green; STOP — the /goal span │
│                                  ends here (ADR-061 inv. 3)           │
│    "refactor"                  → NOT here; build-loop's post-green     │
│                                  step runs it outside the predicate   │
│ 3  Early exit: no red-capable test seam → say so, return to caller    │
│    (inherited; same shape as diagnose-hard-bug step 3)                │
└─────────────────────────────────────────────────────────────────────────┘
```

Station-admission checklist (ADR-085 D6, answered in the adapter's header comment):
queue = the build-loop subtask list · stop = green or early-exit · packet in = task packet +
worktree · packet out = test path(s) registered + green run output · dead-letter = early-exit
returns to caller, no retry · judge = `red-verification.sh` (red) + caller's gates (green) ·
rooms = headless-capable, no human prompt inside · assimilate = none (stateless) · restart =
re-run from step 1, no state carried.

### Callers

| Caller | Where | What changes |
|---|---|---|
| `/brana:build` | `build-loop.md` BUILD step 3 (write failing test → implement) | the two sub-steps become one call to `tdd-organ`; the post-green refactor sub-step is unchanged |
| `/brana:fix` | FIX step 2 ("make the failing test pass") | calls `tdd-organ` with the REPRODUCE test as the red |
| runner (`claude -p`) | via build, unchanged | headless path proven by the adapter having no prompt |

### Upstream step headings the adapter depends on

Recorded so the pin-bump diff reviewer knows what to check: `## Steps` with the numbered
red → mutation-proof → green → refactor sequence; the "Watch it fail" step text. A rename of
either is a shape change (ADR-097 "Risk retained").

## Tests (write first)

- `system/scripts/tests/test-tdd-organ-redirects.sh` — every cross-skill reference in the
  vendored `SKILL.md` appears in the adapter's `redirect-check.md` (same test shape as the
  diagnose-hard-bug pilot).
- `test-skills-lock-hash.sh` — already generic; the new entry is covered.
- One real build run through the wrapped step, recorded in t-2981's notes (AC 3). Evidence:
  `tests_required[]` gained the new test's path *via the hook*, not by hand.

## Acceptance criteria (t-2981, approved — unchanged)

1. `tdd` vendored pinned per ADR-084 pin+sync policy; adapter ≤ ~15 lines mapping brana inputs.
2. `build-loop.md`'s TDD step invokes the adapter; `/brana:fix` can invoke the same adapter (≥2 callers proven).
3. One real build run through the wrapped tdd, recorded in task notes.
4. Station-admission checklist answered in the adapter's header comment.

Added by this spec (ADR-097 D3), to be folded into t-2981's AC on acceptance:

5. The adapter stops at green; refactor is observably outside the `/goal` span (the goal
   predicate evaluates true before any refactor edit).
