# Test-First Development

## Always

For every non-trivial code change:

- **Bug fix:** write a failing test that reproduces the bug, then fix it.
- **New function or feature:** write at least one test before the implementation.
- **Refactor:** verify existing tests pass before and after.

When tests exist, run them before committing. When they don't, write one.

Never weaken a test assertion without first investigating why it fails. The code is wrong until proven otherwise.

## Enhanced enforcement (projects with `docs/decisions/`)

Projects with `docs/decisions/` activate stricter enforcement:

- **ADR before implementation.** Use `/decide <title>` on `feat/*` branches. The PreToolUse hook blocks implementation files until a spec or test exists on the branch.
- **Feature branches require spec/test activity first.** Commits touching `docs/`, `test/`, `tests/`, or `*.test.*`/`*.spec.*` satisfy this.

Projects without `docs/decisions/` don't get hook enforcement, but the testing discipline above still applies.
