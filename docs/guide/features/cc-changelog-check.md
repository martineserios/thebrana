# CC Changelog Check

Automatically detects when Claude Code releases a new version and prompts you to review what changed. Runs weekly via the scheduler.

## Quick Start

The feature runs automatically. When CC updates, you'll see on session start:

```
[CC changelog] New changes detected. Review: ~/.claude/cc-changelog-report.md
```

Read the report and run research:

```
/brana:research Claude Code changelog 2.1.75 to 2.1.76
```

## How It Works

1. Every Monday at 10:00, the scheduler runs `cc-changelog-check.sh`
2. Script checks `npm view @anthropic-ai/claude-code version` against the cached version
3. If the version changed, it writes `~/.claude/cc-changelog-report.md` with old → new version and action steps
4. Next time you start a session, the session-start hook surfaces the report
5. You review the changelog, run `/brana:research` for detailed analysis, and delete the report when done

## Options

| Option | Default | Description |
|--------|---------|-------------|
| Schedule | `Mon *-*-* 10:00:00` | Edit in `~/.claude/scheduler/scheduler.json` → `cc-changelog-review` |
| Cache file | `~/.claude/cc-version-cache` | Stores last known CC version |
| Report file | `~/.claude/cc-changelog-report.md` | Written when version changes, deleted after review |

## Examples

### Version change detected

```
$ ./system/scripts/cc-changelog-check.sh
CC version changed: 2.1.75 → 2.1.76. Report at ~/.claude/cc-changelog-report.md
```

### No changes

```
$ ./system/scripts/cc-changelog-check.sh
CC version unchanged: 2.1.76
```

### First run (baseline)

```
$ ./system/scripts/cc-changelog-check.sh
First run — cached CC version 2.1.76 (local: 2.1.76).
```

## Troubleshooting

| Symptom | Fix |
|---------|-----|
| "ERROR: npm view failed" | Check internet connection and npm installation |
| Report not surfacing on session start | Verify `session-start.sh` has the CC changelog section (search for `cc-changelog-report`) |
| Scheduler not running the check | Run `pgrep -f brana-scheduler` — if empty, restart scheduler |
| Want to force a check | Run `./system/scripts/cc-changelog-check.sh` manually |
