---
depends_on:
  - docs/architecture/decisions/ADR-009-test-lint-feedback-hook.md
---
# t-601: TDD Enforcement Gate

## Problem
Recurring TDD violations — implementation written before tests. The sdd-tdd rule exists but is advisory only.

## Solution
PreToolUse hook that blocks .rs impl file writes on feat/fix branches until a test file exists in the same crate.

## Gate Logic
- Trigger: Edit/Write on `*.rs` (excluding test files)
- Branch: feat/* or fix/* only
- Check: any `*_test.rs`, `test_*.rs`, `tests/` dir, or `#[cfg(test)]` in the crate
- Block if no test found, allow otherwise
