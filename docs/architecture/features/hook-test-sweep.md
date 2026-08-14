# Feature: Hook Test Sweep (validate.sh Check 70)

**Date:** 2026-08-03
**Status:** shipped
**Task:** t-2622

## Goal

`validate.sh` had only two references to `system/hooks/tests/` (Checks 65/66),
a hardcoded 5-file allowlist for statusline suites — not a directory sweep.
The other ~55 suites in that directory, including `test-red-verification.sh`
and t-2501's oracle drift/ship tests in `tests/scripts/`, were correctly
written but never run automatically by `validate.sh` or any `Makefile`
target. Found during t-2602's challenger review as a non-blocking gap.

Running the full sweep for the first time surfaced four suites that were
red for reasons unrelated to their subject under test — stale fixtures and
a real bug in `session-start.sh`, not the hook logic they were written to
exercise. See Design Decisions.

## Design Decisions

**Directory sweep, not a hardcoded per-file list.** Check 66's hardcoded
list is exactly the pattern that let this gap form silently — a new test
file lands in `system/hooks/tests/` and nothing runs it unless someone
remembers to add a `validate.sh` line. `system/scripts/hook-test-sweep.sh`
discovers `test-*.sh` files by glob instead, so new suites need no
`validate.sh` edit.

**Serial by default, not parallel.** A `CONCURRENCY=8` run measured 3 of 62
suites flaking (that pass cleanly serial) from cross-suite interference —
fixed session IDs (`sess-proj`) and shared paths under `/tmp/` and
`~/.swarm/` that different suites collided on when run concurrently. These
~60 suites were written assuming exclusive execution; auditing every one
for parallel-safety was out of scope. Speed is opt-in via
`HOOK_TEST_SWEEP_CONCURRENCY`, not the default — correctness over speed.

**`--fast` flag on validate.sh, not a separate check-skip mechanism.** The
sweep's serial runtime (~4 min) roughly triples `validate.sh`'s total time,
and `validate.sh` is invoked by `/brana:build`'s BUILD→CLOSE gate and
`/brana:ship`'s pre-flight — not just standalone. `--fast` skips Check 70
specifically for local iteration; full gates must run without it.

**Four pre-existing bugs found and fixed while unblocking the sweep** (all
unrelated to each other, all masked by nothing running these suites):

1. `test-tdd-gate.sh` / `test-e2e-hooks.sh` — fixture git repos lived under
   a bare `mktemp -d` (resolves to `/tmp/...`), and `tdd-gate.sh`'s
   `/tmp/*` early-exit (added 2026-06-04, after these tests were last
   touched) made every "should deny" fixture pass through instead. Fixed
   by switching to the `${HOME}/.brana-test-XXXXXX` convention already
   used elsewhere in the repo.
2. `test-close-extraction.sh` — the fake `agy`'s default `--version`
   response (1.0.8) predated `close-extraction.sh`'s `AGY_MIN_VERSION`
   floor being raised to 1.0.10 (1621b484, 2026-06-19); every call that
   didn't override the version was silently rejected by the guard.
3. `test-session-start.sh` — a **real bug**, not a stale fixture:
   `session-start.sh`'s three background jobs (Job 1a/1b/1c) forked via
   `( ... ) &` without redirecting stdout/stderr. A straggler that
   outlived the PIDS wait-loop's own deadline (observed: an
   `npm exec`-spawned node process under the `npx ruflo` fallback in
   `cf-env.sh`) kept the invoking pipe's write end open indefinitely —
   any caller capturing the hook's output via `$(...)` would hang forever,
   even though the hook process itself had already exited cleanly. Fixed
   with explicit `>/dev/null 2>&1` redirects, `timeout -k` kill escalation,
   and switching the test's own capture from a pipe to a temp file so it
   can never wait on a pipe's EOF regardless of what else leaks.
4. `test-session-start.sh`'s own `SAFE_PATH` — a directory-based PATH
   (`/usr/bin:/bin:...`) doesn't isolate `npx` if `git`/`jq` happen to
   share a directory with it, which they do on this machine. Replaced
   with an explicit allowlist bin/ of symlinks to only the tools the
   suite needs.

## Code Flow

- `system/scripts/hook-test-sweep.sh` — discovers `test-*.sh` files under
  given directories (or explicit file args), runs each with `bash`, prints
  `PASS`/`FAIL` per suite plus a summary line, exits 0 iff all ran green
  (or nothing matched).
  - No args → default targets: `system/hooks/tests/` (all `test-*.sh`) +
    `tests/scripts/test-check-oracle-brana-drift.sh` +
    `tests/scripts/test-ship-brana-oracle.sh` (the concrete gap that
    motivated this).
  - `HOOK_TEST_SWEEP_CONCURRENCY` (default `1`) bounds parallelism via
    plain bash job slots — no external tool dependency.
- `validate.sh` Check 70 calls it with no args, prints its summary line
  through `pass`/`fail`, skips with a `warn` under `--fast`.

## Key Files

| File | Role |
|------|------|
| `system/scripts/hook-test-sweep.sh` | Discovery + execution engine |
| `system/scripts/tests/test-hook-test-sweep.sh` | Tests for the sweep script itself |
| `validate.sh` (Check 70, `--fast` flag) | Wiring into the validation gate |
| `system/hooks/session-start.sh` | Real bug fix (background-job stdout leak) |
| `system/hooks/tests/test-{tdd-gate,e2e-hooks,session-start,close-extraction}.sh` | Stale-fixture fixes |

## Testing

- `bash system/scripts/tests/test-hook-test-sweep.sh` — 9 cases covering
  discovery, pass/fail aggregation, explicit-file args, non-`test-*.sh`
  files ignored, empty-directory handling, and the real default targets.
- `./validate.sh --check 69` — runs the full sweep standalone.
- `./validate.sh --fast` — confirms Check 70 is skipped (warn, not fail).

## Known Limitations

- `test-session-start-hybrid-recall.sh` occasionally flakes inside the full
  sweep (not introduced by this change): it exercises `session-start.sh`'s
  real `timeout -k 1 3` brana-recall job, which can exceed 3s under heavy
  sandbox load. Always passes in isolation.
- Only the 4 suites blocking the sweep's initial green run were fixed.
  Other suites may have their own latent bugs not yet surfaced.
