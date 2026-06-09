#!/usr/bin/env bash
# Tests for memory-index-sync.sh PostToolUse hook.
# Simulates Write/Edit tool use on memory files and checks MEMORY.md sync.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$SCRIPT_DIR/../memory-index-sync.sh"
PASS=0
FAIL=0
TOTAL=0
TMPDIR_BASE=$(mktemp -d)

trap 'rm -rf "$TMPDIR_BASE"' EXIT

# ── Helpers ──────────────────────────────────────────────

mk_memory_dir() {
    local d="$TMPDIR_BASE/$1/memory"
    mkdir -p "$d"
    echo "$d"
}

mk_memory_file() {
    local dir="$1" name="$2" filename="$3" desc="${4:-A memory description}"
    cat > "$dir/$filename" <<EOF
---
name: $name
description: $desc
type: feedback
---

Content here.
EOF
}

write_input() {
    local tool="$1" path="$2"
    jq -n --arg t "$tool" --arg p "$path" \
        '{session_id:"s1", tool_name:$t, tool_input:{file_path:$p}, cwd:"/tmp"}'
}

assert_memory_contains() {
    local desc="$1" memory_file="$2" expected="$3"
    TOTAL=$((TOTAL + 1))
    if grep -qF "$expected" "$memory_file" 2>/dev/null; then
        echo "  PASS: $desc"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $desc"
        echo "    expected MEMORY.md to contain: $expected"
        echo "    got: $(cat "$memory_file" 2>/dev/null || echo '(missing)')"
        FAIL=$((FAIL + 1))
    fi
}

assert_memory_not_contains() {
    local desc="$1" memory_file="$2" unexpected="$3"
    TOTAL=$((TOTAL + 1))
    if ! grep -qF "$unexpected" "$memory_file" 2>/dev/null; then
        echo "  PASS: $desc"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $desc"
        echo "    expected MEMORY.md NOT to contain: $unexpected"
        FAIL=$((FAIL + 1))
    fi
}

assert_line_count() {
    local desc="$1" memory_file="$2" expected="$3"
    TOTAL=$((TOTAL + 1))
    local actual
    actual=$(grep -c "^\- \[" "$memory_file" 2>/dev/null || echo 0)
    if [ "$actual" -eq "$expected" ]; then
        echo "  PASS: $desc"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $desc"
        echo "    expected $expected pointer lines, got $actual"
        FAIL=$((FAIL + 1))
    fi
}

# ── Tests ────────────────────────────────────────────────

echo "Test: non-Write/Edit tool is ignored"
DIR=$(mk_memory_dir t1)
mk_memory_file "$DIR" "Test Pattern" "feedback_test.md"
write_input "Bash" "$DIR/feedback_test.md" | bash "$HOOK" 2>/dev/null || true
TOTAL=$((TOTAL + 1))
if [ ! -f "$DIR/MEMORY.md" ]; then
    echo "  PASS: Bash tool does not create MEMORY.md"
    PASS=$((PASS + 1))
else
    echo "  FAIL: Bash tool should not create MEMORY.md"
    FAIL=$((FAIL + 1))
fi

echo "Test: non-memory path is ignored"
DIR=$(mk_memory_dir t2)
mk_memory_file "$DIR" "Test Pattern" "feedback_test.md"
write_input "Write" "$TMPDIR_BASE/feedback_test.md" | bash "$HOOK" 2>/dev/null || true
TOTAL=$((TOTAL + 1))
if [ ! -f "$TMPDIR_BASE/MEMORY.md" ]; then
    echo "  PASS: non-memory path ignored"
    PASS=$((PASS + 1))
else
    echo "  FAIL: non-memory path should be ignored"
    FAIL=$((FAIL + 1))
fi

echo "Test: MEMORY.md itself is skipped"
DIR=$(mk_memory_dir t3)
echo "# Memory" > "$DIR/MEMORY.md"
write_input "Write" "$DIR/MEMORY.md" | bash "$HOOK" 2>/dev/null || true
# MEMORY.md content should be unchanged (only original line)
TOTAL=$((TOTAL + 1))
LINE_COUNT=$(wc -l < "$DIR/MEMORY.md")
if [ "$LINE_COUNT" -le 2 ]; then
    echo "  PASS: MEMORY.md itself not modified by hook"
    PASS=$((PASS + 1))
else
    echo "  FAIL: MEMORY.md should not be modified when it is the target file"
    FAIL=$((FAIL + 1))
fi

echo "Test: appends pointer for new memory file"
DIR=$(mk_memory_dir t4)
mk_memory_file "$DIR" "My Pattern" "feedback_my_pattern.md" "Useful pattern about X"
write_input "Write" "$DIR/feedback_my_pattern.md" | bash "$HOOK" 2>/dev/null || true
assert_memory_contains "pointer line added" "$DIR/MEMORY.md" "feedback_my_pattern.md"
assert_memory_contains "filename stem as label" "$DIR/MEMORY.md" "[feedback_my_pattern]"
assert_memory_contains "description in pointer" "$DIR/MEMORY.md" "Useful pattern about X"

echo "Test: no duplicate on second write of same file"
DIR=$(mk_memory_dir t5)
mk_memory_file "$DIR" "My Pattern" "feedback_dedup.md" "A deduplicated entry"
write_input "Write" "$DIR/feedback_dedup.md" | bash "$HOOK" 2>/dev/null || true
write_input "Write" "$DIR/feedback_dedup.md" | bash "$HOOK" 2>/dev/null || true
assert_line_count "exactly one pointer after two writes" "$DIR/MEMORY.md" 1

echo "Test: skips file without frontmatter name"
DIR=$(mk_memory_dir t6)
cat > "$DIR/feedback_no_name.md" <<'EOF'
---
type: feedback
---
No name field here.
EOF
write_input "Write" "$DIR/feedback_no_name.md" | bash "$HOOK" 2>/dev/null || true
TOTAL=$((TOTAL + 1))
if [ ! -f "$DIR/MEMORY.md" ] || ! grep -q "feedback_no_name.md" "$DIR/MEMORY.md" 2>/dev/null; then
    echo "  PASS: file without name skipped"
    PASS=$((PASS + 1))
else
    echo "  FAIL: file without name should be skipped"
    FAIL=$((FAIL + 1))
fi

echo "Test: Edit tool also triggers sync"
DIR=$(mk_memory_dir t7)
mk_memory_file "$DIR" "Edited Pattern" "feedback_edited.md" "Edited via Edit tool"
write_input "Edit" "$DIR/feedback_edited.md" | bash "$HOOK" 2>/dev/null || true
assert_memory_contains "Edit triggers sync" "$DIR/MEMORY.md" "feedback_edited.md"

echo "Test: multiple memory files accumulate"
DIR=$(mk_memory_dir t8)
mk_memory_file "$DIR" "Alpha" "feedback_alpha.md" "Alpha desc"
mk_memory_file "$DIR" "Beta" "feedback_beta.md" "Beta desc"
write_input "Write" "$DIR/feedback_alpha.md" | bash "$HOOK" 2>/dev/null || true
write_input "Write" "$DIR/feedback_beta.md" | bash "$HOOK" 2>/dev/null || true
assert_line_count "two pointers for two files" "$DIR/MEMORY.md" 2
assert_memory_contains "alpha present" "$DIR/MEMORY.md" "feedback_alpha.md"
assert_memory_contains "beta present" "$DIR/MEMORY.md" "feedback_beta.md"

echo "Test: label uses filename stem when name: frontmatter differs"
# t-1911: name: field may differ from filename stem (e.g. topic_rust-cargo-patterns.md has name: rust-cargo-patterns)
# The hook must use the filename stem as the link label, not the name: value.
DIR=$(mk_memory_dir t9)
mk_memory_file "$DIR" "rust-cargo-patterns" "topic_rust-cargo-patterns.md" "Cargo build patterns"
write_input "Write" "$DIR/topic_rust-cargo-patterns.md" | bash "$HOOK" 2>/dev/null || true
assert_memory_contains "filename stem used as label" "$DIR/MEMORY.md" "[topic_rust-cargo-patterns]"
assert_memory_not_contains "name: value not used as label" "$DIR/MEMORY.md" "[rust-cargo-patterns]"

# ── Summary ──────────────────────────────────────────────
echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
