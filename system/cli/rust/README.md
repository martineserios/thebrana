# Rust Hot-Path Binaries (t-427)

Future Rust binaries that Python calls via subprocess for performance-critical operations.
Currently deferred — Python handles everything fine at <500KB JSON.

## Candidates

### brana-query

Fast JSON filter binary. Replaces `_filter_tasks()` in backlog.py.

```bash
# Usage: pipe tasks.json, get filtered results
brana-query --tag scheduler --status pending < .claude/tasks.json

# Python integration (backlog.py):
result = subprocess.run(
    ["brana-query", "--tag", tag, "--status", status],
    input=json.dumps(tasks), capture_output=True, text=True,
)
filtered = json.loads(result.stdout)
```

### brana-fmt

Themed line renderer. Takes JSON task + theme, outputs styled terminal line.
Replaces `task_line()` in theme.py.

```bash
# Usage: pipe task JSON, get styled output
echo '{"id":"t-001","subject":"Test","status":"pending"}' | brana-fmt --theme emoji

# Python integration (theme.py):
result = subprocess.run(
    ["brana-fmt", "--theme", theme_name],
    input=json.dumps(task), capture_output=True, text=True,
)
print(result.stdout)
```

## When to build

Build when:
- tasks.json exceeds 10K entries and Python parsing is measurably slow
- Distribution requires a single static binary (no Python dependency)
- Profiling shows `_filter_tasks` or `task_line` as actual bottlenecks

Don't build when:
- "Rust is cool" — that's not a bottleneck
- <500KB JSON files parse in milliseconds in Python
