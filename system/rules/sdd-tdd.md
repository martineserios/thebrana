# Test-First Development

## Before implementation

Before writing or editing implementation code, answer: what test would verify this change?

- Write the test first. See it fail. Then implement.
- Bug fix: reproduce with a failing test before fixing.
- Refactor: run existing tests before and after.
- No test framework or no testable logic (config, docs, markup): state this and proceed.

Never weaken a test assertion without investigating the code. The test is right until proven otherwise.

## Enhanced enforcement (projects with decisions directory)

Projects with `docs/decisions/` or `docs/architecture/decisions/` activate stricter enforcement:

- **Spec/test before implementation.** PreToolUse hook blocks implementation file writes on `feat/*`, `fix/*`, `refactor/*` branches until a spec or test exists.
- **Spec activity that satisfies the gate:** commits/changes touching `docs/`, `test/`, `tests/`, `__tests__/`, or `*.test.*`/`*.spec.*` files.
- **Hook enforces spec-before-impl, not test-before-impl.** A spec doc alone satisfies the gate. TDD (test before code) is a discipline rule — when the gate passes via spec-only, still write the failing test before implementation. (Error 75, 2026-03-19)
