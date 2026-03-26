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

# Load ruflo (formerly claude-flow)
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && source "$NVM_DIR/nvm.sh"
CF=""
for name in ruflo claude-flow; do
    for candidate in "$HOME"/.nvm/versions/node/*/bin/$name; do
        [ -x "$candidate" ] && CF="$candidate" && break 2
    done
done
[ -z "$CF" ] && command -v ruflo &>/dev/null && CF="ruflo"
[ -z "$CF" ] && command -v claude-flow &>/dev/null && CF="claude-flow"

if [ -z "$CF" ]; then
    echo "ERROR: ruflo not found. Cannot index." >&2
    exit 1
fi

# Verify we get real embeddings, not hash-fallback
MODEL_CHECK=$($CF embeddings generate --text "test" 2>&1 || true)
if echo "$MODEL_CHECK" | grep -q "hash-fallback"; then
    echo "ERROR: ruflo using hash-fallback embeddings (useless). Install @xenova/transformers." >&2
    exit 1
fi

# Determine which files to index
FILES=()
if [ "${1:-}" = "--changed" ]; then
    # Git-changed files only (for post-commit hook)
    cd "$KNOWLEDGE_DIR"
    while IFS= read -r f; do
        [ -f "$f" ] && FILES+=("$KNOWLEDGE_DIR/$f")
    done < <(git diff --name-only HEAD~1 HEAD -- . 2>/dev/null | grep '\.md$' || true)
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
    # All dimension docs
    for f in "$KNOWLEDGE_DIR"/*.md; do
        [ -f "$f" ] && FILES+=("$f")
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

for filepath in "${FILES[@]}"; do
    filename=$(basename "$filepath")
    doc_slug="${filename%.md}"

    echo "Indexing: $filename"

    # Parse sections by ## headers
    current_section=""
    current_title=""
    section_count=0

    while IFS= read -r line; do
        if [[ "$line" =~ ^##[[:space:]]+(.*) ]]; then
            # New section found — store the previous one if it has content
            if [ -n "$current_section" ] && [ -n "$current_title" ]; then
                section_slug=$(echo "$current_title" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/-/g' | sed 's/--*/-/g' | sed 's/^-//' | sed 's/-$//' | head -c 60)
                key="knowledge:dimension:${doc_slug}:${section_slug}"

                # Truncate to ~2000 chars to keep embeddings focused
                value="${current_section:0:2000}"

                if cd "$HOME" && $CF memory store \
                    -k "$key" \
                    -v "$value" \
                    --namespace knowledge \
                    --tags "source:brana-knowledge,type:dimension,doc:${filename}" \
                    --upsert 2>&1 | grep -q "stored successfully"; then
                    TOTAL_STORED=$((TOTAL_STORED + 1))
                else
                    ERRORS=$((ERRORS + 1))
                    echo "  WARN: Failed to store $key" >&2
                fi
                TOTAL_SECTIONS=$((TOTAL_SECTIONS + 1))
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
        key="knowledge:dimension:${doc_slug}:${section_slug}"
        value="${current_section:0:2000}"

        if cd "$HOME" && $CF memory store \
            -k "$key" \
            -v "$value" \
            --namespace knowledge \
            --tags "source:brana-knowledge,type:dimension,doc:${filename}" \
            --upsert 2>&1 | grep -q "stored successfully"; then
            TOTAL_STORED=$((TOTAL_STORED + 1))
        else
            ERRORS=$((ERRORS + 1))
        fi
        TOTAL_SECTIONS=$((TOTAL_SECTIONS + 1))
    fi

    echo "  → $section_count sections"
done

echo ""
echo "=== Index Complete ==="
echo "Files:    ${#FILES[@]}"
echo "Sections: $TOTAL_SECTIONS"
echo "Stored:   $TOTAL_STORED"
echo "Errors:   $ERRORS"

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
