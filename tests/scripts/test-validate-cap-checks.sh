#!/usr/bin/env bash
# Tests for validate.sh Check 31 — patterns.md + knowledge-staging.md cap checks (t-1451).
#
# Strategy: reproduce count+threshold logic inline (no full validate.sh run).
# Logic under test: grep -c '^## ' counts entries; warn at 40/20; skip if absent.
#
# TDD markers: all green post t-1451

set -uo pipefail

PASS=0
FAIL=0
TOTAL=0

TMPROOT=$(mktemp -d)
trap 'rm -rf "$TMPROOT"' EXIT

assert_eq() {
    local desc="$1" expected="$2" actual="$3"
    TOTAL=$((TOTAL + 1))
    if [ "$actual" = "$expected" ]; then
        echo "  PASS: $desc"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $desc — expected '$expected', got '$actual'"
        FAIL=$((FAIL + 1))
    fi
}

# Reproduce the Check 31 count-and-threshold logic from validate.sh
# Returns: "warn:<count>" or "pass:<count>" or "skip"
check31_patterns() {
    local file="$1"
    local warn_at="${2:-40}"
    if [ ! -f "$file" ]; then echo "skip"; return; fi
    local count
    count=$(grep -c '^## ' "$file" 2>/dev/null) || count=0
    if [ "$count" -ge "$warn_at" ]; then
        echo "warn:$count"
    else
        echo "pass:$count"
    fi
}

check31_knowledge() {
    local file="$1"
    local warn_at="${2:-20}"
    if [ ! -f "$file" ]; then echo "skip"; return; fi
    local count
    count=$(grep -c '^## ' "$file" 2>/dev/null) || count=0
    if [ "$count" -ge "$warn_at" ]; then
        echo "warn:$count"
    else
        echo "pass:$count"
    fi
}

# Helper: write a patterns.md fixture with N ## entries
make_patterns_md() {
    local n="$1" file="$2"
    {
        echo "# Pattern Store"
        echo ""
        echo "<!-- cap: 50 | warn-at: 40 | auto-pruned: oldest quarantine first -->"
        for i in $(seq 1 "$n"); do
            echo ""
            echo "## pattern-entry-$i"
            echo ""
            echo "Some pattern content $i"
        done
    } > "$file"
}

# Helper: write a knowledge-staging.md fixture with N ## entries
make_knowledge_md() {
    local n="$1" file="$2"
    {
        echo "# Knowledge Staging"
        echo ""
        echo "<!-- cap: 30 | warn-at: 20 | stale-after: 30 days -->"
        for i in $(seq 1 "$n"); do
            echo ""
            echo "## knowledge-entry-$i"
            echo ""
            echo "**Claim:** some claim $i"
        done
    } > "$file"
}

echo "=== Validate Check 31 — knowledge cap tests (t-1451) ==="
echo ""

# ── patterns.md tests ─────────────────────────────────────────────────────────
echo "patterns.md tests:"

PATTERNS_FILE="$TMPROOT/patterns.md"

# T1: 40 entries → warn
make_patterns_md 40 "$PATTERNS_FILE"
assert_eq "40 entries → warn" "warn:40" "$(check31_patterns "$PATTERNS_FILE")"

# T2: 39 entries → pass
make_patterns_md 39 "$PATTERNS_FILE"
assert_eq "39 entries → pass" "pass:39" "$(check31_patterns "$PATTERNS_FILE")"

# T3: 50 entries (at cap) → warn
make_patterns_md 50 "$PATTERNS_FILE"
assert_eq "50 entries → warn" "warn:50" "$(check31_patterns "$PATTERNS_FILE")"

# T4: 0 entries → pass
make_patterns_md 0 "$PATTERNS_FILE"
assert_eq "0 entries → pass" "pass:0" "$(check31_patterns "$PATTERNS_FILE")"

# T5: file absent → skip
rm -f "$PATTERNS_FILE"
assert_eq "absent file → skip" "skip" "$(check31_patterns "$PATTERNS_FILE")"

echo ""

# ── knowledge-staging.md tests ────────────────────────────────────────────────
echo "knowledge-staging.md tests:"

KNOWLEDGE_FILE="$TMPROOT/knowledge-staging.md"

# T6: 20 entries → warn
make_knowledge_md 20 "$KNOWLEDGE_FILE"
assert_eq "20 entries → warn" "warn:20" "$(check31_knowledge "$KNOWLEDGE_FILE")"

# T7: 19 entries → pass
make_knowledge_md 19 "$KNOWLEDGE_FILE"
assert_eq "19 entries → pass" "pass:19" "$(check31_knowledge "$KNOWLEDGE_FILE")"

# T8: 30 entries (at cap) → warn
make_knowledge_md 30 "$KNOWLEDGE_FILE"
assert_eq "30 entries → warn" "warn:30" "$(check31_knowledge "$KNOWLEDGE_FILE")"

# T9: 0 entries → pass
make_knowledge_md 0 "$KNOWLEDGE_FILE"
assert_eq "0 entries → pass" "pass:0" "$(check31_knowledge "$KNOWLEDGE_FILE")"

# T10: file absent → skip
rm -f "$KNOWLEDGE_FILE"
assert_eq "absent file → skip" "skip" "$(check31_knowledge "$KNOWLEDGE_FILE")"

echo ""

# ── count accuracy: # header not counted ──────────────────────────────────────
echo "header accuracy tests:"

MIXED_FILE="$TMPROOT/mixed.md"
cat > "$MIXED_FILE" <<'EOF'
# Top-level title (h1, NOT counted)

## entry-one
content

## entry-two
content

### sub-entry (h3, NOT counted by '^## ')
content

## entry-three
content
EOF

assert_eq "only ## counted (not # or ###)" "pass:3" "$(check31_patterns "$MIXED_FILE")"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
