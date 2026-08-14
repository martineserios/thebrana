# Hook Test Sweep

`validate.sh` now runs every `test-*.sh` suite under `system/hooks/tests/`
(plus the t-2501 oracle tests), not just the 5 statusline suites it used
to hardcode. New test files there need no `validate.sh` edit to be covered.

## Quick Start

```bash
./validate.sh --check 69          # run just the sweep
./validate.sh                     # full validate.sh, sweep included
./validate.sh --fast              # full validate.sh, sweep skipped
```

## How It Works

`system/scripts/hook-test-sweep.sh` globs `test-*.sh` files and runs each
one with `bash`. It's serial by default — these suites weren't written to
run concurrently (some share fixed session IDs or `/tmp` state), so
parallelism is opt-in, not the default:

```bash
HOOK_TEST_SWEEP_CONCURRENCY=4 bash system/scripts/hook-test-sweep.sh
```

Only opt into concurrency for a subset of suites you've verified don't
share temp-file or session-ID state — running the full directory
concurrently without auditing it first will flake.

The serial sweep takes ~4 minutes, which is why `--fast` exists: it's for
quick local iteration, not for BUILD→CLOSE gates or ship pre-flight — those
must run the full check.

## Examples

Run the sweep directly, outside validate.sh entirely:

```bash
$ bash system/scripts/hook-test-sweep.sh
PASS: test-ac-lint.sh
PASS: test-bash-output-compress.sh
...
hook-test-sweep: 62 suite(s), 0 failed
```

Run it against just one file or directory:

```bash
$ bash system/scripts/hook-test-sweep.sh system/hooks/tests/test-tdd-gate.sh
PASS: test-tdd-gate.sh

hook-test-sweep: 1 suite(s), 0 failed
```
