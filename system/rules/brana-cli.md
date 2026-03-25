# Brana CLI

Use the `brana` CLI for all operations it supports. Run `brana --help` or `brana <cmd> --help` for full usage.

## Core rules

- **Always prefer CLI over raw file access.** Never `cat`, `jq`, `python3`, Read, Write, or Edit on `.claude/tasks.json`.
- Use `brana backlog` for all task operations (get, set, query, search, add, next, focus, status, stats, roadmap, tree, tags, blocked, stale, context, diff, burndown, rollup, sync).
- `brana backlog add` accepts `--json '{...}'`, `--json @file`, `--json -` (stdin), or shorthand flags: `--subject "..." --stream roadmap --type task --tags "a,b" --effort S`.
- Use `brana ops` for scheduler (status, drift, health, logs, run, enable/disable, metrics, reindex).
- Use `brana doctor` if something feels off. `brana portfolio` for cross-client paths.
- Use `brana transcribe` for audio. `brana files` for large file tracking. `brana feed`/`brana inbox` for content polling.
