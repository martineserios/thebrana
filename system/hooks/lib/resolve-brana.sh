#!/usr/bin/env bash
# Shared brana CLI binary resolution.
# Sources: $BRANA override > PLUGIN_DATA (persistent) > SCRIPT_DIR (dev) > PLUGIN_ROOT (cache) > PATH
#
# Usage: source this file, then use $BRANA
# Expects: SCRIPT_DIR set by the calling hook

_resolve_brana() {
    local candidate

    # 0. Explicit override — same "$BRANA wins" convention already used by
    # close-snapshot.sh ("$BRANA > sibling release build > PATH"). Lets
    # dev/test callers pin a specific binary (e.g. a fake on PATH) without a
    # real sibling release build shadowing it via tier 2 below (t-3316).
    if [ -n "${BRANA:-}" ] && [ -x "${BRANA:-}" ]; then
        echo "$BRANA"
        return 0
    fi

    # 1. PLUGIN_DATA — persistent across plugin updates
    if [ -n "${CLAUDE_PLUGIN_DATA:-}" ]; then
        candidate="${CLAUDE_PLUGIN_DATA}/brana"
        [ -x "$candidate" ] && { echo "$candidate"; return 0; }
    fi

    # 2. Relative to hook script (dev mode / worktree)
    if [ -n "${SCRIPT_DIR:-}" ]; then
        candidate="${SCRIPT_DIR}/../cli/rust/target/release/brana"
        [ -x "$candidate" ] && { echo "$candidate"; return 0; }
    fi

    # 3. PLUGIN_ROOT (cache — may be stale after update)
    if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ]; then
        candidate="${CLAUDE_PLUGIN_ROOT}/cli/rust/target/release/brana"
        [ -x "$candidate" ] && { echo "$candidate"; return 0; }
    fi

    # 4. PATH fallback
    candidate=$(command -v brana 2>/dev/null) || true
    [ -x "$candidate" ] && { echo "$candidate"; return 0; }

    echo ""
    return 1
}

BRANA=$(_resolve_brana) || true
