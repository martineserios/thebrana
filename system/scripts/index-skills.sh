#!/usr/bin/env bash
# Index brana skill frontmatter into ruflo memory for semantic skill routing.
#
# Two-phase pipeline (reuses bulk-index.mjs):
#   Phase 1 (this script): Parse frontmatter → JSONL
#   Phase 2 (bulk-index.mjs): Batch embed + direct SQLite write
#
# Usage:
#   index-skills.sh              # Index all skills (+ orphan cleanup)
#   index-skills.sh --changed    # Index only skills with newer mtime than last run
#
# Each skill's frontmatter (name, description, keywords, task_strategies,
# stream_affinity, group, effort) is stored as a single memory entry.
# Skills can then be discovered via memory_search(namespace: "skills").
#
# Key format: skill:{name}
# Namespace:  skills
# Tags:       source:brana, group:{group}, strategy:{each strategy}

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SYSTEM_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
SKILLS_DIR="$SYSTEM_DIR/skills"
ACQUIRED_DIR="$SKILLS_DIR/acquired"
MTIME_FILE="/tmp/brana-skills-index-mtime"
BULK_INDEXER="$SCRIPT_DIR/bulk-index.mjs"

# Parse frontmatter value from SKILL.md
# Usage: parse_fm "field_name" < file
parse_fm() {
    local field="$1"
    sed -n '/^---$/,/^---$/p' | grep "^${field}:" | head -1 | sed "s/^${field}:[[:space:]]*//" | sed 's/^"//' | sed 's/"$//'
}

# Parse frontmatter array (YAML list on one line: [a, b, c])
parse_fm_array() {
    local field="$1"
    sed -n '/^---$/,/^---$/p' | grep "^${field}:" | head -1 | \
        sed "s/^${field}:[[:space:]]*//" | \
        sed 's/^\[//' | sed 's/\]$//' | \
        sed 's/,/ /g' | sed 's/"//g' | sed "s/'//g" | \
        tr -s ' '
}

# Determine which skills to index
SKILL_FILES=()
CHANGED_ONLY=false
ORPHAN_CLEANUP=true

if [ "${1:-}" = "--changed" ]; then
    CHANGED_ONLY=true
    ORPHAN_CLEANUP=false
fi

# Collect skill files from main + acquired directories
for dir in "$SKILLS_DIR"/*/; do
    skill_file="$dir/SKILL.md"
    [ -f "$skill_file" ] || continue
    # Skip _shared and acquired parent dir
    dirname=$(basename "$dir")
    [ "$dirname" = "_shared" ] && continue
    [ "$dirname" = "acquired" ] && continue

    if [ "$CHANGED_ONLY" = true ] && [ -f "$MTIME_FILE" ]; then
        if [ "$skill_file" -ot "$MTIME_FILE" ]; then
            continue  # Not modified since last index
        fi
    fi
    SKILL_FILES+=("$skill_file")
done

# Also index acquired skills
if [ -d "$ACQUIRED_DIR" ]; then
    for dir in "$ACQUIRED_DIR"/*/; do
        skill_file="$dir/SKILL.md"
        [ -f "$skill_file" ] || continue
        if [ "$CHANGED_ONLY" = true ] && [ -f "$MTIME_FILE" ]; then
            if [ "$skill_file" -ot "$MTIME_FILE" ]; then
                continue
            fi
        fi
        SKILL_FILES+=("$skill_file")
    done
fi

if [ ${#SKILL_FILES[@]} -eq 0 ]; then
    echo "No skills to index."
    touch "$MTIME_FILE"
    exit 0
fi

echo "=== Index Skills ==="
echo "Skills: ${#SKILL_FILES[@]}"
echo ""

# ── Phase 1: Parse frontmatter → JSONL ────────────────────────
JSONL_FILE=$(mktemp /tmp/skill-entries-XXXXXX.jsonl)
trap "rm -f $JSONL_FILE" EXIT

TOTAL=0
SKIPPED=0

for skill_file in "${SKILL_FILES[@]}"; do
    name=$(parse_fm "name" < "$skill_file")
    description=$(parse_fm "description" < "$skill_file")
    keywords=$(parse_fm_array "keywords" < "$skill_file")
    strategies=$(parse_fm_array "task_strategies" < "$skill_file")
    streams=$(parse_fm_array "stream_affinity" < "$skill_file")
    group=$(parse_fm "group" < "$skill_file")
    effort=$(parse_fm "effort" < "$skill_file")

    [ -z "$name" ] && { SKIPPED=$((SKIPPED + 1)); continue; }

    # Build embedding text: name + description + keywords + strategies + streams
    embed_text="$name ${description:-} ${keywords:-} ${strategies:-} ${streams:-}"

    # Determine source tag
    source_tag="source:brana"
    if [[ "$skill_file" == *"/acquired/"* ]]; then
        source_tag="source:external"
    fi

    # Build tags JSON array
    tags_json="[\"${source_tag}\",\"group:${group:-unknown}\""
    for s in $strategies; do
        tags_json="${tags_json},\"strategy:${s}\""
    done
    tags_json="${tags_json}]"

    # Escape embed_text for JSON (this is what bulk-index.mjs embeds + stores as content)
    value_escaped=$(printf '%s' "$embed_text" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()),end='')")

    key="skill:${name}"

    echo "{\"key\":\"$key\",\"value\":$value_escaped,\"namespace\":\"skills\",\"tags\":$tags_json}" >> "$JSONL_FILE"

    echo "  + $name [${group:-unknown}, ${effort:-?}]"
    TOTAL=$((TOTAL + 1))
done

echo ""
echo "Phase 1 complete: $TOTAL entries, $SKIPPED skipped"

if [ "$TOTAL" -eq 0 ]; then
    echo "Nothing to index."
    touch "$MTIME_FILE"
    exit 0
fi

# ── Phase 2: Bulk embed + write via bulk-index.mjs ────────────

# Resolve node (prefer nvm — ruflo is installed there, not in system node)
NODE="${NODE:-}"
if [ -z "$NODE" ]; then
    export NVM_DIR="${NVM_DIR:-$HOME/.nvm}"
    [ -s "$NVM_DIR/nvm.sh" ] && source "$NVM_DIR/nvm.sh" 2>/dev/null
    NODE=$(command -v node 2>/dev/null || echo "")
    # Fallback: search nvm versions dir directly
    if [ -z "$NODE" ] && [ -d "$NVM_DIR/versions" ]; then
        NODE=$(find "$NVM_DIR/versions" -name node -type f | sort -V | tail -1)
    fi
fi

if [ -z "$NODE" ]; then
    echo "ERROR: node not found. Cannot run bulk-index.mjs." >&2
    exit 1
fi

if [ -f "$BULK_INDEXER" ]; then
    CLEANUP_FLAG=""
    if [ "$ORPHAN_CLEANUP" = true ]; then
        CLEANUP_FLAG="--cleanup"
    fi
    echo ""
    echo "Phase 2: Bulk indexing via $BULK_INDEXER"
    $NODE "$BULK_INDEXER" $CLEANUP_FLAG "$JSONL_FILE"
else
    echo "WARN: bulk-index.mjs not found at $BULK_INDEXER"
    echo "JSONL written to: $JSONL_FILE (process manually)"
    trap - EXIT  # don't delete the file
    exit 1
fi

# Update mtime marker
touch "$MTIME_FILE"
