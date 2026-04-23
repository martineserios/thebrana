# system/rules/ — Authoring Contract

Task: t-1285. Enforced by `validate.sh` Check 2.

## Every rule file must declare one of

| Frontmatter | Meaning | When to use |
|---|---|---|
| `paths: ["pattern/**", ...]` | **Scoped** — only loaded when a matching path is in the working set | Most rules. Pair the rule with the files it governs. |
| `always-load: true` | **Always loaded** — present in every session, counts against the context budget | Only for cross-cutting directives that must be universal (e.g. `universal-quality.md`, `git-discipline.md`, `sdd-tdd.md`). |

A rule declaring neither is rejected by `validate.sh`. A rule declaring both is allowed — `paths:` has no effect when `always-load: true` is set, but it can document intended primary scope.

## Why

Before t-1285, "no `paths:`" silently meant "always loaded." Authors adding a new rule without scoping would inflate the always-loaded context budget without noticing. The opt-in flag forces an explicit decision: *"is this rule genuinely global, or did I forget to scope it?"*

## Frontmatter example — scoped

```markdown
---
paths: ["system/hooks/**", "system/rules/**"]
---
# Rules Over Hooks for Behavioral Gates
...
```

## Frontmatter example — always-loaded

```markdown
---
always-load: true
---
# Quality Standards
...
```

## Budget accounting

`validate.sh` Check 5a sums the byte size of every `always-load: true` rule into the "always-loaded context budget" (cap: 28 KB). Path-scoped rules are excluded from this sum.

## Migration log

2026-04-23 (t-1285): 14 pre-existing rules without frontmatter received `always-load: true`. 2 rules using the legacy `globs:` field (`doc-linking.md`, `inbox-convention.md`) were migrated to `paths:`.

## Non-goals

- No automatic path inference. Authors declare intent.
- No support for `globs:` (legacy Cursor convention) going forward. Use `paths:`.
- No severity tiers (`P0 rule` vs `advisory rule`). Rules are enforceable directives; if a rule can be skipped, it belongs in a skill or procedure.
