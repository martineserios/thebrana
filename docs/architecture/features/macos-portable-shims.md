---
status: draft
---
# macOS portable shell shims (t-3373, epic macos-portability t-3372)

## Problem

The repo's ~389 shell scripts assume GNU userland. On macOS (BSD userland,
Apple Silicon + Homebrew) these break: `flock` (26 files), `date -d` (21),
`sha256sum`/`md5sum` (18), `grep -P` (13), `stat -c` (12), `sed -i` (9),
`readlink -f` (5). systemd (11) is a separate task (launchd scheduler).

## Decision

One sourced library, `system/hooks/lib/portable.sh` (next to the other shared
shell libs; scripts already reach it via `$SCRIPT_DIR/../hooks/lib/`).
Callers use `p_*` wrappers instead of the GNU-only forms.

**Capability probing, not `uname`.** Each shim tests what the local tools can
actually do at source time. This keeps Linux on the native GNU fast path,
makes Homebrew `coreutils` (g-prefixed) work automatically, and lets the test
suite exercise the BSD branches on Linux by shrinking `PATH`.

## API

| Function | Replaces | Contract |
|---|---|---|
| `p_flock [-n] LOCK cmd...` | `flock` | Run `cmd` holding `LOCK`. `-n` = fail (exit 1) instead of waiting. Fallback: atomic `mkdir` lock with pid stale-detection. |
| `p_date_d STR [FMT]` | `date -d STR` | STR: `@epoch`, `YYYY-MM-DD`, `YYYY-MM-DDTHH:MM:SS[Z]`, `N unit[s] ago`. Prints epoch seconds, or `date +FMT` if FMT given. Exit 1 on unparseable. |
| `p_sha256 [FILE]` | `sha256sum` | Prints the bare hex digest (stdin if no FILE). |
| `p_md5 [FILE]` | `md5sum` | Same, md5. |
| `p_stat_mtime FILE` | `stat -c %Y` | Epoch seconds. |
| `p_stat_size FILE` | `stat -c %s` | Bytes. |
| `p_sed_i SCRIPT FILE...` | `sed -i SCRIPT FILE` | In-place edit (temp-suffix + delete, valid on GNU and BSD). |
| `p_readlink_f PATH` | `readlink -f` | Canonical absolute path, symlinks resolved. |

## Out of scope

- **`grep -P`**: not shimmed. A PCRE emulation is a footgun. Guidance: rewrite
  with `grep -E` (or `awk`/`sed`) at the call site; where PCRE is genuinely
  required, `command -v ggrep` (Homebrew `grep`) is the documented escape.
  Handled in the caller sweep, not here.
- **Caller sweep**: separate follow-up task under the epic.
- **systemd → launchd**: separate task.

## Testing

`tests/hooks/test-portable.sh` runs every shim twice: native PATH, and a
simulated-BSD PATH (`tests/lib/bsd-path.sh` builds a temp bin dir that
omits `flock`/`sha256sum`/`md5sum`/`realpath` and wraps `date`/`stat`/`sed`/
`readlink` to reject the GNU-only flag forms while accepting the BSD forms).
Real-macOS verification is a CI `macos-latest` job (later task) plus a manual
run on the Mac.
