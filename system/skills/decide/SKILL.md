---
name: decide
description: Create an Architecture Decision Record (ADR) in docs/decisions/
allowed-tools:
  - Bash
  - Read
  - Write
  - Glob
  - Grep
---

# Decide — Create an ADR

Create an Architecture Decision Record using Michael Nygard's lightweight format (Context, Decision, Consequences).

## Process

1. **Parse arguments.** If `$ARGUMENTS` is empty, ask the user for the decision title. If provided, use it directly (e.g., `/decide use JWT for authentication`).

2. **Locate project root.** Run `git rev-parse --show-toplevel` in the current directory. Fall back to `$PWD` if not a git repo.

3. **Check for `docs/decisions/` directory.** If it doesn't exist, ask the user: "This project doesn't have `docs/decisions/` yet. Create it? This also enables spec-before-code enforcement on feat/* branches." If yes, create it with `mkdir -p docs/decisions/`. If no, abort.

4. **Auto-increment ADR number.** Scan `docs/decisions/ADR-*.md` files. Extract the highest NNN from `ADR-NNN-*.md` filenames. New number = highest + 1. If no ADRs exist, start at 001. Zero-pad to 3 digits.

5. **Slugify title.** Convert title to lowercase, replace spaces and special characters with hyphens, collapse multiple hyphens, truncate to 50 characters. Example: "Use JWT for Authentication" becomes `use-jwt-for-authentication`.

6. **Create ADR file.** Write to `docs/decisions/ADR-NNN-slug.md` using the Nygard template:

```markdown
# ADR-NNN: Title

**Date:** YYYY-MM-DD
**Status:** proposed

## Context

[What is the issue motivating this decision or change?]

## Decision

[What is the change that we're proposing and/or doing?]

## Consequences

[What becomes easier or more difficult because of this change?]
```

Replace `NNN` with the zero-padded number, `Title` with the original title, `YYYY-MM-DD` with today's date.

7. **Pre-populate context.** If the conversation so far contains relevant discussion (architecture debate, options weighed, trade-offs discussed), summarize it into the Context section. Don't leave it as a placeholder if there's usable context.

8. **Store in ReasoningBank.** Use the standard binary discovery pattern:

```bash
CF=""
for candidate in "$HOME"/.nvm/versions/node/*/bin/claude-flow; do
    [ -x "$candidate" ] && CF="$candidate" && break
done
[ -z "$CF" ] && command -v claude-flow &>/dev/null && CF="claude-flow"
[ -z "$CF" ] && command -v npx &>/dev/null && CF="npx claude-flow"
```

If `$CF` is found, store:
```bash
cd $HOME && $CF memory store \
  -k "decision:{PROJECT}:{slug}" \
  -v '{"type": "decision", "title": "...", "status": "proposed", "confidence": 0.5, "transferable": false}' \
  --namespace decisions \
  --tags "project:{PROJECT},type:decision,status:proposed"
```

9. **Fallback (claude-flow unavailable).** Append to `~/.claude/projects/{project-hash}/memory/MEMORY.md`:
```
## Decision: {title}
- Date: YYYY-MM-DD
- Status: proposed
- File: docs/decisions/ADR-NNN-slug.md
```

10. **Report.** Show the user: file created, path, ADR number, next step ("Fill in the Context, Decision, and Consequences sections").

## Rules

- Ask for clarification if the title is ambiguous
- Never overwrite an existing ADR
- The ADR format is Nygard lightweight (Context, Decision, Consequences) — not the comprehensive v1 template
- Ask for clarification whenever you need it
