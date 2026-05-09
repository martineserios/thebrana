#!/usr/bin/env bash
# Tests for sync-notebooklm.py
# Validates hash-based sync state tracking, staging output, and action manifest.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SCRIPT_DIR/../sync-notebooklm.py"
PASS=0
FAIL=0
TOTAL=0
TMPDIR_TEST=$(mktemp -d)
trap 'rm -rf "$TMPDIR_TEST"' EXIT

run_sync() {
    local dims_dir="$1"
    local state_file="$2"
    local output_dir="$3"
    local extra_args="${4:-}"
    uv run python "$SCRIPT" \
        --dims-dir "$dims_dir" \
        --state-file "$state_file" \
        --output-dir "$output_dir" \
        $extra_args 2>/dev/null
}

assert_exit0() {
    local desc="$1"; shift
    TOTAL=$((TOTAL + 1))
    if "$@" >/dev/null 2>&1; then
        echo "  PASS: $desc"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $desc"
        FAIL=$((FAIL + 1))
    fi
}

assert_contains() {
    local desc="$1"; shift
    local pattern="$1"; shift
    TOTAL=$((TOTAL + 1))
    local output
    output=$("$@" 2>/dev/null)
    if echo "$output" | grep -qi "$pattern"; then
        echo "  PASS: $desc"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $desc"
        echo "    expected output to contain: $pattern"
        echo "    got: $output"
        FAIL=$((FAIL + 1))
    fi
}

assert_file_exists() {
    local desc="$1"
    local path="$2"
    TOTAL=$((TOTAL + 1))
    if [ -f "$path" ]; then
        echo "  PASS: $desc"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $desc — not found: $path"
        FAIL=$((FAIL + 1))
    fi
}

assert_file_absent() {
    local desc="$1"
    local path="$2"
    TOTAL=$((TOTAL + 1))
    if [ ! -f "$path" ]; then
        echo "  PASS: $desc"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $desc — unexpectedly found: $path"
        FAIL=$((FAIL + 1))
    fi
}

make_dims() {
    local dir="$1"; shift
    mkdir -p "$dir"
    for name in "$@"; do
        echo "# $name" > "$dir/$name.md"
        echo "Content of $name." >> "$dir/$name.md"
    done
}

echo "NotebookLM Sync Tests"
echo "====================="

# ── 1. Script is executable and reachable ───────────────

echo ""
echo "--- Basic invocation ---"

assert_exit0 "Script runs with --help or --version" \
    uv run python "$SCRIPT" --help

# ── 2. New docs → staged + manifest written ─────────────

echo ""
echo "--- New docs staged on first run ---"

DIMS1="$TMPDIR_TEST/dims1"
STATE1="$TMPDIR_TEST/state1.json"
OUT1="$TMPDIR_TEST/out1"
make_dims "$DIMS1" "01-alpha" "02-beta"

run_sync "$DIMS1" "$STATE1" "$OUT1" >/dev/null

assert_file_exists "New doc 01-alpha.md staged in output dir" \
    "$OUT1/01-alpha.md"

assert_file_exists "New doc 02-beta.md staged in output dir" \
    "$OUT1/02-beta.md"

assert_file_exists "State file written after first run" \
    "$STATE1"

TOTAL=$((TOTAL + 1))
if jq -e '.["01-alpha.md"]' "$STATE1" >/dev/null 2>&1; then
    echo "  PASS: State file tracks 01-alpha.md"
    PASS=$((PASS + 1))
else
    echo "  FAIL: State file missing 01-alpha.md entry"
    cat "$STATE1" 2>/dev/null || true
    FAIL=$((FAIL + 1))
fi

# ── 3. Unchanged docs → not re-staged ───────────────────

echo ""
echo "--- Unchanged docs skipped on re-run ---"

OUT1B="$TMPDIR_TEST/out1b"
run_sync "$DIMS1" "$STATE1" "$OUT1B" >/dev/null

assert_file_absent "Unchanged 01-alpha.md not re-staged" \
    "$OUT1B/01-alpha.md"

assert_file_absent "Unchanged 02-beta.md not re-staged" \
    "$OUT1B/02-beta.md"

# ── 4. Changed doc → re-staged ──────────────────────────

echo ""
echo "--- Changed doc re-staged ---"

echo "Updated content of alpha." >> "$DIMS1/01-alpha.md"
OUT1C="$TMPDIR_TEST/out1c"
run_sync "$DIMS1" "$STATE1" "$OUT1C" >/dev/null

assert_file_exists "Changed 01-alpha.md re-staged after content change" \
    "$OUT1C/01-alpha.md"

assert_file_absent "Unchanged 02-beta.md not re-staged in same run" \
    "$OUT1C/02-beta.md"

# ── 5. Removed doc → flagged in output ──────────────────

echo ""
echo "--- Removed doc flagged ---"

rm "$DIMS1/02-beta.md"
OUT1D="$TMPDIR_TEST/out1d"
REMOVED_OUTPUT=$(run_sync "$DIMS1" "$STATE1" "$OUT1D" 2>/dev/null)

TOTAL=$((TOTAL + 1))
if echo "$REMOVED_OUTPUT" | grep -qi "delete\|remov\|02-beta"; then
    echo "  PASS: Removed doc 02-beta.md flagged in output"
    PASS=$((PASS + 1))
else
    echo "  FAIL: Removed doc 02-beta.md not mentioned in output"
    echo "    got: $REMOVED_OUTPUT"
    FAIL=$((FAIL + 1))
fi

TOTAL=$((TOTAL + 1))
if ! jq -e '.["02-beta.md"]' "$STATE1" >/dev/null 2>&1; then
    echo "  PASS: Removed doc removed from state"
    PASS=$((PASS + 1))
else
    echo "  FAIL: Removed doc still in state after deletion"
    FAIL=$((FAIL + 1))
fi

# ── 6. Action summary output ─────────────────────────────

echo ""
echo "--- Action summary output ---"

DIMS2="$TMPDIR_TEST/dims2"
STATE2="$TMPDIR_TEST/state2.json"
OUT2="$TMPDIR_TEST/out2"
make_dims "$DIMS2" "10-gamma" "11-delta"

SUMMARY=$(run_sync "$DIMS2" "$STATE2" "$OUT2" 2>/dev/null)

TOTAL=$((TOTAL + 1))
if echo "$SUMMARY" | grep -qiE "add|new|upload"; then
    echo "  PASS: Summary mentions new/upload action"
    PASS=$((PASS + 1))
else
    echo "  FAIL: Summary missing new/upload action"
    echo "    got: $SUMMARY"
    FAIL=$((FAIL + 1))
fi

# ── 7. Dry-run does not write files ─────────────────────

echo ""
echo "--- Dry-run mode ---"

DIMS3="$TMPDIR_TEST/dims3"
STATE3="$TMPDIR_TEST/state3.json"
OUT3="$TMPDIR_TEST/out3"
make_dims "$DIMS3" "20-epsilon"

run_sync "$DIMS3" "$STATE3" "$OUT3" "--dry-run" >/dev/null

assert_file_absent "Dry-run does not write staged file" \
    "$OUT3/20-epsilon.md"

assert_file_absent "Dry-run does not write state file" \
    "$STATE3"

# ── 8. Non-markdown files ignored ───────────────────────

echo ""
echo "--- Non-markdown files ignored ---"

DIMS4="$TMPDIR_TEST/dims4"
STATE4="$TMPDIR_TEST/state4.json"
OUT4="$TMPDIR_TEST/out4"
make_dims "$DIMS4" "30-zeta"
touch "$DIMS4/not-a-doc.txt"
touch "$DIMS4/.hidden.md"

run_sync "$DIMS4" "$STATE4" "$OUT4" >/dev/null

assert_file_absent "Non-.md file ignored" \
    "$OUT4/not-a-doc.txt"

assert_file_absent "Hidden .md file ignored" \
    "$OUT4/.hidden.md"

assert_file_exists "Regular .md file staged" \
    "$OUT4/30-zeta.md"

# ── Summary ─────────────────────────────────────────────
echo ""
echo "$PASS/$TOTAL passed"
[ "$FAIL" -eq 0 ] || exit 1
