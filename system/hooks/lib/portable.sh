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
if stat -c %Y / >/dev/null 2>&1; then _P_STAT=gnu; else _P_STAT=bsd; fi

p_stat_mtime() { if [ "$_P_STAT" = gnu ]; then stat -c %Y "$1"; else stat -f %m "$1"; fi; }
p_stat_size()  { if [ "$_P_STAT" = gnu ]; then stat -c %s "$1"; else stat -f %z "$1"; fi; }

# ── hashing ──────────────────────────────────────────────────────────────────
# Print the bare hex digest of FILE (or stdin).
p_sha256() {
    if   _p_have sha256sum; then sha256sum "$@" | awk '{print $1}'
    elif _p_have shasum;    then shasum -a 256 "$@" | awk '{print $1}'
    elif _p_have openssl;   then openssl dgst -sha256 -r "$@" | awk '{print $1}'
    else echo "p_sha256: no sha256 tool found" >&2; return 127; fi
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
    local p="$1" l n=0
    [ -n "$p" ] || return 1
    while [ -L "$p" ]; do
        [ $((n += 1)) -gt 40 ] && { echo "p_readlink_f: too many symlinks: $1" >&2; return 1; }
        l="$(readlink "$p")" || return 1
        case "$l" in /*) p="$l" ;; *) p="$(dirname "$p")/$l" ;; esac
    done
    if [ -d "$p" ]; then
        ( cd "$p" && pwd -P )
    else
        local d
        d="$( cd "$(dirname "$p")" 2>/dev/null && pwd -P )" || return 1
        printf '%s/%s\n' "${d%/}" "$(basename "$p")"
    fi
}

# ── date -d ──────────────────────────────────────────────────────────────────
# Formatting an epoch: GNU `date -u -d @E`, BSD `date -u -r E`.
if   date -u -d @0 +%s >/dev/null 2>&1; then _P_DATE=gnu
elif date -u -r 0 +%s  >/dev/null 2>&1; then _P_DATE=bsd
elif _p_have gdate;                    then _P_DATE=gdate
else _P_DATE=none; fi

_p_epoch_fmt() {  # _p_epoch_fmt EPOCH FMT  (UTC)
    case "$_P_DATE" in
        gnu)   date -u -d "@$1" "+$2" ;;
        bsd)   date -u -r "$1" "+$2" ;;
        gdate) gdate -u -d "@$1" "+$2" ;;
        *)     echo "p_date_d: no usable date(1)" >&2; return 127 ;;
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
# STR: now | @EPOCH | YYYY-MM-DD | YYYY-MM-DD[T ]HH:MM[:SS][Z] | "N second|minute|hour|day|week[s] ago"
# Naive dates/times are UTC, and output is UTC (deterministic across machines/TZ).
# Prints epoch seconds, or `date +FMT` if FMT is given. rc 1 if STR is unparseable.
p_date_d() {
    local s="$1" fmt="${2:-}" e n unit
    local re_iso='^([0-9]{4})-([0-9]{2})-([0-9]{2})([T ]([0-9]{2}):([0-9]{2})(:([0-9]{2}))?Z?)?$'
    local re_rel='^([0-9]+) (second|minute|hour|day|week)s? ago$'
    if [ "$s" = now ]; then
        e="$(date +%s)"
    elif [[ "$s" =~ ^@(-?[0-9]+)$ ]]; then
        e="${BASH_REMATCH[1]}"
    elif [[ "$s" =~ $re_iso ]]; then
        local days
        days="$(_p_days_from_civil "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}" "${BASH_REMATCH[3]}")"
        e=$((days * 86400 + 10#${BASH_REMATCH[5]:-0} * 3600 + 10#${BASH_REMATCH[6]:-0} * 60 + 10#${BASH_REMATCH[8]:-0}))
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
# p_flock [-n] LOCK cmd args...  — run cmd holding LOCK; -n = exit 1 if already held.
# Native flock(1) when present; otherwise an atomic mkdir lock (LOCK.d) whose pid
# file lets a crashed holder's lock be reclaimed instead of wedging forever.
p_flock() {
    local nb=0 lock rc
    [ "${1:-}" = "-n" ] && { nb=1; shift; }
    lock="$1"; shift
    if _p_have flock; then
        if [ $nb = 1 ]; then flock -n "$lock" "$@"; else flock "$lock" "$@"; fi
        return $?
    fi
    local dir="$lock.d" pid
    while ! mkdir "$dir" 2>/dev/null; do
        pid="$(cat "$dir/pid" 2>/dev/null)"
        # Empty pid = holder is between mkdir and writing its pid: not stale.
        if [ -n "$pid" ] && ! kill -0 "$pid" 2>/dev/null; then
            rm -rf "$dir"
            continue
        fi
        [ $nb = 1 ] && return 1
        sleep 0.2
    done
    echo $$ >"$dir/pid"
    "$@"; rc=$?
    rm -rf "$dir"
    return $rc
}
