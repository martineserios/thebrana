---
always-load: true
---
# Brana CLI

**Always prefer CLI over raw file access.** Never Read/Write/Edit `.claude/tasks.json` directly.

- `brana backlog` — all task ops (get, set, query, search, add, status, roadmap, tree, tags, blocked, stale)
- `brana ops` — scheduler (status, health, logs, run, enable/disable)
- `brana doctor` — system health. `brana portfolio` — cross-client paths.
- `brana transcribe` — audio/video (`--frames DIR` for video frames). `brana files` — large files. `brana feed`/`brana inbox` — content.
