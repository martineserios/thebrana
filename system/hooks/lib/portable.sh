#!/usr/bin/env bash
# portable.sh — GNU/BSD-portable wrappers for the userland differences that
# break brana scripts on macOS. Source it; call p_* instead of the GNU-only form.
#   source "$SCRIPT_DIR/../hooks/lib/portable.sh"
#
# Capability probing, not uname: each shim tests what the local tools can do, so
# Linux stays on the native fast path and Homebrew coreutils is picked up for free.
# Spec: docs/architecture/features/macos-portable-shims.md (t-3373).
#
# Requires bash (>=3.2; macOS system bash is fine).

_p_have() { command -v "$1" >/dev/null 2>&1; }

# ── stat ─────────────────────────────────────────────────────────────────────
# Probes are lazy: hooks source this on every tool call, so sourcing must not fork.
_P_STAT=""
_p_stat_init() { if stat -c %Y / >/dev/null 2>&1; then _P_STAT=gnu; else _P_STAT=bsd; fi; }

p_stat_mtime() { [ -n "$_P_STAT" ] || _p_stat_init; if [ "$_P_STAT" = gnu ]; then stat -c %Y "$1"; else stat -f %m "$1"; fi; }
p_stat_atime() { [ -n "$_P_STAT" ] || _p_stat_init; if [ "$_P_STAT" = gnu ]; then stat -c %X "$1"; else stat -f %a "$1"; fi; }
p_stat_mode()  { [ -n "$_P_STAT" ] || _p_stat_init; if [ "$_P_STAT" = gnu ]; then stat -c %a "$1"; else stat -f %Lp "$1"; fi; }
p_stat_size()  { [ -n "$_P_STAT" ] || _p_stat_init; if [ "$_P_STAT" = gnu ]; then stat -c %s "$1"; else stat -f %z "$1"; fi; }

# ── hashing ──────────────────────────────────────────────────────────────────
# Print the bare hex digest of FILE (or stdin).
p_sha256() {
    if   _p_have sha256sum; then sha256sum "$@" | awk '{print $1}'
    elif _p_have shasum;    then shasum -a 256 "$@" | awk '{print $1}'
    elif _p_have openssl;   then openssl dgst -sha256 -r "$@" | awk '{print $1}'
    else echo "p_sha256: no sha256 tool found" >&2; return 127; fi
}
# p_sha1 [FILE] — bare hex sha1 (stdin if no FILE). Only for identifiers that already use sha1
# (e.g. tasks-json-backup.sh's slug): switching algorithm would orphan existing backup dirs.
p_sha1() {
    if   _p_have sha1sum; then sha1sum "$@" | awk '{print $1}'
    elif _p_have shasum;  then shasum -a 1 "$@" | awk '{print $1}'
    elif _p_have openssl; then openssl dgst -sha1 -r "$@" | awk '{print $1}'
    else echo "p_sha1: no sha1 tool found" >&2; return 127; fi
}
p_md5() {
    if   _p_have md5sum;  then md5sum "$@" | awk '{print $1}'
    elif _p_have md5;     then md5 -q "$@"
    elif _p_have openssl; then openssl dgst -md5 -r "$@" | awk '{print $1}'
    else echo "p_md5: no md5 tool found" >&2; return 127; fi
}

# ── sed -i ───────────────────────────────────────────────────────────────────
# p_sed_i SCRIPT FILE...  — GNU `sed -i` takes no suffix arg, BSD requires one.
# A suffix attached to -i is the one form both accept; delete the backup after.
p_sed_i() {
    local script="$1" f rc=0
    shift
    for f in "$@"; do
        sed -i.pbak "$script" "$f" && rm -f "$f.pbak" || rc=1
    done
    return $rc
}

# ── readlink -f ──────────────────────────────────────────────────────────────
# Canonical absolute path, symlinks resolved (last component need not exist).
p_readlink_f() {
    local r
    [ -n "${1:-}" ] || return 1
    r="$(p_realpath_m "$1")" || return 1
    [ "$r" = "/" ] || [ -d "${r%/*}" ] || [ -z "${r%/*}" ] || return 1
    printf '%s\n' "$r"
}

# ── date -d ──────────────────────────────────────────────────────────────────
# Formatting an epoch: GNU `date -u -d @E`, BSD `date -u -r E` (probed lazily).
_P_DATE=""
_p_date_init() {
    if   date -u -d @0 +%s >/dev/null 2>&1; then _P_DATE=gnu
    elif date -u -r 0 +%s  >/dev/null 2>&1; then _P_DATE=bsd
    elif _p_have gdate;                    then _P_DATE=gdate
    else _P_DATE=none; fi
}

_p_epoch_fmt() {  # _p_epoch_fmt EPOCH FMT  (UTC)
    [ -n "$_P_DATE" ] || _p_date_init
    case "$_P_DATE" in
        gnu)   date -u -d "@$1" "+$2" ;;
        bsd)   date -u -r "$1" "+$2" ;;
        gdate) gdate -u -d "@$1" "+$2" ;;
        *)     echo "p_date_d: no usable date(1)" >&2; return 127 ;;
    esac
}

# p_epoch_fmt EPOCH FMT — replaces `date -d @EPOCH +FMT` for human display: LOCAL time
# (honours TZ), unlike p_date_d which is UTC.
p_epoch_fmt() {
    [ -n "$_P_DATE" ] || _p_date_init
    case "$_P_DATE" in
        gnu)   date -d "@$1" "+$2" ;;
        bsd)   date -r "$1" "+$2" ;;
        gdate) gdate -d "@$1" "+$2" ;;
        *)     echo "p_epoch_fmt: no usable date(1)" >&2; return 127 ;;
    esac
}

# Days since 1970-01-01 for a civil date (Hinnant's algorithm; pure arithmetic).
_p_days_from_civil() {
    local y=$((10#$1)) m=$((10#$2)) d=$((10#$3)) era yoe doy doe
    [ "$m" -le 2 ] && y=$((y - 1))
    if [ "$y" -ge 0 ]; then era=$((y / 400)); else era=$(((y - 399) / 400)); fi
    yoe=$((y - era * 400))
    doy=$(((153 * ((m + 9) % 12) + 2) / 5 + d - 1))
    doe=$((yoe * 365 + yoe / 4 - yoe / 100 + doy))
    echo $((era * 146097 + doe - 719468))
}

# p_date_d STR [FMT]  — replaces `date -d STR [+FMT]`.
# STR: now | @EPOCH | YYYY-MM-DD | YYYY-MM-DD[T ]HH:MM[:SS[.frac]][ ][Z|+HH[:]MM|-HH[:]MM]
#      | "N second|minute|hour|day|week[s] ago"        (git %ci and ISO-8601 both parse)
# Naive dates/times are UTC, and output is UTC (deterministic across machines/TZ).
# For local-time display use p_epoch_fmt.
# Prints epoch seconds, or `date +FMT` if FMT is given. rc 1 if STR is unparseable.
p_date_d() {
    local s="$1" fmt="${2:-}" e n unit
    local re_iso='^([0-9]{4})-([0-9]{2})-([0-9]{2})([T ]([0-9]{2}):([0-9]{2})(:([0-9]{2})(\.[0-9]+)?)?( ?(Z|([+-])([0-9]{2}):?([0-9]{2})))?)?$'
    local re_rel='^([0-9]+) (second|minute|hour|day|week)s? ago$'
    if [ "$s" = now ]; then
        e="$(date +%s)"
    elif [[ "$s" =~ ^@(-?[0-9]+)$ ]]; then
        e="${BASH_REMATCH[1]}"
    elif [[ "$s" =~ $re_iso ]]; then
        local days y=$((10#${BASH_REMATCH[1]})) mo=$((10#${BASH_REMATCH[2]})) dd=$((10#${BASH_REMATCH[3]})) dim
        case $mo in 1|3|5|7|8|10|12) dim=31 ;; 4|6|9|11) dim=30 ;;
            2) if { [ $((y % 4)) -eq 0 ] && [ $((y % 100)) -ne 0 ]; } || [ $((y % 400)) -eq 0 ]; then dim=29; else dim=28; fi ;;
            *) echo "p_date_d: invalid month in '$s'" >&2; return 1 ;; esac
        if [ "$dd" -lt 1 ] || [ "$dd" -gt "$dim" ] || [ $((10#${BASH_REMATCH[5]:-0})) -gt 23 ] \
           || [ $((10#${BASH_REMATCH[6]:-0})) -gt 59 ] || [ $((10#${BASH_REMATCH[8]:-0})) -gt 59 ]; then
            echo "p_date_d: invalid date/time '$s'" >&2; return 1
        fi
        days="$(_p_days_from_civil "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}" "${BASH_REMATCH[3]}")"
        e=$((days * 86400 + 10#${BASH_REMATCH[5]:-0} * 3600 + 10#${BASH_REMATCH[6]:-0} * 60 + 10#${BASH_REMATCH[8]:-0}))
        if [ -n "${BASH_REMATCH[12]}" ]; then   # numeric offset: local time = UTC + offset
            local off=$((10#${BASH_REMATCH[13]} * 3600 + 10#${BASH_REMATCH[14]} * 60))
            if [ "${BASH_REMATCH[12]}" = "+" ]; then e=$((e - off)); else e=$((e + off)); fi
        fi
    elif [[ "$s" =~ $re_rel ]]; then
        n="${BASH_REMATCH[1]}"; unit="${BASH_REMATCH[2]}"
        case "$unit" in
            second) unit=1 ;; minute) unit=60 ;; hour) unit=3600 ;;
            day) unit=86400 ;; week) unit=604800 ;;
        esac
        e=$(($(date +%s) - n * unit))
    else
        echo "p_date_d: cannot parse '$s'" >&2
        return 1
    fi
    if [ -z "$fmt" ]; then echo "$e"; else _p_epoch_fmt "$e" "$fmt"; fi
}

# ── flock ────────────────────────────────────────────────────────────────────
# ── mkdir-free fallback lock (no flock(1), e.g. stock macOS) ─────────────────────────────────
# The atomic primitive is the SHELL's own noclobber redirect (`set -C; >file` = open(O_CREAT|O_EXCL)),
# NOT mkdir: Ubuntu's default coreutils is now uutils, whose mkdir lets several concurrent callers
# "win" the same directory (reproduced on this repo's dev box — a lock built on it double-granted),
# while python os.mkdir on the same kernel never did. Nothing here depends on a coreutils binary's
# atomicity. The lock is a file LOCK.lk holding the holder's pid.

_p_lock_create() { ( set -C; printf '%s\n' "$$" >"$1" ) 2>/dev/null; }   # rc 0 iff WE created it

# Release only a lock we still own (never delete one that was reclaimed and re-taken by someone else).
_p_lock_drop() { [ "$(cat "$1" 2>/dev/null)" = "$$" ] && rm -f "$1"; return 0; }

# _p_lock_stale FILE — rc 0 iff the holder is provably gone. Unknown is NOT stale: if the file
# vanished or stat fails mid-check (a holder releasing / a new holder arriving) say "not stale" and
# let the caller retry — "stat failed => age 0 => ancient" once let a reclaimer delete a live lock.
# An empty/garbage pid (holder died between create and its pid write; `kill -0 0` / `-1` would
# falsely say "alive") is stale only once the file is >10s old — a live holder writes within ms.
_p_lock_stale() {
    local f="$1" pid mt age
    [ -f "$f" ] || return 1
    pid="$(cat "$f" 2>/dev/null)"
    case "$pid" in
        ''|*[!0-9]*|0)
            mt="$(p_stat_mtime "$f" 2>/dev/null)" || return 1
            case "$mt" in ''|*[!0-9]*) return 1 ;; esac
            age=$(( $(date +%s) - mt ))
            [ "$age" -gt 10 ] ;;
        *)  ! kill -0 "$pid" 2>/dev/null ;;
    esac
}

# _p_lock_take FILE — one attempt; rc 0 = acquired, 1 = held. A dead holder is reclaimed ONLY under a
# second lock (FILE.reclaim) and only if, re-evaluated THERE against the current file, it is still
# the same stale holder — otherwise two waiters that judged the same dead holder could each delete
# the lock and each create it (two holders). A wedged .reclaim (reclaimer died mid-reclaim) is
# cleared after 30s.
_p_lock_take() {
    local lk="$1" rlk="$1.reclaim" pid mt age
    _p_lock_create "$lk" && return 0
    _p_lock_stale "$lk" || return 1
    pid="$(cat "$lk" 2>/dev/null)"
    if ! _p_lock_create "$rlk"; then
        mt="$(p_stat_mtime "$rlk" 2>/dev/null)" || return 1
        case "$mt" in ''|*[!0-9]*) return 1 ;; esac
        age=$(( $(date +%s) - mt ))
        [ "$age" -gt 30 ] || return 1            # a live reclaimer is at work: let it finish
        rm -f "$rlk"
        _p_lock_create "$rlk" || return 1        # cleared a wedged one: take it now, don't make -n callers give up
    fi
    if [ "$(cat "$lk" 2>/dev/null)" = "$pid" ] && _p_lock_stale "$lk"; then rm -f "$lk"; fi
    rm -f "$rlk"
    _p_lock_create "$lk"
}

# p_flock [-n] LOCK cmd args...  — run cmd (or shell function) holding LOCK; -n = rc 1 if held.
# Native flock(1) when present; otherwise the noclobber-file lock (LOCK.lk, see above) whose pid
# file lets a crashed holder's lock be reclaimed instead of wedging forever.
p_flock() {
    local nb=0 lock rc
    [ "${1:-}" = "-n" ] && { nb=1; shift; }
    lock="$1"; shift
    if _p_have flock; then
        # Subshell + fd (not `flock file cmd`) so cmd may be a shell function.
        if [ $nb = 1 ]; then ( flock -n 8 || exit 1; "$@" ) 8>>"$lock"
        else ( flock 8 || exit 1; "$@" ) 8>>"$lock"; fi
        return $?
    fi
    local lk="$lock.lk"
    until _p_lock_take "$lk"; do
        [ $nb = 1 ] && return 1
        sleep 0.2
    done
    "$@"; rc=$?
    _p_lock_drop "$lk"
    return $rc
}

# p_lock_acquire FD FILE [-n | -w SECS]   /   p_lock_release FD FILE
# fd-style exclusive lock for callers that hold a lock across a code region
# (`exec 200>f; flock -w 5 200` ... `flock -u 200`). FD is the caller's fd number.
#   -n      fail immediately (rc 1) if held
#   -w SECS wait up to SECS, then rc 1
#   (none)  wait forever
# Native flock(1) when present; else the same noclobber-file lock (FILE.lk) as p_flock.
# On the fallback path a holder that exits without p_lock_release leaves FILE.lk
# behind; the next acquirer reclaims it once the holder pid is dead.
p_lock_acquire() {
    local fd="$1" file="$2" mode="${3:-}" secs="${4:-}" rc
    # fd reaches eval: digits only, >= 3 (0/1/2 are stdio; a leading 0 is not a valid fd spec)
    case "$fd" in ''|*[!0-9]*|0*|1|2) echo "p_lock_acquire: bad fd '$fd' (need an integer >= 3)" >&2; return 2 ;; esac
    if _p_have flock; then
        eval "exec $fd>>\"\$file\"" || return 1
        case "$mode" in
            -n) flock -n "$fd" ;;
            -w) flock -w "$secs" "$fd" ;;
            *)  flock "$fd" ;;
        esac
        rc=$?
        [ $rc -eq 0 ] || eval "exec $fd>&-"
        return $rc
    fi
    local lk="$file.lk" tries=0 max=-1
    [ "$mode" = "-n" ] && max=0
    [ "$mode" = "-w" ] && max=$((secs * 5))
    until _p_lock_take "$lk"; do
        [ $max -ge 0 ] && [ $tries -ge $max ] && return 1
        tries=$((tries + 1))
        sleep 0.2
    done
    return 0
}

p_lock_release() {
    local fd="$1" file="$2"
    case "$fd" in ''|*[!0-9]*|0*|1|2) echo "p_lock_release: bad fd '$fd' (need an integer >= 3)" >&2; return 2 ;; esac
    if _p_have flock; then
        flock -u "$fd"
        eval "exec $fd>&-"
    else
        _p_lock_drop "$file.lk"
    fi
}

# ── timeout ──────────────────────────────────────────────────────────────────
# p_timeout [-k KILL_AFTER] SECS cmd args...   — rc 124 on timeout, else cmd's rc.
# (GNU timeout returns 137 instead when -k had to escalate to KILL; the fallback returns 124.
# Treat "timed out" as rc 124 or 137.)
# GNU timeout(1) when present (Linux; Homebrew coreutils' gtimeout on macOS); otherwise a
# bash watchdog: cmd runs in the background with stdin preserved, a watchdog TERMs it (and
# its direct children) after SECS, then KILLs after KILL_AFTER. The watchdog's stdout/stderr
# go to /dev/null so a surrounding $(...) never waits out the timeout.
# The fallback signals the child and its direct children, not the whole process group as GNU
# timeout does — grandchildren of a wrapper shell can outlive it.
p_timeout() {
    if   _p_have timeout;  then timeout "$@";  return $?
    elif _p_have gtimeout; then gtimeout "$@"; return $?
    fi
    local kill_after="" secs pid wd rc=0 wrc=0
    if [ "${1:-}" = "-k" ]; then kill_after="$2"; shift 2; fi
    secs="$1"; shift
    "$@" <&0 &
    pid=$!
    (
        sleep "$secs"
        if kill -0 "$pid" 2>/dev/null; then
            pkill -TERM -P "$pid" 2>/dev/null; kill -TERM "$pid" 2>/dev/null
            if [ -n "$kill_after" ]; then   # detached escalation: outlives this stage on purpose
                ( sleep "$kill_after"; pkill -KILL -P "$pid" 2>/dev/null; kill -KILL "$pid" 2>/dev/null ) >/dev/null 2>&1 &
            fi
            exit 124
        fi
        exit 0
    ) >/dev/null 2>&1 &
    wd=$!
    wait "$pid" 2>/dev/null || rc=$?
    pkill -P "$wd" 2>/dev/null; kill "$wd" 2>/dev/null
    wait "$wd" 2>/dev/null || wrc=$?
    [ "$wrc" -eq 124 ] && return 124
    return "$rc"
}

# ── realpath ─────────────────────────────────────────────────────────────────
# p_realpath_m PATH — `realpath -m`: absolute; every symlink resolved AS IT IS MET, before the next
# `..` is applied (physical, like GNU — `root/link/..` is the PARENT OF LINK'S TARGET, not `root`);
# nonexistent tail allowed. A lexical `..` collapse here let a symlink escape a containment check
# (lint-heal.sh's allowlist) — Gate 3, t-3381. rc 1 on a symlink loop (>40 links).
p_realpath_m() {
    local in="$1" cur="/" rest seg next target links=0
    [ -n "$in" ] || return 1
    case "$in" in /*) rest="${in#/}" ;; *) rest="${PWD#/}/$in" ;; esac
    while [ -n "$rest" ]; do
        seg="${rest%%/*}"
        if [ "$seg" = "$rest" ]; then rest=""; else rest="${rest#*/}"; fi
        case "$seg" in
            ""|.) continue ;;
            ..)   cur="${cur%/*}"; [ -n "$cur" ] || cur="/"; continue ;;
        esac
        next="${cur%/}/$seg"
        if [ -L "$next" ]; then
            links=$((links + 1))
            [ "$links" -gt 40 ] && { echo "p_realpath_m: too many symlinks: $in" >&2; return 1; }
            target="$(readlink "$next")" || return 1
            case "$target" in
                /*) cur="/"; rest="${target#/}${rest:+/$rest}" ;;
                *)  rest="$target${rest:+/$rest}" ;;
            esac
        else
            cur="$next"
        fi
    done
    printf '%s\n' "$cur"
}

# p_relpath BASE PATH — `realpath --relative-to=BASE PATH` (both may be nonexistent).
p_relpath() {
    local cur target up="" rest
    cur="$(p_realpath_m "$1")" || return 1
    target="$(p_realpath_m "$2")" || return 1
    while [ "$cur" != / ] && [ "$target" != "$cur" ] && [ "${target#"$cur"/}" = "$target" ]; do
        cur="$(dirname "$cur")"; up="../$up"
    done
    rest="${target#"$cur"}"; rest="${rest#/}"
    rest="${up}${rest}"; rest="${rest%/}"
    printf '%s\n' "${rest:-.}"
}

# ── date -Iseconds / nanosecond clock ────────────────────────────────────────
# p_date_iso — `date -Iseconds` (local time, colon offset: 2026-09-29T14:18:03-03:00).
# BSD date has no -I; GNU's %z has no colon.
p_date_iso() {
    local d
    d="$(date +%Y-%m-%dT%H:%M:%S%z)"
    printf '%s:%s\n' "${d%??}" "${d: -2}"
}

# p_now_ms — epoch milliseconds. bash >= 5 EPOCHREALTIME (no fork); else `date +%s%N`
# (prints a literal N on BSD), then perl (ships with macOS), then whole seconds.
p_now_ms() {
    local n
    if [ -n "${EPOCHREALTIME:-}" ]; then   # bash >= 5: no fork; separator follows the locale
        n="${EPOCHREALTIME//[.,]/}"
        echo $((n / 1000)); return 0
    fi
    n="$(date +%s%N 2>/dev/null)"
    case "$n" in
        ""|*[!0-9]*) ;;
        *) echo $((n / 1000000)); return 0 ;;
    esac
    if _p_have perl; then perl -MTime::HiRes=time -e 'printf "%d\n", time()*1000'
    else echo $(( $(date +%s) * 1000 )); fi
}

# ── touch ────────────────────────────────────────────────────────────────────
# p_touch_at FILE EPOCH — set FILE's mtime (and atime) to EPOCH seconds, past or future.
# `touch -d 'N days ago'` / `-d '+2 seconds'` are GNU-only (BSD touch -d wants ISO 8601);
# `touch -t CCYYMMDDhhmm.SS` is the form both accept. Pair with p_date_d for "N days ago":
#   p_touch_at "$f" "$(p_date_d '35 days ago')"
p_touch_at() {
    case "${2:-}" in ''|*[!0-9]*) echo "p_touch_at: EPOCH must be a non-negative integer, got '${2:-}'" >&2; return 2 ;; esac
    touch -t "$(p_epoch_fmt "$2" %Y%m%d%H%M.%S)" "$1"
}
