# bootstrap.sh Reference

> The identity layer deployment script. Deploys `~/.claude/CLAUDE.md`, scripts, scheduler, ruflo config, and plugin registration. Safe to re-run — idempotent.

## What bootstrap.sh Handles

The brana system has two layers. bootstrap.sh owns the identity layer:

| Layer | Who deploys it | What it contains |
|-------|---------------|-----------------|
| **Plugin** (`system/`) | CC natively (`--plugin-dir ./system`) | Skills, agents, hooks, commands |
| **Identity** (`~/.claude/`) | `./bootstrap.sh` | CLAUDE.md, scripts, scheduler, ruflo, plugin registration |

**Do not confuse** bootstrap.sh with deploy.sh — `deploy.sh` is deprecated and will be removed. `bootstrap.sh` is the current deployment path.

## Usage

```bash
./bootstrap.sh                # Full sync (idempotent, safe to re-run)
./bootstrap.sh --check        # Dry-run: show what would change without applying
./bootstrap.sh --sync-plugin  # Sync installed plugin cache with current system/
./bootstrap.sh --help         # Show usage
```

After any run, bootstrap creates `/tmp/brana-bootstrap-pending-restart`. The next CC session start surfaces a banner: *"Previous bootstrap changed hooks — restart CC to activate."* The sentinel is one-shot and cleared on first CC start.

## Steps (in order)

### Pre-flight: CC version check

Exits with error if the installed Claude Code version is below the minimum required for two CVEs:

| CVE | Minimum CC version | Risk |
|-----|-------------------|------|
| CVE-2026-21852 | 2.0.65 | API key exfil via ANTHROPIC_BASE_URL |
| CVE-2025-59536 | 1.0.111 | Hooks RCE |

**Fix:** `npm i -g @anthropic-ai/claude-code`

### Step 1: CLAUDE.md (identity)

Deploys `system/CLAUDE.md` to `~/.claude/CLAUDE.md`.

If `~/.claude/CLAUDE.md` exists, is not marked "intentionally blank", and differs from the source, bootstrap creates a backup at `~/.claude/CLAUDE.md.bootstrap-backup` before overwriting. The backup is only created once — subsequent runs skip it if the backup file already exists.

### Step 1b: Plugin migration cleanup

Removes stale directories that `deploy.sh` used to copy to `~/.claude/`:
- `~/.claude/skills/`
- `~/.claude/commands/`
- `~/.claude/agents/`

These are now provided by the plugin. Leftover copies cause duplicate loading.

### Step 2: Rules (cleanup only)

Rules are **not deployed by bootstrap** — they load from the plugin. If you have stale `.md` files in `~/.claude/rules/` from a previous `deploy.sh` run, bootstrap removes them to prevent double-loading.

> Rule authoring: add rules to `system/rules/` and load the plugin. Do not place rules in `~/.claude/rules/` manually.

### Step 3: Scripts

Syncs `system/scripts/` → `~/.claude/scripts/`. All `.sh` files in the target are made executable. Removes files in the target that no longer exist in the source (brana-managed — no user files should live here).

### Step 4: Statusline

Copies `system/statusline.sh` → `~/.claude/statusline.sh` and makes it executable.

### Step 4b: PostToolUse cleanup

CC #24529 (PostToolUse hooks not firing from plugin) was resolved. This step removes the old workaround entries from `~/.claude/settings.json` `.hooks` field. If `jq` is not installed, this step is skipped with a warning.

### Step 4c: Undercover mode

Sets `~/.claude/settings.json` `attribution` field to `{"commit": "", "pr": ""}`. This tells CC not to add `Co-Authored-By` trailers to commits or PRs — the no-attribution hard rule.

If `jq` is not installed or `settings.json` doesn't exist, this step is skipped.

### Step 4d: Git pre-commit hook

Deploys `system/scripts/git-hooks/pre-commit` to `~/.config/git/hooks/pre-commit` and `~/.config/git/hooks/commit-msg`. This is the git-side backstop for the no-attribution rule.

**Activation is opt-in.** Bootstrap does not set `core.hooksPath` globally. You must run:

```bash
git config --global core.hooksPath ~/.config/git/hooks
```

Bootstrap will print a reminder if `core.hooksPath` is not set. If it is set to a different path, bootstrap also prints a warning.

### Step 5: Scheduler

Deploys the scheduler runtime to `~/.claude/scheduler/`:

- `brana-scheduler` — main scheduler binary
- `brana-scheduler-runner.sh` — job runner
- `brana-scheduler-notify.sh` — notification handler
- `check-agentdb-integration.sh` — AgentDB health check
- `templates/` — job templates

Creates `~/.claude/scheduler/scheduler.json` from the template if it doesn't exist yet. Edit `scheduler.json` to configure your scheduled jobs, then run `brana-scheduler deploy` to activate.

Creates `~/.local/bin/brana-scheduler` symlink for PATH access.

### Step 6: ruflo runtime

Checks for a `ruflo` or `claude-flow` binary in `~/.nvm/versions/node/*/bin/`. If found:

1. Installs `sql.js` if missing (required for AgentDB)
2. Deploys `~/.claude-flow/embeddings.json` (semantic search config)
3. Patches `@claude-flow/memory/dist/index.js` with the ControllerRegistry shim (bridges memory-bridge.js → AgentDB v3)

If ruflo is not found, this step is skipped. The system falls back to native auto memory (`~/.claude/projects/*/memory/`).

### Step 6b: MCP servers (settings.local.json)

Configures ruflo as an MCP server in `~/.claude/settings.local.json` (gitignored, per-machine). Uses the wrapper script `system/scripts/ruflo-mcp.sh` if present; falls back to the ruflo binary directly.

`settings.local.json` is per-machine and never committed — safe to edit for local overrides.

**Single-instance enforcement (flock mutex):** `ruflo-mcp.sh` uses `flock -n` to ensure only one ruflo process writes to `~/.swarm/memory.db` at a time. SQLite WAL mode allows concurrent readers but concurrent writers corrupt B-trees — confirmed by two corruption events (April + June 2026) caused by one ruflo process per CC terminal session. When a second CC session starts while ruflo is already running, the wrapper exits immediately and ruflo shows as "failed" in `/mcp`. This is expected — run `/mcp reconnect` in that session once the first session closes, or after the first session's ruflo exits.

### Step 7: Plugin auto-registration

Registers the brana plugin with CC's plugin system so it loads automatically without `--plugin-dir`:

| Sub-step | What it does |
|----------|-------------|
| **7a** | Adds brana to `~/.claude/plugins/known_marketplaces.json` |
| **7b** | Symlinks `~/.claude/plugins/marketplaces/brana` → this repo (dev mode: local changes are live) |
| **7c** | Snapshots `system/` to `~/.claude/plugins/cache/brana/brana/<version>/`. CC reads from this cache. |
| **7d** | Checks `~/.local/bin/brana` mtime vs newest `*.rs` source. Warns if binary predates source (stale binary = silent failures). |
| **7e** | Registers in `~/.claude/plugins/installed_plugins.json` with current git SHA and version |
| **7f** | Writes `~/.claude/installed_plugins.json` (the simple registry CC uses for `brana doctor` check 2). Step 7e writes the verbose `plugins/installed_plugins.json`; step 7f keeps the simpler sibling in sync so fresh installs pass the doctor check without a separate manual step. Uses `jq` if available, falls back to a `printf` write if not. |

After step 7, CC loads the plugin from the cache automatically — you don't need `--plugin-dir ./system` for normal sessions. Use `--plugin-dir ./system` when you want to test local changes before snapshotting.

The symlink in 7b means: once bootstrap runs, `--sync-plugin` (or re-running `bootstrap.sh`) is usually enough to push changes to the cache without a full reinstall.

---

## --check Mode

```bash
./bootstrap.sh --check
```

Prints what would change without applying anything. Output uses:
- `+` new file/entry
- `~` changed file/entry
- `=` unchanged
- `-` would remove

Use this before running a full sync to see the diff.

## --sync-plugin Mode

```bash
./bootstrap.sh --sync-plugin
```

Standalone operation. Finds the installed plugin cache directory and rsyncs `system/` into it. Use after making changes to skills/hooks/agents when you want to push to the cache without running the full identity-layer bootstrap.

Requires the plugin to already be installed (will error with install instructions if not).

---

## Troubleshooting

**CC version check fails:**
```
! CC 2.0.40 < 2.0.65 — CVE-2026-21852 unfixed. Run: npm i -g @anthropic-ai/claude-code
```
Upgrade CC and re-run.

**jq not found:**
Settings.json and MCP server steps are skipped with a `!` warning. Install jq: `sudo apt install jq` or `brew install jq`.

**ruflo not found:**
```
— ruflo not found (Layer 0 fallback)
```
ruflo is optional. The system works without it at reduced capability (no cross-session search). To install ruflo, follow `docs/guide/troubleshooting.md`.

**ruflo shows "failed" in /mcp after opening a second CC session:**
```
[ruflo-mcp] Another instance is running (PID: 12345). Exiting to prevent DB corruption.
```
This is the flock mutex working correctly — only one ruflo instance may write to `memory.db`. Close the first session (or wait for it to close), then run `/mcp reconnect` in the new session to start ruflo there. If the first session's ruflo already exited and you still see this, check for stale lock files: `rm -f ~/.swarm/ruflo-mcp.lock ~/.swarm/ruflo-mcp.pid`.

**Plugin not installed (--sync-plugin fails):**
```
No installed brana plugin found in ~/.claude/plugins/cache/brana/brana
Install with: claude plugin install brana
```
Run a full `./bootstrap.sh` first (step 7 registers the plugin).

**core.hooksPath not set:**
```
! To activate globally, run: git config --global core.hooksPath ~/.config/git/hooks
```
This is a reminder, not an error. Run the command to activate the no-attribution git hook globally.

**CLAUDE.md backup created:**
```
Backed up existing CLAUDE.md
```
Your previous `~/.claude/CLAUDE.md` is at `~/.claude/CLAUDE.md.bootstrap-backup`. Review and merge any personal additions before deleting.

---

## When to Re-run

| Situation | Action |
|-----------|--------|
| Updated `system/CLAUDE.md` | `./bootstrap.sh` |
| Added/changed a script in `system/scripts/` | `./bootstrap.sh` |
| Changed scheduler config | `./bootstrap.sh` then `brana-scheduler deploy` |
| Added a skill/hook/agent (plugin) | `./bootstrap.sh --sync-plugin` (or `./bootstrap.sh`) |
| First install on a new machine | `./bootstrap.sh` |
| Upgraded CC (CVE patch) | `./bootstrap.sh` (re-checks version, cleans stale hooks) |

**Do not** edit `~/.claude/` files directly — they are overwritten on the next bootstrap run.

---

## See Also

- [`plugin-structure.md`](plugin-structure.md) — what the plugin layer contains
- [`plugin-lifecycle.md`](plugin-lifecycle.md) — how CC loads the plugin at session start
- [`developer-quickstart.md`](developer-quickstart.md) — full deploy cycle for new components
- [`docs/reference/scripts.md`](../reference/scripts.md) — all helper scripts deployed by bootstrap

## Field Notes

### 2026-06-13: rules write path is system/rules/ not ~/.claude/rules/ (t-1944)
When editing rule files, target `system/rules/<file>.md` — not `~/.claude/rules/<file>.md`. bootstrap.sh `sync_dir` deploys to the latter and **deletes any file absent from `system/rules/`**, so a hand-placed file in `~/.claude/rules/` will be silently removed on the next bootstrap run. Equivalent: always author in `system/`, deploy via bootstrap.
Source: t-1944 2026-06-13 — Edit tool initially targeted wrong path

### 2026-06-13: validate.sh Check 29 fires after any rules change — run brana reference generate first (t-1944)
After adding, removing, or renaming files in `system/rules/`, `brana reference generate` must be run before `validate.sh` — Check 29 diffs the generated reference docs against their sources and fails if they're out of date. Running it takes ~1s and updates `docs/reference/rules.md`. Add this to any rules-refactor checklist.
Source: t-1944 2026-06-13

### 2026-06-10: rules deployment restored — t-760's plugin assumption was false (t-1946, E2026-06-10)
t-760 (2026-03-30) stopped bootstrap from copying `system/rules/` to `~/.claude/rules/` on the assumption that the plugin loads them. **CC plugins cannot provide rules** — no rules component exists in the plugin spec (verified against plugins-reference docs 2026-06-10). The deployed copies survived on disk until bootstrap's t-760 cleanup step finally ran (2026-06-10), then the entire discipline shell silently undeployed — zero rules loaded for new sessions. Bootstrap now syncs `system/rules/` → `~/.claude/rules/` again (README.md excluded — authoring contract, not a rule; it has no frontmatter and would always-load as noise). Also removed the dead Cursor-legacy `alwaysApply:` field from 3 rules — `paths:` scoping was the operative contract all along.
