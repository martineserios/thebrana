#!/usr/bin/env bash
# Tests for statusline-slow-cache.sh — the scheduled job that writes
# slow-changing signals (ruflo health, portfolio pulse, knowledge freshness)
# to a TSV cache file for statusline.sh to read.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SLOW_CACHE_SCRIPT="$SCRIPT_DIR/../../scripts/statusline-slow-cache.sh"
PASS=0
FAIL=0
TOTAL=0
TMPDIR=$(mktemp -d)

trap 'rm -rf "$TMPDIR"' EXIT

# ── Helpers ──────────────────────────────────────────────

assert_eq() {
    local desc="$1" expected="$2" actual="$3"
    TOTAL=$((TOTAL + 1))
    if [ "$expected" = "$actual" ]; then
        echo "  PASS: $desc"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $desc"
        echo "    expected: $expected"
        echo "    got:      $actual"
        FAIL=$((FAIL + 1))
    fi
}

assert_match() {
    local desc="$1" pattern="$2" actual="$3"
    TOTAL=$((TOTAL + 1))
    if [[ "$actual" =~ $pattern ]]; then
        echo "  PASS: $desc"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $desc"
        echo "    expected match: $pattern"
        echo "    got: $actual"
        FAIL=$((FAIL + 1))
    fi
}

assert_gt() {
    local desc="$1" val="$2" threshold="$3"
    TOTAL=$((TOTAL + 1))
    if (( val > threshold )); then
        echo "  PASS: $desc"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $desc"
        echo "    expected > $threshold, got: $val"
        FAIL=$((FAIL + 1))
    fi
}

assert_file_exists() {
    local desc="$1" file="$2"
    TOTAL=$((TOTAL + 1))
    if [ -f "$file" ]; then
        echo "  PASS: $desc"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $desc"
        echo "    file not found: $file"
        FAIL=$((FAIL + 1))
    fi
}

# ── Scenario 1: Output format ───────────────────────────
echo "=== Scenario 1: TSV output format ==="

# Run with custom output path
OUTFILE="$TMPDIR/slow-cache.tsv"
BRANA_SLOW_CACHE_FILE="$OUTFILE" bash "$SLOW_CACHE_SCRIPT" 2>/dev/null

assert_file_exists "cache file created" "$OUTFILE"

# Check TSV has exactly 6 tab-separated fields
FIELD_COUNT=$(head -1 "$OUTFILE" | awk -F'\t' '{print NF}')
assert_eq "TSV has 6 fields" "6" "$FIELD_COUNT"

# Parse fields
IFS=$'\t' read -r RUFLO_COUNT RUFLO_REINDEX_DATE RUFLO_STALE PORTFOLIO_PENDING KNOWLEDGE_DAYS TIMESTAMP < "$OUTFILE"

assert_match "ruflo_count is numeric" "^[0-9]+$" "$RUFLO_COUNT"
assert_match "ruflo_reindex_date is date or dash" "^([0-9]{4}-[0-9]{2}-[0-9]{2}|-)$" "$RUFLO_REINDEX_DATE"
assert_match "ruflo_stale is numeric" "^[0-9]+$" "$RUFLO_STALE"
assert_match "portfolio_pending is numeric" "^[0-9]+$" "$PORTFOLIO_PENDING"
assert_match "knowledge_days is numeric" "^[0-9]+$" "$KNOWLEDGE_DAYS"
assert_match "timestamp is ISO-ish" "^[0-9]{4}-[0-9]{2}-[0-9]{2}" "$TIMESTAMP"

# ── Scenario 2: Ruflo unavailable ────────────────────────
echo ""
echo "=== Scenario 2: Ruflo DB unavailable ==="

OUTFILE2="$TMPDIR/slow-cache-no-ruflo.tsv"
BRANA_SLOW_CACHE_FILE="$OUTFILE2" BRANA_RUFLO_DB="/nonexistent/memory.db" bash "$SLOW_CACHE_SCRIPT" 2>/dev/null
EXIT_CODE=$?

assert_eq "exits 0 even without ruflo" "0" "$EXIT_CODE"
assert_file_exists "cache file still created" "$OUTFILE2"

IFS=$'\t' read -r RC RD RS PP KD TS < "$OUTFILE2"
assert_eq "ruflo_count is 0 when unavailable" "0" "$RC"
assert_eq "ruflo_reindex_date is dash when unavailable" "-" "$RD"

# ── Scenario 3: No brana-knowledge repo ──────────────────
echo ""
echo "=== Scenario 3: No brana-knowledge repo ==="

OUTFILE3="$TMPDIR/slow-cache-no-knowledge.tsv"
BRANA_SLOW_CACHE_FILE="$OUTFILE3" BRANA_KNOWLEDGE_DIR="/nonexistent/brana-knowledge" bash "$SLOW_CACHE_SCRIPT" 2>/dev/null

IFS=$'\t' read -r RC RD RS PP KD TS < "$OUTFILE3"
assert_eq "knowledge_days is 0 when repo missing" "0" "$KD"

# ── Scenario 4: Live data (if available) ─────────────────
echo ""
echo "=== Scenario 4: Live data sanity ==="

if [ -f "$HOME/.swarm/memory.db" ]; then
    IFS=$'\t' read -r RUFLO_COUNT _ _ _ _ _ < "$TMPDIR/slow-cache.tsv"
    assert_gt "ruflo has entries on this machine" "$RUFLO_COUNT" 0
else
    echo "  SKIP: no ruflo DB on this machine"
fi

if [ -d "$HOME/enter_thebrana/brana-knowledge" ]; then
    IFS=$'\t' read -r _ _ _ _ KD _ < "$TMPDIR/slow-cache.tsv"
    # Knowledge should have been updated within last 30 days
    TOTAL=$((TOTAL + 1))
    if (( KD <= 30 )); then
        echo "  PASS: knowledge freshness within 30 days ($KD)"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: knowledge stale ($KD days)"
        FAIL=$((FAIL + 1))
    fi
else
    echo "  SKIP: no brana-knowledge on this machine"
fi

# ── Scenario 5: Idempotency ─────────────────────────────
echo ""
echo "=== Scenario 5: Idempotent reruns ==="

OUTFILE5="$TMPDIR/slow-cache-idem.tsv"
BRANA_SLOW_CACHE_FILE="$OUTFILE5" bash "$SLOW_CACHE_SCRIPT" 2>/dev/null
FIRST=$(cat "$OUTFILE5")
sleep 1
BRANA_SLOW_CACHE_FILE="$OUTFILE5" bash "$SLOW_CACHE_SCRIPT" 2>/dev/null
SECOND=$(cat "$OUTFILE5")

# Fields 1-5 should be identical (only timestamp differs)
FIRST_DATA=$(echo "$FIRST" | cut -f1-5)
SECOND_DATA=$(echo "$SECOND" | cut -f1-5)
assert_eq "data fields stable across reruns" "$FIRST_DATA" "$SECOND_DATA"

# ── Summary ──────────────────────────────────────────────
echo ""
echo "=== Results: $PASS/$TOTAL passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
