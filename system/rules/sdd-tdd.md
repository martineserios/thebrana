# Spec-Driven & Test-Driven Development

## When `docs/decisions/` exists in the project

This project has opted into spec-driven development:

- **Create an ADR before implementing any new feature.** Use `/decide <title>` to create one in `docs/decisions/`. The PreToolUse hook will block implementation on `feat/*` branches until a spec or test exists.
- **Write tests before implementation code.** If TDD-Guard is installed, it enforces this automatically.
- **Feature branches (`feat/*`) must have spec/test activity before implementation.** Commits touching `docs/`, `test/`, `tests/`, or `*.test.*`/`*.spec.*` files satisfy this requirement.

## When `tdd-guard` is installed

TDD-Guard enforces RED-GREEN-REFACTOR:
- Write a failing test first
- Write minimal code to pass
- Refactor while green
- Toggle with `tdd-guard on/off`

## For projects without `docs/decisions/`

These rules don't apply — the project hasn't opted into SDD enforcement.

## Recommended setup for new projects

- `mkdir -p docs/decisions` — opt into spec-driven enforcement
- `npm install -g tdd-guard && tdd-guard on` — opt into TDD enforcement
