#!/usr/bin/env bash
# Shared helpers for hook test scripts.
# Source this file after setting HOOK in the caller.

# Pipe $1 (JSON input) to the hook script, merging stderr into stdout.
run_hook() {
    local input="$1"
    echo "$input" | bash "$HOOK" 2>&1
}
