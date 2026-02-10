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

3. **Recall relevant patterns**: use pattern-recall logic (claude-flow `npx claude-flow hooks recall --query "{tech stack}"` or fallback to `~/.claude/projects/*/memory/` grep) to surface patterns from other projects using the same technologies.

4. **Check existing configuration**: look for `.claude/CLAUDE.md` in the project — if present, read it. If not, suggest creating one based on findings.

5. **Check PM integration**: look for GitHub Issues, a PM repo, or project management references.

6. **Present summary**:
   - Tech stack detected
   - Relevant patterns found (with source projects)
   - Project structure overview
   - Suggested next steps

7. If this is a genuinely new project with no `.claude/CLAUDE.md`, create an initial one with project-specific conventions discovered during scanning.
