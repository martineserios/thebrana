#!/usr/bin/env bash
# Tests for system/scripts/ac-lint.sh — AC heuristic-lint classifier.
# Verifies each of the 8 machine-checkable heuristics from docs/architecture/ac-grammar.md
# is classified as "checkable", and prose criteria are classified as "prose".
#
# Interface under test: ac-lint.sh "<criterion>"
#   exit 0 + stdout "checkable" → criterion matches a heuristic (will auto-complete)
#   exit 1 + stdout "prose"     → criterion is free-text (will need manual sign-off)
#
# t-2200 (TDD for t-2201). Grammar source: docs/architecture/ac-grammar.md.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLASSIFIER="$SCRIPT_DIR/../../scripts/ac-lint.sh"

PASS=0
FAIL=0
TOTAL=0

check() {
    local label="$1" criterion="$2" expected_class="$3" expected_exit="$4"
    TOTAL=$((TOTAL + 1))
    local actual_class actual_exit
    actual_class=$(bash "$CLASSIFIER" "$criterion" 2>/dev/null); actual_exit=$?
    if [ "$actual_class" = "$expected_class" ] && [ "$actual_exit" -eq "$expected_exit" ]; then
        echo "  PASS: $label"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $label"
        echo "        criterion : $criterion"
        echo "        expected  : class=$expected_class exit=$expected_exit"
        echo "        got       : class=$actual_class exit=$actual_exit"
        FAIL=$((FAIL + 1))
    fi
}

# ── Guard ────────────────────────────────────────────────────────────────────
if [ ! -f "$CLASSIFIER" ]; then
    echo "SKIP: $CLASSIFIER not found (implement in t-2201)"
    exit 0
fi

echo "=== AC lint classifier tests (docs/architecture/ac-grammar.md) ==="

# ── Heuristic 1: file exists ─────────────────────────────────────────────────
echo "--- Heuristic 1: file exists ---"
check "h1 .md extension"   "file docs/architecture/ac-grammar.md exists"       "checkable" 0
check "h1 .sh extension"   "file system/hooks/goal-completion.sh exists"        "checkable" 0
check "h1 .json extension" "file .claude/tasks.json exists"                     "checkable" 0
check "h1 .rs extension"   "file src/main.rs exists"                            "checkable" 0
check "h1 .toml extension" "file Cargo.toml exists"                             "checkable" 0

# ── Heuristic 2: backlog get returns ─────────────────────────────────────────
echo "--- Heuristic 2: brana backlog get returns ---"
check "h2 status field"    "brana backlog get t-123 --field status returns completed"    "checkable" 0
check "h2 bare returns"    "brana backlog get t-2199 returns acceptance_criteria"        "checkable" 0

# ── Heuristic 3: validate.sh check ───────────────────────────────────────────
echo "--- Heuristic 3: validate.sh Check N passes ---"
check "h3 check number"    "validate.sh Check 18 passes"  "checkable" 0
check "h3 check lowercase" "validate.sh check 5 passes"   "checkable" 0

# ── Heuristic 4: hook exists ─────────────────────────────────────────────────
echo "--- Heuristic 4: hook X.sh exists ---"
check "h4 hook exists"     "hook goal-completion.sh exists"   "checkable" 0
check "h4 hook ac-lint"    "hook ac-lint.sh exists"           "checkable" 0

# ── Heuristic 5: file contains ───────────────────────────────────────────────
echo "--- Heuristic 5: file {path} contains \"{string}\" ---"
check "h5 contains"        'file system/skills/build/phases/load.md contains "acceptance_criteria"'  "checkable" 0
check "h5 contains adr"    'file docs/architecture/decisions/ADR-047-acceptance-criteria-schema.md contains "ac-grammar.md"' "checkable" 0

# ── Heuristic 6: jq returns ──────────────────────────────────────────────────
echo "--- Heuristic 6: jq '{expr}' {file} returns \"{value}\" ---"
check "h6 jq returns"      "jq '.version' docs/spec-graph.json returns \"1\""   "checkable" 0
check "h6 jq nested"       "jq '.status' .claude/tasks.json returns \"ok\""     "checkable" 0

# ── Heuristic 7: command passes ──────────────────────────────────────────────
echo "--- Heuristic 7: \"{command}\" passes ---"
check "h7 cargo test"      '"cargo test" passes'            "checkable" 0
check "h7 pytest"          '"pytest" passes'                "checkable" 0
check "h7 bash tests/"     '"bash tests/run.sh" passes'     "checkable" 0
check "h7 bun test"        '"bun test" passes'              "checkable" 0

# ── Heuristic 8: git log checks ──────────────────────────────────────────────
echo "--- Heuristic 8: git log ---"
check "h8 changes committed"       "changes to load.md committed"            "checkable" 0
check "h8 commit msg contains"     'commit message contains "t-2199"'        "checkable" 0

# ── Prose (UNKNOWN) — must NOT be checkable ───────────────────────────────────
echo "--- Prose criteria (should classify as prose) ---"
check "prose: works correctly"     "works correctly"                          "prose" 1
check "prose: user experience"     "user experience is smooth"                "prose" 1
check "prose: tests pass vague"    "all tests pass"                           "prose" 1
check "prose: code is clean"       "code is clean and readable"               "prose" 1
check "prose: no errors"           "no errors in the console"                 "prose" 1
check "prose: AC: prefix stripped" "AC: the feature works as expected"        "prose" 1

# ── Edge cases ────────────────────────────────────────────────────────────────
echo "--- Edge cases ---"
check "edge: empty string"         ""                                          "prose" 1
check "edge: AC: prefix on h1"     "AC: file docs/guide.md exists"            "checkable" 0
check "edge: AC: prefix on h3"     "AC: validate.sh Check 7 passes"           "checkable" 0
check "edge: h7 not-allowlisted"   '"rm -rf /" passes'                        "prose" 1
check "edge: h5 no path traversal" 'file ../../../etc/passwd contains "root"' "prose" 1
check "edge: h5 absolute path"     'file /etc/hosts contains "localhost"'     "prose" 1

# ── Summary ──────────────────────────────────────────────────────────────────
echo ""
echo "=== AC lint results: $PASS passed, $FAIL failed, $TOTAL total ==="
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
