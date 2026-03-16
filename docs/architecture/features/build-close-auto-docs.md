# Feature: Auto-Generate Tech Docs + User Guide in CLOSE

**Date:** 2026-03-11
**Task:** t-382
**Status:** shipped
**Branch:** feat/t-382-build-close-docs

## Goal

Features were shipping without documentation — knowledge stayed trapped in code and git history. This adds template-driven doc generation to the /brana:build CLOSE step so every feature produces a tech doc (for developers) and a user guide (for users) automatically.

## Design Decisions

- **Template-driven, not free-form** — consistent structure across all feature docs. Templates live alongside the skill at `system/skills/build/templates/`.
- **Strategy-aware routing** — not all work types need both docs. Features/greenfield/migration get both; refactors get tech doc only if architecture changed; bug fixes skip entirely.
- **Separate from command/workflow docs** — user guides go to `docs/guide/features/` (new), not mixed with command reference. Tech docs go to existing `docs/architecture/features/`.
- **Inline in CLOSE step, not a separate skill** — follows automation-through-usage principle. Zero extra commands to remember.

## Code Flow

1. **Entry:** Documentation is front-loaded in two places: (a) SPECIFY feature spec includes a Documentation Plan section, (b) PLAN step mandates doc tasks in the task breakdown. CLOSE generates the actual doc content.
2. **Core:** CLOSE step 6 checks strategy → selects which templates to fill → generates docs from build context
3. **Output:** up to 2 files written per feature build

### Key Files

| File | Role |
|------|------|
| `system/skills/build/SKILL.md` | CLOSE step 4 — strategy routing + doc generation instructions |
| `system/skills/build/templates/tech-doc.md` | Tech doc template (Goal, Design Decisions, Code Flow, Testing, Limitations) |
| `system/skills/build/templates/user-guide.md` | User guide template (Quick Start, How It Works, Options, Examples, Troubleshooting) |
| `docs/guide/features/` | Output directory for user guides |
| `docs/architecture/features/` | Output directory for tech docs (pre-existing) |

## Testing

```bash
bash tests/skills/test_build_close_docs.sh
```

14 assertions: template existence, required sections, SKILL.md references, strategy routing, output directories.

## Known Limitations

- Templates are guidance, not enforced schema — the LLM fills them based on build context. Quality depends on how much context survived through the build.
- No automated validation that generated docs match the template structure (would require a post-write hook).
- Refactor tech docs are judgment-based ("only if architecture changed") — no automated detection.
