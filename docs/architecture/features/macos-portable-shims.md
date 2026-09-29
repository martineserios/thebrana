---
status: implemented
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
| `p_flock [-n] LOCK cmd...` | `flock file cmd` | Run `cmd` (or a shell function) holding `LOCK`. `-n` = fail (rc 1) instead of waiting. Fallback: atomic `mkdir` lock with pid stale-detection. |
| `p_lock_acquire FD FILE [-n\|-w SECS]` / `p_lock_release FD FILE` | `exec N>f; flock [-w S] N` … `flock -u N` | fd-style exclusive lock held across a code region; FD is the caller's fd number. Same fallback as `p_flock`. |
| `p_date_d STR [FMT]` | `date -d STR [+FMT]` | STR: `now`, `@epoch`, `YYYY-MM-DD`, ISO-8601 / git `%ci` with optional fraction and `Z`/`±HH[:]MM` offset, `N unit[s] ago`. Parsed in pure shell (no `date -d`). **UTC in, UTC out** (deterministic across TZ). Prints epoch seconds, or `date +FMT` if FMT given. rc 1 if unparseable. |
| `p_epoch_fmt EPOCH FMT` | `date -d @E +FMT` | Local-time formatting for human display (honours `TZ`). |
| `p_sha256 [FILE]` | `sha256sum` | Prints the bare hex digest (stdin if no FILE). |
| `p_md5 [FILE]` | `md5sum` | Same, md5. |
| `p_stat_mtime FILE` / `p_stat_atime FILE` | `stat -c %Y` / `%X` | Epoch seconds. |
| `p_stat_size FILE` | `stat -c %s` | Bytes. |
| `p_sed_i SCRIPT FILE...` | `sed -i SCRIPT FILE` | In-place edit (temp-suffix + delete, valid on GNU and BSD). |
| `p_readlink_f PATH` | `readlink -f` | Canonical absolute path, symlinks resolved. |

## Known limit — lock interop with the Rust CLI

Without `flock(1)` (stock macOS) the fallback is a `mkdir` lock. It serializes
shell against shell only; it **cannot exclude a Rust `flock(2)` holder**. The one
site that shares a lock with the CLI is `post-tasks-validate.sh` (`tasks.json.lock`
sidecar). Before this change that site had no lock at all on macOS (`flock: command
not found`), so this is an improvement, not a regression — but it is a **stopgap**.
Mitigation: `brew install discoteq/discoteq/flock` (documented in the setup guide,
t-3376). Root-cause option, not built: a `brana lock` Rust subcommand sharing
`lock_tasks`'s lock implementation, so shell and CLI lock through one code path.
On the fallback path a holder that exits without releasing leaves `FILE.d`
behind; the next acquirer reclaims it once the holder pid is dead.

## Enforcement — `lint-portability.sh` (validate Check 76)

`system/scripts/lint-portability.sh` fails on `flock`, `date -d`, `sha256sum`,
`md5sum`, `stat -c`, `sed -i`, `readlink -f` and `grep -P` in tracked `*.sh` and
extensionless sh/bash-shebang files (skips `tests/`, `docs/`, `portable.sh`,
itself; full-line comments ignored). Per-line escape hatch: `# portable-ok:
<reason>` (used for remote-host commands, the systemd-only scheduler awaiting
t-3375, and `aliases.sh`, which is sourced into zsh where bash-only
`portable.sh` cannot load). `tests/scripts/test-lint-portability.sh` is the
must-fire test. New GNU-isms cannot re-enter unnoticed.

## Bash floor — decision (t-3378)

macOS ships bash 3.2; 9 scripts use `mapfile`/`readarray`/`declare -A` (bash >= 4).
Decision: **require Homebrew bash (>= 4)** rather than rewrite them. Hooks run as
`bash <script>` and 148/151 scripts use `#!/usr/bin/env bash`, so the requirement is
exactly "the `bash` first on PATH is >= 4" — Homebrew's `brew shellenv` already puts it
ahead of `/bin`. `bootstrap.sh` enforces it in `platform_preflight()` (fails with a
`brew install bash` hint) and warns when `flock(1)` is missing on macOS. Covered by
`tests/bootstrap/test-preflight-platform.sh`. Revisit only if a hook must run under an
absolute `/bin/bash` (none does today; 3 scripts carry `#!/bin/bash` but use no bash-4
features).

## Shell snippets in markdown

Skill phase docs contain shell that agents run, often under **zsh**. They must not
source `portable.sh` (bash-only). Use inline forms: arithmetic instead of
`date -d '6 hours ago'`, `git stash list --format=%ct` instead of parsing dates,
`grep -E` instead of `grep -P`, `md5sum || md5 -q`, and a `date -d … || date -j -u -f …`
pair where a real date must be parsed (brana writes UTC).

## Out of scope

- **`grep -P`**: not shimmed. A PCRE emulation is a footgun. Guidance: rewrite
  with `grep -E` (or `awk`/`sed`) at the call site; where PCRE is genuinely
  required, `command -v ggrep` (Homebrew `grep`) is the documented escape.
  Done per call site in the t-3374 sweep (13 sites rewritten; old/new output
  differential-tested on 81 inputs).
- **systemd → launchd**: t-3375.
- **Second-tier GNU-isms** (`timeout`, `realpath`, `ps etimes`, sed BRE `\+`/`\|`,
  `find -printf`, `date %N`, `tac`, `head -n -N`, `/proc`): t-3377.
- **Tests and remaining md snippets**: t-3379.

## Testing

`tests/hooks/test-portable.sh` (67 assertions) runs every shim twice: native PATH, and a
simulated-BSD PATH (`tests/lib/bsd-path.sh` builds a temp bin dir that
omits `flock`/`sha256sum`/`md5sum`/`realpath` and wraps `date`/`stat`/`sed`/
`readlink` to reject the GNU-only flag forms while accepting the BSD forms).
Real-macOS verification is a CI `macos-latest` job (later task) plus a manual
run on the Mac.
