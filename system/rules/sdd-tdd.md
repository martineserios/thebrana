# Test-First Development

## Before implementation

Before writing or editing implementation code, answer: what test would verify this change?

- Write the test first. See it fail. Then implement.
- Bug fix: reproduce with a failing test before fixing.
- Refactor: run existing tests before and after.
- No test framework or no testable logic (config, docs, markup): state this and proceed.

Never weaken a test assertion without investigating the code. The test is right until proven otherwise.

## Enhanced enforcement (projects with `docs/decisions/`)

Projects with `docs/decisions/` activate stricter enforcement:

- **ADR before implementation.** Use `/decide <title>` on `feat/*` branches. The PreToolUse hook blocks implementation files until a spec or test exists on the branch.
- **Feature branches require spec/test activity first.** Commits touching `docs/`, `test/`, `tests/`, or `*.test.*`/`*.spec.*` satisfy this.

Projects without `docs/decisions/` don't get hook enforcement, but the testing discipline above still applies.
