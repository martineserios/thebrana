#!/usr/bin/env bash
# ruflo-discovery.sh — locate the ruflo (or legacy claude-flow) binary. (t-3381)
#
#   source "$SCRIPT_DIR/system/hooks/lib/ruflo-discovery.sh"
#   CF_BIN="$(ruflo_find_bin)"    # empty + rc 1 when not installed
#
# Order: an nvm-managed install first (the original behaviour), then anything on PATH — Homebrew's
# node (`/opt/homebrew/bin`), a custom npm prefix, a distro package. PATH is walked explicitly with
# -x: bash's `command -v` also reports a NON-executable file as found. `ruflo` beats `claude-flow`.
# Only absolute PATH entries are considered (a relative one is a PATH-planting vector).
ruflo_find_bin() {
    local name candidate d IFS
    for name in ruflo claude-flow; do
        for candidate in "$HOME"/.nvm/versions/node/*/bin/$name; do
            [ -f "$candidate" ] && [ -x "$candidate" ] && { printf '%s\n' "$candidate"; return 0; }
        done
        IFS=:
        for d in $PATH; do
            # ABSOLUTE entries only: "." / "bin" / "node_modules/.bin" / "" (= cwd) resolve against
            # wherever bootstrap happens to run, and bootstrap then npm-installs into a dir derived
            # from the binary it finds.
            case "$d" in /*) ;; *) continue ;; esac
            candidate="$d/$name"
            [ -f "$candidate" ] && [ -x "$candidate" ] && { printf '%s\n' "$candidate"; return 0; }
        done
        unset IFS
    done
    return 1
}
