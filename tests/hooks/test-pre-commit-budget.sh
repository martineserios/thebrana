#!/usr/bin/env bash
# Tests for pre-commit budget gate (t-1200)
# Validates: gate blocks when context budget >28672 bytes, passes when under.
#
# Run: bash tests/hooks/test-pre-commit-budget.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
HOOK="$REPO_ROOT/system/scripts/git-hooks/pre-commit"

PASS=0
FAIL=0
TOTAL=0

assert_exit() {
    local desc="$1" expected="$2" actual="$3"
    (( TOTAL++ )) || true
    if [ "$actual" -eq "$expected" ]; then
        echo "  PASS: $desc"
        (( PASS++ )) || true
    else
        echo "  FAIL: $desc — expected exit $expected, got $actual"
        (( FAIL++ )) || true
    fi
}

assert_contains() {
    local desc="$1" needle="$2" haystack="$3"
    (( TOTAL++ )) || true
    if [[ "$haystack" =~ $needle ]]; then
        echo "  PASS: $desc"
        (( PASS++ )) || true
    else
        echo "  FAIL: $desc"
        echo "         expected pattern: '$needle'"
        echo "         not found in output"
        (( FAIL++ )) || true
    fi
}

# ── Scaffold: create a minimal temp git repo with brana structure ────────────
make_brana_repo() {
    local dir="$1"
    git init -q "$dir"
    git -C "$dir" config user.email "test@test.com"
    git -C "$dir" config user.name "Test"
    # Minimal brana structure needed for budget gate to activate
    mkdir -p "$dir/system/skills/my-skill" "$dir/system/hooks" "$dir/system/rules" "$dir/system/agents"
    # Minimal initial commit so git is usable
    touch "$dir/README.md"
    git -C "$dir" add README.md
    git -C "$dir" commit -q -m "init"
}

run_budget_gate() {
    local repo="$1"
    local exit_code=0
    OUT=$(cd "$repo" && bash "$HOOK" 2>&1) || exit_code=$?
    echo "$OUT"
    return $exit_code
}

# ── Test 1: no system/ dir → hook passes (not a brana repo) ─────────────────
echo "Test 1: non-brana repo → budget gate skipped"
TMPDIR1=$(mktemp -d)
trap 'rm -rf "$TMPDIR1"' EXIT
git init -q "$TMPDIR1"
git -C "$TMPDIR1" config user.email "t@t.com"
git -C "$TMPDIR1" config user.name "T"
touch "$TMPDIR1/README.md"
git -C "$TMPDIR1" add README.md
git -C "$TMPDIR1" commit -q -m "init"
EXIT1=0; OUT1=$(cd "$TMPDIR1" && bash "$HOOK" 2>&1) || EXIT1=$?
assert_exit "non-brana repo → exit 0" 0 "$EXIT1"

# ── Test 2: system/ present but budget under limit → passes ─────────────────
echo "Test 2: brana repo, budget under limit → passes"
TMPDIR2=$(mktemp -d)
trap 'rm -rf "$TMPDIR2"' EXIT
make_brana_repo "$TMPDIR2"
# Write a small CLAUDE.md (~100 bytes)
echo "# Small CLAUDE" > "$TMPDIR2/system/CLAUDE.md"
# One small rule (no paths: → always loaded)
printf -- '---\nalwaysApply: true\n---\n# Rule\nShort rule.\n' > "$TMPDIR2/system/rules/rule-01.md"
# One skill
mkdir -p "$TMPDIR2/system/skills/my-skill"
printf -- '---\nname: my-skill\ndescription: "Short description"\nstatus: stable\n---\n' > "$TMPDIR2/system/skills/my-skill/SKILL.md"
EXIT2=0; OUT2=$(cd "$TMPDIR2" && bash "$HOOK" 2>&1) || EXIT2=$?
assert_exit "under-budget repo → exit 0" 0 "$EXIT2"

# ── Test 3: budget over limit → blocked ─────────────────────────────────────
echo "Test 3: budget over limit → commit blocked"
TMPDIR3=$(mktemp -d)
trap 'rm -rf "$TMPDIR3"' EXIT
make_brana_repo "$TMPDIR3"
# Write a 30KB CLAUDE.md (exceeds 28672 limit on its own)
python3 -c "print('# ' + 'x' * 30000)" > "$TMPDIR3/system/CLAUDE.md"
mkdir -p "$TMPDIR3/system/skills/sk" "$TMPDIR3/system/agents"
EXIT3=0; OUT3=$(cd "$TMPDIR3" && bash "$HOOK" 2>&1) || EXIT3=$?
assert_exit "over-budget → exit 1" 1 "$EXIT3"
assert_contains "over-budget → shows COMMIT BLOCKED" "COMMIT BLOCKED" "$OUT3"
assert_contains "over-budget → shows byte count" "bytes" "$OUT3"
assert_contains "over-budget → shows limit" "28672" "$OUT3"

# ── Test 4: paths: rules excluded from budget ────────────────────────────────
echo "Test 4: rule with paths: frontmatter → excluded from always-loaded budget"
TMPDIR4=$(mktemp -d)
trap 'rm -rf "$TMPDIR4"' EXIT
make_brana_repo "$TMPDIR4"
echo "# Small CLAUDE" > "$TMPDIR4/system/CLAUDE.md"
# Scoped rule (has paths: → NOT always-loaded, should not count)
printf -- '---\npaths:\n  - "*.rs"\n---\n%s\n' "$(python3 -c "print('x' * 29000)")" > "$TMPDIR4/system/rules/scoped-rule.md"
EXIT4=0; OUT4=$(cd "$TMPDIR4" && bash "$HOOK" 2>&1) || EXIT4=$?
assert_exit "scoped rule excluded → exit 0" 0 "$EXIT4"

# ── Test 5: skill descriptions counted (just description: line) ──────────────
echo "Test 5: skill description lines are counted in budget"
TMPDIR5=$(mktemp -d)
trap 'rm -rf "$TMPDIR5"' EXIT
make_brana_repo "$TMPDIR5"
# No CLAUDE.md, no rules — only skill descriptions fill the budget
# 28673+ bytes of description: lines
echo "# min" > "$TMPDIR5/system/CLAUDE.md"
for i in $(seq 1 20); do
    mkdir -p "$TMPDIR5/system/skills/sk-$i"
    # Each description line ~1500 bytes → 20 × 1500 = 30000 bytes
    desc=$(python3 -c "print('description: \"' + 'y' * 1490 + '\"')")
    printf -- '---\nname: sk-%d\n%s\nstatus: stable\n---\n' "$i" "$desc" > "$TMPDIR5/system/skills/sk-$i/SKILL.md"
done
EXIT5=0; OUT5=$(cd "$TMPDIR5" && bash "$HOOK" 2>&1) || EXIT5=$?
assert_exit "large skill descriptions → exit 1" 1 "$EXIT5"
assert_contains "large skill descriptions → COMMIT BLOCKED" "COMMIT BLOCKED" "$OUT5"

# ── Summary ──────────────────────────────────────────────────────────────────
echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ]
