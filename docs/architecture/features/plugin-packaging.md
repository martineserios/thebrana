---
depends_on:
  - docs/architecture/decisions/ADR-015-state-consolidation-plugin-first.md
---
# Feature: Plugin Packaging — Distribute thebrana as CC Plugin

**Date:** 2026-03-08
**Status:** shipped

## Spike Results (2026-03-08)

- `${CLAUDE_PLUGIN_ROOT}` resolves to plugin absolute path at runtime ✓
- Relative `./` paths do NOT work — must use the variable ✓
- Skills load and namespace correctly (`/test-hooks:hello`) ✓
- Hook scripts execute without error when using `${CLAUDE_PLUGIN_ROOT}` ✓
- Hook stdout not surfaced as conversation text (brana hooks use structured output patterns)
**Task:** t-232

## Problem

thebrana uses `deploy.sh` to copy ~80 files from `system/` to `~/.claude/`. This creates friction: every edit to a skill, hook, or agent requires re-running deploy.sh + restarting Claude Code. The copy-based approach also prevents distribution — other users can't install thebrana without cloning the repo and running the script.

Claude Code 2.1.71 introduced a native plugin system (`.claude-plugin/plugin.json`, `claude plugin install`, marketplace support, `--plugin-dir` for dev). thebrana's `system/` structure maps almost 1:1 to a plugin.

## Decision Record (frozen 2026-03-08)

> Do not modify after acceptance.

**Context:** Analyzed 5 distribution approaches (symlinks, npm package, git-clone+install, CC templates, CC plugin). Claude Code's plugin system (v1.0.33+) natively supports bundling skills, agents, hooks, commands with namespacing, versioning, and marketplace distribution. The npm package approach would duplicate what CC plugins already provide.

thebrana has two concerns:
1. **Toolkit** (skills, agents, hooks, commands) — distributable, versioned, isolated
2. **Identity** (CLAUDE.md, rules, scripts, scheduler, ruflo) — personal config, one-time setup

Plugins handle #1 natively. #2 stays as a bootstrap script because plugins can't distribute rules or modify `~/.claude/CLAUDE.md` by design (those are user-owned).

**Decision:**
1. Convert `system/` to a CC plugin (add `.claude-plugin/plugin.json`, convert hooks format)
2. Write `bootstrap.sh` for identity layer (CLAUDE.md, rules, scripts, scheduler, ruflo)
3. Set up GitHub-based marketplace for distribution
4. Skills become namespaced: `/brana:build`, `/brana:close`, etc.
5. Dev mode via `claude --plugin-dir ./system` (no deploy needed)
6. `deploy.sh` preserved during transition, deprecated after validation

**Consequences:**
- All skill references across skills, rules, and docs must update to `/brana:*` namespace
- Hook scripts move from `settings.json` references to `hooks/hooks.json` format
- Users installing thebrana get toolkit via `claude plugin install`, identity via `bootstrap.sh`
- `deploy.sh` eventually removed (replaced by plugin install + bootstrap)

## Constraints

- Claude Code 2.1.71+ required (plugin system)
- Plugin `settings.json` only supports `agent` key — hook configs must use `hooks/hooks.json`
- Plugin hooks reference scripts relative to plugin root, not `$HOME/.claude/hooks/`
- Rules can't be distributed via plugins — bootstrap handles them
- Namespaced skills (`/brana:build`) — no way to get short names from plugins
- Must preserve current functionality during transition (deploy.sh stays until validated)

## Scope (v1)

### In scope
- Plugin manifest (`.claude-plugin/plugin.json`)
- Convert hooks from `settings.json` + `*.sh` to `hooks/hooks.json` + `*.sh`
- Bootstrap script for identity layer
- Update all internal skill cross-references to namespaced names
- Update delegation-routing.md and other rules referencing skill names
- GitHub marketplace setup
- Validate with `claude plugin validate`
- Test with `--plugin-dir`
- Update docs (CLAUDE.md, guide/)

### Out of scope
- Official Anthropic marketplace submission (future, after open-source)
- npm package (replaced by plugin approach)
- Automated migration from deploy.sh (manual transition)
- Personal workspace setup (separate task)

## Research

### CC Plugin System (verified against docs + CLI)
- Plugin = directory with `.claude-plugin/plugin.json` manifest
- Supports: `skills/`, `agents/`, `commands/`, `hooks/hooks.json`, `.mcp.json`, `.lsp.json`, `settings.json`
- Skills namespaced: `/plugin-name:skill-name`
- Dev mode: `claude --plugin-dir ./path`
- Install: `claude plugin install name` from marketplace
- Validate: `claude plugin validate ./path`
- Marketplace: GitHub repo or HTTP URL with manifest

### Hooks Format Change
Current (`system/settings.json`):
```json
{
  "hooks": {
    "PreToolUse": [{
      "matcher": "Write|Edit",
      "hooks": [{"type": "command", "command": "$HOME/.claude/hooks/pre-tool-use.sh", "timeout": 5000}]
    }]
  }
}
```

Plugin format (`hooks/hooks.json`):
```json
{
  "hooks": {
    "PreToolUse": [{
      "matcher": "Write|Edit",
      "hooks": [{"type": "command", "command": "./hooks/pre-tool-use.sh", "timeout": 5000}]
    }]
  }
}
```

Key difference: paths relative to plugin root, not `$HOME`.

### deploy.sh Inventory (what moves where)

| Component | Count | Destination |
|-----------|-------|-------------|
| Skills | 24 | Plugin `skills/` |
| Agents | 11 | Plugin `agents/` |
| Hook scripts | 10 | Plugin `hooks/*.sh` |
| Commands | 5 | Plugin `commands/` |
| Hook config | 1 (settings.json) | Plugin `hooks/hooks.json` |
| CLAUDE.md | 1 | Bootstrap → `~/.claude/` |
| Rules | 12 | Bootstrap → `~/.claude/rules/` |
| Scripts | 6 | Bootstrap → `~/.claude/scripts/` |
| Scheduler | 7 files | Bootstrap → `~/.claude/scheduler/` |
| ruflo | 3 files | Bootstrap → `~/.claude-flow/` |
| settings.json merge | 1 | Bootstrap (hooks portion removed, only non-hook settings remain) |
| statusline.sh | 1 | Bootstrap → `~/.claude/` |

### Namespace Impact

Skills referencing other skills (internal cross-refs):
- `/brana:build` calls `/brana:challenge` → `/brana:build` calls `/brana:challenge`
- Delegation routing references `/brana:build`, `/brana:close`, `/brana:backlog`, etc.
- ~15 rules/docs reference skill names

## Design

### 1. Plugin Structure

```
system/
├── .claude-plugin/
│   └── plugin.json              ← NEW
├── skills/                      ← existing skills
│   ├── build/SKILL.md
│   ├── challenge/SKILL.md
│   └── ...
├── agents/                      ← existing (11 agents)
├── commands/                    ← existing (5 commands)
├── hooks/                       ← RESTRUCTURED
│   ├── hooks.json               ← NEW (replaces settings.json hooks section)
│   ├── pre-tool-use.sh          ← existing scripts, paths updated
│   ├── post-tool-use.sh
│   ├── session-start.sh
│   ├── session-end.sh
│   └── ...
└── settings.json                ← stripped to non-hook settings only (if any remain)
```

### 2. plugin.json Manifest

```json
{
  "name": "brana",
  "description": "AI development system — skills, agents, and hooks for systematic software engineering with Claude Code",
  "version": "0.7.0",
  "author": {
    "name": "Martin Eserios"
  },
  "repository": "https://github.com/martineserios/thebrana",
  "license": "MIT"
}
```

### 3. hooks/hooks.json

Convert from `system/settings.json` → `system/hooks/hooks.json`. All `$HOME/.claude/hooks/` paths become relative `./hooks/` paths.

### 4. bootstrap.sh

Handles the identity layer (non-plugin components):

```bash
#!/usr/bin/env bash
# One-time setup for brana identity layer
# Plugin handles: skills, agents, hooks, commands
# Bootstrap handles: CLAUDE.md, rules, scripts, scheduler, ruflo

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SYSTEM_DIR="$SCRIPT_DIR/system"
TARGET_DIR="$HOME/.claude"

# 1. Validate (reuse validate.sh, scoped to identity files)
# 2. Backup existing CLAUDE.md
# 3. Copy CLAUDE.md
# 4. Copy rules/
# 5. Copy scripts/
# 6. Setup scheduler (dirs, scripts, templates, symlink)
# 7. Setup ruflo (sql.js, embeddings, shim)
# 8. Report
```

### 5. Namespace Migration

Update all references from `/skill-name` to `/brana:skill-name`:
- All SKILL.md files referencing other skills
- `system/rules/delegation-routing.md`
- `system/CLAUDE.md` (agent table, commands table)
- `docs/` files referencing commands
- Hook scripts that invoke skills

### 6. deploy.sh Transition

- Keep `deploy.sh` during transition — mark as deprecated
- Add warning: "deploy.sh is deprecated. Use: claude --plugin-dir ./system + ./bootstrap.sh"
- Remove after validation period (1-2 weeks)

## Challenger findings

**Verdict:** PROCEED WITH CHANGES

### Critical (3)

**C1: Hook scripts source `$HOME/.claude/scripts/cf-env.sh` — cross-boundary dependency.**
4 hook scripts hardcode `source "$HOME/.claude/scripts/cf-env.sh"`. Plugin hooks would depend on bootstrap-layer files. If user installs plugin without bootstrap, hooks silently fail.
→ **Resolution:** Bundle `cf-env.sh` inside plugin at `hooks/lib/cf-env.sh`, use relative path. Plugin stays self-contained for its own hooks. Other scripts (index-knowledge.sh, etc.) stay in bootstrap since they're not hook dependencies.

**C2: Relative hook paths (`./hooks/pre-tool-use.sh`) are unverified.**
CC might resolve `./` from CWD, not plugin dir. If so, every hook fails.
→ **Resolution:** Run 10-minute spike BEFORE implementation. Create minimal test plugin with one hook, install via `claude plugin install`, verify execution. This gates the entire migration.

**C3: 49 `$HOME/.claude/` references across 32 files — only ~15 namespace refs accounted for.**
Many files reference `$HOME/.claude/` paths. Some are valid (bootstrap-layer files), some break (files that moved into plugin).
→ **Resolution:** Add path audit as first build step. Classify each occurrence as "valid (points to bootstrap layer)" vs "needs update (now inside plugin)."

### Warnings (4)

**W1: settings.json may be empty after hooks extraction.** Confirmed: current settings.json contains ONLY hooks. No plugin settings.json needed.

**W2: Namespace migration broader than spec accounts for.** `~/.claude/rules/*.md`, project MEMORY.md files, other project CLAUDE.md files all reference `/brana:build`, `/brana:close`, etc.
→ **Resolution:** Add migration checklist: system/rules, system/CLAUDE.md, ~/.claude/memory/MEMORY.md, all project .claude/ files. Check if CC supports simultaneous old+new names during transition.

**W3: bootstrap.sh should be re-runnable, not "one-time".** Rules and CLAUDE.md change frequently. Need a re-deploy mechanism.
→ **Resolution:** Make bootstrap.sh idempotent with diff checking. `bootstrap.sh` (full sync) or `bootstrap.sh --check` (show what would change).

**W4: No rollback plan / duplicate hook risk.** If hooks defined in both ~/.claude/settings.json (old deploy) AND plugin hooks/hooks.json, hooks may fire twice.
→ **Resolution:** Document that deploy.sh hooks must be removed from ~/.claude/settings.json before plugin activation. Add to migration checklist.

### Observations (3)

- O1: Verify marketplace access is actually available before planning distribution around it.
- O2: `session-start-venture.sh` not wired in settings.json — may be legacy. Clarify.
- O3: Add changelog for 0.6.0 → 0.7.0 transition.

## Post-Ship Errata

### E1: PostToolUse/PostToolUseFailure don't fire from plugin hooks.json (2026-03-09) — RESOLVED 2026-05-08

~~CC v2.1.x does not dispatch PostToolUse or PostToolUseFailure events to plugin hooks.~~ Fixed in CC v2.1.133.

**Root cause (historical):** `CLAUDE_PLUGIN_ROOT` not set by hook executor (CC issue [#24529](https://github.com/anthropics/claude-code/issues/24529)). Finding: hooks must be present in `hooks.json` **at session startup** — mid-session injection is ignored.

**Resolution:** PostToolUse/PostToolUseFailure/TaskCompleted hooks moved back to `system/hooks/hooks.json`. `bootstrap.sh` Step 4b now removes the workaround entries from `~/.claude/settings.json`.

### E2: Stale ~/.claude/{skills,commands,agents} from deploy.sh (2026-03-09)

Users upgrading from `deploy.sh` to the plugin have stale copies of skills, commands, and agents in `~/.claude/`. These cause duplicate skill registration — skills appear both unprefixed (from `~/.claude/skills/`) and with `brana:` prefix (from the plugin). Silent, confusing failure mode.

**Fix:** `bootstrap.sh` Step 1b removes `~/.claude/skills/`, `~/.claude/commands/`, and `~/.claude/agents/` if they exist. Users must run `bootstrap.sh` after upgrading to clear the duplicates. The plugin is the sole source for these components.

### E3: Plugin cache does not auto-update after new commits (2026-03-09)

`claude plugin install` snapshots files at the install-time git SHA into `~/.claude/plugins/cache/<marketplace>/<plugin>/<version>/`. After new commits to `system/`, the cache silently serves stale skills, agents, and hooks — no auto-update, no warning. Renames are worst-case: old files persist alongside new ones (e.g., `project-scanner.md` still present after rename to `client-scanner.md`).

**Impact:** Users running installed plugins get outdated behavior indefinitely. Discovered when cache was 40 commits behind HEAD after the t-281 projects→clients rename.

**Workarounds:**
1. **Dev mode (recommended for contributors):** `claude --plugin-dir ./system` — always reads from HEAD, no cache involved.
2. **Manual sync:** `rsync -av --delete system/ ~/.claude/plugins/cache/brana/brana/0.7.0/` — must use `--delete` to remove renamed/deleted files.
3. **Reinstall:** `claude plugin uninstall brana && claude plugin install brana` — re-snapshots from current commit.

**Future fix:** Add a `bootstrap.sh --sync-plugin` flag or post-merge hook that auto-syncs `system/` to the plugin cache when changes are detected.

## Field Notes

### 2026-05-08: Hook registration is read-once at CC session startup
CC reads `hooks.json` (and `settings.json` hooks) once when the session starts. Modifying hook config mid-session — via bootstrap.sh, reconcile, or manual edits — is silently ignored. The fix for t-235 required a CC restart to take effect even though the hooks were already in hooks.json. Rule: always restart CC after any hook config change. Scripts that mutate hook config should print a restart reminder.
Source: t-235 canary test / close session 2026-05-08
