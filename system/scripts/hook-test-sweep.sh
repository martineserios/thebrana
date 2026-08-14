#!/usr/bin/env bash
# hook-test-sweep.sh — discover and run test-*.sh suites in parallel (t-2622).
#
# Exists so validate.sh doesn't need a hardcoded per-file list (Check 66's
# pattern) that silently stops growing when a new test-*.sh lands under
# system/hooks/tests/. Any file matching test-*.sh in a swept directory runs
# automatically; adding a new suite there requires no validate.sh edit.
#
# Usage: hook-test-sweep.sh [dir-or-file ...]
#   No args -> default targets: system/hooks/tests/ (every test-*.sh, ~60
#   suites), plus the t-2501 oracle tests in tests/scripts/ (named
#   explicitly since they don't share a directory with the rest of the
#   sweep). Both are the concrete gap that motivated this script.
#
# Runs suites with bounded parallelism via HOOK_TEST_SWEEP_CONCURRENCY.
# Defaults to 1 (serial) — these ~60 pre-existing suites were written
# assuming exclusive execution and several collide when run concurrently
# (fixed session IDs, shared /tmp/brana-context-*, ~/.swarm/*.lock): a
# CONCURRENCY=8 run measured 3 suites flaking that pass cleanly serial
# (t-2622). Serial takes ~230s; opt into a higher CONCURRENCY only for
# subsets you've verified don't share temp-file/session-ID state.
#
# Prints one PASS/FAIL line per suite, then a summary. Exit 0 iff all ran
# green (or nothing matched — an empty sweep is not a failure).

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
CONCURRENCY="${HOOK_TEST_SWEEP_CONCURRENCY:-1}"

# Already run individually by validate.sh Check 65/66 (statusline suites,
# t-2467/t-2470) — excluded ONLY from the no-args default so the default
# sweep and those checks don't double-run the same 5 files every validate.sh
# invocation (challenger finding, t-2622). Passing an explicit directory/file
# arg bypasses this exclusion — the caller asked for exactly that.
DEFAULT_EXCLUDE=(
    test-statusline-epic.sh
    test-statusline-width.sh
    test-statusline-cache.sh
    test-session-score.sh
    test-statusline-integration.sh
)

if [ "$#" -gt 0 ]; then
    TARGETS=("$@")
    EXCLUDE=()
else
    TARGETS=(
        "$ROOT/system/hooks/tests"
        "$ROOT/tests/scripts/test-check-oracle-brana-drift.sh"
        "$ROOT/tests/scripts/test-ship-brana-oracle.sh"
    )
    EXCLUDE=("${DEFAULT_EXCLUDE[@]}")
fi

is_excluded() {
    local base="$1" e
    for e in "${EXCLUDE[@]:-}"; do
        [ "$base" = "$e" ] && return 0
    done
    return 1
}

FILES=()
for t in "${TARGETS[@]}"; do
    if [ -d "$t" ]; then
        while IFS= read -r -d '' f; do
            is_excluded "$(basename "$f")" && continue
            FILES+=("$f")
        done < <(find "$t" -maxdepth 1 -name 'test-*.sh' -print0 | sort -z)
    elif [ -f "$t" ]; then
        FILES+=("$t")
    fi
done

if [ "${#FILES[@]}" -eq 0 ]; then
    echo "hook-test-sweep: no test-*.sh suites found"
    exit 0
fi

RESULTS_DIR=$(mktemp -d)
trap 'rm -rf "$RESULTS_DIR"' EXIT

run_one() {
    local f="$1" idx="$2" out
    out="$RESULTS_DIR/$idx"
    if bash "$f" >"$out.log" 2>&1; then
        echo "0" > "$out.rc"
    else
        echo "1" > "$out.rc"
    fi
}

# Bounded parallelism: launch CONCURRENCY suites, wait for the batch, repeat.
# (No external job-control tool required — plain bash job slots.)
idx=0
running=0
for f in "${FILES[@]}"; do
    run_one "$f" "$idx" &
    idx=$((idx + 1))
    running=$((running + 1))
    if [ "$running" -ge "$CONCURRENCY" ]; then
        wait -n 2>/dev/null || wait
        running=$((running - 1))
    fi
done
wait

FAILED=()
i=0
for f in "${FILES[@]}"; do
    rc=$(cat "$RESULTS_DIR/$i.rc" 2>/dev/null || echo 1)
    base=$(basename "$f")
    if [ "$rc" -eq 0 ]; then
        echo "PASS: $base"
    else
        FAILED+=("$base")
        echo "FAIL: $base"
        tail -5 "$RESULTS_DIR/$i.log" 2>/dev/null | sed 's/^/  /'
    fi
    i=$((i + 1))
done

echo ""
echo "hook-test-sweep: ${#FILES[@]} suite(s), ${#FAILED[@]} failed"
[ "${#FAILED[@]}" -eq 0 ]
