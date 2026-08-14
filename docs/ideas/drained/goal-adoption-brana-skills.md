---
title: /goal Adoption — brana Skills
status: idea
created: 2026-05-24
related: cc-feature-adoption-v2.1.136-142.md
---

# /goal Adoption — brana Skills

> Brainstormed 2026-05-24.

## Problem

42 of 46 brana procedures lack `/goal`, leaving multi-turn sessions unanchored. Skills drift mid-execution — especially long `fix` and `brainstorm` sessions — requiring reorientation. `/goal` (CC v2.1.139) sets a completion condition that Claude works toward across turns and self-terminates when met.

## Audit Results

**Have /goal:** `build.md`, `close.md`, `research.md`, `ship.md` (4 of 46)

**High-value gaps:**

| Skill | Step Registry? | Goal role | Flag design |
|-------|---------------|-----------|-------------|
| `fix.md` | Yes (5 steps) | Anchor — orientation, not termination | Default on (`--no-goal` to skip) |
| `brainstorm.md` | Yes (9 steps) | Anchor — after SEED when slug known | Opt-in (`--goal` to enable) |
| `reconcile.md` | Yes | Anchor | Phase 2 |
| `align.md` | Yes | Anchor | Phase 2 |
| `docs.md` | No | Completion signal | Phase 2 |
| `onboard.md` | Partial | Completion signal | Phase 2 |

**Skip (single-turn or tool-driven):** `sitrep`, `log`, `retrospective`, `memory`, `gsheets`, `scheduler`, `plugin`, `gemini`

## Taxonomy

Two distinct `/goal` roles emerged from the brainstorm:

- **Anchor style** (for step-registry skills): `/goal` states the process and last step as terminator. Direction signal, not a precise completion trigger. Step registry handles "where am I"; `/goal` handles "where am I going."
- **Completion signal** (for simple skills without step registries): `/goal` states the concrete output artifact or outcome. Claude self-terminates when it verifies the output exists.

## Goal String Candidates (fix.md)

Two patterns to A/B test:

**Option A — Arrow protocol:**
```
/goal "fix {task-id}: reproduce → diagnose → fix → verify → commit"
```
Simple. Last step (commit) is the natural terminator.

**Option B — Step-registry-aware:**
```
/goal "fix {task-id}: all 5 step tasks completed — REPRODUCE, DIAGNOSE, FIX, VERIFY, COMMIT"
```
Explicit. Self-termination tied to task state, not prose interpretation.

**Approach:** Ship both as selectable variants (`--goal-style=arrow|registry`). Measure empirically over 3+ sessions each.

## Goal String (brainstorm.md)

Called after SEED (when slug is known):
```
/goal "brainstorm {slug}: explore → challenge → shape → save — idea doc committed at docs/ideas/{slug}.md"
```

Opt-in via `--goal` flag. Default behavior unchanged.

## Risks

| Risk | Mitigation |
|------|-----------|
| Premature self-termination in fix.md | Option A: COMMIT is last step; hard to satisfy early |
| /goal conflicts with open exploration in brainstorm | Opt-in flag; user controls when to enable |
| Option A vs B produce different behaviors | Treat as experiment; document findings in dim-58 |
| reconcile/align/docs left as gaps | Explicit Phase 2 scope; taxonomy doc covers them |

## Next Steps

1. **P1:** Edit `fix.md` — add `/goal` at Step 1 entry, default-on, `--no-goal` escape hatch. Ship Option A first.
2. **P1:** Edit `brainstorm.md` — add `/goal` call after SEED phase (slug known), `--goal` flag to enable.
3. **Validate:** Run 3 sessions each with/without flag. Note premature termination or drift incidents.
4. **Document:** Add findings to `brana-knowledge/dimensions/58-claude-code-changelog-2026.md` under "Field Notes: /goal adoption patterns."
5. **Phase 2:** Extend anchor pattern to `reconcile.md`, `align.md`; completion signal to `docs.md`, `onboard.md`.
