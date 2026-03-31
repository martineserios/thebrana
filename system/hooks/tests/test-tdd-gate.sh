#!/usr/bin/env bash
# Tests for tdd-gate.sh hook
# Simulates PreToolUse JSON input and checks pass/deny decisions.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$SCRIPT_DIR/../tdd-gate.sh"
PASS=0
FAIL=0
TMPDIR=$(mktemp -d)

trap 'rm -rf "$TMPDIR"' EXIT

# Setup: create a fake git repo with Cargo.toml
setup_crate() {
    local dir="$1"
    mkdir -p "$dir/src"
    git -C "$dir" init -q 2>/dev/null
    echo '[package]' > "$dir/Cargo.toml"
    echo 'fn main() {}' > "$dir/src/main.rs"
    git -C "$dir" add -A && git -C "$dir" commit -q -m "init" 2>/dev/null
}

# Helper: make JSON input
make_input() {
    local tool="$1" file="$2" cwd="$3"
    cat <<JSON
{"tool_name":"$tool","tool_input":{"file_path":"$file"},"cwd":"$cwd"}
JSON
}

# Helper: run hook and check result
assert_allows() {
    local desc="$1" input="$2"
    local result
    result=$(echo "$input" | BRANA_HOOK_PROFILE=standard bash "$HOOK" 2>/dev/null)
    if echo "$result" | jq -e '.continue == true' >/dev/null 2>&1; then
        echo "  PASS: $desc"
        ((PASS++))
    else
        echo "  FAIL: $desc — expected allow, got: $result"
        ((FAIL++))
    fi
}

assert_denies() {
    local desc="$1" input="$2"
    local result
    result=$(echo "$input" | BRANA_HOOK_PROFILE=standard bash "$HOOK" 2>/dev/null)
    if echo "$result" | jq -e '.hookSpecificOutput.permissionDecision == "deny"' >/dev/null 2>&1; then
        echo "  PASS: $desc"
        ((PASS++))
    else
        echo "  FAIL: $desc — expected deny, got: $result"
        ((FAIL++))
    fi
}

echo "TDD Gate Tests"
echo "=============="

# --- Test 1: Non-Rust file → allow ---
CRATE1="$TMPDIR/crate1"
setup_crate "$CRATE1"
git -C "$CRATE1" checkout -q -b feat/t-100-test
assert_allows "Non-Rust file passes through" \
    "$(make_input Edit "$CRATE1/README.md" "$CRATE1")"

# --- Test 2: Rust file on main → allow ---
CRATE2="$TMPDIR/crate2"
setup_crate "$CRATE2"
assert_allows "Rust file on main branch passes through" \
    "$(make_input Write "$CRATE2/src/main.rs" "$CRATE2")"

# --- Test 3: Rust impl file on feat/ with NO tests → deny ---
CRATE3="$TMPDIR/crate3"
setup_crate "$CRATE3"
git -C "$CRATE3" checkout -q -b feat/t-200-impl
assert_denies "Rust impl on feat/ with no tests → deny" \
    "$(make_input Edit "$CRATE3/src/lib.rs" "$CRATE3")"

# --- Test 4: Rust impl on feat/ WITH tests/ dir → allow ---
CRATE4="$TMPDIR/crate4"
setup_crate "$CRATE4"
git -C "$CRATE4" checkout -q -b feat/t-300-impl
mkdir -p "$CRATE4/tests"
echo '#[test] fn it_works() {}' > "$CRATE4/tests/integration.rs"
assert_allows "Rust impl on feat/ with tests/ dir → allow" \
    "$(make_input Edit "$CRATE4/src/lib.rs" "$CRATE4")"

# --- Test 5: Rust impl on feat/ WITH *_test.rs → allow ---
CRATE5="$TMPDIR/crate5"
setup_crate "$CRATE5"
git -C "$CRATE5" checkout -q -b feat/t-400-impl
echo '#[test] fn t() {}' > "$CRATE5/src/lib_test.rs"
assert_allows "Rust impl on feat/ with *_test.rs → allow" \
    "$(make_input Edit "$CRATE5/src/lib.rs" "$CRATE5")"

# --- Test 6: Editing a test file directly → allow ---
CRATE6="$TMPDIR/crate6"
setup_crate "$CRATE6"
git -C "$CRATE6" checkout -q -b feat/t-500-test
assert_allows "Editing a test file (*_test.rs) passes through" \
    "$(make_input Edit "$CRATE6/src/lib_test.rs" "$CRATE6")"

# --- Test 7: Rust impl on fix/ with no tests → deny ---
CRATE7="$TMPDIR/crate7"
setup_crate "$CRATE7"
git -C "$CRATE7" checkout -q -b fix/t-600-bugfix
assert_denies "Rust impl on fix/ with no tests → deny" \
    "$(make_input Write "$CRATE7/src/main.rs" "$CRATE7")"

# --- Test 8: Rust impl on feat/ WITH #[cfg(test)] → allow ---
CRATE8="$TMPDIR/crate8"
setup_crate "$CRATE8"
git -C "$CRATE8" checkout -q -b feat/t-700-impl
echo -e 'fn foo() {}\n#[cfg(test)]\nmod tests { #[test] fn t() {} }' > "$CRATE8/src/main.rs"
assert_allows "Rust impl on feat/ with #[cfg(test)] → allow" \
    "$(make_input Edit "$CRATE8/src/lib.rs" "$CRATE8")"

# --- Summary ---
echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
