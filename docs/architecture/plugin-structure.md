# Plugin Structure

> How the brana plugin is organized, what Claude Code requires, and what goes where. The plugin is a toolkit loaded natively by CC. The identity layer is a separate concern deployed by `bootstrap.sh`.

## CC Plugin Requirements

A Claude Code plugin is a directory with a `.claude-plugin/plugin.json` manifest. CC discovers the plugin from this manifest and loads its contents (skills, hooks, agents, commands).

### plugin.json

The manifest lives at `system/.claude-plugin/plugin.json`:

```json
{
  "name": "brana",
  "description": "AI development system — skills, agents, and hooks for systematic software engineering with Claude Code",
  "version": "1.0.0",
  "author": {
    "name": "Martin Eserios"
  },
  "repository": "https://github.com/martineserios/thebrana",
  "license": "MIT",
  "keywords": ["ai", "development", "tdd", "skills", "agents", "hooks"]
}
```

| Field | Required | Description |
|-------|----------|-------------|
| `name` | Yes | Plugin name. Skills get namespaced as `/name:skill`. |
| `description` | Yes | One-line description for marketplace discovery. |
| `version` | Yes | Semver. Increment on meaningful changes to the plugin. |
| `author` | Yes | Author name (and optionally email, url). |
| `repository` | No | GitHub URL for marketplace install. |
| `license` | No | License identifier. |
| `keywords` | No | Search keywords for marketplace. |

### Directory Layout

CC expects specific subdirectories inside the plugin root:

```
system/                           Plugin root
├── .claude-plugin/
│   └── plugin.json               ← Manifest (required)
├── skills/                       ← Slash commands (/brana:*)
│   ├── build/SKILL.md
│   ├── close/SKILL.md
│   ├── research/SKILL.md
│   └── .../SKILL.md
├── hooks/
│   ├── hooks.json                ← Hook registrations
│   ├── pre-tool-use.sh
│   ├── session-start.sh
│   ├── session-end.sh
│   ├── post-tool-use.sh          ← Installed via bootstrap (CC #24529)
│   └── lib/                      ← Shared hook libraries
│       └── cf-env.sh
├── agents/                       ← Agent definitions
│   ├── scout.md
│   ├── challenger.md
│   └── .../name.md
├── commands/                     ← Multi-step command definitions
│   ├── maintain-specs.md
│   └── .../name.md
├── scripts/                      ← Helper scripts (optional)
└── CLAUDE.md                     ← Plugin-level identity
```

### How CC Resolves Paths

Hook commands in `hooks.json` must use `${CLAUDE_PLUGIN_ROOT}` to reference scripts relative to the plugin directory:

```json
"command": "${CLAUDE_PLUGIN_ROOT}/hooks/pre-tool-use.sh"
```

Relative paths (`./hooks/pre-tool-use.sh`) resolve from CWD, not the plugin directory. This causes hooks to break when CC runs from a different directory.

### Skill Namespacing

All skills get prefixed with the plugin name. A skill named `build` becomes `/brana:build` when invoked. This prevents collisions with other plugins.

## Brana Conventions

Beyond CC's requirements, brana adds conventions for consistency:

### Skills (`system/skills/`)

- One directory per skill, named after the skill
- Main file is always `SKILL.md`
- Helper scripts live alongside in the same directory
- `acquired/` subdirectory holds marketplace-installed skills (excluded from `validate.sh` name checks)

### Hooks (`system/hooks/`)

- Shell scripts in the hooks directory root
- `hooks.json` at the hooks directory root
- `lib/` subdirectory for shared libraries (e.g., `cf-env.sh`)
- All scripts must be executable (`chmod +x`)

### Agents (`system/agents/`)

- One `.md` file per agent
- Filename matches the agent's `name` field (without `.md`)

### Commands (`system/commands/`)

- Markdown files with YAML frontmatter (like skills but for multi-step orchestration)
- Used for spec workflows that combine multiple skills

### CLAUDE.md (`system/CLAUDE.md`)

- Plugin-level identity: principles, agents table, portfolio reference
- Loaded when the plugin is active
- Separate from the project-level `CLAUDE.md` and the bootstrap-installed `~/.claude/CLAUDE.md`

## Plugin vs Bootstrap: What Goes Where

Brana uses a two-layer architecture. Understanding the split is important when adding new components.

### Plugin Layer (`system/`)

**Loaded by CC natively.** No installation step needed for dev mode (`--plugin-dir`). For production, users install via marketplace.

| Component | Location | Why it's here |
|-----------|----------|---------------|
| Skills | `system/skills/` | CC loads and namespaces them automatically |
| Agents | `system/agents/` | CC discovers them for Agent tool |
| Commands | `system/commands/` | CC discovers them as commands |
| Hooks (Pre/Session) | `system/hooks/hooks.json` | CC reads plugin hooks.json |
| Hook scripts | `system/hooks/*.sh` | Referenced by hooks.json |
| Plugin identity | `system/CLAUDE.md` | CC loads plugin CLAUDE.md |

### Identity Layer (`bootstrap.sh` -> `~/.claude/`)

**Deployed once via `bootstrap.sh`.** Survives across projects and sessions. Not tied to any specific plugin.

| Component | Source | Target | Why it's here |
|-----------|--------|--------|---------------|
| Global identity | `bootstrap.sh` | `~/.claude/CLAUDE.md` | User-level identity, not plugin-scoped |
| Rules | `bootstrap.sh` | `~/.claude/rules/` | Always-loaded behavioral directives |
| Scripts | `bootstrap.sh` | `~/.claude/scripts/` | Shared utilities (backup, env, etc.) |
| PostToolUse hooks | `bootstrap.sh` | `~/.claude/settings.json` | CC #24529 workaround |
| Scheduler | `bootstrap.sh` | `~/.claude/scheduler/` | Cron-based background jobs |

### Decision Guide

When adding something new, ask:

| Question | Answer | Put it in... |
|----------|--------|-------------|
| Is it a slash command? | Yes | Plugin (`system/skills/`) |
| Is it a behavioral rule? | Yes | Bootstrap (via `bootstrap.sh`) |
| Is it a hook on PreToolUse/SessionStart/SessionEnd? | Yes | Plugin (`system/hooks/hooks.json`) |
| Is it a hook on PostToolUse/PostToolUseFailure? | Yes | Bootstrap (via `bootstrap.sh`) until CC #24529 is fixed |
| Is it a helper script used by hooks? | Yes | Plugin (`system/hooks/lib/`) with bootstrap fallback |
| Does it need to exist without the plugin? | Yes | Bootstrap |

## Version Management

The plugin version lives in `system/.claude-plugin/plugin.json`. Follow semver:

- **Patch** (1.0.1): Bug fixes to existing skills/hooks/agents
- **Minor** (1.1.0): New skills, agents, or hooks. Non-breaking changes.
- **Major** (2.0.0): Breaking changes to skill interfaces, hook behavior, or agent contracts

The version in `plugin.json` is what the marketplace uses. The project-level version in the root `CLAUDE.md` tracks the overall system version (both plugin and identity layer).

### Install Modes

```bash
# Dev mode — loads from local source, changes take effect on restart
claude --plugin-dir ./system

# Marketplace install — downloads and caches
/plugin marketplace add martineserios/thebrana
/plugin install brana

# Sync dev changes to installed cache
./bootstrap.sh --sync-plugin
```

After marketplace install, the plugin is cached at `~/.claude/plugins/cache/brana/brana/{version}/`. Use `bootstrap.sh --sync-plugin` to push local changes to the cache during development.
