# Testing and Validation

> How to validate the brana system before deploying changes. Covers `validate.sh` checks, hook testing, and skill testing in dev mode.

## validate.sh

The primary pre-deploy validation tool. Run it from the repo root:

```bash
./validate.sh
```

It exits 0 on success, 1 if any check fails. Warnings do not cause failure.

### Check 1: Skill Frontmatter

For each `system/skills/*/SKILL.md` (excluding `acquired/`):

- File exists in the skill directory
- Has valid YAML frontmatter (between `---` markers)
- YAML parses without errors
- `name` field matches the directory name

**Common failures:**
- Renamed directory but forgot to update `name:` in frontmatter
- Invalid YAML syntax (missing quotes around descriptions with colons)

### Check 2: Rule Files

For each `system/rules/*.md`:

- If it has YAML frontmatter, the YAML is valid
- Rules without frontmatter are valid (they load unconditionally)

### Check 3: JSON Validity

- `system/settings.json` (if present) is valid JSON
- Since v1.0.0, `settings.json` is optional in the plugin (PostToolUse hooks live in `bootstrap.sh`)

### Check 4: Agent Frontmatter

For each `system/agents/*.md`:

- Has valid YAML frontmatter
- Has a `name` field
- Has a `description` field

### Check 5: Context Budget

Calculates the total always-loaded content size:

- `system/CLAUDE.md` (full file)
- Rules without `paths:` field (loaded unconditionally)
- Skill descriptions (just the `description:` line from each skill)
- Agent descriptions (from frontmatter)

**Budget limit:** 28,672 bytes (28KB). Exceeding this degrades Claude's performance because too much instruction text competes for context window space.

### Check 5b: Instruction Density

Counts the number of always-present directives (lines starting with `- **`, numbered lists with bold, table rows, imperative sentences).

- **Warning threshold:** 200 directives
- **Failure threshold:** 300 directives

Too many directives means Claude cannot follow all of them reliably. Prefer fewer, stronger rules.

### Check 6: No Secrets

Scans `system/` for patterns like `API_KEY=`, `SECRET=`, `PASSWORD=`, `TOKEN=`, `PRIVATE_KEY=`. Excludes comments, examples, and placeholder text.

### Check 7: Duplicate Skill Names

Ensures no two skills share the same `name:` field. Duplicate names would cause one skill to shadow the other.

### Check 8: File Size Sanity

Flags any file in `system/` over 50KB. Large files indicate content that should be split or externalized.

### Check 9: Hook Scripts

For each `system/hooks/*.sh`:

- File is not empty
- Has a valid shebang (`#!/usr/bin/env bash` or `#!/bin/bash`)
- Passes `bash -n` syntax check (no parse errors)

For `system/hooks/hooks.json`:

- Valid JSON
- All event names are known CC events (`PreToolUse`, `PostToolUse`, `SessionStart`, etc.)
- Warns if `PostToolUse` or `PostToolUseFailure` appear (CC #24529 means these don't fire from plugins)
- Commands use `${CLAUDE_PLUGIN_ROOT}` (not relative paths)
- Referenced scripts exist and are executable

For `system/settings.json` (if present):

- Hook event names are valid
- Warns that settings.json hooks should be empty in v0.7.0+ (use hooks.json or bootstrap)

### Check 10: Commands

For each file in `system/commands/`:

- Markdown files: valid YAML frontmatter
- Shell scripts: valid shebang and `bash -n` syntax check

### Check 11: Shared Scripts

For each `system/scripts/*.sh`:

- Valid shebang
- Passes `bash -n` syntax check

### Check 12: Skill Dependencies

For each skill with a `depends_on` field:

- Every listed dependency has a corresponding `system/skills/{dep}/` directory
- Catches typos and references to deleted skills

## Pre-Deploy Validation Workflow

Before committing changes to the system:

```bash
# 1. Run validation
./validate.sh

# 2. Fix any errors (warnings are informational)

# 3. Test in dev mode
claude --plugin-dir ./system

# 4. Verify your changes work in a live session

# 5. Commit and push
```

For hook changes, add local testing (next section) between steps 1 and 3.

## Testing Hooks Locally

Hooks can be tested without starting a Claude Code session by piping JSON to them:

### PreToolUse Hook

```bash
# Should block (feat branch, no spec activity, implementation file)
echo '{
  "session_id": "test-1",
  "tool_name": "Write",
  "tool_input": {"file_path": "/home/user/project/src/main.py"},
  "cwd": "/home/user/project"
}' | bash system/hooks/pre-tool-use.sh

# Should pass (writing a test file)
echo '{
  "session_id": "test-1",
  "tool_name": "Write",
  "tool_input": {"file_path": "/home/user/project/tests/test_main.py"},
  "cwd": "/home/user/project"
}' | bash system/hooks/pre-tool-use.sh
```

### PostToolUse Hook

```bash
echo '{
  "session_id": "test-1",
  "tool_name": "Write",
  "tool_input": {"file_path": "/tmp/test.py"},
  "cwd": "/tmp"
}' | bash system/hooks/post-tool-use.sh
```

### SessionStart Hook

```bash
echo '{
  "session_id": "test-1",
  "cwd": "/home/user/project",
  "hook_event_name": "SessionStart"
}' | bash system/hooks/session-start.sh
```

### Validation Checklist for Hook Testing

1. **Valid JSON output** — pipe output through `jq .` to verify
2. **Graceful on empty input** — `echo '' | bash hook.sh` should return `{"continue": true}`
3. **Graceful on missing fields** — `echo '{}' | bash hook.sh` should return `{"continue": true}`
4. **Stays under timeout** — `time bash hook.sh < input.json` should complete in under 5s (tool hooks) or 10s (session hooks)
5. **No stderr noise** — redirect stderr to check: `bash hook.sh < input.json 2>/tmp/hook-errors`

## Testing Skills in Dev Mode

Skills cannot be tested outside Claude Code. Use dev mode:

```bash
claude --plugin-dir ./system
```

In the session:

1. Invoke the skill: `/brana:my-skill`
2. Verify it follows the instructions in SKILL.md
3. Check that only `allowed-tools` are used (Claude will refuse others)
4. Test edge cases: missing files, empty input, error conditions

Changes to SKILL.md require restarting Claude Code. Edit, restart, test.

### Quick Iteration Loop

```bash
# Terminal 1: Edit the skill
vim system/skills/my-skill/SKILL.md

# Terminal 2: Restart Claude Code and test
claude --plugin-dir ./system
# > /brana:my-skill
```

## Checking Session Logs

After testing hooks in a live session, check the session JSONL file for logged events:

```bash
# Find the session log
ls -la /tmp/brana-session-*.jsonl

# Read events
cat /tmp/brana-session-*.jsonl | jq .
```

This file is created by `post-tool-use.sh` and consumed by `session-end.sh` to compute flywheel metrics.
