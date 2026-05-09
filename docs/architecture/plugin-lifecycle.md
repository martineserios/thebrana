# Plugin Lifecycle

> What happens — in order — when Claude Code starts a session with the brana plugin loaded. A companion to [`plugin-structure.md`](plugin-structure.md) (what goes where) and [R6 Agent Loop](../reflections/33-agent-loop.md) (what happens per turn).

## Session Startup Sequence

When you run `claude --plugin-dir ./system` (dev mode) or start CC with the plugin installed, this sequence fires:

```
1. Plugin discovery
2. Component registration
3. Context assembly
4. SessionStart hooks
5. User prompt
```

### 1. Plugin Discovery

CC scans the plugin directory for `.claude-plugin/plugin.json`. If found:
- Reads `name`, `version`, `description`
- The `name` field becomes the skill namespace prefix (`brana` → `/brana:*`)
- Sets `CLAUDE_PLUGIN_ROOT` env var to the plugin root path (used in hook command references)

**Dev mode vs installed:**

| Mode | Plugin root | `CLAUDE_PLUGIN_ROOT` |
|------|------------|----------------------|
| `--plugin-dir ./system` | `./system` | Absolute path of `./system` |
| Installed | `~/.claude/plugins/cache/brana/brana/<version>/` | Path in cache |

Changes to `system/` in dev mode take effect on the next CC restart — CC reads plugin files once at startup.

### 2. Component Registration

CC scans the plugin root and registers each component type:

**Skills** (`system/skills/*/SKILL.md`):
- CC reads each `SKILL.md` and parses the YAML frontmatter
- The directory name becomes the skill slug
- `description` is loaded into session context immediately (counts toward context budget)
- `allowed-tools` is stored — enforced at invocation time

**Hooks** (`system/hooks/hooks.json`):
- CC reads the hook registration file
- Each `{event → matcher → script}` mapping is registered
- Scripts in `hooks.json` must use `${CLAUDE_PLUGIN_ROOT}` paths

**Agents** (`system/agents/*.md`):
- CC reads agent definitions for the `Agent` tool
- Agents are available immediately as subagent_type options

**Plugin CLAUDE.md** (`system/CLAUDE.md`):
- Loaded into the system prompt as plugin-level identity
- Layered on top of the project's `.claude/CLAUDE.md` and the global `~/.claude/CLAUDE.md`

**Bootstrap-installed components** (from `./bootstrap.sh`):
- `~/.claude/rules/` — always-loaded behavioral directives (already on disk, CC reads at startup)
- `~/.claude/settings.json` — PostToolUse hook wiring (CC #24529 workaround)
- `~/.claude/CLAUDE.md` — global identity

### 3. Context Assembly

Before the first user prompt, CC builds the system prompt:

```
~/.claude/CLAUDE.md          (global identity — portfolio, principles)
  + system/CLAUDE.md         (plugin identity — mastermind role)
  + .claude/CLAUDE.md        (project-specific conventions)
  + ~/.claude/rules/*.md     (always-loaded behavioral directives)
  + skill descriptions        (one per registered skill)
```

The combined context is what Claude "knows" before you type anything. This is why description length and rule size matter — every byte here costs tokens every turn.

### 4. SessionStart Hooks

Two hooks fire automatically before the user sees a prompt:

| Script | What it does |
|--------|-------------|
| `session-start.sh` | Derives project name from git root, queries ruflo for recent patterns, recalls relevant knowledge, surfaces any pending bootstrap restart notification |
| `session-start-venture.sh` | Detects venture projects (checks for `docs/sops/`, `docs/okrs/`), nudges the daily-ops agent if found |

These hooks inject `additionalContext` — text that appears at the top of the first user turn as session state. This is how Claude starts already knowing which project you're in and what happened last session.

### 5. User Prompt

The session is live. CC waits for input.

---

## Skill Invocation Flow

When you type `/brana:build`:

```
1. CC matches "brana:build" to a registered skill
2. Reads system/skills/build/SKILL.md body as instructions
3. Enforces allowed-tools list (blocks any tool not listed)
4. Claude executes the instructions as a turn
```

The skill body is injected as a system-level directive. Claude follows it as a procedure, not as static data. This is why skill bodies use imperative phrasing ("Read the file", "Run validate.sh") rather than descriptive phrasing.

**Allowed-tools enforcement** happens at the tool-call level: if Claude attempts to use `Write` during a skill that doesn't list it, the tool call is rejected before execution. The model sees an error and cannot proceed with that tool.

**Arguments** (`$ARGUMENTS`): Anything typed after the skill name is available as `$ARGUMENTS` inside the skill body. If your skill body references `$ARGUMENTS`, CC substitutes the literal string. Use `argument-hint` in frontmatter to hint the autocomplete dropdown.

---

## Hook Execution Flow

For every tool call during a session, CC runs through the registered hook chain:

```
Claude decides to use tool X
  → CC checks PreToolUse hooks for tool X
      → Hook script receives JSON on stdin
      → Hook script writes JSON to stdout
      → If any hook returns {"continue": false}: tool blocked, loop stops
      → If all return {"continue": true}: tool executes
  → Tool result returned to Claude
  → CC runs PostToolUse hooks for tool X
      → Hook scripts run (best-effort — failures are non-fatal)
      → additionalContext from PostToolUse hooks is prepended to the next turn
```

### PreToolUse JSON

Hook receives on stdin:

```json
{
  "session_id": "abc123",
  "tool_name": "Write",
  "tool_input": {
    "file_path": "/path/to/file.py",
    "content": "..."
  },
  "cwd": "/path/to/project"
}
```

Hook must respond on stdout:

```json
{"continue": true}
// or
{"continue": false, "stopReason": "Explanation shown to Claude"}
// or
{"continue": true, "additionalContext": "Note injected into next turn"}
```

### PostToolUse JSON

Same input shape, plus `tool_result`:

```json
{
  "session_id": "abc123",
  "tool_name": "Write",
  "tool_input": { "file_path": "...", "content": "..." },
  "tool_result": { "success": true },
  "cwd": "/path/to/project"
}
```

PostToolUse hooks can return `additionalContext` but **cannot block** — `continue: false` is ignored for PostToolUse (the tool already ran).

### Timeout behavior

Each hook has a configured timeout (default 5,000ms for most, 3,000ms for lightweight gates). If a hook exceeds its timeout:
- CC treats it as `{"continue": true}` (non-blocking timeout)
- The session continues; the hook's output is discarded
- This is why slow hooks silently stop working: no error, just ignored output

---

## Session Teardown

At session end (user closes CC or types `/exit`):

```
1. SessionEnd hook fires (session-end.sh)
2. Hook flushes accumulated events to persistent storage
3. Computes flywheel metrics (correction rate, test write rate, etc.)
4. Writes session summary to ruflo memory
5. CC process exits
```

Session state written in step 4 is what `session-start.sh` reads next time, closing the learning loop.

---

## PostToolUse Workaround (CC #24529)

Claude Code v2.1.x has a bug: **PostToolUse and PostToolUseFailure hooks don't fire from plugin `hooks.json`**. Only PreToolUse, SessionStart, and SessionEnd work via the plugin.

**Workaround:** `bootstrap.sh` installs PostToolUse and PostToolUseFailure hooks directly into `~/.claude/settings.json` with absolute paths. The plugin's `hooks.json` only declares PreToolUse, SessionStart, and SessionEnd.

```
Plugin hooks.json → PreToolUse, SessionStart, SessionEnd  ✓
bootstrap.sh → ~/.claude/settings.json → PostToolUse, PostToolUseFailure  ✓
```

Track CC issue #24529. When fixed, PostToolUse hooks can move back to `hooks.json`.

---

## Dev Iteration Loop

```
Edit system/skills/foo/SKILL.md
  → Restart CC (ctrl+C, rerun claude --plugin-dir ./system)
  → /brana:foo to test

Edit system/hooks/bar.sh
  → chmod +x system/hooks/bar.sh  (if new file)
  → Restart CC
  → Trigger the hook condition to test

Edit system/rules/baz.md
  → ./bootstrap.sh  (identity layer deploy)
  → Restart CC
  → Rule is now always-loaded

Edit system/hooks/post-*.sh (PostToolUse)
  → ./bootstrap.sh  (rewires ~/.claude/settings.json)
  → Restart CC
```

The single most common mistake: editing a skill and expecting changes without restarting CC. CC reads plugin files once at startup — mid-session edits are invisible until the next restart.

---

## See Also

- [`plugin-structure.md`](plugin-structure.md) — directory layout, what goes in which layer
- [`developer-quickstart.md`](developer-quickstart.md) — add your first skill in 10 min
- [`33-agent-loop.md`](../reflections/33-agent-loop.md) — per-turn execution model (hook fire points in the loop)
- [`extending-hooks.md`](extending-hooks.md) — hook authoring patterns and safety rules
- [`overview.md`](overview.md) — three-layer architecture, feedback loop
