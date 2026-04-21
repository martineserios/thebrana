#!/usr/bin/env bash
# Shared Layer 1 path definitions for PreToolUse hooks.
#
# Usage: source "$(dirname "${BASH_SOURCE[0]}")/layer1-paths.sh"
#
# Layer 1 files are human-authored and load-bearing — never written by LLMs.
# Any hook that guards writes should source this lib and call is_layer1_file.
#
# Provides:
#   is_layer1_file FILE_PATH — returns 0 (true) if the path is a Layer 1 file

# Returns 0 if the given path is a Layer 1 (human-authored) file.
# Currently: any file named CLAUDE.md at any depth.
is_layer1_file() {
    local path="$1"
    case "$path" in
        *CLAUDE.md) return 0 ;;
        *)          return 1 ;;
    esac
}
