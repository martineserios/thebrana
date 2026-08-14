#!/usr/bin/env bash
# Backport the upstream @claude-flow/memory packaging fix to the pinned
# install (t-2626 / t-2757).
#
# The pinned 3.0.0-alpha.21 dist/index.js exports ControllerRegistry twice:
#   line ~2:  export { ControllerRegistry } from './controller-registry-shim.js';
#   line ~62: export { ControllerRegistry, INIT_LEVELS } from './controller-registry.js';
# Duplicate ESM exports are a SyntaxError, so the AgentDB bridge import
# crashes ("Duplicate export of 'ControllerRegistry'"), latches the failure
# for the process lifetime, and every ruflo memory op falls back to sql.js —
# whole-file 41MB read-modify-writeFileSync. That fallback is the root cause
# of the daily ~/.swarm/memory.db torn-write corruption, the rotation loop,
# and the recurring knowledge loss (t-2615 evidence chain).
#
# Fix = dedupe: keep the deliberate shim export (it is the bridge-facing
# class), drop ControllerRegistry from the legacy line, keep INIT_LEVELS.
# With the import valid, the bridge initializes and writes go through the
# native better-sqlite3 WAL path: concurrent-safe (AC1), atomic under kill
# (AC2), no upstream dependency (AC3).
#
# Idempotent; never blocks the caller (ruflo-mcp.sh runs it pre-exec).
# Re-applies automatically after an npm upgrade/reinstall reverts the dist.
# Override target for tests: RUFLO_MEMORY_INDEX=/path/to/index.js

set -uo pipefail

DUP_LINE="export { ControllerRegistry, INIT_LEVELS } from './controller-registry.js';"
FIXED_LINE="export { INIT_LEVELS } from './controller-registry.js';"
SHIM_MARK="ControllerRegistry } from './controller-registry-shim.js'"

TARGET="${RUFLO_MEMORY_INDEX:-}"
if [ -z "$TARGET" ]; then
    TARGET=$(find "$HOME/.nvm/versions/node" \
        -path "*/ruflo/node_modules/@claude-flow/memory/dist/index.js" \
        2>/dev/null | head -1)
fi

if [ -z "$TARGET" ] || [ ! -f "$TARGET" ]; then
    echo "[patch-ruflo-memory] @claude-flow/memory dist/index.js not found — nothing to patch." >&2
    exit 0
fi

if ! grep -qF "$DUP_LINE" "$TARGET"; then
    # Already patched, or a different (fixed) upstream version — verify the
    # invariant and stay quiet.
    COUNT=$(grep -c "export { ControllerRegistry" "$TARGET" || true)
    if [ "$COUNT" -gt 1 ]; then
        echo "[patch-ruflo-memory] WARN: $COUNT ControllerRegistry exports in an unrecognized layout — manual look needed: $TARGET" >&2
    fi
    exit 0
fi

if ! grep -qF "$SHIM_MARK" "$TARGET"; then
    echo "[patch-ruflo-memory] WARN: shim export missing — layout unrecognized, refusing to patch: $TARGET" >&2
    exit 0
fi

cp "$TARGET" "${TARGET}.bak-$(date +%Y%m%d)" 2>/dev/null || true
# Escape for sed: the line contains { } . / ; — use a python-free approach
# with grep -v style rewrite via awk (exact full-line match, no regex).
tmp=$(mktemp)
awk -v dup="$DUP_LINE" -v fixed="$FIXED_LINE" '{ if ($0 == dup) print fixed; else print $0 }' \
    "$TARGET" > "$tmp" && mv "$tmp" "$TARGET"

if [ "$(grep -c "export { ControllerRegistry" "$TARGET")" = "1" ]; then
    echo "[patch-ruflo-memory] patched: deduped ControllerRegistry export in $TARGET"
else
    echo "[patch-ruflo-memory] WARN: post-patch verification failed for $TARGET" >&2
fi
exit 0
