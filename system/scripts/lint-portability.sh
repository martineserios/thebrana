#!/usr/bin/env bash
# lint-portability.sh — fail on GNU-only userland forms in production shell scripts.
# Classes: flock, date -d/-I/%N, sha*/md5sum, stat -c, sed -i (any flag order), readlink -f, grep -P,
# touch -d, getent, nproc, #!/bin/bash shebangs,
# timeout, realpath, find -printf, tac, head -n -N, GNU-only BRE (sed \\+ \\s, grep \\|).
# Every hit must use a p_* shim from system/hooks/lib/portable.sh instead
# (spec: docs/architecture/features/macos-portable-shims.md, t-3374).
#
# Usage: lint-portability.sh [ROOT]     (default: git toplevel; scans tracked *.sh)
# Exit 1 on any violation. Escape hatch for a line that is already guarded or has
# its own BSD branch: append `# portable-ok: <reason>` to that line.
#
# Scope: all tracked *.sh and extensionless sh/bash-shebang files, tests included. Exempt by name:
# only files that merely QUOTE or EMULATE GNU forms (tests/lib/bsd-path.sh, this lint's own test) —
# a test the macOS job RUNS must not be exempt (test-portable.sh was, and executed GNU `touch -d`). A hit is also exempt when the line
# directly above is `# portable-ok-next: <reason>`. Skips tests/, */tests/, docs/, portable.sh and this file.
# Full-line comments are ignored.
set -u
ROOT="${1:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
cd "$ROOT" || exit 2

PATS=(
  '(^|[^A-Za-z_-])flock([[:space:]]|$)'
  'date( -[a-zA-Z]+)* (-d|--date)'
  '(sha256sum|md5sum|sha1sum|sha512sum|sha384sum|sha224sum)'
  'stat -c'
  'sed( +[^|;&]*)? +-[a-zA-Z]*i([[:space:]]|$)|sed .*--in-place'
  'readlink -f'
  'grep -[a-zA-Z]*P'
  '(^|[^A-Za-z_-])timeout[[:space:]]+(-|[0-9$"])'
  '(^|[^A-Za-z_-])realpath[[:space:]]'
  'find .*-printf'
  'date( -[a-zA-Z]+)* -[a-zA-Z]*I'
  'date .*%[0-9]?N'
  '(^|[^A-Za-z_-])tac([[:space:]]|$)'
  'head -n? ?-[0-9]'
  'sed .*\\[+?sSwW|]'
  "grep( -[a-zA-Z]+)* +['\"][^'\"]*\\\\[|+?]"
  'touch( +-[a-zA-Z]+)* +(-d|--date)'
  '(^|[^A-Za-z_-])getent([[:space:]]|$|[)|;&])'
  '(^|[^A-Za-z_-])nproc([[:space:]]|$|[)|;&])'
)
ADVICE=(
  'use p_flock / p_lock_acquire'
  'use p_date_d / p_epoch_fmt'
  'use p_sha256 / p_md5 / p_sha1'
  'use p_stat_mtime / p_stat_size'
  'use p_sed_i (or the portable sed -i.bak form)'
  'use p_readlink_f'
  'rewrite with grep -E / sed -E / awk (no PCRE on BSD grep)'
  'use p_timeout (macOS has no timeout(1))'
  'use p_realpath_m / p_readlink_f / p_relpath'
  'use stat via p_stat_mtime/p_stat_atime in a loop (BSD find has no -printf)'
  'use p_date_iso (BSD date has no -I)'
  'use p_now_ms (BSD date has no %N)'
  "use awk '{a[NR]=\$0} END{for(i=NR;i>0;i--)print a[i]}' (no tac on macOS)"
  "use sed '\$d' (BSD head has no negative counts)"
  'use sed -E with ERE (BSD sed BRE has no \\+ \\? \\| \\s \\w)'
  'use grep -E with ERE (\\| \\+ \\? are GNU BRE extensions)'
  'use p_touch_at FILE EPOCH (touch -d is GNU-only; BSD wants ISO) — pair with p_date_d'
  'macOS has no getent: for an unset HOME use "$(cd ~ && pwd)" (bash resolves ~ from passwd)'
  'macOS has no nproc: use `nproc 2>/dev/null || sysctl -n hw.ncpu` and mark the line portable-ok'
)
# Per-rule lines to ignore after matching (same index as PATS; empty = none).
EXCL=(
  '' '' '' '' '' '' '' '' '' '' '' '' '' ''
  'sed( +-[a-zA-Z]+)* +-[a-zA-Z]*[Er]'
  'grep( +-[a-zA-Z]+)* +-[a-zA-Z]*[EP]|egrep'
)

# Tracked *.sh plus extensionless files with a sh/bash shebang (hook entry points, CLIs).
files="$( { git ls-files '*.sh'
            git ls-files | grep -vE '\.[A-Za-z0-9]+$' | while IFS= read -r f; do
                [ -f "$f" ] && head -n1 "$f" 2>/dev/null | grep -qE '^#!.*(ba)?sh([[:space:]]|$)' && echo "$f"
            done; } | sort -u | grep -vE '^docs/|^system/hooks/lib/portable\.sh$|^system/scripts/lint-portability\.sh$|^tests/lib/bsd-path\.sh$|^tests/scripts/test-lint-portability\.sh$')"
bad=0
for i in "${!PATS[@]}"; do
    pat="${PATS[$i]}"; advice="${ADVICE[$i]}"
    while IFS= read -r line; do
        [ -n "$line" ] || continue
        # `# portable-ok-next: reason` on the line directly above also exempts a hit.
        _f="${line%%:*}"; _r="${line#*:}"; _n="${_r%%:*}"
        if [ "${_n:-0}" -gt 1 ] 2>/dev/null \
            && sed -n "$((_n - 1))p" "$_f" | grep -qE '^[[:space:]]*#[[:space:]]*portable-ok-next:'; then
            continue
        fi
        echo "$line  <-- $advice"
        bad=$((bad + 1))
    done < <(printf '%s\n' "$files" | xargs grep -nE -- "$pat" 2>/dev/null \
        | grep -vE '^[^:]+:[0-9]+:[[:space:]]*#' \
        | grep -v 'portable-ok:' \
        | { if [ -n "${EXCL[$i]:-}" ]; then grep -vE -- "${EXCL[$i]}"; else cat; fi; } | cut -c1-200)
done

# Shim functions cannot be exec'd. `env`/`nice`/`nohup`/`setsid`/`xargs`/`sudo`/`exec`/`command`
# run an *executable*, so `env -u X p_timeout ...` dies with 127 — which red-verification.sh read
# as "test ran red" (t-3377). Backslash continuations are joined so the wrapper and the shim
# may sit on different lines. Order must be shim first: `p_timeout 5 env -u X cmd`.
WRAP_RE='(^|[^A-Za-z_-])(env|nice|nohup|setsid|xargs|sudo|exec|command)[[:space:]]([^|;&]*[[:space:]])?p_[a-z0-9_]+([[:space:]]|$)'
while IFS= read -r line; do
    [ -n "$line" ] || continue
    echo "$line  <-- shim function after an exec wrapper (env/nohup/xargs/...): put the shim first, e.g. p_timeout 5 env ..."
    bad=$((bad + 1))
done < <(printf '%s\n' "$files" | while IFS= read -r f; do
    [ -f "$f" ] && awk -v F="$f" -v RE="$WRAP_RE" '
        { line = $0 }
        cur == "" { start = NR }
        line ~ /^[[:space:]]*#/ && cur == "" { next }
        { sub(/[[:space:]]+$/, "", line) }
        line ~ /\\$/ { sub(/\\$/, "", line); cur = cur " " line; next }
        { cur = cur " " line
          if (cur !~ /portable-ok:/ && cur ~ RE) { t = cur; gsub(/^[[:space:]]+/, "", t); print F ":" start ": " substr(t, 1, 160) }
          cur = "" }
    ' "$f"
done)

# Unbraced `$var` directly followed by a non-ASCII byte: under the macOS runner's locale bash counts
# that byte as part of the identifier, so `"$a→$b"` expands `$a→` (unset) and prints only `$b` — the
# 7h `~ would update 0.0.9→0.1.0` line came out as `→0.1.0` on macOS CI (t-3427). Brace it: `${a}→`.
UNBRACED_RE=$'\\$[A-Za-z_][A-Za-z0-9_]*[\x80-\xff]'
while IFS= read -r line; do
    [ -n "$line" ] || continue
    echo "$line  <-- unbraced \$var before a non-ASCII char: write \${var} (macOS bash reads the byte into the name)"
    bad=$((bad + 1))
done < <(printf '%s\n' "$files" | LC_ALL=C xargs grep -nE -- "$UNBRACED_RE" 2>/dev/null \
    | LC_ALL=C grep -vE '^[^:]+:[0-9]+:[[:space:]]*#' | grep -v 'portable-ok:' | cut -c1-200)

# Shebang: `#!/bin/bash` / `#!/bin/sh` run a directly-executed script under macOS's bash 3.2,
# bypassing bootstrap's PATH-bash >= 4 preflight (statusline, the MCP wrapper). Use
# `#!/usr/bin/env bash`. There is no escape hatch: a trailing comment on a shebang line is not portable.
while IFS= read -r f; do
    [ -f "$f" ] || continue
    first="$(head -n1 "$f" 2>/dev/null)"
    case "$first" in
        '#!/bin/bash'|'#!/bin/bash '*|'#!/bin/sh'|'#!/bin/sh '*)
            echo "$f:1: $first  <-- use #!/usr/bin/env bash (a /bin/bash shebang runs under macOS's bash 3.2)"
            bad=$((bad + 1)) ;;
    esac
done <<< "$files"

# A file that calls a p_* shim must source portable.sh itself, or the call dies with
# "command not found" at runtime. A `cp .../portable.sh` (fixtures) does not count. Comments and
# lines marked portable-ok are ignored; a call shape is required (shim name preceded by a
# separator, not a quote), so prose in strings does not trip it.
# Shim names come from portable.sh itself (the lint script's OWN repo — the scanned tree may be a
# fixture), so a newly added shim cannot be left out: p_sha1 and p_touch_at were missing from the
# hand-written list in the very commit that added them.
SHIM_NAMES="$(grep -oE '^p_[a-z0-9_]+\(\)' "$(dirname "${BASH_SOURCE[0]}")/../hooks/lib/portable.sh" | tr -d '()' | sed 's/^p_//' | paste -sd'|' -)"
[ -n "$SHIM_NAMES" ] || { echo "lint-portability: cannot read shim names from portable.sh" >&2; exit 2; }
SHIM_RE="(^|[[:space:];|&(\`])p_($SHIM_NAMES)([[:space:]]|$|\\))"
while IFS= read -r f; do
    [ -f "$f" ] || continue
    n="$(grep -vE '^[[:space:]]*#' "$f" | grep -v 'portable-ok' | grep -cE "$SHIM_RE")"
    if [ "${n:-0}" -gt 0 ] && ! grep -qE '^[[:space:]]*(source|\.)[[:space:]].*portable\.sh' "$f"; then
        echo "$f:1:  <-- calls p_* shim(s) ($n line(s)) but never sources portable.sh (a cp of it does not count)"
        bad=$((bad + 1))
    fi
done <<< "$files"

if [ "$bad" -eq 0 ]; then echo "OK: no GNU-only forms in shell scripts (tests included)"; exit 0; fi
echo "$bad portability violation(s)"; exit 1
