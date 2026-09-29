#!/usr/bin/env bash
# Tests for system/hooks/lib/portable.sh — GNU (native) and simulated-BSD PATH.
# Run: bash tests/hooks/test-portable.sh

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
LIB="$REPO_ROOT/system/hooks/lib/portable.sh"
_BSD_REAL_PATH="$PATH"
# shellcheck source=../lib/bsd-path.sh
source "$REPO_ROOT/tests/lib/bsd-path.sh"

PASS=0; FAIL=0
assert() {
    local desc="$1" expected="$2" actual="$3"
    if [ "$expected" = "$actual" ]; then PASS=$((PASS+1)); echo "  PASS: $desc"
    else FAIL=$((FAIL+1)); echo "  FAIL: $desc (expected '$expected', got '$actual')"; fi
}

TMP="$(mktemp -d)"; BSD_BIN="$(make_bsd_bin)"
trap 'rm -rf "$TMP" "$BSD_BIN"' EXIT

echo "=== test-portable.sh ==="
[ -f "$LIB" ] || { echo "  FAIL: $LIB missing"; exit 1; }

# Run one snippet in a fresh bash under the given PATH ("native" | "bsd").
run_in() {
    local mode="$1" snippet="$2" path="$PATH"
    [ "$mode" = bsd ] && path="$BSD_BIN"
    PATH="$path" bash -c "source '$LIB'; $snippet" 2>&1
}

printf 'hello\n' >"$TMP/f.txt"
ln -s "$TMP/f.txt" "$TMP/link.txt"
touch -d '2024-01-02 03:04:05 UTC' "$TMP/f.txt"

for mode in native bsd; do
    echo "--- mode: $mode ---"

    if [ "$mode" = bsd ]; then
        # Guard the guard: the simulated PATH must really be BSD-shaped, or the
        # fallback branches below would be silently untested.
        assert "bsd: sanity — rejects date -d / stat -c / sed -i / readlink -f" "1111" \
            "$(PATH="$BSD_BIN"; date -d 2024-01-01 >/dev/null 2>&1; a=$?; stat -c %s /etc >/dev/null 2>&1; b=$?; sed -i s/a/b/ /dev/null >/dev/null 2>&1; c=$?; readlink -f / >/dev/null 2>&1; d=$?; echo $a$b$c$d)"
        assert "bsd: sanity — flock and sha256sum absent" "11" \
            "$(PATH="$BSD_BIN"; command -v flock >/dev/null 2>&1; a=$?; command -v sha256sum >/dev/null 2>&1; echo $a$?)"
    fi

    assert "$mode: p_sha256 file" \
        "5891b5b522d5df086d0ff0b110fbd9d21bb4fc7163af34d08286a2e846f6be03" \
        "$(run_in $mode "p_sha256 '$TMP/f.txt'")"
    assert "$mode: p_sha256 stdin" \
        "5891b5b522d5df086d0ff0b110fbd9d21bb4fc7163af34d08286a2e846f6be03" \
        "$(run_in $mode "printf 'hello\n' | p_sha256")"
    assert "$mode: p_md5 file" "b1946ac92492d2347c6235b4d2611184" \
        "$(run_in $mode "p_md5 '$TMP/f.txt'")"

    assert "$mode: p_stat_mtime" "1704164645" "$(run_in $mode "p_stat_mtime '$TMP/f.txt'")"
    assert "$mode: p_stat_size"  "6"          "$(run_in $mode "p_stat_size '$TMP/f.txt'")"
    assert "$mode: p_stat_atime" "1704164645" "$(touch -a -d '2024-01-02 03:04:05 UTC' "$TMP/f.txt"; run_in $mode "p_stat_atime '$TMP/f.txt'")"

    assert "$mode: p_date_d @epoch"    "1704164645" "$(run_in $mode "p_date_d @1704164645")"
    assert "$mode: p_date_d ISO date"  "1704153600" "$(run_in $mode "p_date_d 2024-01-02")"
    assert "$mode: p_date_d ISO Z"     "1704164645" "$(run_in $mode "p_date_d 2024-01-02T03:04:05Z")"
    assert "$mode: p_date_d fmt"       "2024-01-02" "$(run_in $mode "p_date_d 2024-01-02T03:04:05Z %Y-%m-%d")"
    assert "$mode: p_date_d N days ago" "86400" \
        "$(run_in $mode "a=\$(p_date_d '2 days ago'); b=\$(p_date_d '1 day ago'); echo \$((b-a))")"
    # git %ci style (space + numeric offset), colon offset, fractional seconds
    assert "$mode: p_date_d git %ci offset"   "1704164645" "$(run_in $mode "p_date_d '2024-01-02 05:04:05 +0200'")"
    assert "$mode: p_date_d colon offset"     "1704164645" "$(run_in $mode "p_date_d '2024-01-01T22:04:05-05:00'")"
    assert "$mode: p_date_d fractional secs"  "1704164645" "$(run_in $mode "p_date_d '2024-01-02T03:04:05.987Z'")"
    assert "$mode: p_date_d minutes only"     "1704164640" "$(run_in $mode "p_date_d '2024-01-02T03:04Z'")"
    # local-time formatting (display use): honours TZ on both paths
    assert "$mode: p_epoch_fmt local TZ"      "12:04" "$(run_in $mode "TZ=Asia/Tokyo p_epoch_fmt 1704164645 %H:%M")"
    assert "$mode: p_epoch_fmt UTC"           "03:04" "$(run_in $mode "TZ=UTC p_epoch_fmt 1704164645 %H:%M")"
    assert "$mode: p_date_d garbage rc=1" "1" "$(run_in $mode "p_date_d 'not a date' >/dev/null 2>&1; echo \$?")"

    printf 'a b a\n' >"$TMP/s.txt"
    run_in $mode "p_sed_i 's/a/X/g' '$TMP/s.txt'" >/dev/null
    assert "$mode: p_sed_i edits in place" "X b X" "$(cat "$TMP/s.txt")"
    assert "$mode: p_sed_i leaves no backup" "" "$(ls "$TMP" | grep -E '\.(bak|tmp)$' || true)"

    assert "$mode: p_readlink_f symlink" "$(cd "$TMP" && pwd -P)/f.txt" \
        "$(run_in $mode "p_readlink_f '$TMP/link.txt'")"
    assert "$mode: p_readlink_f relative dir" "$(cd "$TMP" && pwd -P)" \
        "$(run_in $mode "cd '$TMP' && p_readlink_f .")"

    # flock: runs command, returns its rc
    assert "$mode: p_flock runs cmd" "ran" "$(run_in $mode "p_flock '$TMP/l1.lock' echo ran")"
    assert "$mode: p_flock runs shell functions" "fn-ran" \
        "$(run_in $mode "f() { echo fn-ran; }; p_flock '$TMP/lf.lock' f")"
    assert "$mode: p_flock propagates rc" "7" "$(run_in $mode "p_flock '$TMP/l2.lock' bash -c 'exit 7'; echo \$?")"
    # mutual exclusion: while a holder sleeps, -n from another process fails with 1
    run_in $mode "p_flock '$TMP/l3.lock' sleep 2" >/dev/null &
    HOLDER=$!; sleep 0.5
    assert "$mode: p_flock -n fails while held" "1" "$(run_in $mode "p_flock -n '$TMP/l3.lock' echo nope >/dev/null 2>&1; echo \$?")"
    wait $HOLDER
    assert "$mode: p_flock -n ok after release" "ok" "$(run_in $mode "p_flock -n '$TMP/l3.lock' echo ok")"
    # fd-style locks: p_lock_acquire FD FILE [-n|-w SECS] / p_lock_release FD FILE
    assert "$mode: lock acquire+release" "in out" \
        "$(run_in $mode "p_lock_acquire 9 '$TMP/k1.lock' && echo -n in; p_lock_release 9 '$TMP/k1.lock' && echo ' out'")"
    run_in $mode "p_lock_acquire 9 '$TMP/k2.lock'; sleep 2; p_lock_release 9 '$TMP/k2.lock'" >/dev/null &
    HOLDER=$!; sleep 0.5
    assert "$mode: lock -n fails while held"   "1" "$(run_in $mode "p_lock_acquire 8 '$TMP/k2.lock' -n; echo \$?")"
    assert "$mode: lock -w 1 times out"        "1" "$(run_in $mode "p_lock_acquire 8 '$TMP/k2.lock' -w 1; echo \$?")"
    assert "$mode: lock -w 5 waits then wins"  "0" "$(run_in $mode "p_lock_acquire 8 '$TMP/k2.lock' -w 5; echo \$?")"
    wait $HOLDER
    # lock is per-FILE, fd number is caller's business; released lock reacquirable
    assert "$mode: lock reacquire after release" "0" "$(run_in $mode "p_lock_acquire 7 '$TMP/k2.lock' -n; echo \$?")"
    # stale lock (dead pid) must not wedge the fallback
    if [ "$mode" = bsd ]; then
        mkdir "$TMP/l4.lock.d"; echo 999999 >"$TMP/l4.lock.d/pid"
        assert "$mode: p_flock recovers stale lock" "ok" "$(run_in $mode "p_flock -n '$TMP/l4.lock' echo ok")"
    fi
done

echo; echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
