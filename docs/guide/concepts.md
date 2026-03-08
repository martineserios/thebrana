# Concepts

Glossary of brana terms.

## System components

| Term | What it is |
|------|-----------|
| **Skill** | A slash command that guides a specific workflow. Lives in `system/skills/{name}/SKILL.md`. |
| **Hook** | A shell script that runs automatically on events (session start/end, before/after tool use). Lives in `system/hooks/`. |
| **Rule** | A behavioral directive loaded every session. Lives in `system/rules/`. Short, prescriptive. |
| **Agent** | A specialized sub-agent that auto-delegates when context matches. Lives in `system/agents/`. |
| **Command** | A server-side command that appears in the `/` menu. Lives in `system/commands/`. |

## Task system

| Term | What it is |
|------|-----------|
| **Phase** | Top-level work container (`ph-NNN`). Groups milestones. |
| **Milestone** | Mid-level grouping (`ms-NNN`). Groups tasks. |
| **Task** | A unit of work (`t-NNN`). Has status, tags, stream, priority. |
| **Stream** | Category of work: `roadmap`, `bugs`, `tech-debt`, `docs`, `experiments`, `research`. |
| **Strategy** | How `/build` approaches the work: `feature`, `bug-fix`, `refactor`, `spike`, `migration`, `investigation`, `greenfield`. |
| **Build step** | Current position in the build loop: `classify`, `specify`, `plan`, `build`, `close`. |

## Knowledge system

| Term | What it is |
|------|-----------|
| **Dimension doc** | Deep research document in `brana-knowledge/dimensions/`. Source of truth for a topic. |
| **Reflection doc** | Cross-cutting synthesis in `docs/reflections/`. Derives from dimensions. |
| **Roadmap doc** | Implementation plan in `docs/`. Derives from reflections. |
| **Pattern** | A learned problem-solution pair stored in claude-flow memory with a confidence score. |
| **Auto memory** | Claude-authored notes in `~/.claude/projects/*/memory/MEMORY.md`. Persists across sessions. |

## Development practices

| Term | What it is |
|------|-----------|
| **SDD** | Spec-Driven Development — write the spec before the code. |
| **TDD** | Test-Driven Development — write the test before the implementation. |
| **ADR** | Architecture Decision Record — documents a design decision in `docs/decisions/`. |
| **Feature spec** | Merged ADR + feature brief with a frozen Decision Record section. |
| **Confidence** | Score (0-1) on a stored pattern. < 0.2 = suspect, 0.2-0.7 = quarantined, >= 0.7 = proven. |
