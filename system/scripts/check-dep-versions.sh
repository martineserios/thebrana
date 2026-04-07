#!/usr/bin/env bash
# Dependency Version Tracker — checks all external deps against latest versions.
# Covers: Rust crates (Cargo.toml), npm tools (claude-code, ruflo), system CLIs.
# Reports only — never auto-upgrades.
#
# Usage: ./check-dep-versions.sh [--quiet]
# Output: /tmp/brana-dep-versions.txt

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CARGO_DIR="$SCRIPT_DIR/../cli/rust"
REPORT="/tmp/brana-dep-versions.txt"
QUIET="${1:-}"

log() { [[ "$QUIET" == "--quiet" ]] || echo "$@"; }

# ── Helpers ──────────────────────────────────────────────────────────────────

# Compare semver: returns "ok", "patch", "minor", or "major"
classify_update() {
    local current="$1" latest="$2"
    # Strip leading = or ^ or ~ for comparison
    current="${current#=}" ; current="${current#^}" ; current="${current#~}"
    latest="${latest#=}" ; latest="${latest#^}" ; latest="${latest#~}"

    [[ "$current" == "$latest" ]] && echo "ok" && return

    local cur_major cur_minor lat_major lat_minor
    cur_major="${current%%.*}" ; lat_major="${latest%%.*}"
    cur_minor="${current#*.}" ; cur_minor="${cur_minor%%.*}"
    lat_minor="${latest#*.}" ; lat_minor="${lat_minor%%.*}"

    if [[ "$cur_major" != "$lat_major" ]]; then
        echo "MAJOR"
    elif [[ "$cur_minor" != "$lat_minor" ]]; then
        echo "minor"
    else
        echo "patch"
    fi
}

# Query crates.io for latest version of a crate
crates_io_latest() {
    local crate="$1"
    curl -sf --max-time 10 "https://crates.io/api/v1/crates/$crate" \
        | grep -oE '"max_stable_version":"[^"]*"' \
        | head -1 \
        | cut -d'"' -f4
}

# Query npm registry for latest version
npm_latest() {
    local pkg="$1"
    npm view "$pkg" version 2>/dev/null || echo "?"
}

# ── Report Setup ─────────────────────────────────────────────────────────────

{
    echo "# Dependency Version Report — $(date '+%Y-%m-%d %H:%M')"
    echo ""

    # ── Rust Crates ──────────────────────────────────────────────────────────

    echo "## Rust Crates (workspace)"
    echo ""
    printf "%-20s %-12s %-12s %s\n" "CRATE" "CURRENT" "LATEST" "STATUS"
    printf "%-20s %-12s %-12s %s\n" "─────" "───────" "──────" "──────"

    if [ -f "$CARGO_DIR/Cargo.toml" ]; then
        # Extract workspace deps: lines matching `name = "version"` or `name = { version = "x" }`
        while IFS= read -r line; do
            # Skip comments, empty lines, section headers
            [[ "$line" =~ ^[[:space:]]*# ]] && continue
            [[ -z "$line" ]] && continue
            [[ "$line" =~ ^\[ ]] && continue

            local_name="" local_ver=""

            # Pattern: crate = "version"
            if [[ "$line" =~ ^([a-zA-Z_-]+)[[:space:]]*=[[:space:]]*\"([0-9][^\"]*)\" ]]; then
                local_name="${BASH_REMATCH[1]}"
                local_ver="${BASH_REMATCH[2]}"
            # Pattern: crate = { version = "version" ... }
            elif [[ "$line" =~ ^([a-zA-Z_-]+)[[:space:]]*=.*version[[:space:]]*=[[:space:]]*\"([0-9][^\"]*)\" ]]; then
                local_name="${BASH_REMATCH[1]}"
                local_ver="${BASH_REMATCH[2]}"
            fi

            [ -z "$local_name" ] && continue

            latest=$(crates_io_latest "$local_name")
            if [ -z "$latest" ]; then
                printf "%-20s %-12s %-12s %s\n" "$local_name" "$local_ver" "?" "error"
            else
                status=$(classify_update "$local_ver" "$latest")
                printf "%-20s %-12s %-12s %s\n" "$local_name" "$local_ver" "$latest" "$status"
            fi
        done < <(sed -n '/^\[workspace\.dependencies\]/,/^\[/p' "$CARGO_DIR/Cargo.toml" | head -n -1 | tail -n +2)
    else
        echo "(no Cargo.toml found at $CARGO_DIR)"
    fi

    echo ""

    # ── npm / Global Tools ───────────────────────────────────────────────────

    echo "## Global Tools"
    echo ""
    printf "%-20s %-12s %-12s %s\n" "TOOL" "CURRENT" "LATEST" "STATUS"
    printf "%-20s %-12s %-12s %s\n" "─────" "───────" "──────" "──────"

    # Claude Code
    cc_local=$(claude --version 2>/dev/null | head -1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1) || cc_local="?"
    cc_latest=$(npm_latest "@anthropic-ai/claude-code")
    cc_status=$(classify_update "$cc_local" "$cc_latest")
    printf "%-20s %-12s %-12s %s\n" "claude-code" "$cc_local" "$cc_latest" "$cc_status"

    # Ruflo
    ruflo_local=$(ruflo --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1) || ruflo_local="?"
    ruflo_latest=$(npm_latest "ruflo")
    ruflo_status=$(classify_update "$ruflo_local" "$ruflo_latest")
    printf "%-20s %-12s %-12s %s\n" "ruflo" "$ruflo_local" "$ruflo_latest" "$ruflo_status"

    echo ""

    # ── npm project deps (if any package.json exists) ────────────────────────

    # Check common locations for package.json
    for pjson_dir in "$SCRIPT_DIR/.." "$SCRIPT_DIR/../.."; do
        pjson="$pjson_dir/package.json"
        if [ -f "$pjson" ]; then
            echo "## npm Dependencies ($(realpath "$pjson_dir"))"
            echo ""
            (cd "$pjson_dir" && npm outdated --long 2>/dev/null) || echo "(npm outdated failed or no deps)"
            echo ""
        fi
    done

    # ── Summary ──────────────────────────────────────────────────────────────

    echo "---"
    echo "Generated: $(date '+%Y-%m-%d %H:%M:%S')"
    echo "Run: system/scripts/check-dep-versions.sh"

} > "$REPORT" 2>&1

log "Report written to $REPORT"
log ""
cat "$REPORT"
