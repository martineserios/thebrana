#!/usr/bin/env bash
# Index brana-knowledge dimension docs into ruflo memory for semantic search.
#
# Two-phase pipeline:
#   Phase 1 (shell): Parse markdown by ## headers, classify tier/type → JSONL
#   Phase 2 (node):  bulk-index.mjs reads JSONL → batch embed + direct SQLite write
#
# Usage:
#   index-knowledge.sh              # Index all dimension docs (full reindex + orphan cleanup)
#   index-knowledge.sh file1.md     # Index specific file(s)
#   index-knowledge.sh --changed    # Index only git-changed files (for post-commit hook)
#
# Each doc is split by ## headings. Each section becomes a memory entry with:
#   Key:       knowledge:{type}:{doc-slug}:{section-slug}
#   Namespace: knowledge
#   Tags:      source:{repo},type:{type},doc:{filename},tier:{tier}

set -euo pipefail

KNOWLEDGE_DIR="${BRANA_KNOWLEDGE_DIR:-$HOME/enter_thebrana/brana-knowledge/dimensions}"
THEBRANA_DIR="${BRANA_THEBRANA_DIR:-$HOME/enter_thebrana/thebrana}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BULK_INDEXER="$SCRIPT_DIR/bulk-index.mjs"
MCP_INDEXER="$SCRIPT_DIR/mcp-index.mjs"

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

# ── Determine which files to index ──────────────────────────
FILES=()
ORPHAN_CLEANUP=false
if [ "${1:-}" = "--changed" ]; then
    # Git-changed files only (for post-commit hook)
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

# ── Phase 1: Parse markdown → JSONL ────────────────────────
JSONL_FILE=$(mktemp /tmp/knowledge-sections-XXXXXX.jsonl)
trap "rm -f $JSONL_FILE" EXIT

TOTAL_SECTIONS=0
TOTAL_FILES=0

for filepath in "${FILES[@]}"; do
    filename=$(basename "$filepath")
    doc_slug="${filename%.md}"
    doc_type=$(classify_type "$filepath")
    doc_tier=$(classify_tier "$filepath")
    doc_source=$(classify_source "$filepath")

    echo "Parsing: $filename [$doc_type, tier:$doc_tier]"

    # Build tags as JSON array
    TAGS_JSON="[\"${doc_source}\",\"type:${doc_type}\",\"doc:${filename}\",\"tier:${doc_tier}\"]"

    # Parse sections by ## headers
    current_section=""
    current_title=""
    section_count=0

    while IFS= read -r line; do
        if [[ "$line" =~ ^##[[:space:]]+(.*) ]]; then
            # New section found — emit the previous one
            if [ -n "$current_section" ] && [ -n "$current_title" ]; then
                section_slug=$(echo "$current_title" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/-/g' | sed 's/--*/-/g' | sed 's/^-//' | sed 's/-$//' | head -c 60)
                key="knowledge:${doc_type}:${doc_slug}:${section_slug}"
                # Truncate to ~2000 chars to keep embeddings focused
                value="${current_section:0:2000}"
                # Escape for JSON (newlines, quotes, backslashes)
                value=$(printf '%s' "$value" | jq -Rs '.')
                echo "{\"key\":\"$key\",\"value\":$value,\"tags\":$TAGS_JSON}" >> "$JSONL_FILE"
                section_count=$((section_count + 1))
            fi
            current_title="${BASH_REMATCH[1]}"
            current_section=""
        else
            if [ -n "$current_title" ]; then
                current_section+="$line"$'\n'
            fi
        fi
    done < "$filepath"

    # Emit the last section
    if [ -n "$current_section" ] && [ -n "$current_title" ]; then
        section_slug=$(echo "$current_title" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/-/g' | sed 's/--*/-/g' | sed 's/^-//' | sed 's/-$//' | head -c 60)
        key="knowledge:${doc_type}:${doc_slug}:${section_slug}"
        value="${current_section:0:2000}"
        value=$(printf '%s' "$value" | jq -Rs '.')
        echo "{\"key\":\"$key\",\"value\":$value,\"tags\":$TAGS_JSON}" >> "$JSONL_FILE"
        section_count=$((section_count + 1))
    fi

    TOTAL_SECTIONS=$((TOTAL_SECTIONS + section_count))
    TOTAL_FILES=$((TOTAL_FILES + 1))
    echo "  → $section_count sections"
done

echo ""
echo "Phase 1 complete: $TOTAL_SECTIONS sections from $TOTAL_FILES files → $JSONL_FILE"

if [ $TOTAL_SECTIONS -eq 0 ]; then
    echo "No sections to index."
    exit 0
fi

# ── Phase 2: Embed + store via Node.js ──────────────────────
# Default: MCP-first (mcp-index.mjs) — auto-embeddings, zero schema coupling.
# Fallback: SQLite direct (bulk-index.mjs) — offline, emergency recovery.
# Override: set USE_SQLITE=1 to force the SQLite path.

# Resolve node (prefer nvm)
NODE="${NODE:-}"
if [ -z "$NODE" ]; then
    export NVM_DIR="${NVM_DIR:-$HOME/.nvm}"
    if [ -s "$NVM_DIR/nvm.sh" ]; then
        source "$NVM_DIR/nvm.sh" 2>/dev/null
    fi
    NODE=$(command -v node 2>/dev/null || echo "")
    if [ -z "$NODE" ] && [ -d "$NVM_DIR/versions" ]; then
        NODE=$(find "$NVM_DIR/versions" -name node -type f | sort -V | tail -1)
    fi
fi

if [ -z "$NODE" ]; then
    echo "ERROR: node not found. Cannot run indexer." >&2
    exit 1
fi

CLEANUP_FLAG=""
if [ "$ORPHAN_CLEANUP" = true ]; then
    CLEANUP_FLAG="--cleanup"
fi

# Choose indexer: MCP-first unless USE_SQLITE=1 or ruflo not available or mcp-index.mjs missing
USE_MCP=false
if [ "${USE_SQLITE:-}" != "1" ] && [ -f "$MCP_INDEXER" ] && command -v ruflo &>/dev/null; then
    USE_MCP=true
fi

if [ "$USE_MCP" = true ]; then
    echo ""
    echo "Phase 2: MCP indexing via $MCP_INDEXER"
    set +e
    INDEXER_OUTPUT=$($NODE "$MCP_INDEXER" $CLEANUP_FLAG "$JSONL_FILE" 2>&1)
    MCP_EXIT=$?
    set -e
    if [ "$MCP_EXIT" -ne 0 ]; then
        echo "WARN: MCP indexing failed (exit $MCP_EXIT) — ruflo MCP unavailable, falling back to SQLite"
        echo ""
        echo "Phase 2: SQLite indexing via $BULK_INDEXER (MCP fallback)"
        INDEXER_OUTPUT=$($NODE "$BULK_INDEXER" $CLEANUP_FLAG "$JSONL_FILE" 2>&1)
    fi
else
    # Fallback: SQLite direct (bulk-index.mjs)
    if [ "${USE_SQLITE:-}" = "1" ]; then
        echo ""
        echo "Phase 2: SQLite indexing via $BULK_INDEXER (USE_SQLITE=1)"
    elif ! command -v ruflo &>/dev/null; then
        echo ""
        echo "Phase 2: SQLite indexing via $BULK_INDEXER (ruflo not found — falling back)"
    elif [ ! -f "$MCP_INDEXER" ]; then
        echo ""
        echo "Phase 2: SQLite indexing via $BULK_INDEXER (mcp-index.mjs not found — falling back)"
    fi

    if [ ! -f "$BULK_INDEXER" ]; then
        echo "ERROR: bulk-index.mjs not found at $BULK_INDEXER" >&2
        echo "Falling back to legacy per-section storage..." >&2
        # Legacy fallback: load ruflo CLI and store one-by-one
        if [ -f "$SCRIPT_DIR/cf-env.sh" ]; then
            source "$SCRIPT_DIR/cf-env.sh"
        elif [ -f "$HOME/.claude/scripts/cf-env.sh" ]; then
            source "$HOME/.claude/scripts/cf-env.sh"
        fi
        if [ -z "${CF:-}" ]; then
            echo "ERROR: ruflo not found. Cannot index." >&2
            exit 1
        fi
        STORED=0
        ERRORS=0
        while IFS= read -r line; do
            key=$(echo "$line" | jq -r '.key')
            value=$(echo "$line" | jq -r '.value')
            tags=$(echo "$line" | jq -r '.tags | join(",")')
            output=$(cd "$HOME" && timeout 15 $CF memory store -k "$key" -v "$value" --namespace knowledge --tags "$tags" --upsert 2>&1) || true
            if echo "$output" | grep -q "stored successfully"; then
                STORED=$((STORED + 1))
            else
                ERRORS=$((ERRORS + 1))
            fi
        done < "$JSONL_FILE"
        echo "=== Legacy Index Complete ==="
        echo "Stored: $STORED  Errors: $ERRORS"
        exit 0
    fi

    INDEXER_OUTPUT=$($NODE "$BULK_INDEXER" $CLEANUP_FLAG "$JSONL_FILE" 2>&1)
fi

echo "$INDEXER_OUTPUT"

# Tolerate up to 5% error rate from indexer output
BULK_ERRORS=$(echo "$INDEXER_OUTPUT" | grep -oP 'Errors:\s+\K\d+' || echo "0")
if [ "$TOTAL_SECTIONS" -gt 0 ] && [ "$BULK_ERRORS" -gt 0 ]; then
    ERROR_PCT=$((BULK_ERRORS * 100 / TOTAL_SECTIONS))
    if [ "$ERROR_PCT" -ge 5 ]; then
        echo "Error rate ${ERROR_PCT}% exceeds 5% threshold"
        exit 1
    fi
fi
