#!/usr/bin/env bash
# lint-portability.sh — fail on GNU-only userland forms in production shell scripts.
# Every hit must use a p_* shim from system/hooks/lib/portable.sh instead
# (spec: docs/architecture/features/macos-portable-shims.md, t-3374).
#
# Usage: lint-portability.sh [ROOT]     (default: git toplevel; scans tracked *.sh)
# Exit 1 on any violation. Escape hatch for a line that is already guarded or has
# its own BSD branch: append `# portable-ok: <reason>` to that line.
#
# Scope: production scripts (*.sh and extensionless sh/bash-shebang files). Skips tests/, */tests/, docs/, portable.sh and this file.
# Full-line comments are ignored.
set -u
ROOT="${1:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
cd "$ROOT" || exit 2

PATS=(
  '(^|[^A-Za-z_-])flock([[:space:]]|$)'
  'date (-d|--date)'
  '(sha256sum|md5sum)'
  'stat -c'
  'sed -i([[:space:]]|$)'
  'readlink -f'
  'grep -[a-zA-Z]*P'
)
ADVICE=(
  'use p_flock / p_lock_acquire'
  'use p_date_d / p_epoch_fmt'
  'use p_sha256 / p_md5'
  'use p_stat_mtime / p_stat_size'
  'use p_sed_i'
  'use p_readlink_f'
  'rewrite with grep -E / sed -E / awk (no PCRE on BSD grep)'
)

# Tracked *.sh plus extensionless files with a sh/bash shebang (hook entry points, CLIs).
files="$( { git ls-files '*.sh'
            git ls-files | grep -vE '\.[A-Za-z0-9]+$' | while IFS= read -r f; do
                [ -f "$f" ] && head -n1 "$f" 2>/dev/null | grep -qE '^#!.*(ba)?sh([[:space:]]|$)' && echo "$f"
            done; } | sort -u | grep -vE '(^|/)tests?/|^docs/|^system/hooks/lib/portable\.sh$|^system/scripts/lint-portability\.sh$')"
bad=0
for i in "${!PATS[@]}"; do
    pat="${PATS[$i]}"; advice="${ADVICE[$i]}"
    while IFS= read -r line; do
        [ -n "$line" ] || continue
        echo "$line  <-- $advice"
        bad=$((bad + 1))
    done < <(printf '%s\n' "$files" | xargs grep -nE -- "$pat" 2>/dev/null \
        | grep -vE '^[^:]+:[0-9]+:[[:space:]]*#' \
        | grep -v 'portable-ok:' | cut -c1-200)
done

if [ "$bad" -eq 0 ]; then echo "OK: no GNU-only forms in production scripts"; exit 0; fi
echo "$bad portability violation(s)"; exit 1
