# Auto-Generated Feature Docs

Every time you build a feature with `/brana:build`, the CLOSE step automatically generates two documents: a tech doc for developers and a user guide for end users.

## Quick Start

```
/brana:build "my new feature"
# ... SPECIFY → PLAN → BUILD → CLOSE
# At CLOSE, brana auto-generates:
#   docs/architecture/features/my-new-feature.md  (tech doc)
#   docs/guide/features/my-new-feature.md          (user guide)
```

No extra commands needed — it happens as part of CLOSE.

## How It Works

1. You build a feature using `/brana:build` (or `/brana:backlog start`)
2. When the build reaches the CLOSE step, brana checks the strategy type
3. Based on the strategy, it generates the appropriate docs from templates
4. Docs are committed alongside the feature code

## Options

| Strategy | Tech Doc | User Guide |
|----------|----------|------------|
| feature | yes | yes |
| greenfield | yes | yes |
| migration | yes | yes |
| refactor | only if architecture changed | no |
| bug-fix | no | no |

## Examples

### Feature build

```
/brana:build "Add PDF export to proposals"
# At CLOSE, generates:
#   docs/architecture/features/pdf-export.md
#   docs/guide/features/pdf-export.md
```

Both docs are filled from the context of your build — design decisions from SPECIFY, implementation details from BUILD.

### Refactor (no user guide)

```
/brana:build "Refactor hook loading to use plugin registry"
# At CLOSE, generates:
#   docs/architecture/features/hook-loading-refactor.md  (if architecture changed)
# No user guide — refactors don't change user-facing behavior
```

## Troubleshooting

| Symptom | Fix |
|---------|-----|
| Docs not generated at CLOSE | Check strategy type — bug fixes and spikes skip docs |
| Doc content is thin | More context in SPECIFY = richer docs. Detailed specs pay off here |
| Want to regenerate docs | Edit the generated files directly — they're regular markdown |
