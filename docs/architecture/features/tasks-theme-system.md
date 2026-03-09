# Feature: Themeable Task Display

**Date:** 2026-02-27
**Status:** shipped

## Goal

Make `/brana:tasks` output visually configurable with 3 display themes (classic, emoji, minimal), selectable via persistent config with per-command override — so the user picks the aesthetic they prefer once and every subcommand respects it.

## Audience

Solo developer using brana's task system across multiple projects.

## Constraints

- Skill is instruction-based (SKILL.md), not code — themes are rendering instructions, not code logic
- Must not break existing output for users who don't set a theme (classic = current behavior)
- Emoji characters are 2-char width in monospace — alignment instructions must account for this
- Config file must be simple (JSON, <10 lines)
- Box-drawing characters require UTF-8 terminal (universal on modern systems)

## Scope (v1)

### Three themes

| Element | Classic | Emoji | Minimal |
|---------|---------|-------|---------|
| Done | `✓` | `✅` | `●` |
| In progress | `←` | `🔨` | `◐` |
| Pending | `→` | `🔲` | `○` |
| Blocked | `·` | `🔒` | `⊘` |
| Parked | `·` | `💤` | `◌` |
| Progress fill | `█` | `█` | `━` |
| Progress empty | `░` | `░` | `╍` |
| Tree connectors | `├── └── │` | `├── └── │` | `├── └── │` |
| Project header | plain | `📋` prefix | plain |
| Portfolio header | plain | boxed `╭╮╰╯` + `📊` | plain |
| Priority high | `high` | `⚡high` | `high` |
| Blocked ref | `blocked by t-NNN` | `⛓ t-NNN` | `← t-NNN` |
| Health dot | — | `🟢`/`🟡`/`🔴` | — |

### Persistence (hybrid)

- **Config file:** `~/.claude/tasks-config.json` (global only — simplified from per-project after challenger review)
- **Set command:** `/brana:tasks theme <name>` writes to config
- **Override flag:** `--theme <name>` on any subcommand, one-time
- **Default:** `classic` when no config exists
- **Resolution:** `--theme` flag > global config > classic default

### Box-drawing trees

All themes use `├──`, `└──`, `│` for roadmap hierarchy. Replaces indentation-only style.

### Affected subcommands

Every subcommand that renders output: status, portfolio, roadmap, next, tags, context, start, done, add, execute.

## Deferred

- Custom themes (user-defined icon maps)
- Color themes (if Claude Code ever supports ANSI)
- Per-project theme override (project-level config)
- Compact/verbose density toggle (orthogonal to theme)

## Research findings

- Modern CLIs (gh, cargo, taskwarrior) use configurable output formats
- Unicode box-drawing is standard for tree views (tree, npm ls)
- Partial block characters give smooth progress bars
- Emoji 2-char width is the main alignment challenge in monospace
- Claude Code renders GFM markdown in monospace — code blocks preserve spacing

## Design

### Post-challenger adjustments
- **Theme drift mitigation:** Uses "task-line template" pattern — compact inline block near top of SKILL.md, referenced by name in every rendering section. Avoids distant lookup table problem.
- **Config simplified:** Global-only (`~/.claude/tasks-config.json`), 2-level resolution (flag > global > classic). No per-project config.
- **Emoji alignment:** Accepted as trade-off. Emoji theme trades column precision for visual scannability.
- **Tree connectors:** Universal (all themes), removed from theme table since they don't vary.
- **No ADR:** Cosmetic feature in a single file with no architectural impact.

### Files modified
- `system/skills/tasks/SKILL.md` — theme system + rendering updates (617 → 758 lines)

## Learnings

- Instruction-based systems (SKILL.md) need repetitive local references, not distant lookup tables — LLMs attend to nearby examples
- Challenger review caught the core risk (theme drift) before build, saving rework
- The "render using task-line template" phrase acts as a consistent anchor across sections

## Open questions

None — shaped interactively, design validated by challenger.
