#!/usr/bin/env bash
# Shared git helper functions for PreToolUse hooks.
#
# Usage: source "$(dirname "${BASH_SOURCE[0]}")/git-helpers.sh"
#
# Provides:
#   extract_git_c_dir COMMAND   — returns the path from `git -C <path>`, or ""
#   resolve_lookup_dir COMMAND CWD — returns -C path if present, else CWD

# Extract the path passed to `git -C <path>` from a command string.
# Returns empty string if no -C flag is present.
extract_git_c_dir() {
    local command="$1"
    echo "$command" | sed -n 's/.*git[[:space:]]\+-C[[:space:]]\+\([^[:space:]]*\).*/\1/p'
}

# Return the directory to use for git operations: the -C target if present,
# otherwise fall back to CWD.
resolve_lookup_dir() {
    local command="$1"
    local cwd="$2"
    local git_c_path
    git_c_path=$(extract_git_c_dir "$command")
    echo "${git_c_path:-$cwd}"
}
