#!/usr/bin/env bash
# ruflo-cli.sh — single sanctioned CLI entry for ruflo (t-1936).
#
# Cures two diseases at one choke point:
#
# 1. Shebang breakage (t-1934): the ruflo npm tarball ships bin/ruflo.js with a
#    CRLF shebang (verified 3.10.39 + 3.10.40) and the Jun 9 update dropped the
#    exec bit. Direct invocation dies with "env: 'node\r'". We resolve the bin
#    symlink to the real .js and exec node on it — immune to both.
#
# 2. Session-row contamination (architecture review 2026-06-10 §4): session
#    namespace rows score a constant 0.5, so a namespace-less `memory search`
#    returns them as noise and drowns real recall. The documented rule —
#    "namespace 'all' only with threshold 0.55" — lived only in .mcp.json
#    instructions and CLAUDE.md; callers forgot it. Now the wrapper injects
#    `--threshold 0.55` whenever `memory search` is called without an explicit
#    --namespace or --threshold. Namespaced and explicitly-thresholded calls
#    pass through untouched.
#
# RUFLO_CLI_DRYRUN=1 prints the final command instead of executing (tests).

set -u

# ── Resolve node + ruflo entry .js ────────────────────────────────────────
RUFLO_BIN=""
for name in ruflo claude-flow; do
    for candidate in "$HOME"/.nvm/versions/node/*/bin/$name; do
        [ -e "$candidate" ] && RUFLO_BIN="$candidate" && break 2
    done
    [ -z "$RUFLO_BIN" ] && [ -e "$HOME/.npm-global/bin/$name" ] && RUFLO_BIN="$HOME/.npm-global/bin/$name" && break
done
[ -z "$RUFLO_BIN" ] && RUFLO_BIN="$(command -v ruflo || command -v claude-flow || true)"

if [ -z "$RUFLO_BIN" ]; then
    echo "[ruflo-cli] ruflo not found (nvm, ~/.npm-global, PATH). Install: npm i -g ruflo" >&2
    exit 127
fi

RUFLO_JS="$(readlink -f "$RUFLO_BIN" 2>/dev/null || echo "$RUFLO_BIN")"

# Prefer node from the same install tree as the bin (version match), then PATH.
NODE_BIN="$(dirname "$RUFLO_BIN")/node"
[ -x "$NODE_BIN" ] || NODE_BIN="$(command -v node || true)"
if [ -z "$NODE_BIN" ]; then
    echo "[ruflo-cli] node not found on PATH." >&2
    exit 127
fi

# ── Contamination guard: memory search without namespace/threshold ───────
args=("$@")
if [ "${1:-}" = "memory" ] && [ "${2:-}" = "search" ]; then
    has_scope=0
    for a in "$@"; do
        case "$a" in
            --namespace|--namespace=*|--threshold|--threshold=*) has_scope=1 ;;
        esac
    done
    if [ "$has_scope" -eq 0 ]; then
        args+=(--threshold 0.55)
        echo "[ruflo-cli] namespace-less search: injected --threshold 0.55 (session rows score 0.5 — see t-1936)" >&2
    fi
fi

# ── Execute (always from $HOME so ruflo uses ~/.swarm/memory.db) ──────────
if [ "${RUFLO_CLI_DRYRUN:-0}" = "1" ]; then
    echo "$NODE_BIN $RUFLO_JS ${args[*]}"
    exit 0
fi
cd "$HOME"
exec "$NODE_BIN" "$RUFLO_JS" "${args[@]}"
