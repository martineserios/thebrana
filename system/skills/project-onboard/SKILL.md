---
name: project-onboard
description: Bootstrap a new project by scanning its structure and recalling relevant portfolio knowledge
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

3. **Recall relevant patterns**: use pattern-recall logic (locate claude-flow binary via smart discovery, then `cd $HOME && $CF memory search -q "{tech stack}"`, or fallback to `~/.claude/projects/*/memory/` grep) to surface patterns from other projects using the same technologies.

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

7. **Present summary**:
   - Tech stack detected
   - Relevant patterns found (with source projects)
   - Project structure overview
   - Suggested next steps

8. If this is a genuinely new project with no `.claude/CLAUDE.md`, create an initial one with project-specific conventions discovered during scanning.

## Rules

- **Ask for clarification whenever you need it.** If the project structure is unusual, you're unsure about conventions to adopt, or you need the user to confirm tech stack choices — ask. Don't guess.
