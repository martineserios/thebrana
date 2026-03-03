# ADR-010: PR Review Agent via PostToolUse Hook

**Date:** 2026-03-03
**Status:** accepted
**Task:** [t-044](../../.claude/tasks.json)

## Context

Brana's feedback loop captures test/lint signals (ADR-009) but has no structured code review signal. When a PR is created, the diff goes unreviewed until a human looks at it. A PR review agent, auto-triggered by detecting `gh pr create` in PostToolUse, would provide immediate structured feedback on code quality, security, and style — closing the review gap identified in the context engineering analysis (backlog #61).

## Decision

### 1. PostToolUse hook detects `gh pr create`

A dedicated hook file (`post-pr-review.sh`) fires on Bash tool use. It matches the command against `gh\s+pr\s+create` and returns an `additionalContext` nudge to auto-delegate to the pr-reviewer agent. This is advisory — not blocking.

Separate hook file (not embedded in post-tool-use.sh) because:
- post-tool-use.sh handles outcome classification (test/lint/correction)
- PR review is a different concern: delegation trigger, not metric collection
- Follows the post-plan-challenge.sh pattern (single-purpose PostToolUse hooks)

### 2. pr-reviewer agent (Sonnet, read-only + Bash)

| Property | Value |
|----------|-------|
| Model | Sonnet |
| Tools | Read, Glob, Grep, Bash |
| Disallowed | Write, Edit, NotebookEdit |
| Trigger | `additionalContext` nudge from hook |

The agent reads the PR diff via `gh pr diff`, checks for security issues, logic bugs, style violations, missing tests, and breaking changes. Output is a structured review with severity levels.

### 3. Session event logging

The hook appends a `pr-create` outcome to the session JSONL file. session-end.sh counts PR creates alongside existing metrics, enabling trending of PR creation frequency.

### 4. post-tool-use.sh integration

post-tool-use.sh gains `pr-create` as an outcome type in its Bash command classification, so the main event stream also captures the signal for flywheel metrics.

## Alternatives Considered

- **PreToolUse blocking gate:** Would prevent PR creation until review passes. Too aggressive — review is advisory, not mandatory.
- **Embedding in post-tool-use.sh:** Would mix concerns (metric classification vs. delegation trigger). Separate file is cleaner and follows existing patterns.
- **Opus model for reviewer:** Overkill for code review. Sonnet is sufficient for structured diff analysis and much faster.

## Consequences

- Every `gh pr create` triggers a structured code review nudge
- PR review frequency becomes a trackable session metric
- The agent is read-only — cannot modify code, only advise
- False positives from commands containing "gh pr create" as a substring are possible but harmless (advisory only)

## References

- Feature doc: [docs/features/pr-review-agent.md](../features/pr-review-agent.md) (planned)
- Architecture: [doc 14](../reflections/14-mastermind-architecture.md) — feedback loop gaps
- Predecessor: [ADR-009](ADR-009-test-lint-feedback-hook.md) — test/lint feedback hook
