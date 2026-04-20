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

# --- Test 2: Rust file on main with no tests → deny (branch filter removed per ADR-031) ---
CRATE2="$TMPDIR/crate2"
setup_crate "$CRATE2"
assert_denies "Rust file on main with no tests → deny" \
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

# === Python tests ===

# Helper: setup a Python project
setup_python() {
    local dir="$1"
    mkdir -p "$dir/src"
    git -C "$dir" init -q 2>/dev/null
    echo '[project]' > "$dir/pyproject.toml"
    echo 'def main(): pass' > "$dir/src/app.py"
    git -C "$dir" add -A && git -C "$dir" commit -q -m "init" 2>/dev/null
}

# --- Test 9: Python impl on feat/ with NO tests → deny ---
PY1="$TMPDIR/py1"
setup_python "$PY1"
git -C "$PY1" checkout -q -b feat/t-800-py
assert_denies "Python impl on feat/ with no tests → deny" \
    "$(make_input Edit "$PY1/src/app.py" "$PY1")"

# --- Test 10: Python impl on feat/ WITH test file → allow ---
PY2="$TMPDIR/py2"
setup_python "$PY2"
git -C "$PY2" checkout -q -b feat/t-801-py
echo 'def test_main(): pass' > "$PY2/src/test_app.py"
assert_allows "Python impl on feat/ with test_*.py → allow" \
    "$(make_input Edit "$PY2/src/app.py" "$PY2")"

# --- Test 11: Python test file itself → allow ---
PY3="$TMPDIR/py3"
setup_python "$PY3"
git -C "$PY3" checkout -q -b feat/t-802-py
assert_allows "Writing a Python test file passes through" \
    "$(make_input Write "$PY3/src/test_app.py" "$PY3")"

# === JS/TS tests ===

setup_js() {
    local dir="$1"
    mkdir -p "$dir/src"
    git -C "$dir" init -q 2>/dev/null
    echo '{"name":"test"}' > "$dir/package.json"
    echo 'export default {}' > "$dir/src/index.ts"
    git -C "$dir" add -A && git -C "$dir" commit -q -m "init" 2>/dev/null
}

# --- Test 12: TS impl on feat/ with NO tests → deny ---
JS1="$TMPDIR/js1"
setup_js "$JS1"
git -C "$JS1" checkout -q -b feat/t-900-ts
assert_denies "TS impl on feat/ with no tests → deny" \
    "$(make_input Edit "$JS1/src/index.ts" "$JS1")"

# --- Test 13: TS impl on feat/ WITH .test.ts → allow ---
JS2="$TMPDIR/js2"
setup_js "$JS2"
git -C "$JS2" checkout -q -b feat/t-901-ts
echo 'test("works", () => {})' > "$JS2/src/index.test.ts"
assert_allows "TS impl on feat/ with .test.ts → allow" \
    "$(make_input Edit "$JS2/src/index.ts" "$JS2")"

# --- Test 14: Writing a .spec.js file → allow ---
JS3="$TMPDIR/js3"
setup_js "$JS3"
git -C "$JS3" checkout -q -b feat/t-902-js
assert_allows "Writing a .spec.js test file passes through" \
    "$(make_input Write "$JS3/src/app.spec.js" "$JS3")"

# === Shell tests ===

setup_shell() {
    local dir="$1"
    mkdir -p "$dir"
    git -C "$dir" init -q 2>/dev/null
    echo '#!/bin/bash' > "$dir/deploy.sh"
    git -C "$dir" add -A && git -C "$dir" commit -q -m "init" 2>/dev/null
}

# --- Test 15: Shell script on feat/ with NO tests → deny ---
SH1="$TMPDIR/sh1"
setup_shell "$SH1"
git -C "$SH1" checkout -q -b feat/t-1000-sh
assert_denies "Shell script on feat/ with no tests → deny" \
    "$(make_input Edit "$SH1/deploy.sh" "$SH1")"

# --- Test 16: Shell script on feat/ WITH test file → allow ---
SH2="$TMPDIR/sh2"
setup_shell "$SH2"
git -C "$SH2" checkout -q -b feat/t-1001-sh
echo '#!/bin/bash' > "$SH2/test-deploy.sh"
assert_allows "Shell script on feat/ with test-*.sh → allow" \
    "$(make_input Edit "$SH2/deploy.sh" "$SH2")"

# === Go tests ===

setup_go() {
    local dir="$1"
    mkdir -p "$dir"
    git -C "$dir" init -q 2>/dev/null
    echo 'module example.com/test' > "$dir/go.mod"
    echo 'package main' > "$dir/main.go"
    git -C "$dir" add -A && git -C "$dir" commit -q -m "init" 2>/dev/null
}

# --- Test 17: Go impl on feat/ with NO tests → deny ---
GO1="$TMPDIR/go1"
setup_go "$GO1"
git -C "$GO1" checkout -q -b feat/t-1100-go
assert_denies "Go impl on feat/ with no tests → deny" \
    "$(make_input Edit "$GO1/main.go" "$GO1")"

# --- Test 18: Go impl on feat/ WITH _test.go → allow ---
GO2="$TMPDIR/go2"
setup_go "$GO2"
git -C "$GO2" checkout -q -b feat/t-1101-go
echo 'package main' > "$GO2/main_test.go"
assert_allows "Go impl on feat/ with _test.go → allow" \
    "$(make_input Edit "$GO2/main.go" "$GO2")"

# --- Test 19: .md files early exit — no TDD gate, no find commands ---
MD_DIR="$TMPDIR/md-project"
setup_crate "$MD_DIR"  # Rust project with no tests (would deny .rs files)
git -C "$MD_DIR" checkout -q -b feat/t-1293-docs
assert_allows ".md file in no-test project passes through immediately" \
    "$(make_input Write "$MD_DIR/docs/ARCHITECTURE.md" "$MD_DIR")"
assert_allows ".md in repo root passes through" \
    "$(make_input Write "$MD_DIR/README.md" "$MD_DIR")"
assert_allows "CLAUDE.md passes through" \
    "$(make_input Edit "$MD_DIR/.claude/CLAUDE.md" "$MD_DIR")"

# --- Summary ---
echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
