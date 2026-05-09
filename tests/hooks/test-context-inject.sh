#!/usr/bin/env bash
# test-context-inject.sh — tests for context-inject.sh (t-204 task injection + t-1381 file path injection)
#
# Run: bash tests/hooks/test-context-inject.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
HOOK="$REPO_ROOT/system/hooks/context-inject.sh"

PASS=0
FAIL=0
TOTAL=0

assert_contains() {
    local desc="$1" needle="$2" haystack="$3"
    (( TOTAL++ )) || true
    if echo "$haystack" | grep -qE "$needle"; then
        echo "  PASS: $desc"
        (( PASS++ )) || true
    else
        echo "  FAIL: $desc"
        echo "         expected pattern: '$needle'"
        echo "         in output: '$haystack'"
        (( FAIL++ )) || true
    fi
}

assert_not_contains() {
    local desc="$1" needle="$2" haystack="$3"
    (( TOTAL++ )) || true
    if ! echo "$haystack" | grep -qE "$needle"; then
        echo "  PASS: $desc"
        (( PASS++ )) || true
    else
        echo "  FAIL: $desc"
        echo "         unexpected pattern: '$needle'"
        echo "         in output: '$haystack'"
        (( FAIL++ )) || true
    fi
}

assert_count_le() {
    local desc="$1" max="$2" actual="$3"
    (( TOTAL++ )) || true
    if [ "$actual" -le "$max" ]; then
        echo "  PASS: $desc (got $actual ≤ $max)"
        (( PASS++ )) || true
    else
        echo "  FAIL: $desc (got $actual, expected ≤ $max)"
        (( FAIL++ )) || true
    fi
}

# Invoke the hook with a plain prompt string
invoke_hook() {
    local prompt="$1"
    local json
    json=$(printf '{"prompt":%s}' "$(printf '%s' "$prompt" | jq -Rs '.')")
    echo "$json" | bash "$HOOK" 2>/dev/null || echo '{"continue": true}'
}

echo "=== test-context-inject.sh ==="
echo ""

# ── Prerequisite ─────────────────────────────────────────────────────────────
echo "Prerequisite:"
(( TOTAL++ )) || true
if [ -f "$HOOK" ]; then
    echo "  PASS: context-inject.sh exists"
    (( PASS++ )) || true
else
    echo "  FAIL: context-inject.sh not found at $HOOK"
    (( FAIL++ )) || true
fi

(( TOTAL++ )) || true
if [ -x "$HOOK" ]; then
    echo "  PASS: context-inject.sh is executable"
    (( PASS++ )) || true
else
    echo "  FAIL: context-inject.sh is NOT executable"
    (( FAIL++ )) || true
fi
echo ""

# ── Fast path ────────────────────────────────────────────────────────────────
echo "Fast path (no task IDs, no file paths):"

output=$(invoke_hook "")
assert_contains "empty prompt → continue:true"     '"continue"[[:space:]]*:[[:space:]]*true' "$output"
assert_not_contains "empty prompt → no additionalContext" 'additionalContext'                 "$output"

output=$(invoke_hook "what should I work on today?")
assert_contains "plain text → continue:true"       '"continue"[[:space:]]*:[[:space:]]*true' "$output"
assert_not_contains "plain text → no additionalContext"   'additionalContext'                 "$output"

output=$(invoke_hook "see https://example.com/foo/bar.sh for details")
assert_not_contains "https URL → not treated as file path" 'additionalContext'                "$output"
echo ""

# ── File path injection (t-1381) ──────────────────────────────────────────────
echo "File path injection (t-1381):"

TMPDIR_TEST=$(mktemp -d)
trap 'rm -rf "$TMPDIR_TEST"' EXIT

# Create fixture files
FIXTURE_A="$TMPDIR_TEST/fixture-a.sh"
printf '#!/bin/bash\n# FIXTURE_MARKER_ALPHA\necho "hello from fixture a"\n' > "$FIXTURE_A"

FIXTURE_B="$TMPDIR_TEST/fixture-b.sh"
printf '#!/bin/bash\n# FIXTURE_MARKER_BETA\necho "hello from fixture b"\n' > "$FIXTURE_B"

FIXTURE_C="$TMPDIR_TEST/fixture-c.sh"
printf '#!/bin/bash\n# FIXTURE_MARKER_GAMMA\n' > "$FIXTURE_C"

FIXTURE_D="$TMPDIR_TEST/fixture-d.sh"
printf '#!/bin/bash\n# FIXTURE_MARKER_DELTA\n' > "$FIXTURE_D"

# Test: absolute path in prompt → content injected
output=$(invoke_hook "what does $FIXTURE_A do?")
assert_contains "absolute path → additionalContext present"  'additionalContext'       "$output"
assert_contains "absolute path → file content injected"      'FIXTURE_MARKER_ALPHA'   "$output"

# Test: non-existent absolute path → no injection
output=$(invoke_hook "look at /nonexistent/path/to/file.sh please")
assert_not_contains "nonexistent path → no additionalContext" 'additionalContext'      "$output"

# Test: path mentioned among other words → still detected
output=$(invoke_hook "I edited $FIXTURE_B yesterday and it works now")
assert_contains "path in sentence → content injected"        'FIXTURE_MARKER_BETA'    "$output"

# Test: max 3 file paths enforced (4 paths given → at most 3 injected)
output=$(invoke_hook "files: $FIXTURE_A $FIXTURE_B $FIXTURE_C $FIXTURE_D")
file_header_count=$(echo "$output" | grep -oE 'fixture-[a-d]\.sh' | sort -u | wc -l | tr -d ' ')
assert_count_le "max 3 file paths (4 given → ≤ 3 injected)" 3 "$file_header_count"

# Test: ~ path → expanded to HOME and resolved
# Use the hook file itself — it lives under $HOME and has a .sh extension
if [[ "$REPO_ROOT" == "$HOME"* ]]; then
    TILDE_HOOK="~${REPO_ROOT#$HOME}/system/hooks/context-inject.sh"
    output=$(invoke_hook "what does $TILDE_HOOK do?")
    assert_contains "~ path → additionalContext present" 'additionalContext' "$output"
    assert_contains "~ path → file content injected"    'UserPromptSubmit'   "$output"
fi

# Test: relative path (repo file we know exists) → content injected
output=$(invoke_hook "what does system/hooks/context-inject.sh do?")
assert_contains "relative repo path → content injected" 'UserPromptSubmit' "$output"

# Test: https URL is NOT matched as a file path
output=$(invoke_hook "see https://github.com/foo/bar.sh for reference")
assert_not_contains "https URL → not injected as file" 'File context\|additionalContext' "$output"
echo ""

# ── Combined task + file injection ───────────────────────────────────────────
echo "Combined: task ID + file path (requires brana CLI):"
output=$(invoke_hook "working on t-1381, check $FIXTURE_A")
# File content should always be injected regardless of brana availability
assert_contains "file content injected even with task ID present" 'FIXTURE_MARKER_ALPHA' "$output"
echo ""

# ── Summary ──────────────────────────────────────────────────────────────────
echo ""
echo "Results: $PASS passed, $FAIL failed, $TOTAL total"
if [ "$FAIL" -gt 0 ]; then
    echo "STATUS: RED"
    exit 1
else
    echo "STATUS: GREEN"
    exit 0
fi
