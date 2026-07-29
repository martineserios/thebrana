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

# Epoch milliseconds.
#
# NOT `date +%s%3N`. The %N field width is silently ignored on some coreutils
# builds — this machine returns all 9 nanosecond digits, so %s%3N yields epoch
# NANOseconds (19 digits). Callers then compared a nanosecond delta against a
# millisecond budget and reported a 7.9-second run as "7945758448ms" (92 days).
# %s%N is unambiguous everywhere; divide explicitly.
now_ms() {
    local ns
    ns=$(date +%s%N 2>/dev/null) || { echo 0; return; }
    case "$ns" in
        *[!0-9]*|"") echo 0 ;;
        *) echo $(( ns / 1000000 )) ;;
    esac
}

# Timed JSON-extracting variant. Outputs "elapsed_ms|json_output".
run_hook_timed() {
    local input="$1"
    local start_ms end_ms elapsed output
    start_ms=$(now_ms)
    output=$(echo "$input" | bash "$HOOK" 2>/dev/null | grep '^{' | head -1)
    end_ms=$(now_ms)
    elapsed=$((end_ms - start_ms))
    echo "$elapsed|$output"
}
