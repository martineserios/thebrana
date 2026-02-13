---
name: project-onboard
description: Bootstrap a new project by scanning its structure and recalling relevant portfolio knowledge. Use when entering an unfamiliar project for the first time.
allowed-tools:
  - Bash
  - Read
  - Glob
  - Grep
  - Write
---

# Project Onboard

1. **Detect tech stack**: read `package.json`, `pyproject.toml`, `Cargo.toml`, `go.mod`, or other manifest files to identify the project's technologies.

2. **Scan project structure**: list key directories, entry points, and config files. Build a mental model of the project.

3. **Recall relevant patterns**: use pattern-recall logic (locate claude-flow binary via smart discovery, then `cd $HOME && $CF memory search --query "{tech stack}"`, or fallback to `~/.claude/projects/*/memory/` grep) to surface patterns from other projects using the same technologies.

   ```bash
   CF=""
   for candidate in "$HOME"/.nvm/versions/node/*/bin/claude-flow; do
       [ -x "$candidate" ] && CF="$candidate" && break
   done
   [ -z "$CF" ] && command -v claude-flow &>/dev/null && CF="claude-flow"
   [ -z "$CF" ] && command -v npx &>/dev/null && CF="npx claude-flow"
   ```

4. **Check existing configuration**: look for `.claude/CLAUDE.md` in the project — if present, read it. If not, suggest creating one based on findings.

5. **Check PM integration**: look for GitHub Issues, a PM repo, or project management references.

6. **Check SDD/TDD setup:**
   - Does `docs/decisions/` exist? If yes, report "SDD enforcement: active (PreToolUse hook blocks impl without spec on feat/* branches)"
   - Check if `tdd-guard` is in PATH (`command -v tdd-guard`). If yes, report "TDD enforcement: active (TDD-Guard PreToolUse hook)"
   - If neither exists, include in the summary:
     "**SDD/TDD not configured.** To enable:
      - `mkdir -p docs/decisions` — spec-before-code enforcement
      - `npm install -g tdd-guard && tdd-guard on` — test-before-code enforcement"

7. **Check auto memory health**: read the project's `MEMORY.md` in `~/.claude/projects/*/memory/` if it exists:
   - Is it over 200 lines? (warn: only first 200 lines are loaded at session start)
   - Does it contain behavioral directives ("always", "never", "must", "should") that belong in `~/.claude/rules/` or CLAUDE.md?
   - The distinction: MEMORY.md stores facts Claude discovered. Rules/CLAUDE.md store instructions humans wrote.

8. **Present summary**:
   - Tech stack detected
   - Relevant patterns found (with source projects)
   - Project structure overview
   - Auto memory health (clean / needs attention)
   - Suggested next steps

9. If this is a genuinely new project with no `.claude/CLAUDE.md`, create an initial one with project-specific conventions discovered during scanning.

## Rules

- **Ask for clarification whenever you need it.** If the project structure is unusual, you're unsure about conventions to adopt, or you need the user to confirm tech stack choices — ask. Don't guess.
