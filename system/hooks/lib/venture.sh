#!/usr/bin/env bash
# Shared venture project detection — sourced by session hooks.
# Returns 0 if the given directory looks like a venture/business project.

_detect_venture() {
    local cwd="$1"
    for dir in docs/sops docs/okrs docs/metrics docs/pipeline docs/venture; do
        [ -d "$cwd/$dir" ] && return 0
    done
    [ -f "$cwd/CLAUDE.md" ] && grep -qiE '(venture|business|startup|revenue|pipeline|okr|growth)' "$cwd/CLAUDE.md" 2>/dev/null && return 0
    return 1
}
