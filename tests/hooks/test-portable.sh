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
        assert "bsd: sanity — timeout/gtimeout/realpath/tac absent, date -I and %N unsupported" "11111" \
            "$(PATH="$BSD_BIN"; a=1; for c in timeout gtimeout realpath tac; do command -v $c >/dev/null 2>&1 && a=0; done; date -Iseconds >/dev/null 2>&1; b=$?; [ "$(date +%N)" = N ]; c=$((1-$?)); echo $a$b$c$a$a)"
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
    assert "$mode: p_stat_mode (octal perms)" "640" "$(chmod 640 "$TMP/f.txt"; run_in $mode "p_stat_mode '$TMP/f.txt'")"
    assert "$mode: p_stat_mode dir" "750" "$(mkdir -p "$TMP/md" && chmod 750 "$TMP/md"; run_in $mode "p_stat_mode '$TMP/md'")"
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

# ── second-tier shims (t-3377) ─────────────────────────────────────────────
mkdir -p "$TMP/rp/real/sub"; ln -s "$TMP/rp/real" "$TMP/rp/lnk"
for mode in native bsd; do
    echo "--- second tier: $mode ---"
    # p_timeout
    assert "$mode: p_timeout passes rc" "7" "$(run_in $mode "p_timeout 5 bash -c 'exit 7'; echo \$?")"
    assert "$mode: p_timeout fast cmd output" "ok" "$(run_in $mode "p_timeout 5 echo ok")"
    assert "$mode: p_timeout kills slow cmd, rc 124" "124" "$(run_in $mode "p_timeout 1 sleep 5; echo \$?")"
    assert "$mode: p_timeout -k form" "124" "$(run_in $mode "p_timeout -k 1 1 sleep 5; echo \$?")"
    # GNU timeout reports 137 when it had to KILL; the fallback reports 124 — either means "timed out".
    assert "$mode: p_timeout -k escalates past a TERM-ignoring cmd" "timed-out" \
        "$(rc=$(run_in $mode "p_timeout -k 1 1 bash -c 'trap \"\" TERM; sleep 9'; echo \$?"); case $rc in 124|137) echo timed-out;; *) echo "rc=$rc";; esac)"
    assert "$mode: p_timeout preserves stdin" "piped" "$(printf 'piped\n' | PATH="$([ $mode = bsd ] && echo "$BSD_BIN" || echo "$PATH")" bash -c "source '$LIB'; p_timeout 5 cat")"
    assert "$mode: p_timeout is silent on stderr" "" "$(run_in $mode "p_timeout 1 sleep 5" 2>&1)"
    t0=$SECONDS; run_in $mode "x=\$(p_timeout 30 echo hi); echo \$x" >/dev/null; dt=$((SECONDS - t0))
    assert "$mode: p_timeout in \$(...) does not wait out the timeout" "fast" "$([ $dt -lt 5 ] && echo fast || echo "slow:${dt}s")"
    assert "$mode: p_timeout leaves no orphan watchdog sleeping" "0" \
        "$(run_in $mode "p_timeout 40 true; sleep 0.3; ps -eo comm,args | awk '\$1==\"sleep\" && \$2==40' | wc -l" | tr -d ' ')"
    # p_realpath_m / p_relpath
    RP="$(cd "$TMP/rp" && pwd -P)"
    assert "$mode: p_realpath_m resolves symlink dir" "$RP/real/sub" "$(run_in $mode "p_realpath_m '$TMP/rp/lnk/sub'")"
    assert "$mode: p_realpath_m nonexistent tail" "$RP/real/nope/x" "$(run_in $mode "p_realpath_m '$TMP/rp/lnk/nope/x'")"
    assert "$mode: p_realpath_m collapses .. and ." "$RP/real" "$(run_in $mode "p_realpath_m '$TMP/rp/real/sub/../././'")"
    assert "$mode: p_realpath_m relative" "$RP/real/sub" "$(run_in $mode "cd '$TMP/rp' && p_realpath_m real/sub")"
    assert "$mode: p_realpath_m root" "/" "$(run_in $mode "p_realpath_m /")"
    assert "$mode: p_relpath down"  "sub" "$(run_in $mode "p_relpath '$TMP/rp/real' '$TMP/rp/real/sub'")"
    assert "$mode: p_relpath up"    "../.." "$(run_in $mode "p_relpath '$TMP/rp/real/sub' '$TMP/rp'")"
    assert "$mode: p_relpath sideways" "../real/sub" "$(run_in $mode "mkdir -p '$TMP/rp/other'; p_relpath '$TMP/rp/other' '$TMP/rp/real/sub'")"
    assert "$mode: p_relpath same" "." "$(run_in $mode "p_relpath '$TMP/rp/real' '$TMP/rp/real'")"
    # p_date_iso — same shape as GNU `date -Iseconds` (colon offset), honours TZ
    assert "$mode: p_date_iso shape" "yes" "$(run_in $mode "p_date_iso" | grep -qE '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}[+-][0-9]{2}:[0-9]{2}$' && echo yes || echo no)"
    assert "$mode: p_date_iso offset (India +05:30)" "+05:30" "$(run_in $mode "TZ=Asia/Kolkata p_date_iso" | grep -oE '[+-][0-9]{2}:[0-9]{2}$')"
    assert "$mode: p_date_iso matches date -Iseconds offset (Sao Paulo)" \
        "$(TZ=America/Sao_Paulo date -Iseconds | grep -oE '[+-][0-9]{2}:[0-9]{2}$')" "$(run_in $mode "TZ=America/Sao_Paulo p_date_iso" | grep -oE '[+-][0-9]{2}:[0-9]{2}$')"
    # p_now_ms
    assert "$mode: p_now_ms without EPOCHREALTIME (perl/date fallback)" "ok" \
        "$(a=$(run_in $mode "unset EPOCHREALTIME; p_now_ms"); b=$(( $(date +%s) * 1000 )); d=$(( a - b )); [ ${#a} -eq 13 ] && [ $d -gt -5000 ] && [ $d -lt 5000 ] && echo ok || echo "bad:$a")"
    assert "$mode: p_now_ms is epoch millis" "ok" "$(a=$(run_in $mode "p_now_ms"); b=$(( $(date +%s) * 1000 )); d=$(( a - b )); [ ${#a} -eq 13 ] && [ $d -gt -5000 ] && [ $d -lt 5000 ] && echo ok || echo "bad:$a")"
done

echo; echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
