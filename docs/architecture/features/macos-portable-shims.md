---
status: implemented
---
# macOS portable shell shims (t-3373, epic macos-portability t-3372)

> **Verification status.** Everything below is implemented and unit-tested on Linux, including against a
> simulated-BSD PATH. **None of it has run on real macOS yet** — the advisory `macos` CI job
> (`.github/workflows/ci.yml`, t-3376) is the first real run. "Implemented" means "built and tested
> here", not "proven on a Mac". See [Known unverified](#known-unverified-on-real-macos).

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
| `p_flock [-n] LOCK cmd...` | `flock file cmd` | Run `cmd` (or a shell function) holding `LOCK`. `-n` = fail (rc 1) instead of waiting. Fallback: a noclobber-file lock `LOCK.lk` with pid stale-detection (see below). |
| `p_lock_acquire FD FILE [-n\|-w SECS]` / `p_lock_release FD FILE` | `exec N>f; flock [-w S] N` … `flock -u N` | fd-style exclusive lock held across a code region; FD is the caller's fd number. Same fallback as `p_flock`. `FD` must be an integer 3..254 (it reaches `eval`; anything else returns 2), `-w` needs a whole number of seconds (it reaches `$(( ))`), and a lock path that is a symlink/dir/device is **refused with rc 3**. |
| `p_date_d STR [FMT]` | `date -d STR [+FMT]` | STR: `now`, `@epoch`, `YYYY-MM-DD`, ISO-8601 / git `%ci` with optional fraction and `Z`/`±HH[:]MM` offset, `N unit[s] ago`. Parsed in pure shell (no `date -d`). **UTC in, UTC out** (deterministic across TZ). Prints epoch seconds, or `date +FMT` if FMT given. rc 1 if unparseable. |
| `p_epoch_fmt EPOCH FMT` | `date -d @E +FMT` | Local-time formatting for human display (honours `TZ`). |
| `p_sha256 [FILE]` | `sha256sum` | Prints the bare hex digest (stdin if no FILE). |
| `p_md5 [FILE]` | `md5sum` | Same, md5. |
| `p_sha1 [FILE]` | `sha1sum` | Same, sha1 — only for identifiers that already use it (changing the algorithm would orphan them). |
| `p_touch_at FILE EPOCH` | `touch -d 'N days ago'` | Set mtime via `touch -t` (portable); pair with `p_date_d`. |
| `p_stat_mtime FILE` / `p_stat_atime FILE` | `stat -c %Y` / `%X` | Epoch seconds. |
| `p_stat_size FILE` | `stat -c %s` | Bytes. |
| `p_stat_mode FILE` | `stat -c %a` | Octal permission bits (`640`). |
| `p_sed_i SCRIPT FILE...` | `sed -i SCRIPT FILE` | In-place edit (temp-suffix + delete, valid on GNU and BSD). |
| `p_readlink_f PATH` | `readlink -f`, plain `realpath` | Canonical absolute path, symlinks resolved. |
| `p_realpath_m PATH` | `realpath -m` | Absolute, `.`/`..` collapsed, existing symlinks resolved, nonexistent tail allowed. |
| `p_relpath BASE PATH` | `realpath --relative-to` | Relative path from BASE to PATH (either may not exist). |
| `p_timeout [-k K] SECS cmd...` | `timeout` | GNU `timeout`, else `gtimeout`, else a bash watchdog (stdin preserved, TERM then optional KILL, rc 124; GNU returns 137 if it had to KILL — treat 124/137 as "timed out"). The fallback signals the child and its direct children, not the whole process group. |
| `p_date_iso` | `date -Iseconds` | Local time with a colon offset (`2026-09-29T14:18:03-03:00`). |
| `p_now_ms` | `date +%s%N` / 1e6 | Epoch ms: bash 5 `EPOCHREALTIME` (no fork), else `date %N`, else perl, else whole seconds. |

## The fallback lock (and why it is not `mkdir`)

Without `flock(1)` the lock is a file `LOCK.lk` holding the holder's pid, created with the shell's own
noclobber redirect (`set -C; > file` = `open(O_CREAT|O_EXCL)`). It is deliberately **not** a `mkdir` lock:
Ubuntu's default coreutils is now uutils, whose `mkdir` lets several concurrent callers "win" the same
directory (reproduced on this repo's dev box; python's `os.mkdir` on the same kernel never double-granted).
A lock must not depend on a coreutils binary's atomicity. (Observed on one box — `mkdir (uutils coreutils) 0.8.0`,
Ubuntu, kernel 7.0 — not a survey of all distributions.) A dead holder is reclaimed **only under a second
lock (`LOCK.lk.reclaim`) and only if re-evaluated there against the current file** — the first, naive
version let two waiters both "reclaim" and both hold the lock (Gate 3 review). `tests/hooks/test-lock-stress.sh` is the evidence: 16 contenders × 8 rounds, **every round
starting from a stale lock** so the reclaim path runs each time, with a noclobber overlap detector. Mutation-checked:
swapping in the naive reclaim (delete the stale lock, no second lock, no re-check) makes it fail on every run (54–62
overlaps); the real code passes. An empty/garbage pid (`kill -0 0` and `-1` falsely report alive) counts as stale
only after 10 s; "stat failed" is treated as *unknown, not stale*; release removes only a lock we still own.

### Hardening contract, and its limits

- **Non-regular lock path → refused (rc 3).** A symlink (a dangling one makes the O_EXCL create fail forever; one
  to `/dev/null` makes noclobber "succeed" for *every* caller — mutual exclusion silently gone), a directory or a
  device at `LOCK.lk` / `LOCK.lk.reclaim` is an attack or a mistake: it is refused with a message, never spun on.
- **Lock paths belong in a user-private directory (0700).** The check cannot close a swap race in a shared directory
  (an attacker replacing the file between our check and our create). `autonomous-runner.sh`'s default worktree lock is
  under `/tmp/brana-runner/`; that is fine on a single-user laptop, not on a shared host.
- A live process owned by *another user* makes `kill -0` fail with EPERM, so liveness also asks `ps -p`.
- **Residual race, documented not fixed:** clearing a *wedged* `LOCK.lk.reclaim` (a reclaimer that crashed mid-reclaim,
  >30 s old) is itself an unserialized remove-then-create. Triggering a double-grant needs a crash inside a ~1 ms
  window *and* two waiters racing the clear. Closing it needs an atomic compare-and-delete, which shell lacks.
- pid reuse after a crash can make a dead holder look alive (wedge) and a recycled pid can receive the `p_timeout`
  escalation `kill -KILL` — more likely on macOS, where pids top out near 99999. Low practical likelihood.

## Known limit — lock interop with the Rust CLI

Without `flock(1)` (stock macOS) the fallback is the noclobber-file lock above. It serializes
shell against shell only; it **cannot exclude a Rust `flock(2)` holder**. The one
site that shares a lock with the CLI is `post-tasks-validate.sh` (`tasks.json.lock`
sidecar). Before this change that site had no lock at all on macOS (`flock: command
not found`), so this is an improvement, not a regression — but it is a **stopgap**.
Mitigation: `brew install discoteq/discoteq/flock` (documented in the setup guide,
t-3376). Root-cause option, not built: a `brana lock` Rust subcommand sharing
`lock_tasks`'s lock implementation, so shell and CLI lock through one code path.
On the fallback path a holder that exits without releasing leaves `FILE.lk`
behind; the next acquirer reclaims it once the holder pid is dead.

## Enforcement — `lint-portability.sh` (validate Check 76)

`system/scripts/lint-portability.sh` fails on `flock`, `date -d/-I/%N`, `sha256sum`,
`md5sum`/`sha1sum`/`sha512sum`, `stat -c`, `sed -i` (any flag order; `-i.bak` is the portable form and passes),
`readlink -f`, `grep -P`, `touch -d`, `getent`, `nproc`, `timeout`, `realpath`,
`find -printf`, `tac`, `head -n -N`, and GNU-only BRE (`sed \+ \? \| \s \w`, `grep \| \+ \?`;
use `-E`) in tracked `*.sh` and
extensionless sh/bash-shebang files — **tests included** since t-3379 (skips `docs/`,
`portable.sh`, itself, and three files that quote GNU forms as data: `tests/lib/bsd-path.sh`,
`tests/hooks/test-portable.sh`, `tests/scripts/test-lint-portability.sh`; full-line comments
ignored). Per-line escape hatch: `# portable-ok: <reason>` on the line, or `# portable-ok-next: <reason>` on
the line above (for lines that cannot carry a comment, e.g. case arms or continuations). Two
structural rules besides the GNU forms: a shim after an exec wrapper (`env p_timeout`) and a file
that calls a `p_*` shim without sourcing `portable.sh` (a `cp` of it does not count; both bit
this effort). Per-line escape hatch (original wording): `# portable-ok:
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
absolute `/bin/bash` (none does today). The four scripts that carried a `#!/bin/bash` shebang (statusline,
the MCP wrapper, `update-mcp-servers.sh`, `init-project`) run *directly* and so bypassed the PATH-bash check;
they now use `#!/usr/bin/env bash`, and the lint fails on any `#!/bin/bash` / `#!/bin/sh` shebang.

## Shell snippets in markdown

Skill phase docs contain shell that agents run, often under **zsh**. They must not
source `portable.sh` (bash-only). Use inline forms: arithmetic instead of
`date -d '6 hours ago'`, `git stash list --format=%ct` instead of parsing dates,
`grep -E` instead of `grep -P`, `md5sum || md5 -q`, and a `date -d … || date -j -u -f …`
pair where a real date must be parsed (brana writes UTC).

## `p_date_d` is not a drop-in for `date -d`

It is a pure-shell parser with a deliberately narrow grammar (`now`, `@epoch`, ISO-8601 / git `%ci` incl. fraction and
`Z`/`±HH[:]MM`, `N unit[s] ago`). **Divergences from GNU, by design:** a naive timestamp is **UTC** (GNU: local time);
impossible calendar dates (`2026-02-31`, hour 24, `:60`) are rc 1 (as GNU); and these are **rc 1 where GNU accepts
them**: `yesterday`/`tomorrow`, `N month|year ago`, `3 days` (no "ago"), `+1 day`, `last monday`, a trailing `UTC`/`GMT`,
short `+00` offsets, RFC-2822 dates. "N days ago" is `now − N·86400` s, not calendar days (differs by an hour across a DST
change). Every converted call site was checked to feed in-grammar input (ISO written_at, git `%ci`, `YYYY-MM-DD`);
`tests/hooks/test-portable.sh` compares it with GNU `date` on that corpus (on a GNU host).

## Known unverified on real macOS

Things Linux testing cannot settle; the advisory `macos` CI job (and then a real Mac) must:

| Item | Why it is unverified | How CI/you will know |
|---|---|---|
| `\s`, `\b`, `\S` inside `grep -E` (~60 lines, including the `rm -rf` guard in `bash-risk-classifier.sh` and the branch/worktree gates) | believed supported by Apple's grep, not verified; a silent miss would let a guard pass | the hook guard tests (`tests/hooks`, `system/hooks/tests`) run on the macOS job — a deny-path test failing there is the signal |
| `rsync -a --delete --itemize-changes` (bootstrap) | macOS 15.4+ ships openrsync, whose option set may differ | the job prints `rsync --version` and warns if `bootstrap --check` reports a failed dry-run |
| `sort -V -C` in bootstrap's version gate for the assistant CLI | BSD sort support assumed | first run on a machine with that CLI installed |
| `osascript` desktop notification | untestable off macOS (the env/argv construction is unit-tested) | first reminder on a Mac |
| BSD `sed` and `\n` in a replacement | assumed to differ from GNU; deliberately **not** asserted either way in the lint tests | any `sed` that builds multi-line output, if one exists |
| `native-tls` needs no OpenSSL on Apple targets | inferred from the crate's target-gated deps | the job's `cargo build --release` |

## Out of scope

- **`grep -P`**: not shimmed. A PCRE emulation is a footgun. Guidance: rewrite
  with `grep -E` (or `awk`/`sed`) at the call site; where PCRE is genuinely
  required, `command -v ggrep` (Homebrew `grep`) is the documented escape.
  Done per call site in the t-3374 sweep (13 sites rewritten; old/new output
  differential-tested on 81 inputs).
- **systemd → launchd**: t-3375.
- **Second-tier GNU-isms**: done in t-3377 (`timeout`, `realpath`, `find -printf`, `date -I`/`%N`,
  `tac`, `head -n -N`, GNU-only BRE). Deliberately left, both already guarded and both scheduler
  concerns owned by t-3375: `/proc/meminfo` in `brana-scheduler-runner.sh` (on macOS the read fails
  and the memory guard is simply disabled) and `notify-send` in `brana-scheduler-notify.sh`
  (a `command -v` guard; macOS needs `osascript`).
- **Tests**: done in t-3379 (lint now scans them). Remaining md snippets `.claude/loop.md:75`
  (user-specific path) and `judge-sizing.md:174` (already carries a BSD fallback) are left as is.

## Testing

`tests/hooks/test-portable.sh` runs every shim twice: native PATH, and a
simulated-BSD PATH (`tests/lib/bsd-path.sh` builds a temp bin dir that
omits `flock`/`sha256sum`/`md5sum`/`realpath` and wraps `date`/`stat`/`sed`/
`readlink` to reject the GNU-only flag forms while accepting the BSD forms).
Real-macOS verification is a CI `macos-latest` job (later task) plus a manual
run on the Mac.
