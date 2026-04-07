#!/usr/bin/env bash
# End-to-end hook tests — real git repos, real staged files, real commits.
#
# Unlike the unit tests (test-doc-gate.sh, test-main-guard.sh, test-tdd-gate.sh)
# which pipe mock JSON to hook scripts, these tests:
#   1. Create a real temp git repo
#   2. Install hooks as actual git pre-commit hooks
#   3. Stage real files
#   4. Run `git commit`
#   5. Assert the commit was blocked or allowed
#
# The hooks are PreToolUse hooks (JSON stdin), so each pre-commit wrapper
# synthesizes the JSON payload from the actual git state and pipes it to
# the hook script. If the hook returns "deny", the pre-commit exits 1.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOKS_DIR="$SCRIPT_DIR/.."
PASS=0
FAIL=0
TOTAL=0
E2E_TMPDIR=$(mktemp -d)

trap 'rm -rf "$E2E_TMPDIR"' EXIT

# ── Helpers ──────────────────────────────────────────────

assert_commit_succeeds() {
    local desc="$1"
    local repo_dir="$2"
    local msg="${3:-e2e test commit}"
    TOTAL=$((TOTAL + 1))
    local output
    output=$(git -C "$repo_dir" commit -m "$msg" 2>&1)
    local rc=$?
    if [ $rc -eq 0 ]; then
        echo "  PASS: $desc"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $desc"
        echo "    expected: commit to succeed (rc=0)"
        echo "    got:      rc=$rc"
        echo "    output:   $output"
        FAIL=$((FAIL + 1))
    fi
}

assert_commit_fails() {
    local desc="$1"
    local repo_dir="$2"
    local msg="${3:-e2e test commit}"
    TOTAL=$((TOTAL + 1))
    local output
    output=$(git -C "$repo_dir" commit -m "$msg" 2>&1)
    local rc=$?
    if [ $rc -ne 0 ]; then
        echo "  PASS: $desc"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $desc"
        echo "    expected: commit to fail (rc!=0)"
        echo "    got:      rc=$rc (commit succeeded)"
        FAIL=$((FAIL + 1))
    fi
}

# Create a git repo and install a pre-commit hook that wraps a brana hook.
# Usage: init_repo <dir> <branch> <hook_script>
# The pre-commit hook synthesizes JSON from git state and pipes it to the hook.
init_repo() {
    local dir="$1"
    local branch="$2"
    local hook_script="$3"

    mkdir -p "$dir"
    git -C "$dir" init -q -b main 2>/dev/null
    git -C "$dir" config user.email "test@test.com"
    git -C "$dir" config user.name "Test"

    # Initial commit so HEAD exists
    echo "init" > "$dir/init.txt"
    git -C "$dir" add -A
    git -C "$dir" commit -q -m "init" 2>/dev/null

    # Switch branch if needed
    if [ "$branch" != "main" ]; then
        git -C "$dir" checkout -q -b "$branch" 2>/dev/null
    fi

    # Install pre-commit hook that wraps the brana hook
    mkdir -p "$dir/.git/hooks"
    cat > "$dir/.git/hooks/pre-commit" <<PCHOOK
#!/usr/bin/env bash
# E2E wrapper: synthesize JSON input and pipe to brana hook
REPO_ROOT=\$(git rev-parse --show-toplevel)

# Build the JSON payload that PreToolUse hooks expect
JSON=\$(cat <<ENDJSON
{
  "tool_name": "Bash",
  "tool_input": {
    "command": "git commit -m 'e2e'"
  },
  "cwd": "\$REPO_ROOT"
}
ENDJSON
)

OUTPUT=\$(echo "\$JSON" | BRANA_HOOK_PROFILE=standard bash "$hook_script" 2>/dev/null)

# Check if hook denied
if echo "\$OUTPUT" | jq -e '.hookSpecificOutput.permissionDecision == "deny"' >/dev/null 2>&1; then
    REASON=\$(echo "\$OUTPUT" | jq -r '.hookSpecificOutput.permissionDecisionReason // "denied"')
    echo "HOOK DENIED: \$REASON" >&2
    exit 1
fi
exit 0
PCHOOK
    chmod +x "$dir/.git/hooks/pre-commit"
}

# Install a pre-commit hook for tdd-gate (Write/Edit tool, not Bash)
# tdd-gate checks Write/Edit tool_input.file_path, so we need a different wrapper
# that iterates staged files and checks each one.
init_repo_tdd() {
    local dir="$1"
    local branch="$2"
    local hook_script="$3"

    mkdir -p "$dir"
    git -C "$dir" init -q -b main 2>/dev/null
    git -C "$dir" config user.email "test@test.com"
    git -C "$dir" config user.name "Test"

    echo "init" > "$dir/init.txt"
    git -C "$dir" add -A
    git -C "$dir" commit -q -m "init" 2>/dev/null

    if [ "$branch" != "main" ]; then
        git -C "$dir" checkout -q -b "$branch" 2>/dev/null
    fi

    mkdir -p "$dir/.git/hooks"
    cat > "$dir/.git/hooks/pre-commit" <<PCHOOK
#!/usr/bin/env bash
# E2E wrapper: check each staged file against tdd-gate
REPO_ROOT=\$(git rev-parse --show-toplevel)
STAGED=\$(git diff --cached --name-only)

for FILE in \$STAGED; do
    FULL_PATH="\$REPO_ROOT/\$FILE"
    JSON=\$(cat <<ENDJSON
{
  "tool_name": "Write",
  "tool_input": {
    "file_path": "\$FULL_PATH"
  },
  "cwd": "\$REPO_ROOT"
}
ENDJSON
)
    OUTPUT=\$(echo "\$JSON" | BRANA_HOOK_PROFILE=standard bash "$hook_script" 2>/dev/null)
    if echo "\$OUTPUT" | jq -e '.hookSpecificOutput.permissionDecision == "deny"' >/dev/null 2>&1; then
        REASON=\$(echo "\$OUTPUT" | jq -r '.hookSpecificOutput.permissionDecisionReason // "denied"')
        echo "HOOK DENIED (\$FILE): \$REASON" >&2
        exit 1
    fi
done
exit 0
PCHOOK
    chmod +x "$dir/.git/hooks/pre-commit"
}

# Stage files in a repo (creates parent dirs)
stage_files() {
    local dir="$1"; shift
    for f in "$@"; do
        mkdir -p "$dir/$(dirname "$f")"
        echo "content" > "$dir/$f"
        git -C "$dir" add "$f"
    done
}

# ── Doc Gate E2E Tests ──────────────────────────────────

echo "Doc Gate E2E Tests"
echo "=================="

# Test 1: Behavioral file without docs → commit blocked
REPO="$E2E_TMPDIR/doc-deny"
init_repo "$REPO" "feat/test" "$HOOKS_DIR/doc-gate.sh"
stage_files "$REPO" "system/hooks/new-hook.sh"
assert_commit_fails "doc-gate: behavioral file without docs blocks commit" "$REPO"

# Test 2: Behavioral file WITH docs → commit allowed
REPO="$E2E_TMPDIR/doc-allow"
init_repo "$REPO" "feat/test" "$HOOKS_DIR/doc-gate.sh"
stage_files "$REPO" "system/hooks/new-hook.sh" "docs/architecture/hooks.md"
assert_commit_succeeds "doc-gate: behavioral file with docs allows commit" "$REPO"

# Test 3: Non-behavioral files only → commit allowed
REPO="$E2E_TMPDIR/doc-nonbehavioral"
init_repo "$REPO" "feat/test" "$HOOKS_DIR/doc-gate.sh"
stage_files "$REPO" "README.md" "config.toml"
assert_commit_succeeds "doc-gate: non-behavioral files allow commit" "$REPO"

# Test 4: Behavioral file with CLAUDE.md doc → commit allowed
REPO="$E2E_TMPDIR/doc-claude-md"
init_repo "$REPO" "feat/test" "$HOOKS_DIR/doc-gate.sh"
stage_files "$REPO" "system/skills/foo.md" "CLAUDE.md"
assert_commit_succeeds "doc-gate: behavioral file with CLAUDE.md allows commit" "$REPO"

# Test 5: Escape hatch --no-doc-check → commit allowed
REPO="$E2E_TMPDIR/doc-escape"
init_repo "$REPO" "feat/test" "$HOOKS_DIR/doc-gate.sh"
stage_files "$REPO" "system/agents/agent.sh"
# Override the pre-commit to include the escape flag in the command
cat > "$REPO/.git/hooks/pre-commit" <<'PCHOOK'
#!/usr/bin/env bash
REPO_ROOT=$(git rev-parse --show-toplevel)
JSON=$(cat <<ENDJSON
{
  "tool_name": "Bash",
  "tool_input": {
    "command": "git commit -m 'add agent --no-doc-check'"
  },
  "cwd": "$REPO_ROOT"
}
ENDJSON
)
PCHOOK
# Rewrite with proper hook path
cat > "$REPO/.git/hooks/pre-commit" <<PCHOOK
#!/usr/bin/env bash
REPO_ROOT=\$(git rev-parse --show-toplevel)
JSON=\$(cat <<ENDJSON
{
  "tool_name": "Bash",
  "tool_input": {
    "command": "git commit -m 'add agent --no-doc-check'"
  },
  "cwd": "\$REPO_ROOT"
}
ENDJSON
)
OUTPUT=\$(echo "\$JSON" | BRANA_HOOK_PROFILE=standard bash "$HOOKS_DIR/doc-gate.sh" 2>/dev/null)
if echo "\$OUTPUT" | jq -e '.hookSpecificOutput.permissionDecision == "deny"' >/dev/null 2>&1; then
    exit 1
fi
exit 0
PCHOOK
chmod +x "$REPO/.git/hooks/pre-commit"
assert_commit_succeeds "doc-gate: --no-doc-check escape allows commit" "$REPO"

echo ""

# ── Main Guard E2E Tests ────────────────────────────────

echo "Main Guard E2E Tests"
echo "===================="

# Test 6: Behavioral file on main → commit blocked
REPO="$E2E_TMPDIR/main-deny"
init_repo "$REPO" "main" "$HOOKS_DIR/main-guard.sh"
stage_files "$REPO" "system/skills/new-skill.md"
assert_commit_fails "main-guard: behavioral file on main blocks commit" "$REPO"

# Test 7: Behavioral file on feature branch → commit allowed
REPO="$E2E_TMPDIR/main-feat"
init_repo "$REPO" "feat/my-feature" "$HOOKS_DIR/main-guard.sh"
stage_files "$REPO" "system/skills/new-skill.md"
assert_commit_succeeds "main-guard: behavioral file on feature branch allows commit" "$REPO"

# Test 8: Non-behavioral file on main → commit allowed
REPO="$E2E_TMPDIR/main-docs"
init_repo "$REPO" "main" "$HOOKS_DIR/main-guard.sh"
stage_files "$REPO" "docs/guide/usage.md"
assert_commit_succeeds "main-guard: non-behavioral file on main allows commit" "$REPO"

# Test 9: Escape hatch --force-main → commit allowed
REPO="$E2E_TMPDIR/main-escape"
init_repo "$REPO" "main" "$HOOKS_DIR/main-guard.sh"
stage_files "$REPO" "system/commands/cmd.sh"
cat > "$REPO/.git/hooks/pre-commit" <<PCHOOK
#!/usr/bin/env bash
REPO_ROOT=\$(git rev-parse --show-toplevel)
JSON=\$(cat <<ENDJSON
{
  "tool_name": "Bash",
  "tool_input": {
    "command": "git commit -m 'hotfix --force-main'"
  },
  "cwd": "\$REPO_ROOT"
}
ENDJSON
)
OUTPUT=\$(echo "\$JSON" | BRANA_HOOK_PROFILE=standard bash "$HOOKS_DIR/main-guard.sh" 2>/dev/null)
if echo "\$OUTPUT" | jq -e '.hookSpecificOutput.permissionDecision == "deny"' >/dev/null 2>&1; then
    exit 1
fi
exit 0
PCHOOK
chmod +x "$REPO/.git/hooks/pre-commit"
assert_commit_succeeds "main-guard: --force-main escape allows commit" "$REPO"

# Test 10: Multiple behavioral files on main → commit blocked
REPO="$E2E_TMPDIR/main-multi"
init_repo "$REPO" "main" "$HOOKS_DIR/main-guard.sh"
stage_files "$REPO" "system/hooks/a.sh" "system/skills/b.md" "system/cli/c.rs"
assert_commit_fails "main-guard: multiple behavioral files on main blocks commit" "$REPO"

echo ""

# ── TDD Gate E2E Tests ──────────────────────────────────

echo "TDD Gate E2E Tests"
echo "=================="

# Test 11: Rust impl without tests → commit blocked
REPO="$E2E_TMPDIR/tdd-rust-deny"
init_repo_tdd "$REPO" "feat/impl" "$HOOKS_DIR/tdd-gate.sh"
echo '[package]' > "$REPO/Cargo.toml"
mkdir -p "$REPO/src"
git -C "$REPO" add Cargo.toml
git -C "$REPO" commit -q -m "add manifest"
echo 'fn main() {}' > "$REPO/src/main.rs"
git -C "$REPO" add src/main.rs
assert_commit_fails "tdd-gate: Rust impl without tests blocks commit" "$REPO"

# Test 12: Rust impl WITH tests/ dir → commit allowed
REPO="$E2E_TMPDIR/tdd-rust-allow"
init_repo_tdd "$REPO" "feat/impl" "$HOOKS_DIR/tdd-gate.sh"
echo '[package]' > "$REPO/Cargo.toml"
mkdir -p "$REPO/src" "$REPO/tests"
echo '#[test] fn it_works() {}' > "$REPO/tests/integration.rs"
git -C "$REPO" add Cargo.toml tests/
git -C "$REPO" commit -q -m "add manifest and tests"
echo 'fn main() {}' > "$REPO/src/main.rs"
git -C "$REPO" add src/main.rs
assert_commit_succeeds "tdd-gate: Rust impl with tests/ dir allows commit" "$REPO"

# Test 13: Python impl without tests → commit blocked
REPO="$E2E_TMPDIR/tdd-py-deny"
init_repo_tdd "$REPO" "feat/impl" "$HOOKS_DIR/tdd-gate.sh"
echo '[project]' > "$REPO/pyproject.toml"
mkdir -p "$REPO/src"
git -C "$REPO" add pyproject.toml
git -C "$REPO" commit -q -m "add manifest"
echo 'def main(): pass' > "$REPO/src/app.py"
git -C "$REPO" add src/app.py
assert_commit_fails "tdd-gate: Python impl without tests blocks commit" "$REPO"

# Test 14: Python impl WITH test file → commit allowed
REPO="$E2E_TMPDIR/tdd-py-allow"
init_repo_tdd "$REPO" "feat/impl" "$HOOKS_DIR/tdd-gate.sh"
echo '[project]' > "$REPO/pyproject.toml"
mkdir -p "$REPO/src"
echo 'def test_main(): pass' > "$REPO/src/test_app.py"
git -C "$REPO" add pyproject.toml src/test_app.py
git -C "$REPO" commit -q -m "add manifest and tests"
echo 'def main(): pass' > "$REPO/src/app.py"
git -C "$REPO" add src/app.py
assert_commit_succeeds "tdd-gate: Python impl with test file allows commit" "$REPO"

# Test 15: JS/TS impl without tests → commit blocked
REPO="$E2E_TMPDIR/tdd-ts-deny"
init_repo_tdd "$REPO" "feat/impl" "$HOOKS_DIR/tdd-gate.sh"
echo '{"name":"test"}' > "$REPO/package.json"
mkdir -p "$REPO/src"
git -C "$REPO" add package.json
git -C "$REPO" commit -q -m "add manifest"
echo 'export default {}' > "$REPO/src/index.ts"
git -C "$REPO" add src/index.ts
assert_commit_fails "tdd-gate: TS impl without tests blocks commit" "$REPO"

# Test 16: JS/TS impl WITH .test.ts → commit allowed
REPO="$E2E_TMPDIR/tdd-ts-allow"
init_repo_tdd "$REPO" "feat/impl" "$HOOKS_DIR/tdd-gate.sh"
echo '{"name":"test"}' > "$REPO/package.json"
mkdir -p "$REPO/src"
echo 'test("works", () => {})' > "$REPO/src/index.test.ts"
git -C "$REPO" add package.json src/index.test.ts
git -C "$REPO" commit -q -m "add manifest and tests"
echo 'export default {}' > "$REPO/src/index.ts"
git -C "$REPO" add src/index.ts
assert_commit_succeeds "tdd-gate: TS impl with .test.ts allows commit" "$REPO"

# Test 17: Non-code files bypass tdd-gate → commit allowed
REPO="$E2E_TMPDIR/tdd-noncode"
init_repo_tdd "$REPO" "feat/docs" "$HOOKS_DIR/tdd-gate.sh"
stage_files "$REPO" "README.md" "docs/guide.md"
assert_commit_succeeds "tdd-gate: non-code files bypass gate" "$REPO"

# Test 18: Test file itself → commit allowed (even without other tests)
REPO="$E2E_TMPDIR/tdd-testfile"
init_repo_tdd "$REPO" "feat/tests" "$HOOKS_DIR/tdd-gate.sh"
echo '[package]' > "$REPO/Cargo.toml"
mkdir -p "$REPO/tests"
git -C "$REPO" add Cargo.toml
git -C "$REPO" commit -q -m "add manifest"
echo '#[test] fn it_works() {}' > "$REPO/tests/integration.rs"
git -C "$REPO" add tests/integration.rs
assert_commit_succeeds "tdd-gate: committing a test file itself is allowed" "$REPO"

echo ""

# ── Combined Hooks E2E Tests ────────────────────────────

echo "Combined Hooks E2E Tests"
echo "========================"

# Test 19: Install both doc-gate and main-guard — behavioral on main → blocked by main-guard
REPO="$E2E_TMPDIR/combined-main-block"
init_repo "$REPO" "main" "$HOOKS_DIR/main-guard.sh"
# Chain both hooks in pre-commit
cat > "$REPO/.git/hooks/pre-commit" <<PCHOOK
#!/usr/bin/env bash
REPO_ROOT=\$(git rev-parse --show-toplevel)
JSON=\$(cat <<ENDJSON
{
  "tool_name": "Bash",
  "tool_input": {
    "command": "git commit -m 'e2e'"
  },
  "cwd": "\$REPO_ROOT"
}
ENDJSON
)

# Run main-guard first
OUTPUT=\$(echo "\$JSON" | BRANA_HOOK_PROFILE=standard bash "$HOOKS_DIR/main-guard.sh" 2>/dev/null)
if echo "\$OUTPUT" | jq -e '.hookSpecificOutput.permissionDecision == "deny"' >/dev/null 2>&1; then
    echo "MAIN-GUARD DENIED" >&2
    exit 1
fi

# Run doc-gate second
OUTPUT=\$(echo "\$JSON" | BRANA_HOOK_PROFILE=standard bash "$HOOKS_DIR/doc-gate.sh" 2>/dev/null)
if echo "\$OUTPUT" | jq -e '.hookSpecificOutput.permissionDecision == "deny"' >/dev/null 2>&1; then
    echo "DOC-GATE DENIED" >&2
    exit 1
fi

exit 0
PCHOOK
chmod +x "$REPO/.git/hooks/pre-commit"
stage_files "$REPO" "system/skills/new.md"
assert_commit_fails "combined: behavioral on main blocked (main-guard fires first)" "$REPO"

# Test 20: Both hooks on feature branch, behavioral without docs → blocked by doc-gate
REPO="$E2E_TMPDIR/combined-doc-block"
mkdir -p "$REPO"
git -C "$REPO" init -q -b main 2>/dev/null
git -C "$REPO" config user.email "test@test.com"
git -C "$REPO" config user.name "Test"
echo "init" > "$REPO/init.txt"
git -C "$REPO" add -A && git -C "$REPO" commit -q -m "init"
git -C "$REPO" checkout -q -b feat/combo
cat > "$REPO/.git/hooks/pre-commit" <<PCHOOK
#!/usr/bin/env bash
REPO_ROOT=\$(git rev-parse --show-toplevel)
JSON=\$(cat <<ENDJSON
{
  "tool_name": "Bash",
  "tool_input": {
    "command": "git commit -m 'e2e'"
  },
  "cwd": "\$REPO_ROOT"
}
ENDJSON
)

OUTPUT=\$(echo "\$JSON" | BRANA_HOOK_PROFILE=standard bash "$HOOKS_DIR/main-guard.sh" 2>/dev/null)
if echo "\$OUTPUT" | jq -e '.hookSpecificOutput.permissionDecision == "deny"' >/dev/null 2>&1; then
    echo "MAIN-GUARD DENIED" >&2
    exit 1
fi

OUTPUT=\$(echo "\$JSON" | BRANA_HOOK_PROFILE=standard bash "$HOOKS_DIR/doc-gate.sh" 2>/dev/null)
if echo "\$OUTPUT" | jq -e '.hookSpecificOutput.permissionDecision == "deny"' >/dev/null 2>&1; then
    echo "DOC-GATE DENIED" >&2
    exit 1
fi

exit 0
PCHOOK
chmod +x "$REPO/.git/hooks/pre-commit"
stage_files "$REPO" "system/hooks/hook.sh"
assert_commit_fails "combined: behavioral on feat without docs blocked (doc-gate fires)" "$REPO"

# Test 21: Both hooks on feature branch, behavioral WITH docs → allowed
REPO="$E2E_TMPDIR/combined-allow"
mkdir -p "$REPO"
git -C "$REPO" init -q -b main 2>/dev/null
git -C "$REPO" config user.email "test@test.com"
git -C "$REPO" config user.name "Test"
echo "init" > "$REPO/init.txt"
git -C "$REPO" add -A && git -C "$REPO" commit -q -m "init"
git -C "$REPO" checkout -q -b feat/combo
cat > "$REPO/.git/hooks/pre-commit" <<PCHOOK
#!/usr/bin/env bash
REPO_ROOT=\$(git rev-parse --show-toplevel)
JSON=\$(cat <<ENDJSON
{
  "tool_name": "Bash",
  "tool_input": {
    "command": "git commit -m 'e2e'"
  },
  "cwd": "\$REPO_ROOT"
}
ENDJSON
)

OUTPUT=\$(echo "\$JSON" | BRANA_HOOK_PROFILE=standard bash "$HOOKS_DIR/main-guard.sh" 2>/dev/null)
if echo "\$OUTPUT" | jq -e '.hookSpecificOutput.permissionDecision == "deny"' >/dev/null 2>&1; then
    echo "MAIN-GUARD DENIED" >&2
    exit 1
fi

OUTPUT=\$(echo "\$JSON" | BRANA_HOOK_PROFILE=standard bash "$HOOKS_DIR/doc-gate.sh" 2>/dev/null)
if echo "\$OUTPUT" | jq -e '.hookSpecificOutput.permissionDecision == "deny"' >/dev/null 2>&1; then
    echo "DOC-GATE DENIED" >&2
    exit 1
fi

exit 0
PCHOOK
chmod +x "$REPO/.git/hooks/pre-commit"
stage_files "$REPO" "system/hooks/hook.sh" "docs/architecture/hooks.md"
assert_commit_succeeds "combined: behavioral on feat with docs allowed (both hooks pass)" "$REPO"

echo ""

# ── Summary ─────────────────────────────────────────────

echo "=============================="
echo "E2E Results: $PASS/$TOTAL passed, $FAIL failed"
echo "=============================="
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
