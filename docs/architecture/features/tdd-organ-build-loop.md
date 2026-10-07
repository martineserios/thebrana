# Feature: `tdd` organ — vendored Pocock `tdd`, called from the build loop and `/brana:fix`

**Date:** 2026-10-07 (revised same day after the ADR-097 challenge)
**Status:** specced — ADR-097 accepted; implementation is t-2981 (M, AC approved), gated on P0 and P1
**Task:** t-2981 · ADR-097 D3 · ADR-085 D4/D6 · ADR-061 §4 · twins t-3010, t-3018

## Problem

brana's TDD discipline is real but diffused: `system/rules/sdd-tdd.md` states it,
`system/skills/build/phases/build-loop.md` narrates it (steps 3c–3h: state the change, write
the failing test, implement, verify, probe boundaries, commit), `system/hooks/red-verification.sh`
registers a red test into `tests_required[]` on the red commit, delegated subtasks receive
`system/skills/_shared/delegation-tdd-checklist.md` instead, and the PreToolUse spec gate checks
that *a spec or test file exists*, not that a red ran. Pocock's `tdd` skill is one artifact
that forces the sequence: name the seam, one failing test, prove the red is real, smallest
green, then refactor.

ADR-085 D4 admits exactly one extraction from build: a phase with ≥2 callers that must run
headless. The write-test → implement pair has both (build + fix; runner).

## Decision Record (frozen 2026-10-07, ADR-097 D3)

**Context:** vendor+wrap is the band's pattern, but the challenge found the band's call path
had never worked: `disable-model-invocation: true` blocks the Skill tool (ADR-076 verified
finding #3), and both live adapters carry it. Organs are repo-local (`bootstrap.sh` syncs only
`system/`). `build-loop.md` has no refactor step.
**Decision:** vendor `tdd` verbatim at the band pin; a ≤15-line **model-invocable** adapter
covers **write the failing test → smallest green** only. The red commit (3d1), the test gate
(3d2), verify, probe boundaries and commit stay caller-owned. Callers probe that the organ
resolves and run today's inline prose when it does not. His refactor step is **out of scope**:
brana's loop has no refactor step today, and t-3018 (refactor-split spike) decides whether one
is added and where. This spec does not pre-decide it.
**Consequences:** ADR-061 invariants 2 (done-signal immutability) and 3 (span boundary) are
untouched because the registration commit and the gate never move. The inline prose and the
organ coexist; a resolution test catches a missing organ, not drift between the two texts,
which t-3010's consolidation addresses.

## Design

### Vendored organ

```
.agents/skills/tdd/            verbatim upstream, pinnedRef = band default pin (v1.3.1)
  SKILL.md (+ agents/openai.yaml if shipped)
.claude/skills/tdd  →  symlink
skills-lock.json               source, skillPath, pinnedRef, computedHash, files[]
```

Hash via `system/scripts/skills-lock-hash.sh .agents/skills/tdd` (never by hand).
`test-skills-lock-hash.sh` already loops every entry.

### Adapter — `system/skills/tdd-organ/SKILL.md`

Model-invocable (no `disable-model-invocation`; the flag would block the very Skill-tool call
its callers make). Its `description` is one short line so the ambient trigger text stays
cheap; callers invoke it explicitly with `Call the Skill tool with "tdd-organ"`.

```
┌──────────────── tdd-organ (adapter, ≤15 lines) ────────────────────────┐
│ 0  Record entry: append {task, caller, ts} to                          │
│    ~/.claude/run-state/pocock-tdd.jsonl (ADR-097 D1 proxies)          │
│ 1  Read the vendored skill: Skill("tdd") — .claude/skills/tdd/SKILL.md │
│ 2  Remap while following it:                                           │
│    "ticket" / "issue"          → the task packet (t-NNN subject + AC)  │
│    "the repo"                  → this worktree (never the main checkout)│
│    GLOSSARY.md                 → docs/domain/ (shared remap note, D7)  │
│    "name the seam"             → surface it from the packet; stop for  │
│                                  confirmation only if the packet lacks │
│    "write the failing test"    → write it, run it, RETURN to caller:  │
│                                  the caller commits (3d1) and the hook │
│                                  registers it (ADR-061 inv. 2)        │
│    "make it pass"              → smallest green; STOP — the /goal span │
│                                  ends here (ADR-061 inv. 3)           │
│    "refactor"                  → not here; out of scope (t-3018)       │
│ 3  Early exit: no red-capable seam → say so, return to caller         │
└─────────────────────────────────────────────────────────────────────────┘
```

Two calls per subtask, not one: the caller invokes the adapter for the red, runs its own 3d1
commit and 3d2 gate, then invokes it again for the green. That is what keeps registration and
the gate in the wrapper (ADR-085 D4).

Station-admission checklist (ADR-085 D6, in the adapter's header comment): queue = the
build-loop subtask list · stop = test written / green / early-exit · packet in = task packet +
worktree + phase (red | green) · packet out = test path(s) or green run output · dead-letter =
early-exit returns to caller · judge = `red-verification.sh` (red) + caller's gates (green) ·
rooms = headless-capable, no prompt inside except the seam confirmation · assimilate = none ·
restart = re-run from step 0.

### Callers and the fallback

| Caller | Where | What changes |
|---|---|---|
| `/brana:build` | `build-loop.md` 3d (write failing test) and 3e (implement) | each becomes: probe `.claude/skills/tdd/SKILL.md` resolves → call `tdd-organ` with phase; else run the existing inline text, which stays in the file |
| `/brana:fix` | REPRODUCE step 3 (write the failing test) and FIX step 2 | same probe + call pattern; fix commits its red too |
| delegated subtasks | `delegation-tdd-checklist.md` | unchanged; the checklist gains one line pointing at the adapter when the organ resolves |
| runner (`claude -p`) | via build, unchanged | headless path proven by the adapter having no prompt except the seam confirmation, which the packet pre-empts |

### What the organ brings that brana's prose does not state (research 2026-10-07 §6 S8)

Kept through the remap; none conflicts with ADR-061:

- **Seam gate** — "No test goes at an unconfirmed seam": the public boundary is named before
  any test file exists.
- **Tautology question** — "If the implementation were wrong, would this test still pass?"
  asked of every red before the caller commits it.
- **One test at a time** — watch red then green with the test unchanged; no horizontal layer
  of tests written up front.
- **Mock boundary** — "Mocks are for system boundaries only… never mock your own modules."

Note: PR #1209's "prove a forced mutation landed" step is in `diagnosing-bugs`, not `tdd`, and
is not in v1.3.1 (ADR-097 D2). It is not part of this organ.

### Upstream step headings the adapter depends on

Recorded so the pin-bump diff reviewer and the heading-presence test know what to check: the
`## Steps` list and the step texts for naming the seam, writing the failing test, watching it
fail, and making it pass (verified at v1.3.1 during P1; the exact strings are copied into
`redirect-check.md` then). A rename is a shape change (ADR-097 D1 "rework").

## Tests (write first)

- `system/scripts/tests/test-tdd-organ-resolves.sh` — the organ symlink resolves in this repo;
  in a fixture repo without `.agents/skills/tdd` the caller's probe takes the inline branch.
- `system/scripts/tests/test-tdd-organ-redirects.sh` — every cross-skill reference in the
  vendored `SKILL.md` appears in the adapter's `redirect-check.md`; every heading the adapter
  names exists in the vendored file (created in P1 for all organs; this one lands with P2).
- `test-skills-lock-hash.sh` — generic; the new entry is covered.
- One real build run through the wrapped steps, recorded in t-2981's notes (AC 3), with the
  new test path landing in `tests_required[]` **via the hook on the 3d1 commit**, not by hand.

## Acceptance criteria (t-2981, approved — unchanged)

1. `tdd` vendored pinned per ADR-084 pin+sync policy; adapter ≤ ~15 lines mapping brana inputs.
2. `build-loop.md`'s TDD step invokes the adapter; `/brana:fix` can invoke the same adapter (≥2 callers proven).
3. One real build run through the wrapped tdd, recorded in task notes.
4. Station-admission checklist answered in the adapter's header comment.

Added by this spec (ADR-097 D3), to be folded into t-2981's AC on start:

5. The adapter is model-invocable and the caller's probe-then-fallback is tested
   (`test-tdd-organ-resolves.sh`).
6. 3d1 (red commit) and 3d2 (gate) remain in `build-loop.md`, with a test asserting the
   adapter is called twice per subtask around them.
7. Docs: `docs/reference/skills.md` lists `tdd-organ`; this spec's status flips to implemented.
