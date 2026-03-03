# ADR-009: Test/Lint Feedback Hook in PostToolUse Chain

**Date:** 2026-03-03
**Status:** accepted
**Task:** [t-043](../../.claude/tasks.json)

## Context

Brana logs corrections and cascades via PostToolUse hooks but has no structured signal for test/lint outcomes. Claude runs tests, they fail, code is edited, tests rerun — but the cycle's effectiveness is invisible. The flywheel metrics promised in [doc 14](../reflections/14-mastermind-architecture.md) (test_pass_rate, lint_pass_rate, auto_fix_rate) can't be computed without this signal.

DeAngelis (context engineering): "More structured feedback = less human-in-the-loop." Stop hooks are the strongest feedback — a structured event stream is the foundation for all downstream automation.

## Decision

### 1. Three-hook event stream

Instrument three existing hooks to classify tool outcomes and append events to a session-scoped JSONL file:

| Hook | Path | Fires on |
|------|------|----------|
| post-tool-use.sh | Success path | test-pass, lint-pass, correction, test-write, success |
| post-tool-use-failure.sh | Failure path | test-fail, lint-fail, failure + error_cat + cascade |
| session-end.sh | Session close | Aggregation, metrics, storage |

### 2. Runner detection via regex

Detect test runners and linters by matching Bash commands against known patterns:

- **Test runners:** npm test, npx jest/vitest/mocha, bun test, pytest, cargo test, go test, make test, ./validate.sh
- **Linters:** eslint, flake8, ruff check, pylint, cargo clippy, golangci-lint, shellcheck, biome check, npm run lint

Regex-based detection over AST parsing — shell commands are too varied for structured parsing, and false negatives (unknown runners classified as `success`) are harmless. False positives (ruff format classified as lint) are the real risk.

### 3. JSONL as append-only event stream

Each hook appends one JSON line to `/tmp/brana-session-{id}.jsonl`. Format:

```json
{"ts": "ISO8601", "tool": "Bash", "outcome": "test-pass", "detail": "npm test"}
{"ts": "ISO8601", "tool": "Edit", "outcome": "correction", "detail": "src/auth.ts", "error_cat": null, "cascade": false}
```

Why JSONL over SQLite: hooks run in subshells with no shared state. Append-only file is the simplest coordination mechanism — no locking, no schema, no connection pooling. session-end.sh reads once at flush.

### 4. Two-layer storage

- **Layer 1 (primary):** claude-flow SQLite via `memory_store`. Keys: `session:{project}:{id}` (patterns), `flywheel:{project}:{id}` (metrics). 5s timeout.
- **Layer 0 (fallback):** Append to `sessions.md` in project auto-memory. Always written if Layer 1 fails or is unavailable.

### 5. Seven flywheel metrics

| Metric | Formula | Signal |
|--------|---------|--------|
| correction_rate | corrections / edits | Planning quality (lower = better) |
| auto_fix_rate | fail→success pairs / failures | Self-repair (higher = better) |
| test_write_rate | test-write / edits | TDD discipline (higher = better) |
| cascade_rate | cascades / failures | Error handling (lower = better) |
| test_pass_rate | pass / (pass + fail) | Test health (higher = better) |
| lint_pass_rate | pass / (pass + fail) | Code quality (higher = better) |
| delegation_count | Task tool invocations | Context management |

N/A when denominator is zero (no test runs → test_pass_rate = N/A).

## Alternatives Considered

- **Structured hook output (JSON return):** Claude Code hooks expect `{"continue": true}` — no channel for structured data back to the session. JSONL sidecar is the only option.
- **SQLite per-event:** Adds locking complexity for concurrent hooks. JSONL is simpler for write-once-read-once pattern.
- **AST-based command detection:** Shell commands are too varied (aliases, scripts, makefiles). Regex with known-runner list is pragmatic and extensible.

## Consequences

- Every session produces structured test/lint signals for flywheel metrics
- Regex detection will miss custom runners — extensible by adding patterns
- False positives (ruff format as lint-pass) must be tested against — challenger identified this as critical bug #2
- Cascade detection requires consecutive failures — interleaved edits break the chain (known limitation, acceptable)
- session-end.sh grows in complexity — test coverage is essential (st-002, st-003, st-004)

## References

- Feature doc: [docs/features/test-lint-feedback-hook.md](../features/test-lint-feedback-hook.md)
- Architecture: [doc 14](../reflections/14-mastermind-architecture.md) — flywheel metrics
- Challenger review: 2026-03-03 — 2 critical bugs, 5 warnings (see feature doc §Known Issues)
