#!/usr/bin/env bash
# Tests for PreToolUse hook: spec-gate.sh (t-2117).
# Advisory gate warns when M+ effort branches lack a feature spec.
# Spec: docs/architecture/features/sdd-spec-gate.md
#
# Run: bash system/hooks/tests/test-spec-gate.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
HOOK="$REPO_ROOT/system/hooks/spec-gate.sh"

PASS=0
FAIL=0
TOTAL=0

assert() {
    local desc="$1" expected="$2" actual="$3"
    TOTAL=$((TOTAL + 1))
    if [ "$expected" = "$actual" ]; then
        echo "  PASS: $desc"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $desc"
        echo "         expected: '$expected'"
        echo "         got:      '$actual'"
        FAIL=$((FAIL + 1))
    fi
}

assert_contains() {
    local desc="$1" needle="$2" haystack="$3"
    TOTAL=$((TOTAL + 1))
    if echo "$haystack" | grep -iqE "$needle"; then
        echo "  PASS: $desc"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $desc"
        echo "         expected pattern: '$needle'"
        echo "         in output: '$haystack'"
        FAIL=$((FAIL + 1))
    fi
}

assert_not_contains() {
    local desc="$1" needle="$2" haystack="$3"
    TOTAL=$((TOTAL + 1))
    if ! echo "$haystack" | grep -iqE "$needle"; then
        echo "  PASS: $desc"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $desc"
        echo "         unexpected pattern found: '$needle'"
        echo "         in output: '$haystack'"
        FAIL=$((FAIL + 1))
    fi
}

# ── Prerequisites ─────────────────────────────────────────────────────────────

echo ""
echo "=== spec-gate.sh tests ==="
echo ""

if [ ! -f "$HOOK" ]; then
    echo "SKIP: $HOOK not found (expected — TDD: test written before hook)"
    echo ""
    echo "Results: 0 passed, 0 failed, 0 total (hook not yet implemented)"
    exit 0
fi

# ── Harness helpers ───────────────────────────────────────────────────────────

# Create an isolated git repo for testing
setup_test_repo() {
    local dir
    dir=$(mktemp -d)
    git init -q "$dir"
    git -C "$dir" config user.email "test@test.com"
    git -C "$dir" config user.name "Test"
    mkdir -p "$dir/docs/architecture/features"
    echo "# placeholder" > "$dir/docs/architecture/features/.gitkeep"
    git -C "$dir" add . && git -C "$dir" commit -q -m "init"
    echo "$dir"
}

# Stub brana backlog get to return a given effort
stub_brana() {
    local effort="$1"
    # Create a stub script on PATH
    local stub_dir
    stub_dir=$(mktemp -d)
    cat > "$stub_dir/brana" <<STUB
#!/usr/bin/env bash
if [[ "\$*" == *"--field effort"* ]]; then
    echo '"$effort"'
else
    echo '{"effort":"$effort"}'
fi
STUB
    chmod +x "$stub_dir/brana"
    echo "$stub_dir"
}

# Run hook with given env, return output + exit code
run_hook() {
    local repo_dir="$1"
    local stub_dir="$2"
    local goal_file="${3:-}"
    local sentinel="${4:-}"

    local env_args=()
    [[ -n "$goal_file" ]] && env_args+=("HOME=$(dirname "$goal_file")")

    # Remove sentinel if specified as "clear"
    [[ "$sentinel" == "clear" ]] && rm -f "$repo_dir/.git/brana-spec-gate-checked"

    local output exit_code=0
    output=$(
        cd "$repo_dir" && \
        PATH="$stub_dir:$PATH" \
        HOME="${goal_file:+$(dirname "$goal_file")}" \
        bash "$HOOK" 2>&1
    ) || exit_code=$?

    echo "$output"
    return $exit_code
}

# ── Test setup ────────────────────────────────────────────────────────────────

REPO=$(setup_test_repo)
trap 'rm -rf "$REPO"' EXIT

# Standard PreToolUse hook input — simulates a Write call on an impl file
HOOK_INPUT='{"tool_name":"Write","tool_input":{"file_path":"/home/test/system/hooks/foo.sh"}}'

# ── Test 1: S-effort branch — gate stays silent ───────────────────────────────

echo "--- T1: S-effort branch — no warning"
STUB=$(stub_brana "S")
git -C "$REPO" checkout -q -b "harness-v2/feat/t-9999-some-feature"

OUT=$(cd "$REPO" && echo "$HOOK_INPUT" | PATH="$STUB:$PATH" bash "$HOOK" 2>&1 || true)
assert_not_contains "S-effort: no advisory" "advisory" "$OUT"
LAST_EXIT=$(cd "$REPO" && echo "$HOOK_INPUT" | PATH="$STUB:$PATH" bash "$HOOK" > /dev/null 2>&1; echo $?)
assert "S-effort: exits 0" "0" "$LAST_EXIT"
rm -rf "$STUB"
rm -f "$REPO/.git/brana-spec-gate-checked"

# ── Test 2: M-effort, no spec — advisory warning emitted ──────────────────────

echo "--- T2: M-effort, no spec on branch — advisory warning"
STUB=$(stub_brana "M")
git -C "$REPO" checkout -q main 2>/dev/null || git -C "$REPO" checkout -q -b main 2>/dev/null || true
git -C "$REPO" checkout -q -b "harness-v2/feat/t-8888-needs-spec"

OUT=$(cd "$REPO" && echo "$HOOK_INPUT" | PATH="$STUB:$PATH" bash "$HOOK" 2>&1 || true)
assert_contains "M-effort no spec: advisory emitted" "advisory" "$OUT"
rm -f "$REPO/.git/brana-spec-gate-checked"
EXIT=$(cd "$REPO" && echo "$HOOK_INPUT" | PATH="$STUB:$PATH" bash "$HOOK" > /dev/null 2>&1; echo $? || echo 0)
assert "M-effort no spec: exits 0 (non-blocking)" "0" "$EXIT"
rm -rf "$STUB"
rm -f "$REPO/.git/brana-spec-gate-checked"

# ── Test 3: M-effort, spec added on branch — no warning ───────────────────────

echo "--- T3: M-effort, spec added on this branch — no warning"
STUB=$(stub_brana "M")
# Add a spec file on this branch
echo "# spec" > "$REPO/docs/architecture/features/t-8888-needs-spec.md"
git -C "$REPO" add docs/architecture/features/t-8888-needs-spec.md
git -C "$REPO" commit -q -m "feat: add spec"

OUT=$(cd "$REPO" && echo "$HOOK_INPUT" | PATH="$STUB:$PATH" bash "$HOOK" 2>&1 || true)
assert_not_contains "M-effort with spec: no advisory" "advisory" "$OUT"
rm -rf "$STUB"
rm -f "$REPO/.git/brana-spec-gate-checked"

# ── Test 4: Sentinel — fires once per branch, silent on repeat ────────────────

echo "--- T4: Sentinel — gate fires once, silent on subsequent calls"
STUB=$(stub_brana "M")
# Branch from main (no spec) to ensure advisory fires on first call
git -C "$REPO" checkout -q main
git -C "$REPO" checkout -q -b "harness-v2/feat/t-7777-sentinel-test"

# First call — should warn
OUT1=$(cd "$REPO" && echo "$HOOK_INPUT" | PATH="$STUB:$PATH" bash "$HOOK" 2>&1 || true)
assert_contains "Sentinel T1: first call warns" "advisory" "$OUT1"

# Sentinel should now exist
assert "Sentinel T2: file created" "0" "$([ -f "$REPO/.git/brana-spec-gate-checked" ] && echo 0 || echo 1)"

# Second call — should be silent
OUT2=$(cd "$REPO" && echo "$HOOK_INPUT" | PATH="$STUB:$PATH" bash "$HOOK" 2>&1 || true)
assert_not_contains "Sentinel T3: second call silent" "advisory" "$OUT2"
rm -rf "$STUB"
rm -f "$REPO/.git/brana-spec-gate-checked"

# ── Test 5: No task ID (detached HEAD / no t-NNN in branch) — silent skip ─────

echo "--- T5: No task ID extractable — silent skip"
STUB=$(stub_brana "M")
# Isolate HOME so active-goal.json on the real host doesn't leak a task ID
FAKE_HOME=$(mktemp -d)
git -C "$REPO" checkout -q -b "hotfix/no-task-id"

OUT=$(cd "$REPO" && echo "$HOOK_INPUT" | HOME="$FAKE_HOME" PATH="$STUB:$PATH" bash "$HOOK" 2>&1 || true)
assert_not_contains "No task ID: no advisory (silent skip)" "advisory" "$OUT"
EXIT=$(cd "$REPO" && echo "$HOOK_INPUT" | HOME="$FAKE_HOME" PATH="$STUB:$PATH" bash "$HOOK" > /dev/null 2>&1; echo $? || echo 0)
assert "No task ID: exits 0" "0" "$EXIT"
rm -rf "$STUB" "$FAKE_HOME"
rm -f "$REPO/.git/brana-spec-gate-checked"

# ── Results ───────────────────────────────────────────────────────────────────

echo ""
echo "Results: $PASS passed, $FAIL failed, $TOTAL total"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
