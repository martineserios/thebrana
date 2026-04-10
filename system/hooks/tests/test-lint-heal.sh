#!/usr/bin/env bash
# Tests for lint-heal.sh — Deterministic Lint+Heal L2
# Spec: docs/architecture/features/lint-heal-deterministic.md
#
# Test strategy:
#   - All tests run against a fixture MEMORY_ROOT (mktemp -d)
#   - lint-heal.sh is invoked with LINT_HEAL_MEMORY_ROOT override
#   - --dry-run mode tested separately from live mode
#   - Layer 2 guard tested by attempting write to disallowed path

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LINT_HEAL="$SCRIPT_DIR/../../scripts/lint-heal.sh"
PASS=0
FAIL=0
TOTAL=0

TMPDIR_ROOT=$(mktemp -d)
trap 'rm -rf "$TMPDIR_ROOT"' EXIT

# ── Helpers ──────────────────────────────────────────────────

assert_eq() {
    local desc="$1" expected="$2" actual="$3"
    TOTAL=$((TOTAL + 1))
    if [ "$expected" = "$actual" ]; then
        echo "  PASS: $desc"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $desc"
        echo "    expected: [$expected]"
        echo "    got:      [$actual]"
        FAIL=$((FAIL + 1))
    fi
}

assert_contains() {
    local desc="$1" needle="$2" haystack="$3"
    TOTAL=$((TOTAL + 1))
    if echo "$haystack" | grep -qF "$needle"; then
        echo "  PASS: $desc"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $desc"
        echo "    expected to contain: [$needle]"
        echo "    in: [$haystack]"
        FAIL=$((FAIL + 1))
    fi
}

assert_not_contains() {
    local desc="$1" needle="$2" haystack="$3"
    TOTAL=$((TOTAL + 1))
    if ! echo "$haystack" | grep -qF "$needle"; then
        echo "  PASS: $desc"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $desc"
        echo "    expected NOT to contain: [$needle]"
        echo "    in: [$haystack]"
        FAIL=$((FAIL + 1))
    fi
}

assert_file_exists() {
    local desc="$1" path="$2"
    TOTAL=$((TOTAL + 1))
    if [ -f "$path" ] || [ -d "$path" ]; then
        echo "  PASS: $desc"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $desc — file not found: $path"
        FAIL=$((FAIL + 1))
    fi
}

assert_file_not_exists() {
    local desc="$1" path="$2"
    TOTAL=$((TOTAL + 1))
    if [ ! -f "$path" ]; then
        echo "  PASS: $desc"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $desc — file unexpectedly exists: $path"
        FAIL=$((FAIL + 1))
    fi
}

# Run lint-heal in a fixture environment.
# Overrides HOME to TMPDIR_ROOT so all state files are isolated.
run_lint_heal() {
    HOME="$TMPDIR_ROOT" bash "$LINT_HEAL" "$@" 2>&1
}

# Create a memory file with frontmatter in a fixture dir.
make_memory_file() {
    local dir="$1" filename="$2"
    shift 2
    # Remaining args: key=value pairs for frontmatter
    mkdir -p "$dir"
    local file="$dir/$filename"
    echo "---" > "$file"
    for kv in "$@"; do
        echo "$kv" >> "$file"
    done
    echo "---" >> "$file"
    echo "" >> "$file"
    echo "Content for $filename" >> "$file"
    echo "$file"
}

# ── Setup: build fixture MEMORY_ROOT ─────────────────────────
setup_fixture() {
    # Mirror ~/.claude/projects/ structure under TMPDIR_ROOT
    mkdir -p "$TMPDIR_ROOT/.claude/projects"
    mkdir -p "$TMPDIR_ROOT/.swarm"
}

# ═════════════════════════════════════════════════════════════
echo "lint-heal.sh Tests"
echo "=================="
# ═════════════════════════════════════════════════════════════

setup_fixture

# ──────────────────────────────────────────────────────────────
echo ""
echo "── Pass 1: Dedup ────────────────────────────────────────"
# ──────────────────────────────────────────────────────────────

# T1: dry-run does NOT delete stale file, does NOT create archive
T1_DIR=$(mktemp -d "$TMPDIR_ROOT/.claude/projects/XXXXXX")
mkdir -p "$T1_DIR/clients/nexeye/memory"
mkdir -p "$T1_DIR/projects/nexeye/memory"
STALE=$(make_memory_file "$T1_DIR/projects/nexeye/memory" "feedback_foo.md" \
    "name: foo" "type: feedback" "description: foo pattern")
CANON=$(make_memory_file "$T1_DIR/clients/nexeye/memory" "feedback_foo.md" \
    "name: foo" "type: feedback" "description: foo pattern")

OUT=$(HOME="$TMPDIR_ROOT" \
    LINT_HEAL_MEMORY_ROOT="$T1_DIR" \
    bash "$LINT_HEAL" --dry-run 2>&1) || true

assert_file_exists "T1: stale file present after dry-run" "$STALE"
assert_contains "T1: dry-run output mentions archive action" "archive" "$OUT"

# T2: live run archives stale (projects/) copy and removes it
T2_DIR=$(mktemp -d "$TMPDIR_ROOT/.claude/projects/XXXXXX")
mkdir -p "$T2_DIR/clients/nexeye/memory"
mkdir -p "$T2_DIR/projects/nexeye/memory"
STALE2=$(make_memory_file "$T2_DIR/projects/nexeye/memory" "feedback_bar.md" \
    "name: bar" "type: feedback" "description: bar pattern")
CANON2=$(make_memory_file "$T2_DIR/clients/nexeye/memory" "feedback_bar.md" \
    "name: bar" "type: feedback" "description: bar pattern")

HOME="$TMPDIR_ROOT" \
    LINT_HEAL_MEMORY_ROOT="$T2_DIR" \
    bash "$LINT_HEAL" 2>&1 || true

assert_file_not_exists "T2: stale file removed after live run" "$STALE2"
assert_file_exists     "T2: canonical file preserved" "$CANON2"
# Archive dir should contain the stale file
ARCHIVE_TODAY="$TMPDIR_ROOT/.claude/memory/archive/$(date +%Y-%m-%d)"
ARCHIVED_FILES=$(find "$ARCHIVE_TODAY" -name '*feedback_bar*' 2>/dev/null | wc -l)
assert_eq "T2: stale file archived" "1" "$ARCHIVED_FILES"

# T3: dedup skips when only one path (no duplicate)
T3_DIR=$(mktemp -d "$TMPDIR_ROOT/.claude/projects/XXXXXX")
mkdir -p "$T3_DIR/clients/nexeye/memory"
SOLO=$(make_memory_file "$T3_DIR/clients/nexeye/memory" "feedback_solo.md" \
    "name: solo" "type: feedback" "description: solo pattern")

HOME="$TMPDIR_ROOT" \
    LINT_HEAL_MEMORY_ROOT="$T3_DIR" \
    bash "$LINT_HEAL" 2>&1 || true

assert_file_exists "T3: single-copy file not touched" "$SOLO"

# T4: when both copies are in canonical (non-projects/) paths, archive the older one
T4_DIR=$(mktemp -d "$TMPDIR_ROOT/.claude/projects/XXXXXX")
mkdir -p "$T4_DIR/clients/a/memory"
mkdir -p "$T4_DIR/clients/b/memory"
OLD=$(make_memory_file "$T4_DIR/clients/a/memory" "feedback_dupe.md" \
    "name: dupe" "type: feedback" "description: dupe pattern")
# Make OLD older than NEW
touch -t 202001010000 "$OLD"
NEW=$(make_memory_file "$T4_DIR/clients/b/memory" "feedback_dupe.md" \
    "name: dupe" "type: feedback" "description: dupe pattern")

HOME="$TMPDIR_ROOT" \
    LINT_HEAL_MEMORY_ROOT="$T4_DIR" \
    bash "$LINT_HEAL" 2>&1 || true

assert_file_not_exists "T4: older duplicate archived (removed)" "$OLD"
assert_file_exists     "T4: newer duplicate preserved" "$NEW"

# ──────────────────────────────────────────────────────────────
echo ""
echo "── Pass 2: Contradiction detection ─────────────────────"
# ──────────────────────────────────────────────────────────────

# T5: contradiction flagged when ≥2 files positive + ≥2 files negative for same concept
T5_DIR=$(mktemp -d "$TMPDIR_ROOT/.claude/projects/XXXXXX")
mkdir -p "$T5_DIR/clients/p/memory"

# 2 positive files
for i in 1 2; do
cat > "$T5_DIR/clients/p/memory/feedback_pos${i}.md" <<EOF
---
name: positive-rule-${i}
type: feedback
description: use ruflo
---
Always use ruflo for memory storage.
EOF
done

# 2 negative files
for i in 1 2; do
cat > "$T5_DIR/clients/p/memory/feedback_neg${i}.md" <<EOF
---
name: negative-rule-${i}
type: feedback
description: avoid ruflo
---
Never use ruflo in this context — avoid ruflo integration here.
EOF
done

REPORT5="$TMPDIR_ROOT/.claude/lint-heal-report.md"
HOME="$TMPDIR_ROOT" \
    LINT_HEAL_MEMORY_ROOT="$T5_DIR" \
    bash "$LINT_HEAL" 2>&1 || true

assert_file_exists "T5: report written" "$REPORT5"
REPORT5_CONTENT=$(cat "$REPORT5" 2>/dev/null || echo "")
assert_contains "T5: contradiction candidate in report" "ruflo" "$REPORT5_CONTENT"

# T6: MEMORY.md excluded from contradiction scan
T6_DIR=$(mktemp -d "$TMPDIR_ROOT/.claude/projects/XXXXXX")
mkdir -p "$T6_DIR/clients/p/memory"
# MEMORY.md with contradictory-looking content
cat > "$T6_DIR/clients/p/memory/MEMORY.md" <<'EOF'
# Auto Memory
prefer foo for all operations.
avoid foo in edge cases.
prefer foo when bar is available.
avoid foo when baz is active.
EOF

# No feedback_ files at all
HOME="$TMPDIR_ROOT" \
    LINT_HEAL_MEMORY_ROOT="$T6_DIR" \
    bash "$LINT_HEAL" 2>&1 || true

REPORT6="$TMPDIR_ROOT/.claude/lint-heal-report.md"
REPORT6_CONTENT=$(cat "$REPORT6" 2>/dev/null || echo "")
assert_not_contains "T6: MEMORY.md content not in contradiction candidates" \
    "foo" "$REPORT6_CONTENT" || true
# The contradiction section should show no candidates
assert_contains "T6: no contradiction candidates from MEMORY.md" \
    "No candidates" "$REPORT6_CONTENT"

# T7: single file pair below threshold (1 pos + 1 neg) does NOT flag
T7_DIR=$(mktemp -d "$TMPDIR_ROOT/.claude/projects/XXXXXX")
mkdir -p "$T7_DIR/clients/p/memory"
cat > "$T7_DIR/clients/p/memory/feedback_one_pos.md" <<'EOF'
---
name: one-pos
type: feedback
---
Prefer uv for all Python operations.
EOF
cat > "$T7_DIR/clients/p/memory/feedback_one_neg.md" <<'EOF'
---
name: one-neg
type: feedback
---
Avoid uv in legacy envs.
EOF

HOME="$TMPDIR_ROOT" \
    LINT_HEAL_MEMORY_ROOT="$T7_DIR" \
    bash "$LINT_HEAL" 2>&1 || true

REPORT7="$TMPDIR_ROOT/.claude/lint-heal-report.md"
REPORT7_CONTENT=$(cat "$REPORT7" 2>/dev/null || echo "")
assert_contains "T7: single-pair below threshold shows no candidates" \
    "No candidates" "$REPORT7_CONTENT"

# ──────────────────────────────────────────────────────────────
echo ""
echo "── Pass 3: Frontmatter imputation ───────────────────────"
# ──────────────────────────────────────────────────────────────

# T8: missing name: field gets imputed from filename slug
T8_DIR=$(mktemp -d "$TMPDIR_ROOT/.claude/projects/XXXXXX")
mkdir -p "$T8_DIR/clients/p/memory"
cat > "$T8_DIR/clients/p/memory/feedback_my-pattern.md" <<'EOF'
---
type: feedback
description: existing description
---
Content here.
EOF

HOME="$TMPDIR_ROOT" \
    LINT_HEAL_MEMORY_ROOT="$T8_DIR" \
    bash "$LINT_HEAL" 2>&1 || true

IMPUTED=$(grep "^name:" "$T8_DIR/clients/p/memory/feedback_my-pattern.md" 2>/dev/null || echo "")
assert_contains "T8: missing name: imputed from filename" "name: my-pattern" "$IMPUTED"

# T9: missing type: imputed from filename prefix
T9_DIR=$(mktemp -d "$TMPDIR_ROOT/.claude/projects/XXXXXX")
mkdir -p "$T9_DIR/clients/p/memory"
cat > "$T9_DIR/clients/p/memory/feedback_typed.md" <<'EOF'
---
name: typed
description: typed pattern
---
Content here.
EOF

HOME="$TMPDIR_ROOT" \
    LINT_HEAL_MEMORY_ROOT="$T9_DIR" \
    bash "$LINT_HEAL" 2>&1 || true

IMPUTED9=$(grep "^type:" "$T9_DIR/clients/p/memory/feedback_typed.md" 2>/dev/null || echo "")
assert_contains "T9: missing type: imputed as feedback" "type: feedback" "$IMPUTED9"

# T10: file without frontmatter block (no ---) is NOT modified
T10_DIR=$(mktemp -d "$TMPDIR_ROOT/.claude/projects/XXXXXX")
mkdir -p "$T10_DIR/clients/p/memory"
echo "No frontmatter here." > "$T10_DIR/clients/p/memory/feedback_nofm.md"
ORIG_CONTENT=$(cat "$T10_DIR/clients/p/memory/feedback_nofm.md")

HOME="$TMPDIR_ROOT" \
    LINT_HEAL_MEMORY_ROOT="$T10_DIR" \
    bash "$LINT_HEAL" 2>&1 || true

NEW_CONTENT=$(cat "$T10_DIR/clients/p/memory/feedback_nofm.md")
assert_eq "T10: file without frontmatter block unchanged" "$ORIG_CONTENT" "$NEW_CONTENT"

# T11: dry-run does NOT modify file even with missing frontmatter fields
T11_DIR=$(mktemp -d "$TMPDIR_ROOT/.claude/projects/XXXXXX")
mkdir -p "$T11_DIR/clients/p/memory"
cat > "$T11_DIR/clients/p/memory/feedback_drytest.md" <<'EOF'
---
type: feedback
---
Content.
EOF
ORIG11=$(cat "$T11_DIR/clients/p/memory/feedback_drytest.md")

HOME="$TMPDIR_ROOT" \
    LINT_HEAL_MEMORY_ROOT="$T11_DIR" \
    bash "$LINT_HEAL" --dry-run 2>&1 || true

NEW11=$(cat "$T11_DIR/clients/p/memory/feedback_drytest.md")
assert_eq "T11: dry-run does not modify file with missing name:" "$ORIG11" "$NEW11"

# ──────────────────────────────────────────────────────────────
echo ""
echo "── Pass 4: Concept surfacing ────────────────────────────"
# ──────────────────────────────────────────────────────────────

# T12: concept with ≥10 refs and no doc appears in report
T12_DIR=$(mktemp -d "$TMPDIR_ROOT/.claude/projects/XXXXXX")
mkdir -p "$T12_DIR/clients/p/memory"
{
    echo "# Auto Memory"
    for i in $(seq 1 12); do
        echo "- Use ruflobridge for all integrations ($i)"
    done
} > "$T12_DIR/clients/p/memory/MEMORY.md"

HOME="$TMPDIR_ROOT" \
    LINT_HEAL_MEMORY_ROOT="$T12_DIR" \
    bash "$LINT_HEAL" 2>&1 || true

REPORT12="$TMPDIR_ROOT/.claude/lint-heal-report.md"
REPORT12_CONTENT=$(cat "$REPORT12" 2>/dev/null || echo "")
assert_contains "T12: high-ref undocumented concept surfaced" "ruflobridge" "$REPORT12_CONTENT"

# T13: concept with existing feedback_ doc is NOT surfaced
T13_DIR=$(mktemp -d "$TMPDIR_ROOT/.claude/projects/XXXXXX")
mkdir -p "$T13_DIR/clients/p/memory"
{
    echo "# Auto Memory"
    for i in $(seq 1 12); do
        echo "- Use documented-concept for all cases ($i)"
    done
} > "$T13_DIR/clients/p/memory/MEMORY.md"
# Create the feedback doc for this concept
make_memory_file "$T13_DIR/clients/p/memory" "feedback_documented-concept.md" \
    "name: documented-concept" "type: feedback" "description: documented" > /dev/null

HOME="$TMPDIR_ROOT" \
    LINT_HEAL_MEMORY_ROOT="$T13_DIR" \
    bash "$LINT_HEAL" 2>&1 || true

REPORT13="$TMPDIR_ROOT/.claude/lint-heal-report.md"
REPORT13_CONTENT=$(cat "$REPORT13" 2>/dev/null || echo "")
assert_not_contains "T13: documented concept NOT surfaced" \
    "documented-concept" "$REPORT13_CONTENT"

# ──────────────────────────────────────────────────────────────
echo ""
echo "── Safety invariants ────────────────────────────────────"
# ──────────────────────────────────────────────────────────────

# T14: rollback snapshot created before any writes
T14_DIR=$(mktemp -d "$TMPDIR_ROOT/.claude/projects/XXXXXX")
mkdir -p "$T14_DIR/clients/p/memory"
make_memory_file "$T14_DIR/clients/p/memory" "feedback_x.md" \
    "name: x" "type: feedback" "description: x" > /dev/null

HOME="$TMPDIR_ROOT" \
    LINT_HEAL_MEMORY_ROOT="$T14_DIR" \
    bash "$LINT_HEAL" 2>&1 || true

SNAPSHOT="$TMPDIR_ROOT/.claude/memory/pre-lint-heal-$(date +%Y-%m-%d)"
assert_file_exists "T14: rollback snapshot directory created" "$SNAPSHOT/."

# T15: state file written after successful run
T15_DIR=$(mktemp -d "$TMPDIR_ROOT/.claude/projects/XXXXXX")
mkdir -p "$T15_DIR/clients/p/memory"
make_memory_file "$T15_DIR/clients/p/memory" "feedback_y.md" \
    "name: y" "type: feedback" "description: y" > /dev/null

HOME="$TMPDIR_ROOT" \
    LINT_HEAL_MEMORY_ROOT="$T15_DIR" \
    bash "$LINT_HEAL" 2>&1 || true

STATE="$TMPDIR_ROOT/.swarm/lint-heal-state.json"
assert_file_exists "T15: state file written after run" "$STATE"
STATE_CONTENT=$(cat "$STATE" 2>/dev/null || echo "")
assert_contains "T15: state has last_run_ts" "last_run_ts" "$STATE_CONTENT"
assert_contains "T15: state resets session_count_since_run to 0" \
    '"session_count_since_run": 0' "$STATE_CONTENT"

# T16: dry-run does NOT write state file
T16_DIR=$(mktemp -d "$TMPDIR_ROOT/.claude/projects/XXXXXX")
mkdir -p "$T16_DIR/clients/p/memory"
make_memory_file "$T16_DIR/clients/p/memory" "feedback_z.md" \
    "name: z" "type: feedback" "description: z" > /dev/null
rm -f "$TMPDIR_ROOT/.swarm/lint-heal-state.json"

HOME="$TMPDIR_ROOT" \
    LINT_HEAL_MEMORY_ROOT="$T16_DIR" \
    bash "$LINT_HEAL" --dry-run 2>&1 || true

assert_file_not_exists "T16: dry-run does NOT write state file" \
    "$TMPDIR_ROOT/.swarm/lint-heal-state.json"

# T17: second invocation with live lock aborts with non-zero exit
T17_DIR=$(mktemp -d "$TMPDIR_ROOT/.claude/projects/XXXXXX")
mkdir -p "$T17_DIR/clients/p/memory"
echo "$$" > "$TMPDIR_ROOT/.swarm/lint-heal.lock"  # fake live lock (current PID = always alive)

EXIT_CODE=0
HOME="$TMPDIR_ROOT" \
    LINT_HEAL_MEMORY_ROOT="$T17_DIR" \
    bash "$LINT_HEAL" 2>/dev/null || EXIT_CODE=$?

assert_eq "T17: live lock causes non-zero exit" "1" "$EXIT_CODE"
rm -f "$TMPDIR_ROOT/.swarm/lint-heal.lock"

# ──────────────────────────────────────────────────────────────
echo ""
echo "── Results ──────────────────────────────────────────────"
echo "  Total: $TOTAL  Pass: $PASS  Fail: $FAIL"
if [ "$FAIL" -gt 0 ]; then
    echo "FAILED"
    exit 1
else
    echo "PASSED"
    exit 0
fi
