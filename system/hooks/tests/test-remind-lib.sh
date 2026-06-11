#!/usr/bin/env bash
# Tests: system/hooks/lib/remind.sh — thin wrapper around `brana remind write` (t-1965, ADR-051).
# Verifies: args marshal through to the store; missing binary degrades to
# warn-on-stderr + exit 0 (hooks never block); no jq / JSON mutation in bash.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB="$SCRIPT_DIR/../lib/remind.sh"
PASS=0
FAIL=0
TOTAL=0
TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

REAL_BRANA="$SCRIPT_DIR/../../cli/rust/target/release/brana"
[ -x "$REAL_BRANA" ] || REAL_BRANA="$(command -v brana)"

check() {
    local desc="$1" expected="$2" actual="$3"
    TOTAL=$((TOTAL + 1))
    if [ "$expected" = "$actual" ]; then
        PASS=$((PASS + 1))
    else
        FAIL=$((FAIL + 1))
        echo "FAIL: $desc"
        echo "  expected: $expected"
        echo "  actual:   $actual"
    fi
}

# ── 1. lib exists and sources cleanly ─────────────────────────────────
if [ ! -f "$LIB" ]; then
    echo "FAIL: $LIB does not exist"
    exit 1
fi

# ── 2. write_reminder marshals args into the store ────────────────────
FAKE_HOME="$TMPDIR/home1"
mkdir -p "$FAKE_HOME"
out=$(
    HOME="$FAKE_HOME" BRANA="$REAL_BRANA" bash -c "
        source '$LIB'
        write_reminder --text 'edited hooks 3x — run validate' \
            --action './validate.sh' --priority high \
            --dedup-key hooks-validate --project thebrana --tags 'hooks,validate'
        echo \"exit:\$?\"
    " 2>&1
)
check "write_reminder exits 0" "exit:0" "$(echo "$out" | grep -o 'exit:0' | head -1)"

store="$FAKE_HOME/.claude/reminders.json"
check "store file created" "yes" "$([ -f "$store" ] && echo yes || echo no)"
check "text marshalled" "1" "$(grep -c 'edited hooks 3x' "$store" 2>/dev/null)"
check "action marshalled" "1" "$(grep -c './validate.sh' "$store" 2>/dev/null)"
check "priority marshalled" "1" "$(grep -c '"high"' "$store" 2>/dev/null)"
check "dedup_key marshalled" "1" "$(grep -c 'hooks-validate' "$store" 2>/dev/null)"
check "tags marshalled" "1" "$(grep -c '"validate"' "$store" 2>/dev/null)"

# ── 3. dedup: second identical write increments occurrences ──────────
HOME="$FAKE_HOME" BRANA="$REAL_BRANA" bash -c "
    source '$LIB'
    write_reminder --text 'edited hooks 3x — run validate' --dedup-key hooks-validate
" >/dev/null 2>&1
check "dedup increments occurrences" "1" "$(grep -c '"occurrences": 2' "$store" 2>/dev/null)"

# ── 4. text is required ───────────────────────────────────────────────
rc=0
HOME="$FAKE_HOME" BRANA="$REAL_BRANA" bash -c "
    source '$LIB'
    write_reminder --priority low
" >/dev/null 2>&1 || rc=$?
check "missing --text fails (caller bug, not env)" "no" "$([ "$rc" -eq 0 ] && echo yes || echo no)"

# ── 5. missing binary: warn to stderr, exit 0, hooks never block ─────
FAKE_HOME2="$TMPDIR/home2"
mkdir -p "$FAKE_HOME2"
stderr_file="$TMPDIR/stderr"
rc=99
HOME="$FAKE_HOME2" BRANA="$TMPDIR/no-such-binary" PATH="/usr/bin:/bin" bash -c "
    source '$LIB'
    write_reminder --text 'should not block'
" >/dev/null 2>"$stderr_file" && rc=0 || rc=$?
check "missing binary exits 0" "0" "$rc"
check "missing binary warns on stderr" "yes" "$([ -s "$stderr_file" ] && echo yes || echo no)"
check "missing binary writes no store" "no" "$([ -f "$FAKE_HOME2/.claude/reminders.json" ] && echo yes || echo no)"

# ── 6. no jq, no JSON mutation in the wrapper itself ──────────────────
check "wrapper contains no jq calls" "0" "$(grep -c '\bjq\b' "$LIB")"

echo ""
echo "test-remind-lib: $PASS/$TOTAL passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
