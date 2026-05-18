#!/usr/bin/env bash
# Shared helpers for hook test scripts.
# Source this file after setting HOOK in the caller.

# Pipe $1 (JSON input) to the hook script, merging stderr into stdout.
run_hook() {
    local input="$1"
    echo "$input" | bash "$HOOK" 2>&1
}

# Like run_hook but extracts the first JSON line, discarding stderr.
# Use for hooks that spawn background jobs that write to stdout.
run_hook_json() {
    local input="$1"
    echo "$input" | bash "$HOOK" 2>/dev/null | grep '^{' | head -1
}

# Timed JSON-extracting variant. Outputs "elapsed_ms|json_output".
run_hook_timed() {
    local input="$1"
    local start_ms end_ms elapsed output
    start_ms=$(date +%s%3N 2>/dev/null || echo 0)
    output=$(echo "$input" | bash "$HOOK" 2>/dev/null | grep '^{' | head -1)
    end_ms=$(date +%s%3N 2>/dev/null || echo 0)
    elapsed=$((end_ms - start_ms))
    echo "$elapsed|$output"
}
