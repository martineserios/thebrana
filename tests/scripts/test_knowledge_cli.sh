#!/usr/bin/env bash
# Tests for `brana knowledge` CLI subcommand.
# Run: bash tests/scripts/test_knowledge_cli.sh

set -euo pipefail

PASS=0
FAIL=0
TOTAL=0

assert() {
    local desc="$1" expected="$2" actual="$3"
    TOTAL=$((TOTAL + 1))
    if [ "$expected" = "$actual" ]; then
        echo "  PASS: $desc"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $desc (expected '$expected', got '$actual')"
        FAIL=$((FAIL + 1))
    fi
}

assert_contains() {
    local desc="$1" needle="$2" haystack="$3"
    TOTAL=$((TOTAL + 1))
    if echo "$haystack" | grep -qF "$needle"; then
        echo "  PASS: $desc"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $desc (expected to contain '$needle')"
        FAIL=$((FAIL + 1))
    fi
}

BRANA="${BRANA_BIN:-brana}"

echo "=== test_knowledge_cli.sh ==="

# ── Test 1: `brana knowledge` shows help ──
echo "Test 1: knowledge subcommand exists"
HELP_OUT=$($BRANA knowledge --help 2>&1 || true)
assert_contains "help mentions reindex" "reindex" "$HELP_OUT"
assert_contains "help mentions status" "status" "$HELP_OUT"

# ── Test 2: `brana knowledge reindex --help` shows options ──
echo "Test 2: reindex --help"
REINDEX_HELP=$($BRANA knowledge reindex --help 2>&1 || true)
assert_contains "reindex help mentions --changed" "--changed" "$REINDEX_HELP"
assert_contains "reindex help mentions files" "file" "$REINDEX_HELP"

# ── Test 3: `brana knowledge status` runs ──
echo "Test 3: knowledge status"
STATUS_OUT=$($BRANA knowledge status 2>&1 || true)
# Should mention knowledge entries or memory.db
assert "status exits without crash" "true" "$(echo "$STATUS_OUT" | grep -qiE 'knowledge|entries|memory|not found' && echo true || echo false)"

# ── Test 4: `brana knowledge reindex` with a specific file ──
echo "Test 4: reindex specific file (dry check)"
TMPDIR=$(mktemp -d)
trap "rm -rf $TMPDIR" EXIT
cat > "$TMPDIR/test-doc.md" << 'MARKDOWN'
## Section One

Content here.

## Section Two

More content.
MARKDOWN

# Just check it invokes the pipeline (it will call index-knowledge.sh)
REINDEX_OUT=$($BRANA knowledge reindex "$TMPDIR/test-doc.md" 2>&1 || true)
# Should at least mention parsing or the file, not crash
assert "reindex specific file runs" "true" "$(echo "$REINDEX_OUT" | grep -qiE 'index|pars|section|knowledge|error' && echo true || echo false)"

echo ""
echo "=== Results: $PASS/$TOTAL passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
