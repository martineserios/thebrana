# ADR-014: Plugin Management Skill

**Date:** 2026-03-10
**Status:** accepted
**Branch:** feat/marketplace-publish

## Context

Brana v0.7.0 introduced the plugin architecture (t-232) and `/brana:acquire-skills` for individual skill discovery (t-206). Two gaps remain:

1. **No plugin-level management.** Users can discover individual skills but can't install, update, or remove entire plugins (bundles of skills + agents + hooks). Claude Code's native `/plugin` commands don't exist yet.
2. **No auto-registration.** After cloning thebrana, users must pass `--plugin-dir ./system` every time. Bootstrap should register the plugin so CC auto-loads it.
3. **Marketplace readiness.** When CC ships native marketplace support, brana should be discoverable and installable with zero changes.

## Decision

### 1. `/brana:plugin` skill

Build a unified plugin management skill with subcommands:

| Subcommand | Action |
|------------|--------|
| `add <owner/repo>` | Register a GitHub marketplace in `known_marketplaces.json` |
| `install <name>` | Clone marketplace repo, snapshot plugin source to `~/.claude/plugins/cache/`, register in `installed_plugins.json` |
| `list` | Show installed plugins + available from known marketplaces |
| `remove <name>` | Delete cache + deregister from `installed_plugins.json` |
| `update [name]` | Re-clone and re-snapshot (all or specific plugin) |
| `sync` | Shortcut for `bootstrap.sh --sync-plugin` (dev mode cache sync) |

Key design choices:
- **Mirrors CC's planned API.** When `/plugin` ships natively, `/brana:plugin` becomes a thin wrapper or is retired gracefully.
- **Uses CC's existing file format.** Writes to `installed_plugins.json` (version 2) and `known_marketplaces.json` — same format CC already reads.
- **GitHub-first.** Marketplace source is a GitHub repo with `.claude-plugin/marketplace.json` at root. No npm, no registry server.
- **User confirms everything.** No auto-install, no auto-update without approval.

### 2. Auto-registration in bootstrap.sh

Add Step 7 to bootstrap.sh: register the local `system/` as the brana plugin in CC's config files.

- Write `known_marketplaces.json` entry for `martineserios/thebrana`
- Snapshot `system/` to `~/.claude/plugins/cache/brana/brana/{version}/`
- Register in `installed_plugins.json`
- Idempotent — safe to re-run

### 3. Marketplace metadata

Already in place (`.claude-plugin/marketplace.json` + `system/.claude-plugin/plugin.json`). Version synced to 1.0.0. No changes needed beyond ensuring the schema stays compatible.

## Consequences

- **Easier:** installing brana on a new machine — `./bootstrap.sh` handles everything
- **Easier:** discovering and installing other CC plugins from GitHub
- **Risk:** CC may ship `/plugin` with a different format than what we implement. Mitigated by using CC's existing file formats and keeping the skill thin enough to adapt.
- **Risk:** `installed_plugins.json` overwrite on CC reload. Mitigated by writing the canonical format CC expects. If CC still overwrites, the plugin cache + marketplace registration provide the fallback path.
