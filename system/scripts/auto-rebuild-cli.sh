#!/usr/bin/env bash
set -euo pipefail

# auto-rebuild-cli.sh — Rebuild brana CLI when Rust sources change.
#
# Compares git tree hashes of system/cli/rust/ against a stored hash.
# If changed (or no prior hash), runs cargo build --release with OpenSSL env.
#
# Usage:
#   auto-rebuild-cli.sh           # Check and rebuild if needed
#   auto-rebuild-cli.sh --force   # Force rebuild regardless of hash
#
# Call sites:
#   - sync-state.sh pull (after git pull)
#   - post-merge git hook
#   - manual after pulling changes
#
# Requires: git, cargo, OpenSSL dev headers

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
THEBRANA_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
CLI_DIR="$THEBRANA_ROOT/system/cli/rust"
HASH_FILE="${XDG_STATE_HOME:-$HOME/.local/state}/brana/cli-build-hash"
BINARY="$CLI_DIR/target/release/brana"

log() { echo "[auto-rebuild-cli] $*" >&2; }

# ── Hash computation ──────────────────────────────────────

current_hash() {
    # Hash the entire cli/rust tree — catches Cargo.toml, Cargo.lock, and all source files
    git -C "$THEBRANA_ROOT" rev-parse HEAD:system/cli/rust 2>/dev/null || echo "unknown"
}

stored_hash() {
    if [ -f "$HASH_FILE" ]; then
        cat "$HASH_FILE"
    else
        echo "none"
    fi
}

store_hash() {
    mkdir -p "$(dirname "$HASH_FILE")"
    echo "$1" > "$HASH_FILE"
}

# ── Build ─────────────────────────────────────────────────

do_build() {
    log "building brana CLI (cargo build --release)..."

    # OpenSSL paths required on systems without pkg-config
    export OPENSSL_LIB_DIR="${OPENSSL_LIB_DIR:-/usr/lib/x86_64-linux-gnu}"
    export OPENSSL_INCLUDE_DIR="${OPENSSL_INCLUDE_DIR:-/usr/include/openssl}"

    if (cd "$CLI_DIR" && cargo build --release 2>&1); then
        log "build succeeded"
        return 0
    else
        log "build FAILED (exit $?)"
        return 1
    fi
}

# ── Main ──────────────────────────────────────────────────

main() {
    local force=false
    if [ "${1:-}" = "--force" ]; then
        force=true
    fi

    if [ ! -d "$CLI_DIR" ]; then
        log "skip — CLI directory not found: $CLI_DIR"
        exit 0
    fi

    local cur stored
    cur="$(current_hash)"
    stored="$(stored_hash)"

    if [ "$force" = true ]; then
        log "force rebuild requested"
    elif [ "$cur" = "$stored" ]; then
        log "up to date (hash: ${cur:0:12})"
        exit 0
    else
        log "change detected (stored: ${stored:0:12}, current: ${cur:0:12})"
    fi

    if do_build; then
        store_hash "$cur"
        # Verify binary exists
        if [ -f "$BINARY" ]; then
            log "binary ready: $BINARY"
        else
            log "warning: build succeeded but binary not found at $BINARY"
        fi
    else
        log "build failed — stored hash NOT updated (will retry next run)"
        exit 1
    fi
}

main "$@"
