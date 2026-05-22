---
title: Brana Efficiency — Reduce Usage Without Losing Power
status: idea
created: 2026-05-22
---

# Brana Efficiency — Reduce Usage Without Losing Power

> Brainstormed 2026-05-22. Work in progress.

## Problem

Brana's daily usage is hitting limits. Usage breakdown (last 24h):
- 20% from `/brana:close` — Opus debrief-analyst spawned every session regardless of depth
- 34% from plugin "brana" — accepted as cost of brana being productive (not overhead)
- 18% from subagent-heavy sessions
- 11% from sessions >150k context

Primary pain: close is heavy, sessions bloat. Not: quota cap.

## Key Insight from Brainstorm

The 34% plugin cost is brana DOING work — not wasted overhead. Reducing it means doing less. Accept it.

The ruflo tool count (266 tools registered) appears large but schemas are **deferred** — CC lists names only, doesn't load schemas until ToolSearch is called. Tool count is not a significant cost driver.

The real levers: **close model tier** + **weight-adaptive close** + **context discipline**.

## Proposed Solution

### 1. debrief-analyst: Opus → Sonnet (immediate, 1-line change)

`system/agents/debrief-analyst.md` line 5: `model: opus` → `model: sonnet`

Rationale: debrief is structured extraction (errata classification, pattern routing) — not open-ended reasoning. Sonnet 4.6 executes these tasks at ≥90% of Opus quality. Opus earns its cost for genuinely open-ended reasoning (adversarial review, architecture design). Session analysis is not that.

Risk: might miss a subtle pattern on edge cases. Mitigation: findings reviewed by user before storing; easy to revert.

### 2. Weight-adaptive close (procedure change + escape hatch flags)

Current: close always spawns debrief-analyst, regardless of session depth.

New behavior:
- **LIGHT mode** (inline summary, no agent spawn): 0-1 commits in session AND no code file edits (only .md / state/ changes)
- **FULL mode** (debrief-analyst on Sonnet): ≥2 commits OR any code edits present (.rs, .ts, .py, etc.)
- Bias toward FULL: when ambiguous, default to full.

Escape hatch flags: `/brana:close --light` forces light mode, `/brana:close --full` forces full mode.

Implementation: Step 1 of `system/procedures/close.md` already runs `git log --since` and `git diff --stat`. Add a 10-line branch after those commands.

Close habit is preserved — it still runs on every session. Only the depth of analysis changes.

### 3. Context discipline (operational, not code changes)

- `/compact` after each heavy skill completes (especially after build, research, backlog plan)
- `/clear` when switching to a new task or project within the same session
- Don't mix brainstorm + implementation in the same session (known pattern: brainstorm+ops context split)

## What We're NOT Doing

- Ruflo tool pruning: tools are deferred (schemas not loaded). Keeping all 266 enabled — user wants access to them.
- Reducing close frequency: the habit is intentional and valuable (small learnings compound).
- Downgrading challenger: adversarial review needs reasoning depth — Sonnet is correct tier.

## Engineering Disciplines

- **DDD:** No ADR needed — these are tuning changes, not architectural decisions.
- **TDD:** Debrief quality check — run 5 closes on Sonnet, compare errata density to baseline before committing.
- **SDD:** Update `system/agents/debrief-analyst.md` + `system/procedures/close.md`. No doc system changes.

## Next Steps

1. Change `debrief-analyst.md` model line: `opus` → `sonnet`
2. Add weight-adaptive branching to `close.md` Step 1 Gate check
3. Add `--light` / `--full` argument handling to `close.md`
4. Run 5 closes, compare debrief quality — revert if pattern density drops
5. Document `/compact` discipline in CLAUDE.md field note
