# git-helpers.sh — spec

Task: t-1324 (closes t-1286, t-1316; enables t-1154 fixture)
Related: feedback_hook-bugs-come-in-pairs.md, feedback_hook-git-target-dir.md

## Purpose

Shared path-resolution helpers sourced by `branch-verify.sh`, `main-guard.sh`, and any future `Bash` PreToolUse hook that must reason about the target git repository of a command.

## Public API

### `extract_git_c_dir COMMAND`
Returns the path from `git -C <path>` in `COMMAND`, or empty string if absent.
- Matches the first `-C <path>` occurrence.
- Path terminates at whitespace. (No shell quoting — keep it simple; quoted paths with spaces are rare in agent-issued commands and can be handled later.)

### `extract_cd_prefix_dir COMMAND`
Returns the path from a leading `cd <path> &&` (or `;`, `|&`, `&`) in `COMMAND`, or empty string if absent.
- Must be the **first** token in the command (ignoring leading whitespace).
- Form: `cd <path> && <rest>` where the separator is `&&`, `||`, `;`, or `&` followed by whitespace.
- Path terminates at the separator or whitespace.
- Relative paths (e.g. `../wt`) are returned as-is; callers use `git -C` which handles resolution.

### `resolve_lookup_dir COMMAND CWD`
Returns the directory to use for all `git -C <dir> …` operations in a PreToolUse hook.

**Precedence (first non-empty wins):**
1. `extract_git_c_dir COMMAND` — explicit `-C` flag (most specific, always a git operation target)
2. `extract_cd_prefix_dir COMMAND` — shell `cd <path> && git …` idiom (worktree staging pattern)
3. `CWD` — fall back to the hook's input `cwd`

## Why this matters

`cd <path> && git add X` is a common agent pattern for worktree operations. The hook's input CWD is set by Claude Code (session working dir) — in Bash tool invocations, the session cwd is **not** the target of the in-command `cd`. Without parsing the `cd` prefix, the hook runs `git -C <session-cwd> branch --show-current` against the wrong repo, and either:
- lets a stage through that should be blocked (false negative on main), or
- blocks a legitimate worktree stage (false positive on feature branch).

We hit this ourselves during t-1323: after the hook denied a `cd <wt> && git commit`, the workaround was to reissue as `git -C <wt> commit`. Fixing the helper restores the natural idiom.

## Non-goals

- Shell quoting parity with bash. Commands with quoted/escaped paths are out of scope; callers can pass canonical unquoted paths or use `-C`.
- Multi-stage pipelines (`cd a && cd b && git …`). Single `cd` at start only.
- `pushd`/`popd`. `cd` only.

## Tests (live in `system/hooks/tests/`)

- Unit shell tests in `test-branch-verify.sh` and `test-main-guard.sh` exercise the full hook end-to-end:
  - (a) `cd /wt && git add system/hooks/foo.sh` on a feature branch → pass
  - (b) same on main → deny
  - (c) `cd /a && git -C /b add …` → `-C` wins (target `/b`)
  - (d) no `cd` prefix → CWD used (existing behavior)
  - (e) `cd` with trailing arguments before `&&` does not match (only `cd <path> &&`)
