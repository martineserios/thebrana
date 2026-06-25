#!/usr/bin/env bash
# Tests for learn-sweep.py — the daily-summary learning cursor.
# Hermetic: points the script at a temp sessions dir via LEARN_SWEEP_SESSIONS.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SWEEP="$SCRIPT_DIR/../learn-sweep.py"
PASS=0
FAIL=0
TOTAL=0
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

export LEARN_SWEEP_SESSIONS="$TMP"

run() { python3 "$SWEEP" "$@"; }

check() {
    local label="$1" expected="$2" actual="$3"
    TOTAL=$((TOTAL + 1))
    if [ "$actual" = "$expected" ]; then
        PASS=$((PASS + 1)); echo "  PASS: $label"
    else
        FAIL=$((FAIL + 1)); echo "  FAIL: $label"; echo "    expected: $expected"; echo "    actual:   $actual"
    fi
}

mk_summary() {  # name, qid...
    local f="$TMP/daily-summary-$1.md"; shift
    : > "$f"
    for q in "$@"; do
        printf '## proj branch (aa..bb) — entry %s\n- [pattern/SMALL] note %s\n\n' "$q" "$q" >> "$f"
    done
}

echo "== learn-sweep tests =="

# 1. fresh state: two entries both surface
mk_summary 2026-06-01 q-aaaa1111 q-bbbb2222
check "fresh: count 2/2" "2 unprocessed / 2 total" "$(run --count)"

# 2. default lists the unprocessed q-ids
out=$(run | grep -c 'entry q-')
check "fresh: default lists 2 entries" "2" "$out"

# 3. --commit marks both routed; then 0 unprocessed
run --commit > /dev/null
check "after commit: 0/2" "0 unprocessed / 2 total" "$(run --count)"
check "after commit: default clean" "OK — 0 unprocessed (2 total, all routed)." "$(run)"

# 4. a NEW entry appears -> only the delta surfaces (O(new))
mk_summary 2026-06-02 q-cccc3333
check "new entry: 1/3" "1 unprocessed / 3 total" "$(run --count)"
new=$(run | grep 'entry q-' | grep -c 'q-cccc3333')
check "new entry: surfaces only the new q-id" "1" "$new"
old=$(run | grep 'entry q-' | grep -c 'q-aaaa1111')
check "new entry: does NOT re-surface routed q-id" "0" "$old"

# 5. --seed on a fresh cursor marks everything processed (baseline)
rm -rf "$TMP"; mkdir -p "$TMP"
mk_summary 2026-06-03 q-dddd4444 q-eeee5555
run --seed > /dev/null
check "seed: baseline 0/2" "0 unprocessed / 2 total" "$(run --count)"

# --- boundary probes ---

# 6. no summaries at all
rm -rf "$TMP"; mkdir -p "$TMP"
check "boundary: empty dir 0/0" "0 unprocessed / 0 total" "$(run --count)"
check "boundary: empty dir default" "OK — 0 unprocessed (0 total, all routed)." "$(run)"

# 7. cursor comment lines and duplicate q-ids across summaries are ignored/deduped
mk_summary 2026-06-04 q-ffff6666
mk_summary 2026-06-05 q-ffff6666   # same q-id in two files -> counts once
printf '# a comment line\n\n' >> "$TMP/.learned-cursor"
check "boundary: dup q-id counts once" "1 unprocessed / 1 total" "$(run --count)"

echo "== $PASS/$TOTAL passed, $FAIL failed =="
[ "$FAIL" -eq 0 ]
