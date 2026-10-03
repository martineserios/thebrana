#!/usr/bin/env bash
# mods-sync-shared.sh — vendor mods/_shared/hooks/*.ts into every mod that imports './_shared/'.
#
# WHY. The engine refuses an import that leaves the plugin's folder ("cannot import
# ../../_shared/x ... it is outside the plugin's folder" — tests/fixtures/mods/captures/
# probe-a-shared-import.txt, t-3450), in the source tree and in the install cache alike, so
# the shared code cannot be imported by relative path as cockpit.md first drew it. Each mod
# carries byte-identical copies instead; mods-check.sh --static (validate Check 77a) fails on
# any copy that drifts from its source, and a changed copy is a changed mod, so the
# version-bump guard fires too (that is the cache-drift guard working as intended).
#
# Usage: mods-sync-shared.sh [ROOT] [--check]
#   default  copy (or refresh) the files; prints one line per mod
#   --check  copy nothing; exit 1 if any mod would change
# Targets: every mods/<mod>/ (not _shared) whose hooks/*.ts(x) imports from './_shared/'.
# Files:   SHARED_FILES below — the shared tests are never vendored.
set -u
ROOT="${1:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
[ "${1:-}" = "--check" ] && { ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"; set -- "$ROOT" --check; }
CHECK=false; [ "${2:-}" = "--check" ] && CHECK=true
cd "$ROOT" || exit 2
SRC="mods/_shared/hooks"
SHARED_FILES=(allowlist run state probe snapshot)
[ -d "$SRC" ] || { echo "mods-sync-shared: $SRC not found under $ROOT" >&2; exit 2; }

changes=0
for mod in mods/*/; do
    mod="${mod%/}"; name="$(basename "$mod")"
    [ "$name" = "_shared" ] && continue
    [ -f "$mod/.claude-plugin/plugin.json" ] || continue
    grep -qsE "from ['\"]\./_shared/" "$mod"/hooks/*.ts "$mod"/hooks/*.tsx "$mod"/hooks/*.mts "$mod"/hooks/*.js "$mod"/hooks/*.mjs 2>/dev/null || continue
    for f in "${SHARED_FILES[@]}"; do
        src="$SRC/$f.ts"; dst="$mod/hooks/_shared/$f.ts"
        if [ -f "$dst" ] && cmp -s "$src" "$dst"; then continue; fi
        changes=$((changes + 1))
        if $CHECK; then
            echo "  ~ $dst (would copy from $src)"
        else
            # temp + rename: a concurrent mods-check --static never sees a half-written copy
            mkdir -p "$mod/hooks/_shared" && cp "$src" "$dst.tmp.$$" && mv -f "$dst.tmp.$$" "$dst" && echo "  + $dst"
        fi
    done
done
if $CHECK; then
    [ "$changes" -eq 0 ] && { echo "mods-sync-shared --check: all vendored copies current"; exit 0; }
    echo "mods-sync-shared --check: $changes file(s) out of date — run system/scripts/mods-sync-shared.sh"; exit 1
fi
echo "mods-sync-shared: $changes file(s) copied"
exit 0
