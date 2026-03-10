---
name: plugin
description: "Manage Claude Code plugins — add marketplaces, install, update, remove, list plugins."
group: brana
allowed-tools:
  - Read
  - Write
  - Bash
  - Glob
  - Grep
  - WebFetch
  - AskUserQuestion
  - Agent
---

# Plugin

Manage Claude Code plugins from GitHub marketplaces. Install, update, remove, and list plugins — filling the gap until CC ships native `/plugin` commands.

## Usage

```
/brana:plugin add <owner/repo>        — register a GitHub marketplace
/brana:plugin install <name>          — install a plugin from known marketplaces
/brana:plugin list                    — show installed + available plugins
/brana:plugin remove <name>           — uninstall a plugin
/brana:plugin update [name]           — update all or a specific plugin
/brana:plugin sync                    — sync dev plugin cache (--plugin-dir users)
```

## File Locations

| File | Purpose |
|------|---------|
| `~/.claude/plugins/known_marketplaces.json` | Registered marketplace repos |
| `~/.claude/plugins/installed_plugins.json` | Installed plugin registry (version 2) |
| `~/.claude/plugins/cache/<marketplace>/<plugin>/<version>/` | Cached plugin files |
| `~/.claude/plugins/marketplaces/<marketplace>/` | Cloned marketplace repos |

## Subcommands

### `add <owner/repo>`

Register a GitHub repo as a plugin marketplace.

**Steps:**

1. Validate format: must be `owner/repo` (e.g., `martineserios/thebrana`).

2. Read `~/.claude/plugins/known_marketplaces.json`. Create if missing:
   ```json
   {}
   ```

3. Check if marketplace already registered. If yes, ask user:
   - question: "Marketplace already registered. Update it?"
   - options: ["Yes — re-clone", "No — skip"]

4. Clone/update the marketplace repo:
   ```bash
   git clone --depth 1 "https://github.com/<owner>/<repo>.git" \
       "$HOME/.claude/plugins/marketplaces/<repo-name>/" 2>/dev/null \
   || (cd "$HOME/.claude/plugins/marketplaces/<repo-name>/" && git pull --ff-only)
   ```

5. Verify `.claude-plugin/marketplace.json` exists in the cloned repo. If missing, abort with error.

6. Read the marketplace manifest to confirm it's valid JSON with a `plugins` array.

7. Add entry to `known_marketplaces.json`:
   ```json
   {
     "<repo-name>": {
       "source": {
         "source": "github",
         "repo": "<owner>/<repo>"
       },
       "installLocation": "/home/<user>/.claude/plugins/marketplaces/<repo-name>",
       "lastUpdated": "<ISO timestamp>",
       "autoUpdate": true
     }
   }
   ```

8. Report:
   ```
   Marketplace added: <repo-name>
   Plugins available: <list from marketplace.json>

   Install with: /brana:plugin install <plugin-name>
   ```

### `install <name>`

Install a plugin from a known marketplace.

**Steps:**

1. Read `~/.claude/plugins/known_marketplaces.json`. Error if empty or missing.

2. Search all marketplace repos for a plugin matching `<name>`:
   - For each marketplace, read `<installLocation>/.claude-plugin/marketplace.json`
   - Find the plugin entry where `name` matches

3. If not found, report which marketplaces were searched and suggest `add` first.

4. If found, read the plugin manifest at `<marketplace>/<source>/.claude-plugin/plugin.json` to get version, description.

5. Present to user with AskUserQuestion:
   - question: "Install <name> v<version> from <marketplace>?\n<description>"
   - options: ["Install", "Cancel"]

6. If confirmed, snapshot the plugin source to cache:
   ```bash
   CACHE_DIR="$HOME/.claude/plugins/cache/<marketplace>/<name>/<version>"
   mkdir -p "$CACHE_DIR"
   rsync -av --exclude='.git' --exclude='.claude-plugin' \
       "<marketplace-install-location>/<source>/" "$CACHE_DIR/"
   ```

7. Copy the plugin manifest:
   ```bash
   mkdir -p "$CACHE_DIR/.claude-plugin"
   cp "<marketplace-install-location>/<source>/.claude-plugin/plugin.json" \
       "$CACHE_DIR/.claude-plugin/plugin.json"
   ```

8. Register in `~/.claude/plugins/installed_plugins.json`:
   ```json
   {
     "version": 2,
     "plugins": {
       "<name>": {
         "marketplace": "<marketplace-name>",
         "version": "<version>",
         "installPath": "<CACHE_DIR>",
         "installedAt": "<ISO timestamp>",
         "source": {
           "source": "github",
           "repo": "<owner>/<repo>"
         }
       }
     }
   }
   ```
   Merge with existing plugins — don't overwrite other entries.

9. Report:
   ```
   Installed: <name> v<version>
   Location: <CACHE_DIR>

   Restart Claude Code to activate.
   Skills will be available as /<name>:*
   ```

### `list`

Show installed plugins and available plugins from known marketplaces.

**Steps:**

1. Read `~/.claude/plugins/installed_plugins.json` and `~/.claude/plugins/known_marketplaces.json`.

2. For each installed plugin, read its `plugin.json` from cache to get description and version.

3. For each known marketplace, read its `marketplace.json` to get available plugins.

4. Display:
   ```
   Installed plugins:
     brana v1.0.0 (martineserios/thebrana) — AI development system

   Available from marketplaces:
     claude-plugins-official:
       (list plugins from marketplace.json)
     brana:
       brana v1.0.0 (installed)

   Add marketplaces: /brana:plugin add <owner/repo>
   ```

### `remove <name>`

Uninstall a plugin.

**Steps:**

1. Read `~/.claude/plugins/installed_plugins.json`. Check `<name>` exists.

2. If not found, report error and list installed plugins.

3. Confirm with AskUserQuestion:
   - question: "Remove plugin '<name>'? This deletes cached files."
   - options: ["Remove", "Cancel"]

4. Delete the cache directory:
   ```bash
   rm -rf "$HOME/.claude/plugins/cache/*/<name>/"
   ```

5. Remove from `installed_plugins.json` (delete the key, keep other plugins).

6. Report:
   ```
   Removed: <name>
   Restart Claude Code to deactivate.
   ```

### `update [name]`

Update all installed plugins or a specific one.

**Steps:**

1. Read `installed_plugins.json`. If `<name>` given, filter to that plugin.

2. For each plugin to update:
   a. Find its marketplace in `known_marketplaces.json`
   b. Pull latest: `cd <marketplace-install-location> && git pull --ff-only`
   c. Read updated `marketplace.json` for new version
   d. Compare with installed version

3. Present changes to user:
   ```
   Updates available:
     brana: v1.0.0 → v1.1.0
   ```

4. Confirm with AskUserQuestion:
   - question: "Apply updates?"
   - options: ["Update all", "Pick which", "Skip"]

5. For each confirmed update, re-run the install snapshot (same as `install` step 6-8).

6. Report results.

### `sync`

Sync dev plugin cache with local `system/` directory. Shortcut for `bootstrap.sh --sync-plugin`.

**Steps:**

1. Detect if running inside a plugin repo (check for `system/.claude-plugin/plugin.json` in CWD or parents).

2. If not in a plugin repo, error: "Run from a plugin repo root."

3. Run:
   ```bash
   ./bootstrap.sh --sync-plugin
   ```

4. Report the sync result.

## Notes

- All file writes use CC's existing JSON format for forward compatibility with native `/plugin` commands.
- Marketplace repos must have `.claude-plugin/marketplace.json` at root with a `plugins` array.
- Plugin source directories must have `.claude-plugin/plugin.json` as their manifest.
- This skill becomes redundant when CC ships native plugin management. At that point, it can be retired or become a thin wrapper.
- Never auto-install or auto-update. User confirms every action.
