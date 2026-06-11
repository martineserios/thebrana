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
check "project marshalled" "1" "$(echo "$QJSON" | grep -c testproj)"
check "git_range recorded" "1" "$(echo "$QJSON" | grep -c '\.\.')"
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
H4="$TMPDIR/home4"; mkdir -p "$H4"
stderr_file="$TMPDIR/stderr"
rc=99
HOME="$H4" BRANA="$TMPDIR/missing" PATH="/usr/bin:/bin" bash "$SNAP" --git-root "$R1" --branch feat/x --project p --commit-count 1 >/dev/null 2>"$stderr_file" && rc=0 || rc=$?
check "missing binary exits 0" "0" "$rc"
check "missing binary warns" "yes" "$([ -s "$stderr_file" ] && echo yes || echo no)"

# ── 6. no jq in the script (queue is Rust-owned) ──────────────────────
check "no jq calls in script" "0" "$(grep -v '^\s*#' "$SNAP" | grep -c '\bjq\b')"

echo ""
echo "test-close-snapshot: $PASS/$TOTAL passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
