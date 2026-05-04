#!/usr/bin/env bash
# Diff a procedure file against its golden-path snapshot.
#
# Usage:
#   golden-path-diff.sh                   # diff all snapshots
#   golden-path-diff.sh <skill-name>      # diff one skill
#
# Compares system/procedures/<skill>.md against the matching snapshot(s)
# in system/tests/golden-paths/<skill>-*.json.
#
# Reports three drift categories:
#   1. Tools in procedure not in snapshot   (likely new tool used)
#   2. Tools in snapshot not in procedure   (likely tool removed/renamed)
#   3. Steps in snapshot not in procedure   (likely step removed/renamed)
#
# Exit 0 if no drift, 1 if drift found.
#
# Designed to be sourced from validate.sh OR run standalone.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
GOLDEN_DIR="$REPO_ROOT/system/tests/golden-paths"
PROC_DIR="$REPO_ROOT/system/procedures"

DRIFT_COUNT=0

# Tool name allowlist — only these are considered "tools" when scanning
# procedures. Keeps the regex from matching every backticked word.
KNOWN_TOOLS='Read|Write|Edit|Bash|Glob|Grep|Skill|Task|Agent|AskUserQuestion|TaskCreate|TaskUpdate|TaskList|WebSearch|WebFetch|backlog_get|backlog_set|backlog_add|backlog_query|backlog_search|backlog_stats|memory_search|memory_store'

extract_tools_from_procedure() {
    local proc_file="$1"
    [ -f "$proc_file" ] || return 0
    # Match tool names that appear as either:
    #   - Backticked: `ToolName(...`, `ToolName.`, `ToolName `
    #   - Bare in code: ToolName(
    grep -oE "(\`|^|[[:space:]])($KNOWN_TOOLS)([[:space:](.,\`])" "$proc_file" 2>/dev/null \
        | grep -oE "($KNOWN_TOOLS)" \
        | sort -u
}

extract_tools_from_snapshot() {
    local snap_file="$1"
    jq -r '[.steps[].tool_calls[]?.tool] | unique | .[]' "$snap_file" 2>/dev/null | sort -u
}

extract_steps_from_snapshot() {
    local snap_file="$1"
    jq -r '.steps[].name' "$snap_file" 2>/dev/null | sort -u
}

extract_steps_from_procedure() {
    local proc_file="$1"
    [ -f "$proc_file" ] || return 0
    # Step names appear as "## Step N: NAME", "### NAME", or "1. **NAME**"
    # We extract uppercase-tokens that look like step labels.
    {
        grep -oE '^## Step [0-9a-z]+: ([A-Z][A-Z\-]+)' "$proc_file" 2>/dev/null | sed 's/^## Step [0-9a-z]*: //'
        grep -oE '^### ([A-Z][A-Z\-]+)( |$)' "$proc_file" 2>/dev/null | sed 's/^### //; s/ *$//'
        grep -oE '^[0-9]+\. \*\*[A-Z][A-Z\-]+\*\*' "$proc_file" 2>/dev/null | sed 's/^[0-9]\+\. \*\*//; s/\*\*//'
    } | sort -u
}

diff_one() {
    local snap_file="$1"
    local skill_name
    skill_name=$(jq -r '.skill.name' "$snap_file" 2>/dev/null)
    [ -n "$skill_name" ] && [ "$skill_name" != "null" ] || {
        echo "  WARN: $(basename "$snap_file") missing skill.name — skipping"
        return 0
    }

    local proc_file="$PROC_DIR/$skill_name.md"
    if [ ! -f "$proc_file" ]; then
        echo "  WARN: $(basename "$snap_file") references skill '$skill_name' but $proc_file does not exist"
        DRIFT_COUNT=$((DRIFT_COUNT + 1))
        return 0
    fi

    local snap_label
    snap_label="$(basename "$snap_file" .json)"

    local proc_tools snap_tools
    proc_tools=$(extract_tools_from_procedure "$proc_file")
    snap_tools=$(extract_tools_from_snapshot "$snap_file")

    local new_tools removed_tools
    new_tools=$(comm -23 <(echo "$proc_tools") <(echo "$snap_tools") | grep -v '^$' || true)
    removed_tools=$(comm -13 <(echo "$proc_tools") <(echo "$snap_tools") | grep -v '^$' || true)

    local proc_steps snap_steps
    proc_steps=$(extract_steps_from_procedure "$proc_file")
    snap_steps=$(extract_steps_from_snapshot "$snap_file")
    local snap_only_steps
    snap_only_steps=$(comm -13 <(echo "$proc_steps") <(echo "$snap_steps") | grep -v '^$' || true)

    local issues=0
    [ -n "$new_tools" ] && issues=$((issues + 1))
    [ -n "$removed_tools" ] && issues=$((issues + 1))
    [ -n "$snap_only_steps" ] && issues=$((issues + 1))

    if [ "$issues" -gt 0 ]; then
        echo "  DRIFT: $snap_label vs $skill_name.md"
        [ -n "$new_tools" ] && echo "    new tools in procedure (not in snapshot): $(echo "$new_tools" | paste -sd, -)"
        [ -n "$removed_tools" ] && echo "    tools in snapshot but not in procedure: $(echo "$removed_tools" | paste -sd, -)"
        [ -n "$snap_only_steps" ] && echo "    steps in snapshot but not in procedure: $(echo "$snap_only_steps" | paste -sd, -)"
        DRIFT_COUNT=$((DRIFT_COUNT + issues))
    else
        echo "  OK:    $snap_label vs $skill_name.md"
    fi
}

main() {
    [ -d "$GOLDEN_DIR" ] || {
        echo "FAIL: $GOLDEN_DIR not found"
        exit 1
    }

    local filter="${1:-}"
    local snapshots=()
    if [ -n "$filter" ]; then
        for f in "$GOLDEN_DIR"/"$filter"-*.json "$GOLDEN_DIR"/"$filter".json; do
            [ -f "$f" ] && snapshots+=("$f")
        done
    else
        for f in "$GOLDEN_DIR"/*.json; do
            [ -f "$f" ] && snapshots+=("$f")
        done
    fi

    if [ "${#snapshots[@]}" -eq 0 ]; then
        echo "No snapshots found${filter:+ for '$filter'}"
        exit 0
    fi

    echo "Golden-path drift check"
    echo "======================="
    for snap in "${snapshots[@]}"; do
        diff_one "$snap"
    done
    echo ""
    if [ "$DRIFT_COUNT" -gt 0 ]; then
        echo "Drift: $DRIFT_COUNT issue(s) found"
        exit 1
    else
        echo "Drift: none"
        exit 0
    fi
}

# Only run main if executed directly (not when sourced)
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    main "$@"
fi
