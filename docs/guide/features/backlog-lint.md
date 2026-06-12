# Backlog Lint — is this task ready for autonomous dispatch?

`brana backlog lint <id>` answers one question: can an agent pick this task up without a human in the loop? It runs four definition-of-ready checks and exits 0 (ready) or 1 (not ready), so it composes into scripts and the foreman dispatch loop.

## Usage

```bash
brana backlog lint t-1981            # human-readable verdict
brana backlog lint t-1981 --json     # machine-readable
brana backlog lint t-010 --file /path/to/tasks.json   # explicit tasks file
```

## What you see

Ready:

```
t-1981 ready — all 4 checks pass
```

Not ready — each failed check named on its own line:

```
t-157 not ready
  ✗ machine-verifiable-ac: no AC: lines in context
  ✗ rich-context: no context beyond AC: lines (tasks-need-rich-context)
  ✗ effort-s-or-m: effort not set
```

JSON (`--json`):

```json
{"ready":false,"checks":[{"name":"machine-verifiable-ac","pass":false,"reason":"no AC: lines in context"}, ...],"warnings":[]}
```

## The four checks

| Check | How to make it pass |
|-------|---------------------|
| `machine-verifiable-ac` | At least one `AC:` line in the task context naming a command, exit code, flag, test/assert shape, output verb, or file path. `AC: \`cargo test\` passes` ✓ — `AC: works well` ✗ |
| `rich-context` | Context has prose beyond the `AC:` lines — background, scope, constraints |
| `effort-s-or-m` | Effort set to `S` or `M`. L/XL tasks must be decomposed first |
| `no-open-ambiguity` | No `Q:` / `open Q:` lines in context, and every `blocked_by` task is completed or cancelled |

## Warnings (advisory, never block)

- **Interface-change AC** — an AC seems to imply a new param/field/endpoint; enumerate the change explicitly in the description.
- **Compiled-language task** — tags/description mention rust/cargo/compile; build cycles can make a code-size-S task wall-clock-M.

In human mode warnings print to stderr (`⚠ ...`); in JSON mode they're in the `warnings[]` array.

## Scripting

```bash
if brana backlog lint "$id" >/dev/null 2>&1; then
  dispatch "$id"
fi

brana backlog lint t-1981 --json | jq -r '.checks[] | select(.pass|not) | .name'
```
