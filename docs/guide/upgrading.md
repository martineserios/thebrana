# Upgrading

How to update brana to a new version and what to check afterward.

## Upgrade the plugin

### Marketplace install

If you installed via the marketplace, update with:

```
/plugin update brana
```

This pulls the latest version from the marketplace and updates the plugin cache. Start a new Claude Code session to activate.

### Dev mode

If you use `--plugin-dir ./system`, pull the latest changes:

```bash
cd thebrana
git pull
```

Changes take effect on the next session. No additional steps needed.

## Re-run bootstrap after upgrade

After updating the plugin, re-run bootstrap to sync the identity layer:

```bash
./bootstrap.sh
```

Bootstrap is idempotent. It will show which files changed (`~`), which are new (`+`), and which are unchanged (`=`).

Run `./bootstrap.sh --check` first if you want to preview changes without applying them.

### What bootstrap updates

- `~/.claude/CLAUDE.md` -- identity may have new agent entries or principle updates
- `~/.claude/rules/*.md` -- rules may be added, removed, or refined
- `~/.claude/scripts/*.sh` -- helper scripts may have bug fixes
- `~/.claude/statusline.sh` -- status bar improvements
- `~/.claude/scheduler/` -- scheduler scripts and templates
- `~/.claude/settings.json` -- PostToolUse hook paths may change
- `~/.claude/plugins/` -- plugin cache and registration metadata

Bootstrap also removes stale directories from the pre-plugin era (`~/.claude/skills/`, `~/.claude/commands/`, `~/.claude/agents/`) if they still exist.

## Sync plugin cache (dev mode)

If you are a contributor using dev mode and also have the plugin installed via marketplace, sync your local changes to the cache:

```bash
./bootstrap.sh --sync-plugin
```

This copies `system/` to the plugin cache directory so that sessions without `--plugin-dir` also pick up your changes.

## Post-upgrade checklist

After upgrading, verify everything works:

- [ ] **Start a new session** -- plugin changes require a fresh session
- [ ] **Check hooks fire** -- session-start message should appear
- [ ] **Check skills load** -- tab-complete `/brana:` to verify skills are available
- [ ] **Run scheduler validate** (if using scheduler):

```bash
brana-scheduler validate
```

- [ ] **Check for breaking changes** -- review the changelog or release notes for migration steps

## Redeploy scheduler

If the upgrade includes scheduler changes (new templates, runner fixes), redeploy the systemd units:

```bash
brana-scheduler deploy
```

This regenerates all `.service` and `.timer` files from the current config and templates. Existing job schedules and enabled/disabled state are preserved from `scheduler.json`.

## Version compatibility

| Brana version | Claude Code minimum | Notes |
|---------------|--------------------|----|
| v1.0.0 | v1.0.33 | Current stable release |

Brana tracks Claude Code's plugin API. When CC introduces breaking changes to the plugin system, hooks, or skill format, brana releases a corresponding update.

### Known CC version issues

| CC version | Issue | Workaround |
|------------|-------|------------|
| v2.1.x | PostToolUse hooks from plugins are silently dropped | Bootstrap installs these hooks to `settings.json` instead |
| v2.1.x | `CLAUDE_PLUGIN_ROOT` not always set in hook executor | Plugin hooks use `${CLAUDE_PLUGIN_ROOT}`; settings.json hooks use absolute paths |

### Checking versions

```bash
# Claude Code version
claude --version

# Brana plugin version
jq '.version' system/.claude-plugin/plugin.json

# Installed plugin version
jq '.plugins["brana@brana"][0].version' ~/.claude/plugins/installed_plugins.json
```

## Downgrading

To revert to a previous version:

### Marketplace install

```bash
# Check installed version
jq '.plugins["brana@brana"][0]' ~/.claude/plugins/installed_plugins.json

# Reinstall from a specific commit
git checkout <commit-hash>
./bootstrap.sh --sync-plugin
./bootstrap.sh
```

### Dev mode

```bash
cd thebrana
git checkout <tag-or-commit>
# Next session will use the older version
```

After downgrading, re-run `./bootstrap.sh` to sync the identity layer to the older version.
