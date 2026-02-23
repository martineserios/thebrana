# Memory Framework

Two types of persistent files, two rules.

## CLAUDE.md and rules/

Human-authored, prescriptive. "always X", "never Y", "prefer Z." Loaded every session.

- **CLAUDE.md**: project identity and conventions
- **rules/*.md**: behavioral directives (one concern per file)

## MEMORY.md (auto memory)

Claude-authored, descriptive. "project uses X", "Y pattern worked", "Z is at version N." Private to user. 200-line cap.

- Store cross-cutting learnings, user preferences, and operational gotchas
- Never store behavioral directives ("always", "never", "must", "should")
- If you discover a directive in MEMORY.md, move it to rules/ or CLAUDE.md

### Reference, don't cache

Don't duplicate project facts in MEMORY.md. Rates, stacks, endpoints, numbers, task status — these live in project files. Store a pointer, not the content. Cached facts drift silently.

**Good:** `TinyHomes | projects/tinyhomes/ | docs/decisions/, .claude/tasks.json`
**Bad:** `TinyHomes commission: 10% (8% host + 2% guest)` — stale the day it changes.

## Quick test

Before writing to MEMORY.md, ask:

1. Fact or rule? Facts → MEMORY.md. Rules → rules/.
2. Already in a project file? Store a pointer, not the content.
