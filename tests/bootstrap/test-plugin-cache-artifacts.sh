#!/usr/bin/env bash
# Tests for plugin-cache build-artifact exclusion (t-2500).
#
# bootstrap.sh snapshotted system/ into ~/.claude/plugins/cache/ wholesale,
# including system/cli/rust/target/ — 24GB of Cargo output, against ~13MB for
# every other component combined. It is gitignored build output that never
# belonged in a plugin snapshot. Harms: disk, a multi-GB rsync every run, and a
# staleness check that could never go quiet (target/debug/incremental/*
# fingerprints change on every cargo build). It also made bootstrapping into a
# temp HOME die on "Disk quota exceeded".
#
# The cache cannot simply drop target/: brana and brana-query are resolved via
# CLAUDE_PLUGIN_ROOT (system/hooks/lib/resolve-brana.sh, session-start.sh) and
# would silently fall through to the PATH copy. Those two must survive.
#
# Tests:
#   T1: the kept-binary list names brana and brana-query
#   T2: rsync excludes cli/rust/target/ at every sync site
#   T3: no bare `diff -rq "$CACHE` staleness check remains
#   T4: behavioral — sync excludes build output but keeps the two binaries
#   T5: behavioral — prune reclaims a pre-existing target/ tree
#   T6: behavioral — prune refuses to touch a path outside a plugin cache
#   T7: behavioral — cache_diff notices a stale kept binary
#   T8: behavioral — cache_diff ignores build-output churn

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
BOOTSTRAP="$REPO_ROOT/bootstrap.sh"

PASS=0; FAIL=0; TOTAL=0

check() {
    local desc="$1" ok="$2" detail="${3:-}"
    TOTAL=$((TOTAL+1))
    if [ "$ok" = "0" ]; then
        PASS=$((PASS+1)); echo "  PASS: $desc"
    else
        FAIL=$((FAIL+1)); echo "  FAIL: $desc${detail:+ — $detail}"
    fi
}

echo "=== plugin cache build artifacts (t-2500) ==="

# --- static ------------------------------------------------------------------

grep -q 'CACHE_KEEP_BINS=(brana brana-query)' "$BOOTSTRAP"
check "T1: kept-binary list is brana + brana-query" $?

# Every rsync into a cache dir must carry the exclusion.
BARE=$(grep -n 'rsync -av' "$BOOTSTRAP" | grep -v 'CACHE_RSYNC_EXCLUDES' || true)
[ -z "$BARE" ]
check "T2: all cache rsync sites carry the exclusion" $? "$BARE"

BAREDIFF=$(grep -n 'diff -rq "\$CACHE\|diff -rq "\$cache' "$BOOTSTRAP" || true)
[ -z "$BAREDIFF" ]
check "T3: no bare recursive diff over the cache remains" $? "$BAREDIFF"

# --- behavioral --------------------------------------------------------------
# Extract the helpers rather than sourcing bootstrap.sh (which would deploy).

HELPERS=$(awk '/^CACHE_KEEP_BINS=/{flag=1} flag{print} /^# --- Plugin cache sync/{exit}' "$BOOTSTRAP")
if ! echo "$HELPERS" | grep -q 'prune_cache_target'; then
    for t in T4 T5 T6 T7 T8; do check "$t: helpers extractable" 1 "extraction failed"; done
else
    TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
    SRC="$TMP/system"
    CACHE="$TMP/home/.claude/plugins/cache/brana/brana/1.0.0"
    mkdir -p "$SRC/hooks" "$SRC/cli/rust/target/release" \
             "$SRC/cli/rust/target/debug/incremental" "$CACHE"
    echo 'hook' > "$SRC/hooks/a.sh"
    echo 'BRANA-V1'  > "$SRC/cli/rust/target/release/brana"
    echo 'QUERY-V1'  > "$SRC/cli/rust/target/release/brana-query"
    echo 'mcp'       > "$SRC/cli/rust/target/release/brana-mcp"
    head -c 200000 /dev/zero > "$SRC/cli/rust/target/debug/incremental/blob.bin"

    eval "$HELPERS"

    rsync -a --delete --exclude='.claude-plugin' "${CACHE_RSYNC_EXCLUDES[@]}" "$SRC/" "$CACHE/" >/dev/null 2>&1
    prune_cache_target "$CACHE"
    sync_cache_bins "$SRC" "$CACHE"

    [ -f "$CACHE/hooks/a.sh" ] \
      && [ -f "$CACHE/cli/rust/target/release/brana" ] \
      && [ -f "$CACHE/cli/rust/target/release/brana-query" ] \
      && [ ! -d "$CACHE/cli/rust/target/debug" ] \
      && [ ! -f "$CACHE/cli/rust/target/release/brana-mcp" ]
    check "T4: build output excluded, both resolved binaries kept" $? \
        "$(ls "$CACHE/cli/rust/target/release" 2>/dev/null | tr '\n' ' ')"

    # T5 — a cache populated before the fix must actually shrink. rsync
    # --exclude protects excluded paths from --delete, so without the prune the
    # old tree would survive untouched.
    mkdir -p "$CACHE/cli/rust/target/debug/deps"
    head -c 400000 /dev/zero > "$CACHE/cli/rust/target/debug/deps/old.rlib"
    prune_cache_target "$CACHE"
    [ ! -d "$CACHE/cli/rust/target/debug" ] && [ -f "$CACHE/cli/rust/target/release/brana" ]
    check "T5: prune reclaims a pre-existing target tree" $?

    # T6 — the guard: never delete under a path that is not a plugin cache.
    OUTSIDE="$TMP/not-a-cache"
    mkdir -p "$OUTSIDE/cli/rust/target/debug"
    echo keep > "$OUTSIDE/cli/rust/target/debug/precious"
    prune_cache_target "$OUTSIDE"
    [ -f "$OUTSIDE/cli/rust/target/debug/precious" ]
    check "T6: prune refuses paths outside a plugin cache" $?

    # T7 — a stale kept binary must still be detected.
    echo 'BRANA-V2' > "$SRC/cli/rust/target/release/brana"
    OUT=$(cache_diff "$CACHE" "$SRC")
    [[ "$OUT" == *"Binary brana differs"* ]]
    check "T7: cache_diff detects a stale kept binary" $? "$OUT"

    sync_cache_bins "$SRC" "$CACHE"

    # T8 — build-output churn must NOT register as a difference.
    echo 'churn' > "$SRC/cli/rust/target/debug/incremental/blob.bin"
    OUT=$(cache_diff "$CACHE" "$SRC")
    [ -z "$OUT" ]
    check "T8: cache_diff ignores build-output churn" $? "$OUT"
fi

echo ""
echo "$PASS/$TOTAL passed"
[ "$FAIL" -eq 0 ] || exit 1
