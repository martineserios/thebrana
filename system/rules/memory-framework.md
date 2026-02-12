# Memory Framework

Two types of persistent files, two rules.

## CLAUDE.md and rules/

Human-authored, prescriptive. These tell Claude what to do: "always X", "never Y", "prefer Z." Loaded in full every session. Shared across the team.

- **CLAUDE.md**: project identity and conventions
- **rules/*.md**: behavioral directives (one concern per file)

## MEMORY.md (auto memory)

Claude-authored, descriptive. These record what Claude observed: "project uses X", "Y pattern worked", "Z is at version N." Private to the user. 200-line cap — keep it concise.

- Store facts, observations, and learnings
- Never store behavioral directives ("always", "never", "must", "should")
- If you discover a directive in MEMORY.md, move it to rules/ or CLAUDE.md

## Quick test

Before writing to MEMORY.md, ask: "Is this a fact I observed, or a rule I want enforced?" Facts go in MEMORY.md. Rules go in rules/.
