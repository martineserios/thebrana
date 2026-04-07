---
depends_on:
  - system/statusline.sh
  - system/hooks/post-tasks-validate.sh
---
# Statusline Test Coverage

## Test Files

| File | Scope | Tests |
|------|-------|-------|
| `test-statusline-cache.sh` | TSV cache fields, build_step extraction, mtime freshness | 12 |
| `test-statusline-width.sh` | Width detection, progressive segment dropping | 23 |
| `test-session-score.sh` | Session score counter lifecycle, statusline segment | 14 |
| `test-statusline-integration.sh` | End-to-end: cache flow, session lifecycle, staleness recovery, empty state, width+segments | 44 |

## Integration Test Scenarios

1. **Full render** — all segments present on wide terminal (model, project, branch, CTX%, lines, task, build step, bugs, phase, session score)
2. **Cache to statusline flow** — post-tasks-validate.sh creates cache, statusline.sh reads it without jq
3. **Session lifecycle** — reset counter at session start, increment on completions, verify statusline reflects updates
4. **Staleness recovery** — stale cache detected via mtime, jq fallback fires, cache refreshed inline
5. **Empty/missing state** — no tasks.json, no cache, no score file; statusline renders cleanly with exit 0
6. **Width + segments combined** — narrow terminal with task data drops low-priority segments while keeping model and CTX%
