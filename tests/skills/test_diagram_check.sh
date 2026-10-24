#!/usr/bin/env bash
# Tests for t-4: system/skills/terminal-diagrams/check.py — the alignment checker.
# Each case feeds one diagram on stdin and asserts the exit code (0 = clean, 1 = issues).
# Run: bash tests/skills/test_diagram_check.sh

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
CHECK="$REPO_ROOT/system/skills/terminal-diagrams/check.py"

PASS=0
FAIL=0
TOTAL=0

# expect <desc> <expected-exit> <diagram>
expect() {
    local desc="$1" expected="$2" diagram="$3" actual
    TOTAL=$((TOTAL + 1))
    printf '%s\n' "$diagram" | python3 "$CHECK" - >/dev/null 2>&1
    actual=$?
    if [ "$actual" = "$expected" ]; then
        echo "  PASS: $desc"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $desc (expected exit $expected, got $actual)"
        FAIL=$((FAIL + 1))
    fi
}

echo "=== test_diagram_check.sh ==="

echo "Test 1: well-formed diagrams pass"
expect "aligned box" 0 \
'┌──────┐
│ LOAD │
└──────┘'
expect "flow with arrows" 0 \
'┌──────┐     ┌───────┐
│ LOAD │ ──► │ BUILD │
└──────┘     └───────┘'
expect "table with junctions" 0 \
'┌─────┬─────┐
│ a   │ b   │
├─────┼─────┤
│ 1   │ 2   │
└─────┴─────┘'
expect "tree hanging from a label" 0 \
'root
├── a
│   └── a1
└── b'
expect "box with outgoing line" 0 \
'┌──────┐
│ in   │
└──┬───┘
   ▼
┌──┴───┐
│ out  │
└──────┘'
expect "plain prose block" 0 'just text, no boxes'
expect "fork bracket ending in arrows is not a box" 0 \
'      │
   ┌──┴──┐
yes│     │no
   ▼     ▼'

expect "bracket whose legs land on child boxes" 0 \
'    ┌─────┐
    │ top │
    └──┬──┘
 ┌─────┴─────┐
┌┴──┐       ┌┴──┐
│ a │       │ b │
└───┘       └───┘'

echo "Test 2: misalignment is caught"
expect "right border drifts one column" 1 \
'┌─────────┐
│  LOAD    │
└─────────┘'
expect "bottom corner shifted" 1 \
'┌──────┐
│ LOAD │
└─────┘'
expect "junction with nothing below" 1 \
'┌──────┐
│ in   │
└──┬───┘

  next'
expect "box never closed" 1 \
'┌──────┐
│ LOAD │'

echo "Test 3: unsafe glyphs are caught"
expect "emoji" 1 '┌────┐
│ 🚀 │
└────┘'
expect "CJK wide char" 1 'label 漢字'
expect "variation selector" 1 'ok ✔️'
expect "tab character" 1 "a	b"
expect "diagonal box-drawing" 1 'a ╱ b'

echo "Test 4: width limit"
expect "101 columns fails by default" 1 "$(printf 'x%.0s' $(seq 1 101))"
expect "100 columns passes" 0 "$(printf 'x%.0s' $(seq 1 100))"

echo "Test 5: markdown mode checks fenced blocks only"
TMP="$(mktemp)"
printf '%s\n' 'Prose with a tab	is fine outside fences.' '```' '┌──┐' '│ab│' '└──┘' '```' > "$TMP"
TOTAL=$((TOTAL + 1))
if python3 "$CHECK" "$TMP" >/dev/null 2>&1; then echo "  PASS: clean fenced block"; PASS=$((PASS + 1)); else echo "  FAIL: clean fenced block"; FAIL=$((FAIL + 1)); fi
printf '%s\n' '```' '┌──┐' '│abc│' '└──┘' '```' > "$TMP"
TOTAL=$((TOTAL + 1))
OUT="$(python3 "$CHECK" "$TMP" 2>&1)"
if [ $? -eq 1 ] && [[ "$OUT" == *":3:"* ]]; then echo "  PASS: broken fenced block reported with file line"; PASS=$((PASS + 1)); else echo "  FAIL: broken fenced block reported with file line ($OUT)"; FAIL=$((FAIL + 1)); fi
printf '%s\n' '```text nocheck' '│abc│ ─ (legend)' '```' > "$TMP"
TOTAL=$((TOTAL + 1))
if python3 "$CHECK" "$TMP" >/dev/null 2>&1; then echo "  PASS: nocheck block skipped"; PASS=$((PASS + 1)); else echo "  FAIL: nocheck block skipped"; FAIL=$((FAIL + 1)); fi
rm -f "$TMP"

echo ""
echo "=== Results: $PASS/$TOTAL passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
