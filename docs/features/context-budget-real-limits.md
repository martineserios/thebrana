# Feature: Context Budget Real Limits

**Date:** 2026-02-20
**Status:** shipped
**Backlog:** #55

## Goal

Correct doc 35's misleading "<1% of 200K" claim, add instruction-count validation to `validate.sh`, and document MCP server budget advisory — so the context budget system reflects the true overhead picture.

## Audience

Brana developers (us) — ensuring the budget guardrails match reality.

## Constraints

- Doc changes in enter repo, code changes in thebrana repo
- Instruction counting must be automatable (in validate.sh)
- No new tools or runtime monitoring — keep it deploy-time
- MCP overhead is outside brana's control; only advisory guidance

## Scope (v1)

1. Count current instructions (audit baseline)
2. Add instruction counter to validate.sh (warn >30, error >150)
3. Update doc 35 budget narrative (correct claims, add full overhead picture)
4. Add MCP advisory to context-budget.md rule (5 lines)
5. Update backlog #55 as done

## Deferred

- MCP overhead monitoring tool (wrong layer — Tool Search already mitigates)
- 1M token extended context consideration (attention quality, not window size)
- Per-MCP-server token cost measurements (not publicly available)

## Research findings

- Total fixed overhead: 76-142K tokens (38-71% of 200K), not the <1% doc 35 claims
- MCP tools: 30-70K tokens, reduced to ~8.5K by Tool Search (85%)
- Compaction buffer: 33-45K reserved by Claude Code (invisible to user)
- Instruction density: >150-200 rules causes model inconsistency
- Docs 08, 22 already spec instruction limits (~30 always-present) but validate.sh doesn't enforce them
- Challenger verdict: keep bytes as coarse guardrail, add instruction count as primary quality gate

## Design

### Instruction counting heuristic

Count lines matching directive patterns in always-loaded files:
- Lines starting with `- **` (bold-prefixed list items = directives)
- Lines starting with `- ` followed by imperative verbs (Always, Never, Use, Prefer, Avoid, Check, Run, Keep, Only, Do, Don't)
- Lines in `| ... |` format (table rows with instructions)
- Headings that contain directives (`## Never...`, `## Always...`)

This is a heuristic, not a parser. It's good enough to catch budget creep — not meant to be exact.

### Files to modify

| File | Repo | Change |
|------|------|--------|
| `validate.sh` | thebrana | Add instruction counter (Check 5b) |
| `35-context-engineering-principles.md` | enter | Correct budget narrative |
| `context-budget.md` (rule) | thebrana | Add MCP advisory section |
| `30-backlog.md` | enter | Mark #55 done |
