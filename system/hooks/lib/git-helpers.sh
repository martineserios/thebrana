#!/usr/bin/env bash
# Shared git helper functions for PreToolUse hooks.
#
# Usage: source "$(dirname "${BASH_SOURCE[0]}")/git-helpers.sh"
#
# Provides:
#   extract_git_c_dir COMMAND       — path from `git -C <path>`, or ""
#   extract_cd_prefix_dir COMMAND   — path from leading `cd <path> &&`, or ""
#   resolve_lookup_dir COMMAND CWD  — -C path, else cd-prefix path, else CWD
#
# Spec: git-helpers.spec.md (t-1324)

# Extract the path passed to `git -C <path>` from a command string.
# Returns empty string if no -C flag is present.
extract_git_c_dir() {
    local command="$1"
    echo "$command" | sed -n 's/.*git[[:space:]]\+-C[[:space:]]\+\([^[:space:]]*\).*/\1/p'
}

# Extract the target of a leading `cd <path> &&` (or `;`, `||`) prefix.
# Matches only when `cd` is the first token of the command. Returns empty
# string if no such prefix is present. The path ends at whitespace or the
# next shell separator.
extract_cd_prefix_dir() {
    local command="$1"
    echo "$command" | sed -n 's/^[[:space:]]*cd[[:space:]]\+\([^[:space:]&;|]*\)[[:space:]]*\(&&\|;\|||\).*/\1/p'
}

# Return the directory to use for git operations in a PreToolUse hook.
# Precedence: git -C path > cd-prefix path > CWD.
resolve_lookup_dir() {
    local command="$1"
    local cwd="$2"
    local git_c_path cd_path
    git_c_path=$(extract_git_c_dir "$command")
    if [ -n "$git_c_path" ]; then
        echo "$git_c_path"
        return
    fi
    cd_path=$(extract_cd_prefix_dir "$command")
    echo "${cd_path:-$cwd}"
}
