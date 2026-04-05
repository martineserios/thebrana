# ADR-031: Doc-Enforcement Hook (Scoped Hard Block)

**Date:** 2026-04-04
**Status:** accepted
**Tasks:** t-900
**Source:** Operating model §6

## Context

72% of behavioral commits (124/172) have no documentation updates. The auto-learning loop (ADR-027) is the primary fix — EXTRACT catches changes and PERSIST prompts docs. But auto-learning takes months to reach full coverage (Phase C). Meanwhile, the 72% rate continues.

The existing `tdd-gate.sh` (PreToolUse hook) proves scoped enforcement works: it blocks Write/Edit on feat/fix branches when test files are missing. The same pattern can enforce documentation.

## Decision

Add a PreToolUse deny hook that blocks commits on feat/fix branches when behavioral files changed but no documentation file was included.

### Scope

**Behavioral files** (changes that affect user-visible behavior):

```
system/skills/**
system/hooks/**
system/agents/**
system/commands/**
~/.claude/rules/**
```

**Documentation files** (any of these satisfies the gate):

```
docs/architecture/**
docs/guide/**
docs/reference/**
CLAUDE.md
system/CLAUDE.md
```

### Trigger

PreToolUse on Bash tool, matching `git commit` commands. The hook:

1. Checks current branch — only fires on `feat/*` and `fix/*` branches
2. Runs `git diff --cached --name-only` to get staged files
3. If any behavioral file is staged AND no documentation file is staged → **deny with message**
4. If no behavioral files staged → **allow** (non-behavioral commits pass freely)

### Escape Hatch

`--no-doc-check` in the commit message bypasses the hook. Logged to event log for weekly review.

### Relationship to Auto-Learning

| Mechanism | Coverage | Speed |
|-----------|----------|-------|
| Auto-learning (EXTRACT) | ~90% (when fully deployed) | Month 3+ |
| Doc-enforcement hook | ~10% insurance | Month 1 |

The hook is insurance, not the primary solution. It catches the cases where auto-learning hasn't triggered or the user declined the suggestion. As auto-learning matures, the hook fires less often.

### Implementation

Modeled after `tdd-gate.sh`:
- Same hook type (PreToolUse deny)
- Same branch scoping (feat/fix only)
- Same escape pattern (flag in commit message)
- Lives at `system/hooks/doc-gate.sh`

## Consequences

- Commits on feat/fix branches require docs when behavioral files change
- Main branch is unaffected (most current work happens on main — this changes gradually)
- Combined with auto-learning, targets the 72% → <30% within month 1
- Escape hatch prevents hard blocks on urgent fixes
- Hook fires less as auto-learning matures
