---
always-load: true
---
# Bash: Parallelism and Signals

CC cancels sibling Bash calls when one exits non-zero: guard independent parallel commands
with `; echo EXIT:$?` and check codes after; run dependent ones in one call with `&&`.

Don't trust a signal the shell didn't give you:

- **A piped exit code is the filter's.** `./v.sh | tail; echo $?` reads 0 on failure.
  Redirect: `./v.sh >/tmp/o 2>&1; echo $?; tail /tmp/o`. `$PIPESTATUS` is bash-only —
  this harness is **zsh** (`$pipestatus[1]`), where `PIPESTATUS` expands to empty, so that
  "fix" reports nothing at all.
- **Never `pgrep -f` in a wait loop.** The wrapper's argv holds your whole script, so every
  pattern — bracketed or not — self-matches and it spins forever. Use `kill -0 $PID`, or
  skip it: `run_in_background` already notifies.
- **Verify deploys by reading the deployed file**, not the installer's exit code.
