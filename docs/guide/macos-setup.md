# Setting up brana on a Mac

> **Status.** The shell layer has been made portable and is covered by unit tests that simulate BSD
> userland on Linux. The **macOS CI job is advisory** (see [CI](#how-this-is-tested)): until it has
> been green on real macOS runners, treat anything here that says "expected" as unverified. If a
> step fails, that is a bug in brana, not in your setup — please open an issue with the output.

## Who this is for

A Mac used interactively — a work laptop that sleeps. **It does not run scheduled jobs:** the
scheduler is systemd-only by decision ([ADR-071 amendment](../architecture/decisions/ADR-071-scheduler-thin-layer-over-systemd.md)),
and unattended jobs stay on an always-on Linux host. Everything else (skills, hooks, rules, the
`brana` CLI, backlog, memory) is meant to work the same as on Linux.

## Prerequisites

| Requirement | Why | Install |
|---|---|---|
| Homebrew | everything below | <https://brew.sh> |
| **bash ≥ 4 first on `PATH`** | macOS ships bash 3.2. Hooks run as `bash <script>` and 9 scripts use bash-4 features (`mapfile`, `declare -A`). `bootstrap.sh` refuses to run without it. | `brew install bash` |
| `jq` | hooks, bootstrap, backlog helpers | `brew install jq` |
| `git` | already present (Xcode CLT) | `xcode-select --install` |
| Node.js ≥ 20 | ruflo (memory layer) | `brew install node`, then `npm install -g ruflo` (bootstrap finds it under nvm **or** on `PATH`) |
| Rust toolchain | build the `brana` CLI | `brew install rustup && rustup-init` |
| `uv` | Python helper scripts | `brew install uv` |
| `rsync` | bootstrap deploys hooks/scripts with it. macOS 15.4+ ships *openrsync*; if `./bootstrap.sh --check` reports "dry-run failed" the real deploy still works but `--check` cannot confirm convergence — `brew install rsync` fixes it | `brew install rsync` (only if needed) |
| Claude Code | the plugin host | see Claude Code docs |

**Put Homebrew first on `PATH`** — this is the single most common failure. On Apple Silicon:

```bash
echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >> ~/.zprofile   # then open a new terminal
bash --version | head -1    # must say 4.x or 5.x, NOT 3.2
which bash                  # must be /opt/homebrew/bin/bash
```

### Optional (recommended)

| Package | What it gives you |
|---|---|
| `brew install discoteq/discoteq/flock` | a real `flock(1)`. Without it brana falls back to `mkdir`-based locks, which serialize brana's own scripts against each other but **cannot exclude the Rust `brana` CLI** on `tasks.json`. Fine for one-session use; install `flock` if you run several sessions at once. |
| `brew install coreutils` | `gtimeout`. Optional: `p_timeout` already ends the whole process group on stock macOS (perl `setsid` watchdog, KILL escalation — t-3390); `gtimeout` only changes which tool enforces the ceiling. |

Neither is required — the fallbacks are what CI exercises. Installing them does not turn the portability tests red: `test-portable.sh` and `test-lock-stress.sh` run the fallback-lock assertions under a PATH that hides `flock` whatever is installed (t-3391), while the rest of `test-portable.sh` runs on your real PATH, so a brew `flock` also gets the real-flock path exercised.

## Install

```bash
git clone https://github.com/martineserios/thebrana.git ~/brana
cd ~/brana

./bootstrap.sh --check     # dry run: shows what it would change; also runs the platform preflight
./bootstrap.sh             # deploys the identity layer to ~/.claude/
```

Then build the CLI. No OpenSSL setup is needed on macOS (the Linux quick-start's `OPENSSL_*`
variables do not apply — `native-tls` uses the system Security framework there):

```bash
cd system/cli/rust
cargo build --release -p brana-cli
mkdir -p ~/.local/bin && ln -sf "$PWD/target/release/brana" ~/.local/bin/brana
```

Make sure `~/.local/bin` is on `PATH`, restart Claude Code, then:

```bash
brana doctor
```

## What is different on a Mac

| Area | Behaviour |
|---|---|
| **Scheduler** | None. `brana-scheduler status`/`validate` say so and exit 0; `deploy`/`enable`/`run` exit 1 with the same one-line reason. `brana ops enable/disable` edit `scheduler.json` but tell you nothing was scheduled. `bootstrap.sh` does not seed a `scheduler.json`. |
| **Close queue** | `/brana:close` queues entries for a nightly extraction job that lives on the always-on host. On the Mac nothing extracts them, so after 3 days session start says so and names the manual command: `./system/cron/close-extraction.sh` from the thebrana checkout (needs `agy`). Ignore it if you don't want async extraction on this machine. |
| **Locks** | mkdir-based unless `flock` is installed (see above). |
| **Timeouts** | `p_timeout` runs the command in its own session and kills the whole group at the ceiling, with or without `gtimeout` (t-3390). |
| **Dates** | Scripts use `p_date_d`/`p_epoch_fmt`; naive dates are treated as UTC. |

## Troubleshooting

| Symptom | Cause / fix |
|---|---|
| `ERROR: the 'bash' on PATH is version 3` | Homebrew bash is not first on `PATH`. See [Prerequisites](#prerequisites). |
| `p_timeout: command not found`, `p_date_d: command not found` | a script is running under `sh`/`zsh` or an old copy of `~/.claude/hooks` — re-run `./bootstrap.sh`. |
| Hooks seem to do nothing | `bash --version` inside the shell Claude Code launches, not your login shell. |
| `brana ops run <job>` says *no scheduler backend* | expected — see the table above. |
| Slow first CLI build | `cargo build --release` is ~10 minutes cold; it is cached afterwards. |
| `/brana:close` reports `master has diverged from origin/master` from the knowledge backup | both machines pushed memory snapshots. Do not rebase or force-push. In `brana-knowledge`: `git merge origin/master`, union each conflicted file with `./merge-snapshots.py <ours> <theirs> -o <file>`, commit, push (the message prints the exact recipe; ADR-095 §Amendment 2026-10-03). After a divergence resolved on the other machine, `git pull --ff-only` is all the Mac needs. |

## How this is tested

- `system/scripts/lint-portability.sh` (validate Check 76) fails on GNU-only forms in every shell
  script, tests included — see [macos-portable-shims](../architecture/features/macos-portable-shims.md).
- `tests/hooks/test-portable.sh` runs each shim on a native PATH **and** a simulated-BSD PATH.
- `system/scripts/run-test-suites.sh` (the CI loop, also what you run locally) gives every suite a
  throwaway `HOME` inside your real one and removes it afterwards, so no suite can write into your
  `~/.claude` — the first Mac run found test entries in the real `run-state/persist-failures.log`
  (t-3389). `TEST_SUITE_KEEP_HOME=1` passes your real `HOME` through when you need to diagnose a suite.
- The **`macos` job in `.github/workflows/ci.yml`** runs the shim tests, `bootstrap.sh --check`, builds
  the CLI and runs the shell test suites on a stock macOS runner (Homebrew bash + jq only — no `flock`,
  no coreutils, on purpose). It is **advisory** (`continue-on-error`, not a required check) until it has
  been green for a few runs; then it should be promoted in branch protection.
