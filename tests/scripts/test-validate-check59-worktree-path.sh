#!/usr/bin/env bash
# Unit test for Check 59: worktree paths must be inside $HOME/enter_thebrana/ (t-2081).
#
# A stray worktree (e.g. ~/thebrana-t-NNN vs ~/enter_thebrana/thebrana-t-NNN)
# fails silently at creation; the error surfaces only at file-copy time.
# (Field note 2026-06-13 / worktree-wrong-path-surfaces-at-copy-time)
#
# Tests:
#   T1 — only main worktree present → no violation
#   T2 — extra worktree inside enter_thebrana/ → no violation
#   T3 — extra worktree outside enter_thebrana/ → violation emitted
#   T4 — main worktree (first entry) outside enter_thebrana/ is NOT flagged
#   T5 — mixed set (one good, one stray) → stray flagged only

set -uo pipefail

PASS=0
FAIL=0
TOTAL=0

assert_empty() {
    local desc="$1" result="$2"
    TOTAL=$((TOTAL + 1))
    if [ -z "$result" ]; then
        echo "  PASS: $desc"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $desc — expected no violation, got: $result"
        FAIL=$((FAIL + 1))
    fi
}

assert_contains() {
    local desc="$1" result="$2" needle="$3"
    TOTAL=$((TOTAL + 1))
    if echo "$result" | grep -qF "$needle"; then
        echo "  PASS: $desc"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $desc — expected '$needle' in output, got: $result"
        FAIL=$((FAIL + 1))
    fi
}

FAKE_HOME="/home/testuser"
EXPECTED_PREFIX="$FAKE_HOME/enter_thebrana/"

# Inline reproduction of Check 59 parse logic from validate.sh.
# Input: path to file containing porcelain output, expected path prefix.
# Output: lines for each violating worktree path (non-main, outside prefix).
check59_violations() {
    local porcelain_file="$1"
    local expected_prefix="$2"
    local skip_first=true

    while IFS= read -r line; do
        if [[ "$line" == worktree\ * ]]; then
            local wt_path="${line#worktree }"
            if $skip_first; then
                skip_first=false
                continue
            fi
            if [[ "$wt_path" != "$expected_prefix"* ]]; then
                echo "$wt_path"
            fi
        fi
    done < "$porcelain_file"
}

# Helpers to build mock porcelain output blocks.
# Each block is written to a temp file to preserve blank-line separators between
# worktree entries ($() subshell would strip trailing newlines, merging blocks).
PORCELAIN_TMP=$(mktemp)
trap 'rm -f "$PORCELAIN_TMP"' EXIT

write_porcelain_main() {
    printf 'worktree %s/enter_thebrana/thebrana\nHEAD abc123\nbranch refs/heads/main\n\n' "$FAKE_HOME" > "$PORCELAIN_TMP"
}

write_porcelain_good_extra() {
    write_porcelain_main
    printf 'worktree %s/enter_thebrana/thebrana-t-2081\nHEAD abc123\nbranch refs/heads/feat/t-2081\n\n' "$FAKE_HOME" >> "$PORCELAIN_TMP"
}

write_porcelain_bad_extra() {
    write_porcelain_main
    printf 'worktree %s/thebrana-t-2080\nHEAD abc123\nbranch refs/heads/feat/t-2080\n\n' "$FAKE_HOME" >> "$PORCELAIN_TMP"
}

write_porcelain_mixed() {
    write_porcelain_good_extra
    printf 'worktree %s/thebrana-t-2080\nHEAD abc123\nbranch refs/heads/feat/t-2080\n\n' "$FAKE_HOME" >> "$PORCELAIN_TMP"
}

echo "=== Check 59: Worktree Path Convention (t-2081) ==="
echo ""

echo "=== T1: only main worktree ==="
write_porcelain_main
result=$(check59_violations "$PORCELAIN_TMP" "$EXPECTED_PREFIX")
assert_empty "T1: only main worktree — no violation" "$result"

echo "=== T2: extra worktree inside enter_thebrana/ ==="
write_porcelain_good_extra
result=$(check59_violations "$PORCELAIN_TMP" "$EXPECTED_PREFIX")
assert_empty "T2: correctly-placed extra worktree — no violation" "$result"

echo "=== T3: extra worktree outside enter_thebrana/ ==="
write_porcelain_bad_extra
result=$(check59_violations "$PORCELAIN_TMP" "$EXPECTED_PREFIX")
assert_contains "T3: stray worktree path is detected" "$result" "${FAKE_HOME}/thebrana-t-2080"

echo "=== T4: main worktree outside enter_thebrana/ is never flagged ==="
printf 'worktree %s/thebrana\nHEAD abc123\nbranch refs/heads/main\n\n' "$FAKE_HOME" > "$PORCELAIN_TMP"
result=$(check59_violations "$PORCELAIN_TMP" "$EXPECTED_PREFIX")
assert_empty "T4: first entry skipped regardless of path" "$result"

echo "=== T5: mixed — one good, one stray ==="
write_porcelain_mixed
result=$(check59_violations "$PORCELAIN_TMP" "$EXPECTED_PREFIX")
assert_contains "T5: stray worktree detected in mixed set" "$result" "${FAKE_HOME}/thebrana-t-2080"

echo ""
echo "=== Results: $PASS passed, $FAIL failed, $TOTAL total ==="
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
