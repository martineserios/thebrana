---
status: accepted
produced_by: docs/ideas/brana-v2-compute-model.md
depends_on: []
---
# ADR-040: brana Compute Hierarchy — Claude / Ruflo / Gemini

**Status:** Accepted
**Date:** 2026-05-24
**Task:** t-1625 (brana-v2-compute-model initiative)

---

## Context

brana v2 unifies three independently-designed workstreams — efficiency tuning, Gemini
delegation, and Ruflo multi-agent coordination — into a single layered compute stack.
All three attack the same constraint: brana runs on one compute source (Claude's token
pool, serial execution).

Before this ADR, each workstream was designed separately, creating ambiguity about:
- Which entity is authoritative for any given operation
- Whether Ruflo and Gemini can interact directly
- Which model runs debrief-analyst and why
- When to spawn an agent vs delegate to Gemini vs run inline

This ADR locks seven architectural decisions that must be stable before any delegation
wiring lands (Phases 2–6 of the initiative).

---

## Decision

### 1. Claude is the only system writer

Git, `tasks.json`, hooks, and all ruflo stores go through Claude. Gemini output and
ruflo coordination are inputs to Claude's judgment — never direct writes.

This includes: creating files, applying diffs, merging branches, writing memory entries,
and updating task state. No other entity does these things.

### 2. Ruflo coordinates Claude sub-agents only

`agent_spawn`, `claims`, and `hive-mind` are Claude-to-Claude primitives. Ruflo is a
coordination substrate for Claude workers — it does not coordinate Gemini or any
non-Claude agent type.

### 3. Gemini is dispatched, never coordinated

`agy` (the Gemini delegate) is stateless and fire-and-forget. It has no session ID,
cannot hold claims, cannot report mid-task status, and cannot participate in hive-mind.
Claude dispatches it and reads the result; Ruflo never calls `agy` directly.

Gemini is appropriate for: atomic, system-isolated, brana-agnostic tasks — bulk
summarization, competitive research, boilerplate generation (when enriched by ruflo),
parallel token-heavy work. It is inappropriate for: anything requiring in-session brana
state, multi-step tasks, or direct repo writes.

### 4. Hive-mind quorum workers are Claude only

Quorum deliberation requires brana ADR context, system judgment, and in-session state.
These are Claude capabilities. Gemini has none of them. Quorum workers are always Claude
instances coordinated via ruflo hive-mind.

### 5. /tmp/ invariant is absolute

All Gemini output lands in `/tmp/` only. The MCP server hardcodes this path. Callers
cannot override it. Claude reads `/tmp/result.md` and applies changes to the repo via
`Write`/`Edit` — the CC hooks fire normally, no bypass.

This invariant prevents direct Gemini writes to the codebase and ensures CC hook
enforcement is always active on any change that lands in the repo.

### 6. Sonnet for debrief-analyst

The debrief-analyst agent runs on Sonnet, not Opus. Debrief is structured extraction:
classifying errata, process learnings, and transferable patterns from session output.
This does not require open-ended reasoning. Opus earns its cost only for adversarial
review (challenger) and architecture design requiring broad judgment.

This change applies immediately. Both CLAUDE.md agent tables and the agent frontmatter
must be updated in the same commit.

### 7. Weight-adaptive close

`/brana:close` classifies each session as FULL or LIGHT before deciding whether to spawn
debrief-analyst. Classification is based on `git diff --name-only` output — not
`--stat`, which gives line counts requiring fragile parsing.

**FULL** triggers when ANY of these is true:
- ≥2 commits in the session
- Any changed file matches: `.rs .ts .tsx .js .jsx .py .sh .toml .yaml .yml`
- Any `.json` under `system/` or `.claude/` (behavioral config)

**LIGHT** when ALL changed files are: `.md`, `state/*.json`/`tasks.json`, or `inbox/`

**Escape hatches:** `--light` forces LIGHT; `--full` forces FULL.

Ambiguous cases (authoritative):
- `.sh` hook edits → FULL (behavioral, high-stakes)
- `tasks.json` only → LIGHT (state file)
- `settings.json` → FULL (behavioral config)

Status: `[NOT YET IMPLEMENTED — Phase 0]`. The extension list above is committed to code
in `close.md`, not inferred from prose.

---

## Routing Summary

```
Is this brana-system work?
  YES → Claude only. Never delegate.

  NO — Is it atomic, system-isolated, context-enrichable?
    NO  → Claude only.

    YES — Is it convention-sensitive?
          (boilerplate, test scaffolding, ADR drafts, naming/structure decisions)
          Default: treat as convention-sensitive when in doubt.

      YES — Is ruflo available?
        NO  → ABORT. Error: "ruflo required for convention-sensitive task."
        YES → Gemini (agy_delegate) with ENRICH step mandatory.

      NO  — Is it a sub-agent needing cost tracking?
        YES → ruflo agent_spawn.
        NO  — Is it parallel, bulk, or token-heavy for Claude?
          YES → Gemini (agy_delegate), ENRICH optional.
          NO  → Claude inline.
```

---

## Consequences

- Phases 2–6 of brana-v2-compute-model may now be implemented; this ADR is their gate.
- Delegation wiring must enforce decisions 1–5 structurally — code, not convention.
- Decision 6 (Sonnet for debrief) is an immediate 3-line change; applies before Phase 0 is done.
- Decision 7 (weight-adaptive close) is Phase 0 implementation; tests required before marking done.
- Any future agent type added to the system must be assessed against decisions 2–4 before wiring.

## Non-Actions

- This ADR does not define the Gemini delegation API contract (covered in Phase 3 / t-1576).
- This ADR does not set hive-mind quorum thresholds (covered in t-1638, after t-1599 calibration).
- This ADR does not specify the ENRICH/PERSIST step implementation (covered in Phase 4 / t-1629, t-1631).
- This ADR does not address the lost-update risk on concurrent tasks.json writes (tracked separately).
