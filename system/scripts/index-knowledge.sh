#!/usr/bin/env bash
# Index brana-knowledge dimension docs into ruflo memory for semantic search.
#
# DEPRECATED: This script is now bundled with the knowledge skill.
# Canonical location: system/skills/knowledge/index-knowledge.sh
# Deployed to: $HOME/.claude/skills/knowledge/index-knowledge.sh
# This copy is kept for backward compatibility (brana-knowledge post-commit hook, scheduler).
#
# Usage:
#   index-knowledge.sh              # Index all dimension docs
#   index-knowledge.sh file1.md     # Index specific file(s)
#   index-knowledge.sh --changed    # Index only git-changed files (for post-commit hook)
#
# Each doc is split by ## headings. Each section becomes a memory entry with:
#   Key:       knowledge:dimension:{doc-slug}:{section-slug}
#   Namespace: knowledge
#   Tags:      source:brana-knowledge,type:dimension,doc:{filename}
#   Value:     Section content (auto-embedded by ruflo memory store)

set -euo pipefail

KNOWLEDGE_DIR="${BRANA_KNOWLEDGE_DIR:-$HOME/enter_thebrana/brana-knowledge/dimensions}"
THEBRANA_DIR="${BRANA_THEBRANA_DIR:-$HOME/enter_thebrana/thebrana}"

# 7 doc categories with tier classification
# Format: "directory:type:tier"
# IMPORTANT: more specific paths MUST come before their parent paths
# (decisions/ and features/ before architecture/)
DOC_CATEGORIES=(
    "$KNOWLEDGE_DIR:dimension:semantic"
    "$THEBRANA_DIR/docs/architecture/decisions:decision:semantic"
    "$THEBRANA_DIR/docs/architecture/features:feature:episodic"
    "$THEBRANA_DIR/docs/architecture:architecture:semantic"
    "$THEBRANA_DIR/docs/reflections:reflection:semantic"
    "$THEBRANA_DIR/docs/ideas:idea:working"
    "$THEBRANA_DIR/docs/research:research:episodic"
)

# Load ruflo (formerly claude-flow)
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
if [ -f "$SCRIPT_DIR/cf-env.sh" ]; then
    source "$SCRIPT_DIR/cf-env.sh"
elif [ -f "$HOME/.claude/scripts/cf-env.sh" ]; then
    source "$HOME/.claude/scripts/cf-env.sh"
fi

if [ -z "$CF" ]; then
    echo "ERROR: ruflo not found. Cannot index." >&2
    exit 1
fi

# Verify we get real embeddings, not hash-fallback
MODEL_CHECK=$(timeout 30 $CF embeddings generate --text "test" 2>&1 || true)
if echo "$MODEL_CHECK" | grep -q "hash-fallback"; then
    echo "ERROR: ruflo using hash-fallback embeddings (useless). Install @xenova/transformers." >&2
    exit 1
fi

# Classify tier from filepath
classify_tier() {
    local filepath="$1"
    for cat in "${DOC_CATEGORIES[@]}"; do
        local dir="${cat%%:*}"
        local rest="${cat#*:}"
        local tier="${rest#*:}"
        if [[ "$filepath" == "$dir"/* ]]; then
            echo "$tier"
            return
        fi
    done
    echo "episodic"  # default
}

# Classify type from filepath
classify_type() {
    local filepath="$1"
    for cat in "${DOC_CATEGORIES[@]}"; do
        local dir="${cat%%:*}"
        local rest="${cat#*:}"
        local type="${rest%%:*}"
        if [[ "$filepath" == "$dir"/* ]]; then
            echo "$type"
            return
        fi
    done
    echo "unknown"
}

# Determine source tag from filepath
classify_source() {
    local filepath="$1"
    if [[ "$filepath" == *"brana-knowledge"* ]]; then
        echo "source:brana-knowledge"
    else
        echo "source:thebrana"
    fi
}

# Determine which files to index
FILES=()
ORPHAN_CLEANUP=false
if [ "${1:-}" = "--changed" ]; then
    # Git-changed files only (for post-commit hook)
    # Check both repos for changes
    for cat in "${DOC_CATEGORIES[@]}"; do
        local_dir="${cat%%:*}"
        [ -d "$local_dir" ] || continue
        cd "$local_dir"
        while IFS= read -r f; do
            [ -f "$local_dir/$f" ] && FILES+=("$local_dir/$f")
        done < <(git diff --name-only HEAD~1 HEAD -- . 2>/dev/null | grep '\.md$' || true)
    done
    if [ ${#FILES[@]} -eq 0 ]; then
        echo "No changed markdown files to index."
        exit 0
    fi
elif [ $# -gt 0 ]; then
    # Specific files
    for f in "$@"; do
        if [ -f "$f" ]; then
            FILES+=("$f")
        elif [ -f "$KNOWLEDGE_DIR/$f" ]; then
            FILES+=("$KNOWLEDGE_DIR/$f")
        else
            echo "WARN: File not found: $f" >&2
        fi
    done
else
    # All docs from all 7 categories (full reindex)
    ORPHAN_CLEANUP=true
    for cat in "${DOC_CATEGORIES[@]}"; do
        local_dir="${cat%%:*}"
        [ -d "$local_dir" ] || continue
        for f in "$local_dir"/*.md; do
            [ -f "$f" ] && FILES+=("$f")
        done
    done
fi

if [ ${#FILES[@]} -eq 0 ]; then
    echo "No files to index."
    exit 0
fi

echo "=== Index Knowledge Base ==="
echo "Files: ${#FILES[@]}"
echo ""

TOTAL_SECTIONS=0
TOTAL_STORED=0
ERRORS=0

# Track all keys we store (for orphan cleanup)
STORED_KEYS=()

store_section() {
    local key="$1" value="$2" tags="$3"
    local output
    output=$(cd "$HOME" && timeout 15 $CF memory store \
        -k "$key" \
        -v "$value" \
        --namespace knowledge \
        --tags "$tags" \
        --upsert 2>&1) || true

    if echo "$output" | grep -q "stored successfully"; then
        TOTAL_STORED=$((TOTAL_STORED + 1))
        STORED_KEYS+=("$key")
    else
        ERRORS=$((ERRORS + 1))
        echo "  WARN: Failed to store $key" >&2
    fi
    TOTAL_SECTIONS=$((TOTAL_SECTIONS + 1))
}

for filepath in "${FILES[@]}"; do
    filename=$(basename "$filepath")
    doc_slug="${filename%.md}"
    doc_type=$(classify_type "$filepath")
    doc_tier=$(classify_tier "$filepath")
    doc_source=$(classify_source "$filepath")

    echo "Indexing: $filename [$doc_type, tier:$doc_tier]"

    # Build tags string
    TAGS="${doc_source},type:${doc_type},doc:${filename},tier:${doc_tier}"

    # Parse sections by ## headers
    current_section=""
    current_title=""
    section_count=0

    while IFS= read -r line; do
        if [[ "$line" =~ ^##[[:space:]]+(.*) ]]; then
            # New section found — store the previous one if it has content
            if [ -n "$current_section" ] && [ -n "$current_title" ]; then
                section_slug=$(echo "$current_title" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/-/g' | sed 's/--*/-/g' | sed 's/^-//' | sed 's/-$//' | head -c 60)
                key="knowledge:${doc_type}:${doc_slug}:${section_slug}"

                # Truncate to ~2000 chars to keep embeddings focused
                value="${current_section:0:2000}"
                store_section "$key" "$value" "$TAGS"
            fi

            # Start new section
            current_title="${BASH_REMATCH[1]}"
            current_section=""
            section_count=$((section_count + 1))
        else
            # Accumulate content (skip frontmatter and empty leading lines)
            if [ -n "$current_title" ]; then
                current_section+="$line"$'\n'
            fi
        fi
    done < "$filepath"

    # Store the last section
    if [ -n "$current_section" ] && [ -n "$current_title" ]; then
        section_slug=$(echo "$current_title" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/-/g' | sed 's/--*/-/g' | sed 's/^-//' | sed 's/-$//' | head -c 60)
        key="knowledge:${doc_type}:${doc_slug}:${section_slug}"
        value="${current_section:0:2000}"
        store_section "$key" "$value" "$TAGS"
    fi

    echo "  → $section_count sections"
done

# ── Orphan cleanup (full reindex only) ──────────────────
ORPHANS_REMOVED=0
if [ "$ORPHAN_CLEANUP" = true ] && [ ${#STORED_KEYS[@]} -gt 0 ]; then
    echo ""
    echo "Checking for orphan entries..."
    # List all knowledge:* keys in ruflo
    EXISTING_KEYS=$(cd "$HOME" && $CF memory list --namespace knowledge --format json 2>/dev/null | jq -r '.[].key' 2>/dev/null || true)
    if [ -n "$EXISTING_KEYS" ]; then
        while IFS= read -r existing_key; do
            # Check if this key was stored in this run
            found=false
            for stored_key in "${STORED_KEYS[@]}"; do
                if [ "$existing_key" = "$stored_key" ]; then
                    found=true
                    break
                fi
            done
            if [ "$found" = false ]; then
                if cd "$HOME" && $CF memory delete -k "$existing_key" --namespace knowledge 2>/dev/null; then
                    ORPHANS_REMOVED=$((ORPHANS_REMOVED + 1))
                fi
            fi
        done <<< "$EXISTING_KEYS"
    fi
fi

echo ""
echo "=== Index Complete ==="
echo "Files:    ${#FILES[@]}"
echo "Sections: $TOTAL_SECTIONS"
echo "Stored:   $TOTAL_STORED"
echo "Errors:   $ERRORS"
if [ "$ORPHAN_CLEANUP" = true ]; then
    echo "Orphans:  $ORPHANS_REMOVED removed"
fi

# Tolerate up to 5% error rate (e.g. 2/432 = transient ruflo failures)
if [ $TOTAL_SECTIONS -gt 0 ]; then
    ERROR_PCT=$((ERRORS * 100 / TOTAL_SECTIONS))
    if [ $ERROR_PCT -ge 5 ]; then
        echo "Error rate ${ERROR_PCT}% exceeds 5% threshold"
        exit 1
    elif [ $ERRORS -gt 0 ]; then
        echo "Error rate ${ERROR_PCT}% within tolerance (${ERRORS}/${TOTAL_SECTIONS})"
    fi
fi
