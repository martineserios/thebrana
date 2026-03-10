# Troubleshooting

Common issues with brana, organized by symptom. Each entry follows the pattern: symptom, cause, fix.

## Bootstrap and installation

### Bootstrap fails with "jq not found"

**Symptom:** `./bootstrap.sh` errors out early.

**Cause:** jq is not installed. Bootstrap uses jq to install PostToolUse hooks into `settings.json` and to register the plugin.

**Fix:** Install jq with your package manager:

```bash
# Debian/Ubuntu
sudo apt install jq

# macOS
brew install jq

# Arch
sudo pacman -S jq
```

### Bootstrap succeeds but hooks do not fire

**Symptom:** No session-start message appears. PreToolUse gates are not enforced.

**Cause:** The plugin is not loaded. Bootstrap deploys the identity layer but does not load the plugin itself. You need a separate install step.

**Fix:** Install the plugin via one of two methods:

```bash
# Method 1: Marketplace
/plugin marketplace add martineserios/thebrana
/plugin install brana

# Method 2: Dev mode
claude --plugin-dir ./system
```

Then start a new Claude Code session.

### Bootstrap backs up CLAUDE.md unexpectedly

**Symptom:** Bootstrap creates `~/.claude/CLAUDE.md.bootstrap-backup`.

**Cause:** You had an existing `~/.claude/CLAUDE.md` that differs from the brana version. Bootstrap preserves it as a backup before overwriting.

**Fix:** This is expected behavior. Review the backup and merge any custom content into the brana CLAUDE.md if needed. The backup is only created once.

## Skills and plugin

### Skills not appearing (no /brana:* commands)

**Symptom:** Tab-completing `/brana:` shows nothing.

**Cause:** The plugin is not loaded for this session.

**Fix:** Check which install method you used:

1. **Marketplace install** -- verify the plugin is registered: check `~/.claude/plugins/installed_plugins.json` for a `brana@brana` entry.
2. **Dev mode** -- you must start Claude Code with `claude --plugin-dir ./system` every time. The flag is not persistent.
3. **Restart Claude Code** -- plugin changes require a new session.

### Plugin conflicts with other plugins

**Symptom:** Unexpected behavior, duplicate skill names, or hook errors.

**Cause:** Another plugin may define hooks or skills that conflict with brana.

**Fix:** Check loaded plugins with `/plugin list`. If another plugin uses the same hook events (PreToolUse, SessionStart, SessionEnd), both will fire. Review hook output for errors. Disable the conflicting plugin if needed.

## Hooks

### Hook timeouts (10-second limit)

**Symptom:** Hook output is cut off or the hook silently fails to complete.

**Cause:** Claude Code enforces a 10-second timeout on hooks. Heavy processing (memory queries, API calls) can exceed this.

**Fix:** Brana uses the background-fork pattern for hooks that do heavy work. The hook responds immediately with essential output, then forks processing to the background. If you see timeouts in custom hooks you have added, apply the same pattern:

```bash
# Respond immediately
echo '{"result": "immediate response"}'

# Fork heavy work to background
(
  # slow operations here
) &
disown
```

### PostToolUse hooks not firing

**Symptom:** Post-write validation, PR review triggers, or task validation hooks do not run.

**Cause:** Claude Code v2.1.x has a known bug where PostToolUse and PostToolUseFailure events from plugin `hooks.json` are silently dropped. Only PreToolUse, SessionStart, and SessionEnd work from plugins.

**Fix:** This is already handled by bootstrap. Running `./bootstrap.sh` installs PostToolUse and PostToolUseFailure hooks directly into `~/.claude/settings.json` with absolute paths. This is the only reliable method in CC v2.1.x.

To verify the workaround is in place:

```bash
jq '.hooks.PostToolUse' ~/.claude/settings.json
```

You should see an array of hook entries. If it is empty or missing, re-run `./bootstrap.sh`.

Track CC issue #24529 for upstream fix.

### PreToolUse hook blocks edits unexpectedly

**Symptom:** Claude refuses to write implementation files on a feature branch, saying a spec or test is required first.

**Cause:** The spec-first gate (`pre-tool-use.sh`) requires spec or test activity before allowing implementation edits on `feat/*` branches. This is by design for projects with `docs/decisions/`.

**Fix:** Create a spec or test file first:

1. Write a failing test (`tests/*.test.*` or `*.spec.*`)
2. Or create a spec/ADR in `docs/decisions/`
3. Or commit any change to `docs/` or test directories

If the project should not enforce spec-first, check whether it has a `docs/decisions/` directory. The gate only activates for projects that have one.

## Scheduler

### Scheduler jobs fail with "flock: failed to get lock"

**Symptom:** Job log shows exit with code 75 (SKIPPED).

**Cause:** Another job is already running in the same project. The runner uses flock to prevent concurrent execution per project directory.

**Fix:** This is expected behavior -- the job will run at its next scheduled time. If a job consistently gets skipped, check whether a previous run is stuck:

```bash
# Check for stuck processes
ps aux | grep brana-scheduler-runner

# Check lock files
ls -la ~/.claude/scheduler/locks/
```

Remove the lock file manually if the process has died without cleaning up.

### Scheduler jobs fail with permission errors

**Symptom:** Job log shows permission denied errors.

**Cause:** The runner script or job command lacks execute permission, or loginctl linger is not enabled.

**Fix:**

```bash
# Ensure scripts are executable
chmod +x ~/.claude/scheduler/brana-scheduler-runner.sh
chmod +x ~/.claude/scheduler/brana-scheduler

# Enable linger (required for timers to fire after logout)
sudo loginctl enable-linger $USER
```

### Timers not firing after logout

**Symptom:** Jobs run when logged in but stop after closing the terminal session.

**Cause:** Systemd user sessions are killed on logout by default.

**Fix:** Enable lingering for your user:

```bash
sudo loginctl enable-linger $USER
```

Verify with:

```bash
loginctl show-user $USER | grep Linger
```

### Job timeout (exit code 124)

**Symptom:** Job log ends with `TIMEOUT after Ns`.

**Cause:** The job exceeded its configured `timeoutSeconds`.

**Fix:** Increase the timeout for the job in `scheduler.json`:

```json
{
  "my-job": {
    "timeoutSeconds": 600
  }
}
```

Then redeploy: `brana-scheduler deploy`.

## claude-flow and memory

### claude-flow not found

**Symptom:** Memory-related features degrade silently. Session start hook does not show pattern recall.

**Cause:** claude-flow is not installed globally.

**Fix:**

```bash
npm install -g claude-flow
```

If using nvm, install in the active node version. Bootstrap expects to find `claude-flow` in `~/.nvm/versions/node/*/bin/`.

### Embedding dimension mismatch

**Symptom:** Memory search returns no results or errors about vector dimensions.

**Cause:** Without `@xenova/transformers` installed globally, claude-flow falls back to a hash-based embedding that produces 768-dimensional vectors instead of the expected 384-dimensional ONNX vectors.

**Fix:**

```bash
npm install -g @xenova/transformers@2.17.2
```

Then re-run bootstrap to deploy the correct embeddings config:

```bash
./bootstrap.sh
```

The `~/.claude-flow/embeddings.json` file pins the model to `all-MiniLM-L6-v2` (384-dim). After fixing, reindex the knowledge base:

```bash
./system/scripts/index-knowledge.sh
```

### cf-env.sh sourcing fails in hooks

**Symptom:** Hook scripts fail with `source: not found` or `HOME: unbound variable`.

**Cause:** `$HOME` is not expanded when the script runs inside the Claude Code hook executor.

**Fix:** Use the full absolute path instead of `$HOME`:

```bash
# Wrong
source "$HOME/.claude/scripts/cf-env.sh"

# Right
source /home/yourusername/.claude/scripts/cf-env.sh
```

## General

### Commands silently fail with empty output

**Symptom:** Bash commands return exit code 134 with no error message.

**Cause:** Disk is full (ENOSPC).

**Fix:** Free disk space:

```bash
df -h
# Identify full filesystem, clean up
```

### CLAUDE_PLUGIN_ROOT not set in hooks

**Symptom:** Hook commands using `${CLAUDE_PLUGIN_ROOT}` fail with "file not found".

**Cause:** Claude Code does not always set this variable in the hook executor environment.

**Fix:** All brana plugin hooks use `${CLAUDE_PLUGIN_ROOT}` which works when the plugin is properly loaded. If you see this error, verify the plugin is installed and a fresh session has been started. For hooks installed via settings.json (PostToolUse), bootstrap uses absolute paths instead of `${CLAUDE_PLUGIN_ROOT}`.
