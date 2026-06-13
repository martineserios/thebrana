#!/usr/bin/env bash
# Tests: system/scripts/close-snapshot.sh — Track 1 close-instant snapshot + queue (t-1973, ADR-052).
# Verifies: diff snapshot saved + queue entry appended; 500KB cap sets
# --snapshot-truncated; zero-commit sessions skip cleanly; missing brana
# binary degrades to warn + exit 0 (close never blocks).

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SNAP="$SCRIPT_DIR/../../scripts/close-snapshot.sh"
PASS=0
FAIL=0
TOTAL=0
TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

REAL_BRANA="$SCRIPT_DIR/../../cli/rust/target/release/brana"
[ -x "$REAL_BRANA" ] || REAL_BRANA="$(command -v brana)"

check() {
    local desc="$1" expected="$2" actual="$3"
    TOTAL=$((TOTAL + 1))
    if [ "$expected" = "$actual" ]; then
        PASS=$((PASS + 1))
    else
        FAIL=$((FAIL + 1))
        echo "FAIL: $desc"
        echo "  expected: $expected"
        echo "  actual:   $actual"
    fi
}

make_repo() {
    local dir="$1" commits="$2" filesize="${3:-10}"
    mkdir -p "$dir"
    git -C "$dir" init -q -b main
    git -C "$dir" config user.email t@t.com
    git -C "$dir" config user.name T
    echo base > "$dir/base.txt"
    git -C "$dir" add -A && git -C "$dir" commit -qm "base"
    for i in $(seq 1 "$commits"); do
        head -c "$filesize" /dev/urandom | base64 > "$dir/f$i.txt"
        git -C "$dir" add -A && git -C "$dir" commit -qm "commit $i"
    done
}

if [ ! -f "$SNAP" ]; then
    echo "FAIL: $SNAP does not exist"
    exit 1
fi

# ── 1. happy path: 2 commits → snapshot file + queue entry ───────────
H1="$TMPDIR/home1"; mkdir -p "$H1"
R1="$TMPDIR/repo1"; make_repo "$R1" 2
out=$(HOME="$H1" BRANA="$REAL_BRANA" bash "$SNAP" --git-root "$R1" --branch feat/test --project testproj --commit-count 2 2>&1)
rc=$?
check "exits 0 on happy path" "0" "$rc"
check "snapshot file created" "1" "$(ls "$H1/.claude/sessions/"snap-*.diff 2>/dev/null | wc -l | tr -d ' ')"
QJSON=$(HOME="$H1" "$REAL_BRANA" close-queue list)
check "queue entry created" "1" "$(echo "$QJSON" | grep -c '"id"')"
check "project marshalled" "1" "$(echo "$QJSON" | grep -c '"project": "testproj"')"
check "git_range recorded" "1" "$(echo "$QJSON" | grep -c '"git_range"')"
check "not truncated" "1" "$(echo "$QJSON" | grep -c '"snapshot_truncated": false')"
# snapshot content is a real diff
SNAPFILE=$(ls "$H1/.claude/sessions/"snap-*.diff | head -1)
check "snapshot contains diff" "1" "$(grep -c '^diff --git' "$SNAPFILE" | head -1 | awk '{print ($1>0)?1:0}')"

# ── 2. dedup: running twice for same range → still one entry ─────────
HOME="$H1" BRANA="$REAL_BRANA" bash "$SNAP" --git-root "$R1" --branch feat/test --project testproj --commit-count 2 >/dev/null 2>&1
check "second run dedups" "1" "$(HOME="$H1" "$REAL_BRANA" close-queue list | grep -c '"id"')"

# ── 3. 500KB cap → truncated flag ─────────────────────────────────────
H2="$TMPDIR/home2"; mkdir -p "$H2"
R2="$TMPDIR/repo2"; make_repo "$R2" 1 800000
HOME="$H2" BRANA="$REAL_BRANA" bash "$SNAP" --git-root "$R2" --branch feat/big --project testproj --commit-count 1 >/dev/null 2>&1
check "big diff exits 0" "0" "$?"
check "truncated flag set" "1" "$(HOME="$H2" "$REAL_BRANA" close-queue list | grep -c '"snapshot_truncated": true')"
BIGSNAP=$(ls "$H2/.claude/sessions/"snap-*.diff | head -1)
SIZE=$(stat -c %s "$BIGSNAP")
check "snapshot capped at ~500KB" "1" "$([ "$SIZE" -le 512000 ] && echo 1 || echo 0)"

# ── 4. zero commits → no snapshot, no queue entry, exit 0 ────────────
H3="$TMPDIR/home3"; mkdir -p "$H3"
R3="$TMPDIR/repo3"; make_repo "$R3" 0
HOME="$H3" BRANA="$REAL_BRANA" bash "$SNAP" --git-root "$R3" --branch main --project testproj --commit-count 0 >/dev/null 2>&1
check "zero commits exits 0" "0" "$?"
check "zero commits writes no queue" "0" "$(HOME="$H3" "$REAL_BRANA" close-queue list | grep -c '"id"')"

# ── 5. missing binary → warn stderr, exit 0, close never blocks ──────
# Copy the script to an isolated dir so its sibling-release-build fallback
# cannot resolve — only $BRANA and PATH remain, both dead ends here.
H4="$TMPDIR/home4"; mkdir -p "$H4"
ISO="$TMPDIR/iso"; mkdir -p "$ISO"
cp "$SNAP" "$ISO/close-snapshot.sh"
stderr_file="$TMPDIR/stderr"
rc=99
HOME="$H4" BRANA="$TMPDIR/missing" PATH="/usr/bin:/bin" bash "$ISO/close-snapshot.sh" --git-root "$R1" --branch feat/x --project p --commit-count 1 >/dev/null 2>"$stderr_file" && rc=0 || rc=$?
check "missing binary exits 0" "0" "$rc"
check "missing binary warns" "yes" "$([ -s "$stderr_file" ] && echo yes || echo no)"

# ── 6. no jq in the script (queue is Rust-owned) ──────────────────────
check "no jq calls in script" "0" "$(grep -v '^\s*#' "$SNAP" | grep -c '\bjq\b')"

# ── 7. hunk-boundary cut: truncation never splits a diff --git section ─
# 3 commits each with ~200KB file → total diff ~810KB, cap at 512KB.
H5="$TMPDIR/home5"; mkdir -p "$H5"
R5="$TMPDIR/repo5"; make_repo "$R5" 3 200000
HOME="$H5" BRANA="$REAL_BRANA" bash "$SNAP" --git-root "$R5" --branch feat/big3 --project testproj --commit-count 3 >/dev/null 2>&1
SNAPFILE7=$(ls "$H5/.claude/sessions/"snap-*.diff 2>/dev/null | head -1)
FULL_DIFF_SECTIONS=$(git -C "$R5" diff HEAD~3..HEAD 2>/dev/null | grep -c "^diff --git" || echo 0)
TRUNC_SECTIONS=$(grep -c "^diff --git" "$SNAPFILE7" 2>/dev/null || echo 0)
check "hunk-boundary cut drops at least one section" "1" "$([ "${TRUNC_SECTIONS:-0}" -lt "${FULL_DIFF_SECTIONS:-0}" ] && echo 1 || echo 0)"
# The last section in the truncated file must be complete (has index line).
LAST_DIFF_LINE=$(grep -n "^diff --git" "$SNAPFILE7" 2>/dev/null | tail -1 | cut -d: -f1)
if [ -n "$LAST_DIFF_LINE" ]; then
    HAS_INDEX=$(tail -n +"$LAST_DIFF_LINE" "$SNAPFILE7" | grep -c "^index " || echo 0)
else
    HAS_INDEX=0
fi
check "last section in truncated file is complete" "1" "$([ "${HAS_INDEX:-0}" -gt 0 ] && echo 1 || echo 0)"

# ── 8. omitted_files populated in queue entry when truncated ───────────
QJSON7=$(HOME="$H5" "$REAL_BRANA" close-queue list 2>/dev/null || echo "[]")
OMITTED_COUNT=$(echo "$QJSON7" | python3 -c "
import json, sys
data = json.load(sys.stdin)
e = data[0] if data else {}
files = e.get('omitted_files') or []
print(len(files))
" 2>/dev/null || echo "0")
check "omitted_files populated when truncated" "1" "$([ "${OMITTED_COUNT:-0}" -gt 0 ] && echo 1 || echo 0)"

echo ""
echo "test-close-snapshot: $PASS/$TOTAL passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
