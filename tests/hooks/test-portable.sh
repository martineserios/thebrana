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
        echo 999999 >"$TMP/l4.lock.lk"
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


# ── Gate 3 fixes (t-3381) ──────────────────────────────────────────────────────────────────────
# p_realpath_m must resolve symlinks BEFORE applying `..` (physical, like GNU realpath -m).
# Lexical collapsing let `root/link/..` escape a containment check (lint-heal.sh allowlist).
G="$TMP/g3"; mkdir -p "$G/outside/deep/dir" "$G/root" "$G/real/sub"
ln -s "$G/outside/deep/dir" "$G/root/link"          # absolute symlink to a deep dir
ln -s ../real "$G/root/rel"                          # relative symlink
ln -s /nonexistent/zz "$G/root/dang"                 # dangling
ln -s "$G/real/sub" "$G/root/chain1"; ln -s chain1 "$G/root/chain2"   # chain of links
GR="$(cd "$G" && pwd -P)"
for mode in native bsd; do
    echo "--- gate 3: $mode ---"
    assert "$mode: realpath_m  link/..  resolves the link first (the bypass)" "$GR/outside/deep/x" "$(run_in $mode "p_realpath_m '$G/root/link/../x'")"
    assert "$mode: realpath_m  rel link/.." "$GR/x" "$(run_in $mode "p_realpath_m '$G/root/rel/../x'")"
    assert "$mode: realpath_m  dangling link then child" "/nonexistent/zz/child" "$(run_in $mode "p_realpath_m '$G/root/dang/child'")"
    assert "$mode: realpath_m  link chain" "$GR/real/sub" "$(run_in $mode "p_realpath_m '$G/root/chain2'")"
    assert "$mode: realpath_m  .. past root" "/x" "$(run_in $mode "p_realpath_m '/../../x'")"
    assert "$mode: realpath_m  double slashes and trailing slash" "$GR/real/sub" "$(run_in $mode "p_realpath_m '$G//real///sub/'")"
    assert "$mode: realpath_m  symlink loop fails (rc 1), does not hang" "1" "$(ln -sfn "$G/root/loopb" "$G/root/loopa"; ln -sfn "$G/root/loopa" "$G/root/loopb"; run_in $mode "p_realpath_m '$G/root/loopa' >/dev/null 2>&1; echo \$?")"
    assert "$mode: readlink_f on a path through a link and .." "$GR/real" "$(run_in $mode "p_readlink_f '$G/root/rel/sub/..'")"
    assert "$mode: readlink_f missing parent fails (rc 1)" "1" "$(run_in $mode "p_readlink_f '$G/nope/x' >/dev/null 2>&1; echo \$?")"
done
# Oracle: where GNU realpath exists, the shim must agree with it on every case above.
if command -v realpath >/dev/null 2>&1 && realpath -m / >/dev/null 2>&1; then
    for c in "$G/root/link/../x" "$G/root/rel/../x" "$G/root/dang/child" "$G/root/chain2" "/../../x" "$G//real///sub/" "$G/real/sub/../../root/link/y" "$G/root/./rel/./sub"; do
        assert "oracle: p_realpath_m == realpath -m for $(printf '%s' "$c" | sed "s|$G|G|")" "$(realpath -m "$c")" "$(run_in native "p_realpath_m '$c'")"
    done
fi

# p_date_d: calendar validation (GNU `date -d 2026-02-31` fails; the shim used to return a garbage epoch)
for bad in 2026-02-31 2026-13-01 2026-00-10 2026-04-31 2025-02-29 0000-00-00 2026-01-01T24:00:00 2026-01-01T10:60:00 2026-01-01T10:00:61; do
    assert "p_date_d rejects $bad (rc 1)" "1" "$(run_in native "p_date_d '$bad' >/dev/null 2>&1; echo \$?")"
done
for good in 2024-02-29 2026-12-31 2026-01-01T23:59:59Z 2000-02-29; do
    assert "p_date_d accepts $good" "0" "$(run_in native "p_date_d '$good' >/dev/null 2>&1; echo \$?")"
done

# p_sha1 (tasks-json-backup.sh slug hash: must stay the SAME algorithm or existing backup dirs are orphaned)
for mode in native bsd; do
    assert "$mode: p_sha1 file"  "f572d396fae9206628714fb2ce00f72e94f2258f" "$(run_in $mode "p_sha1 '$TMP/f.txt'")"
    assert "$mode: p_sha1 stdin" "f572d396fae9206628714fb2ce00f72e94f2258f" "$(run_in $mode "printf 'hello\n' | p_sha1")"
    assert "$mode: p_sha1 -> first 8 chars as the backup slug uses it" "f572d396" "$(run_in $mode "printf 'hello\n' | p_sha1 | cut -c1-8")"
    # p_touch_at FILE EPOCH : touch -d 'N days ago' is GNU-only (BSD touch -d wants ISO); touch -t is portable
    printf x >"$TMP/touch.$mode"
    run_in $mode "p_touch_at '$TMP/touch.$mode' 1704164645" >/dev/null 2>&1
    assert "$mode: p_touch_at sets the mtime to the epoch" "1704164645" "$(run_in $mode "p_stat_mtime '$TMP/touch.$mode'")"
    assert "$mode: p_touch_at rejects a non-numeric epoch (rc 2)" "2" "$(run_in $mode "p_touch_at '$TMP/touch.$mode' 'yesterday' >/dev/null 2>&1; echo \$?")"
    assert "$mode: p_touch_at can set a FUTURE mtime" "yes" "$(n=$(date +%s); run_in $mode "p_touch_at '$TMP/touch.$mode' $((n + 3600))" >/dev/null 2>&1; m=$(run_in $mode "p_stat_mtime '$TMP/touch.$mode'"); [ "$m" -gt "$n" ] && echo yes || echo no)"
done
echo -n 'hello' | sha1sum >/dev/null   # (sanity: oracle tool exists on this box)

# p_lock_acquire: fd must be a literal fd >= 3 (it reaches eval)
assert "lock: non-numeric fd rejected (rc 2)" "2" "$(run_in native "p_lock_acquire '9;echo PWNED' '$TMP/fd.lock' >/dev/null 2>&1; echo \$?")"
assert "lock: a hostile fd string is never evaluated" "no" "$(run_in native "p_lock_acquire '9;echo PWNED' '$TMP/fd.lock' 2>&1" | grep -q '^PWNED$' && echo yes || echo no)"
assert "lock: fd 1 (stdout) rejected" "2" "$(run_in native "p_lock_acquire 1 '$TMP/fd.lock' >/dev/null 2>&1; echo \$?")"
assert "lock: fd 2 (stderr) rejected" "2" "$(run_in native "p_lock_acquire 2 '$TMP/fd.lock' >/dev/null 2>&1; echo \$?")"
assert "lock: empty fd rejected" "2" "$(run_in native "p_lock_acquire '' '$TMP/fd.lock' >/dev/null 2>&1; echo \$?")"

# mkdir-lock fallback (BSD PATH has no flock): stale/garbage/empty pid handling and the reclaim race
L="$TMP/lk"; mkdir -p "$L"
old() { touch -d '2 minutes ago' "$1"; }
echo 0  >"$L/g1.lock.lk"; old "$L/g1.lock.lk"
assert "bsd lock: pid '0' (kill -0 0 always succeeds) in an OLD lock file is garbage -> reclaimed" "0" "$(run_in bsd "p_lock_acquire 9 '$L/g1.lock' -n; echo \$?")"
echo -1 >"$L/g2.lock.lk"; old "$L/g2.lock.lk"
assert "bsd lock: pid '-1' in an OLD lock file -> reclaimed" "0" "$(run_in bsd "p_lock_acquire 9 '$L/g2.lock' -n; echo \$?")"
: >"$L/g3.lock.lk"; old "$L/g3.lock.lk"
assert "bsd lock: EMPTY pid in an OLD lock file (holder died before writing it) -> reclaimed, not wedged" "0" "$(run_in bsd "p_lock_acquire 9 '$L/g3.lock' -n; echo \$?")"
: >"$L/g4.lock.lk"
assert "bsd lock: EMPTY pid in a FRESH lock file (holder mid-acquire) -> still held, not stolen" "1" "$(run_in bsd "p_lock_acquire 9 '$L/g4.lock' -n; echo \$?")"
echo 999999 >"$L/g5.lock.lk"; echo 1 >"$L/g5.lock.lk.reclaim"; old "$L/g5.lock.lk.reclaim"
assert "bsd lock: a wedged OLD .reclaim file does not block reclaim forever" "0" "$(run_in bsd "p_lock_acquire 9 '$L/g5.lock' -n; echo \$?")"
assert "bsd lock: release removes only OUR lock (a stolen-and-retaken lock is left alone)" "kept" \
    "$(echo 4242 >"$L/g6.lock.lk"; run_in bsd "p_lock_release 9 '$L/g6.lock'" >/dev/null 2>&1; [ -f "$L/g6.lock.lk" ] && echo kept || echo removed)"
# the race: a stale lock, many contenders -> exactly one holder at a time, all eventually get in.
# The overlap detector is noclobber-based too: uutils mkdir (this box's default) is not a safe detector.
echo 999999 >"$L/race.lock.lk"
: >"$L/race.count"; : >"$L/race.violations"
race_worker() {
    PATH="$BSD_BIN" "$(command -v bash)" -c "
        source '$LIB'
        p_lock_acquire 9 '$L/race.lock' -w 20 || { echo NOACQ >>'$L/race.violations'; exit 0; }
        if ! ( set -C; : >'$L/race.inside' ) 2>/dev/null; then echo OVERLAP >>'$L/race.violations'; fi
        echo x >>'$L/race.count'; sleep 0.05
        rm -f '$L/race.inside'
        p_lock_release 9 '$L/race.lock'"
}
for _ in 1 2 3 4 5 6 7 8; do race_worker & done; wait
assert "bsd lock race: all 8 contenders acquired" "8" "$(wc -l <"$L/race.count" | tr -d ' ')"
assert "bsd lock race: never two holders at once, none starved" "0" "$(wc -l <"$L/race.violations" | tr -d ' ')"

echo; echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
