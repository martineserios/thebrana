#!/usr/bin/env bash
# Tests for patch-ruflo-memory-dup-export.sh (t-2626).
#
# The pinned @claude-flow/memory 3.0.0-alpha.21 exports ControllerRegistry
# twice from dist/index.js (shim line + legacy line) — an ESM SyntaxError
# that crashes the AgentDB bridge import, latching every ruflo memory op
# onto the sql.js whole-file-rewrite fallback (the t-2626 corruption root
# cause). Upstream fixed the packaging; this script backports the dedupe
# to the pinned local install.
#
# Hermetic: target file injected via RUFLO_MEMORY_INDEX.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PATCHER="$SCRIPT_DIR/../patch-ruflo-memory-dup-export.sh"
PASS=0
FAIL=0
TOTAL=0
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

check() {
    local label="$1" expected="$2" actual="$3"
    TOTAL=$((TOTAL + 1))
    if [ "$actual" = "$expected" ]; then
        PASS=$((PASS + 1)); echo "  PASS: $label"
    else
        FAIL=$((FAIL + 1)); echo "  FAIL: $label"; echo "    expected: $expected"; echo "    actual:   $actual"
    fi
}

mk_fixture() {
    cat > "$TMP/index.js" <<'JS'
// ===== ControllerRegistry Shim (bridges memory-bridge.js → AgentDB v3) =====
export { ControllerRegistry } from './controller-registry-shim.js';
/** module docblock */
export { MemoryGraph } from './memory-graph.js';
// ===== Controller Registry (ADR-053) =====
export { ControllerRegistry, INIT_LEVELS } from './controller-registry.js';
export { AgentDBAdapter } from './agentdb-adapter.js';
JS
}

export RUFLO_MEMORY_INDEX="$TMP/index.js"

echo "== patch-ruflo-memory tests =="

# 1. Duplicate present → patched: legacy line keeps INIT_LEVELS, drops
#    ControllerRegistry; shim line untouched; exit 0.
mk_fixture
bash "$PATCHER" >"$TMP/out1.log" 2>&1
check "patch run exits 0" "0" "$?"
check "exactly one ControllerRegistry export remains" "1" \
    "$(grep -c 'export { ControllerRegistry' "$TMP/index.js")"
check "shim export survives" "1" \
    "$(grep -c "ControllerRegistry } from './controller-registry-shim.js'" "$TMP/index.js")"
check "INIT_LEVELS export survives" "1" \
    "$(grep -c "INIT_LEVELS } from './controller-registry.js'" "$TMP/index.js")"
check "backup written" "1" "$(ls "$TMP"/index.js.bak-* 2>/dev/null | wc -l | tr -d ' ')"

# 2. Idempotent: second run exits 0, file unchanged, no second backup.
sum_before=$(md5sum "$TMP/index.js" | cut -d' ' -f1)
bash "$PATCHER" >"$TMP/out2.log" 2>&1
check "second run exits 0" "0" "$?"
check "second run leaves file unchanged" "$sum_before" "$(md5sum "$TMP/index.js" | cut -d' ' -f1)"
check "no second backup" "1" "$(ls "$TMP"/index.js.bak-* 2>/dev/null | wc -l | tr -d ' ')"

# 3. Missing target: exit 0 with a warning — the patcher is wired into the
#    MCP launcher and must never block ruflo startup.
export RUFLO_MEMORY_INDEX="$TMP/nope/index.js"
bash "$PATCHER" >"$TMP/out3.log" 2>&1
check "missing target exits 0" "0" "$?"

echo "== $PASS/$TOTAL passed, $FAIL failed =="
[ "$FAIL" -eq 0 ]
