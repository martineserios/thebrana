#!/usr/bin/env bash
# Regression test: knowledge-backup invocation must not swallow a non-zero
# exit from backup-knowledge.sh (t-2796).
#
# brana-knowledge/backup.sh correctly exits 1 and prints
# "WARNING: Backup integrity check failed: ..." when PRAGMA integrity_check
# finds a corrupt page. But every documented call site in this repo invoked
# it as `"$HOME/.claude/scripts/backup-knowledge.sh" 2>/dev/null || true` —
# the `2>/dev/null` discards the WARNING text and `|| true` forces exit 0
# regardless of outcome, so real DB corruption was silently invisible
# unless someone happened to read raw transcript output.
#
# This test asserts run_knowledge_backup():
#   - exit 0 case  → returns 0, prints nothing to stderr
#   - exit 1 case  → returns 1 (non-zero — NOT swallowed), and the
#                    underlying script's diagnostic text reaches stderr
#
# The function under test is extracted from
# system/skills/_shared/backup-knowledge-invoke.md so this test exercises
# the shipped source, not a copy (t-1978 rot class).
#
# Run: bash tests/procedures/test-backup-knowledge-invoke.sh

set -uo pipefail

PASS=0
FAIL=0
TOTAL=0

assert_eq() {
    local desc="$1" expected="$2" actual="$3"
    TOTAL=$((TOTAL + 1))
    if [ "$expected" = "$actual" ]; then
        echo "  PASS: $desc"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $desc — expected [$expected], got [$actual]"
        FAIL=$((FAIL + 1))
    fi
}

assert_contains() {
    local desc="$1" haystack="$2" needle="$3"
    TOTAL=$((TOTAL + 1))
    if [[ "$haystack" == *"$needle"* ]]; then
        echo "  PASS: $desc"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $desc — expected to find [$needle] in [$haystack]"
        FAIL=$((FAIL + 1))
    fi
}

echo "=== test-backup-knowledge-invoke.sh ==="
echo ""

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
INVOKE_MD="$REPO_ROOT/system/skills/_shared/backup-knowledge-invoke.md"

if [ ! -f "$INVOKE_MD" ]; then
    echo "ERROR: $INVOKE_MD not found"
    exit 1
fi

# Extract the marked block (same convention as epic-ancestor-walk.md)
BLOCK=$(awk '/<!-- BACKUP-KNOWLEDGE-INVOKE-BLOCK -->/{flag=1;next}/<!-- \/BACKUP-KNOWLEDGE-INVOKE-BLOCK -->/{flag=0}flag' "$INVOKE_MD")
if [ -z "$BLOCK" ]; then
    echo "ERROR: BACKUP-KNOWLEDGE-INVOKE-BLOCK not found or empty in $INVOKE_MD"
    exit 1
fi
# Strip the ```bash / ``` fences the block is written inside
BLOCK=$(printf '%s\n' "$BLOCK" | sed '/^```/d')

eval "$BLOCK"

if ! declare -F run_knowledge_backup >/dev/null; then
    echo "ERROR: run_knowledge_backup() not defined after sourcing extracted block"
    exit 1
fi

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

# --- Case A: underlying script exits 0 (healthy backup) ---
cat > "$TMPDIR/ok.sh" <<'EOF'
#!/usr/bin/env bash
echo "ReasoningBank: 42 entries, 3 patterns (1.2M)"
exit 0
EOF
chmod +x "$TMPDIR/ok.sh"

stderr_ok=$(BACKUP_KNOWLEDGE_SCRIPT="$TMPDIR/ok.sh" bash -c "$(declare -f run_knowledge_backup); run_knowledge_backup" 2>&1 1>/dev/null)
rc_ok=0
BACKUP_KNOWLEDGE_SCRIPT="$TMPDIR/ok.sh" bash -c "$(declare -f run_knowledge_backup); run_knowledge_backup" >/dev/null 2>&1 || rc_ok=$?

assert_eq "healthy backup returns exit 0" "0" "$rc_ok"
assert_eq "healthy backup prints no warning to stderr" "" "$stderr_ok"

# --- Case B: underlying script exits 1 (corrupt DB) ---
cat > "$TMPDIR/corrupt.sh" <<'EOF'
#!/usr/bin/env bash
echo "WARNING: Backup integrity check failed: *** in database main *** Tree 95 page 95 cell 0: btreeInitPage() returns error code 11"
exit 1
EOF
chmod +x "$TMPDIR/corrupt.sh"

rc_corrupt=0
BACKUP_KNOWLEDGE_SCRIPT="$TMPDIR/corrupt.sh" bash -c "$(declare -f run_knowledge_backup); run_knowledge_backup" >/dev/null 2>&1 || rc_corrupt=$?
stderr_corrupt=$(BACKUP_KNOWLEDGE_SCRIPT="$TMPDIR/corrupt.sh" bash -c "$(declare -f run_knowledge_backup); run_knowledge_backup" 2>&1 1>/dev/null)

assert_eq "corrupt DB is NOT swallowed — returns non-zero" "1" "$rc_corrupt"
assert_contains "corrupt DB warning reaches stderr" "$stderr_corrupt" "btreeInitPage"
assert_contains "corrupt DB stderr flags the failure clearly" "$stderr_corrupt" "backup-knowledge.sh failed"

echo ""
echo "=== $PASS/$TOTAL passed ==="
[ "$FAIL" -eq 0 ]
