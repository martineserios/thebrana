#!/usr/bin/env bash
# Tests for commit-msg-verify.sh
# Verifies that the hook warns when commit message mentions files not staged.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$SCRIPT_DIR/../commit-msg-verify.sh"
PASS=0
FAIL=0
TMPDIR=$(mktemp -d)

trap 'rm -rf "$TMPDIR"' EXIT

assert_eq() {
    local desc="$1" actual="$2" expected="$3"
    if [ "$actual" = "$expected" ]; then
        echo "  PASS: $desc"
        ((PASS++))
    else
        echo "  FAIL: $desc — expected '$expected', got '$actual'"
        ((FAIL++))
    fi
}

assert_contains() {
    local desc="$1" haystack="$2" needle="$3"
    if echo "$haystack" | grep -qF "$needle"; then
        echo "  PASS: $desc"
        ((PASS++))
    else
        echo "  FAIL: $desc — expected to contain '$needle'"
        ((FAIL++))
    fi
}

assert_not_contains() {
    local desc="$1" haystack="$2" needle="$3"
    if ! echo "$haystack" | grep -qF "$needle"; then
        echo "  PASS: $desc"
        ((PASS++))
    else
        echo "  FAIL: $desc — expected NOT to contain '$needle'"
        ((FAIL++))
    fi
}

assert_continue_true() {
    local desc="$1" json="$2"
    local val
    val=$(echo "$json" | jq -r '.continue' 2>/dev/null)
    if [ "$val" = "true" ]; then
        echo "  PASS: $desc (continue:true)"
        ((PASS++))
    else
        echo "  FAIL: $desc — expected continue:true, got: $json"
        ((FAIL++))
    fi
}

# Helper: make JSON input for Bash tool
make_input() {
    local cmd="$1" cwd="${2:-$TMPDIR/repo}"
    jq -n --arg cmd "$cmd" --arg cwd "$cwd" \
        '{"tool_name": "Bash", "tool_input": {"command": $cmd}, "cwd": $cwd}'
}

# Helper: create temp git repo with staged files
make_repo_with_staged() {
    local repo="$1"
    shift
    git init -q "$repo"
    git -C "$repo" config user.email "test@test.com"
    git -C "$repo" config user.name "Test"
    # Create and stage each file
    for f in "$@"; do
        mkdir -p "$repo/$(dirname "$f")"
        echo "content" > "$repo/$f"
        git -C "$repo" add "$f"
    done
}

echo "commit-msg-verify.sh Tests"
echo "=========================="

# --- Test 1: Non-commit command — pass through ---
echo ""
echo "Test 1: Non-commit command — pass through"
INPUT=$(make_input "ls -la")
RESULT=$(echo "$INPUT" | bash "$HOOK")
assert_continue_true "non-commit passthrough" "$RESULT"

# --- Test 2: Commit with no filenames in message — pass through ---
echo ""
echo "Test 2: Commit with no filenames in message"
INPUT=$(make_input 'git commit -m "fix typo in docs"')
RESULT=$(echo "$INPUT" | bash "$HOOK")
assert_continue_true "no filenames in message passthrough" "$RESULT"

# --- Test 3: Commit mentions file that IS staged — no warning ---
echo ""
echo "Test 3: Commit mentions file that is staged — no warning"
REPO="$TMPDIR/repo3"
make_repo_with_staged "$REPO" "src/foo.rs"
INPUT=$(make_input 'git commit -m "fix(cli): update foo.rs parsing"' "$REPO")
RESULT=$(echo "$INPUT" | bash "$HOOK")
assert_continue_true "staged file mentioned → continue:true" "$RESULT"
# Should have no additionalContext (no warning needed)
CTX=$(echo "$RESULT" | jq -r '.additionalContext // ""' 2>/dev/null)
assert_eq "staged file → no warning context" "$CTX" ""

# --- Test 4: Commit mentions file NOT staged — warn ---
echo ""
echo "Test 4: Commit mentions file not staged — warn"
REPO="$TMPDIR/repo4"
make_repo_with_staged "$REPO" "src/bar.rs"
INPUT=$(make_input 'git commit -m "fix(cli): update skills.rs argument parsing"' "$REPO")
RESULT=$(echo "$INPUT" | bash "$HOOK")
assert_continue_true "unstaged mention → still continue:true (non-blocking)" "$RESULT"
CTX=$(echo "$RESULT" | jq -r '.additionalContext // ""' 2>/dev/null)
assert_contains "unstaged mention → warning context" "$CTX" "skills.rs"
assert_contains "unstaged mention → warning says WARNING" "$CTX" "WARNING"

# --- Test 5: Commit mentions partial match that IS staged (basename match) ---
echo ""
echo "Test 5: Commit mentions file by basename, staged with path — no warning"
REPO="$TMPDIR/repo5"
make_repo_with_staged "$REPO" "system/cli/rust/src/skills.rs"
INPUT=$(make_input 'git commit -m "fix(cli): update skills.rs dispatch"' "$REPO")
RESULT=$(echo "$INPUT" | bash "$HOOK")
assert_continue_true "path-agnostic basename match → continue:true" "$RESULT"
CTX=$(echo "$RESULT" | jq -r '.additionalContext // ""' 2>/dev/null)
assert_eq "path-agnostic basename match → no warning" "$CTX" ""

# --- Test 6: Multiple files mentioned, some staged, some not ---
echo ""
echo "Test 6: Mixed — some mentioned staged, some not"
REPO="$TMPDIR/repo6"
make_repo_with_staged "$REPO" "hooks/pre-tool-use.sh"
INPUT=$(make_input 'git commit -m "fix: update pre-tool-use.sh and config-drift.sh"' "$REPO")
RESULT=$(echo "$INPUT" | bash "$HOOK")
assert_continue_true "mixed mention → continue:true" "$RESULT"
CTX=$(echo "$RESULT" | jq -r '.additionalContext // ""' 2>/dev/null)
assert_contains "mixed → warns about unstaged config-drift.sh" "$CTX" "config-drift.sh"
# pre-tool-use.sh appears only in "Staged files:" section, not as a missing file
MISSING_SECTION=$(echo "$CTX" | sed 's/Staged files:.*//')
assert_not_contains "mixed → missing-files section does not contain staged pre-tool-use.sh" \
    "$MISSING_SECTION" "pre-tool-use.sh"

# --- Test 7: git commit without -m (no parseable message) — pass through ---
echo ""
echo "Test 7: git commit without -m — pass through"
INPUT=$(make_input 'git commit --amend --no-edit')
RESULT=$(echo "$INPUT" | bash "$HOOK")
assert_continue_true "no -m flag → passthrough" "$RESULT"

# --- Test 8: Commit message with .md file mentioned and staged ---
echo ""
echo "Test 8: Markdown file mentioned and staged — no warning"
REPO="$TMPDIR/repo8"
make_repo_with_staged "$REPO" "docs/architecture/hooks.md"
INPUT=$(make_input 'git commit -m "docs: update hooks.md with new gate description"' "$REPO")
RESULT=$(echo "$INPUT" | bash "$HOOK")
assert_continue_true "md file match → continue:true" "$RESULT"
CTX=$(echo "$RESULT" | jq -r '.additionalContext // ""' 2>/dev/null)
assert_eq "md file staged → no warning" "$CTX" ""

# --- Summary ---
echo ""
echo "=========================="
echo "Results: $PASS passed, $FAIL failed"
if [ "$FAIL" -gt 0 ]; then
    exit 1
fi
