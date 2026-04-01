#!/usr/bin/env bash
# Index brana skill frontmatter into ruflo memory for semantic skill routing.
#
# Usage:
#   index-skills.sh              # Index all skills
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

# Load ruflo
if [ -f "$SCRIPT_DIR/cf-env.sh" ]; then
    source "$SCRIPT_DIR/cf-env.sh"
elif [ -f "$HOME/.claude/scripts/cf-env.sh" ]; then
    source "$HOME/.claude/scripts/cf-env.sh"
fi

if [ -z "$CF" ]; then
    echo "ERROR: ruflo not found. Cannot index skills." >&2
    exit 1
fi

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

if [ "${1:-}" = "--changed" ]; then
    CHANGED_ONLY=true
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

TOTAL=0
STORED=0
ERRORS=0

for skill_file in "${SKILL_FILES[@]}"; do
    name=$(parse_fm "name" < "$skill_file")
    description=$(parse_fm "description" < "$skill_file")
    keywords=$(parse_fm_array "keywords" < "$skill_file")
    strategies=$(parse_fm_array "task_strategies" < "$skill_file")
    streams=$(parse_fm_array "stream_affinity" < "$skill_file")
    group=$(parse_fm "group" < "$skill_file")
    effort=$(parse_fm "effort" < "$skill_file")

    [ -z "$name" ] && continue

    # Build embedding text: name + description + keywords + strategies
    embed_text="$name ${description:-} ${keywords:-} ${strategies:-} ${streams:-}"

    # Build tags
    source_tag="source:brana"
    if [[ "$skill_file" == *"/acquired/"* ]]; then
        source_tag="source:external"
    fi
    tags="${source_tag},group:${group:-unknown}"
    # Add each strategy as a tag
    for s in $strategies; do
        tags="${tags},strategy:${s}"
    done

    # Build value JSON
    value="{\"name\":\"${name}\",\"description\":\"${description:-}\",\"keywords\":\"${keywords:-}\",\"strategies\":\"${strategies:-}\",\"streams\":\"${streams:-}\",\"group\":\"${group:-}\",\"effort\":\"${effort:-}\"}"

    key="skill:${name}"

    if cd "$HOME" && $CF memory store \
        -k "$key" \
        -v "$embed_text" \
        --namespace skills \
        --tags "$tags" \
        --upsert 2>&1 | grep -q "stored successfully"; then
        STORED=$((STORED + 1))
        echo "  + $name [$group, $effort]"
    else
        ERRORS=$((ERRORS + 1))
        echo "  WARN: Failed to store $key" >&2
    fi
    TOTAL=$((TOTAL + 1))
done

# Update mtime marker
touch "$MTIME_FILE"

echo ""
echo "=== Skills Index Complete ==="
echo "Total:  $TOTAL"
echo "Stored: $STORED"
echo "Errors: $ERRORS"
