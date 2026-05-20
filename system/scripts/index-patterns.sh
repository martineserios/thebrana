#!/usr/bin/env bash
# Index pattern files (feedback_*.md, project_*.md) from all project memory dirs
# into ruflo memory for semantic search.
#
# Two-phase pipeline (reuses bulk-index.mjs):
#   Phase 1 (this script): Parse frontmatter + body → JSONL
#   Phase 2 (bulk-index.mjs): Batch embed + direct SQLite write
#
# Usage:
#   index-patterns.sh                    # Index all pattern files across all projects
#   index-patterns.sh --project thebrana # Index pattern files for a specific project
#   index-patterns.sh file1.md file2.md  # Index specific files
#
# Each file becomes one memory entry with:
#   Key:       pattern:{type}:{slug}
#   Namespace: pattern
#   Tags:      source:auto-memory,type:{type},project:{project}

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BULK_INDEXER="$SCRIPT_DIR/bulk-index.mjs"

# ── Collect files ─────────────────────────────────────────────
FILES=()
ORPHAN_CLEANUP=false
PROJECT_FILTER=""

while [ $# -gt 0 ]; do
    case "$1" in
        --project)
            PROJECT_FILTER="$2"
            shift 2
            ;;
        --cleanup)
            ORPHAN_CLEANUP=true
            shift
            ;;
        *)
            if [ -f "$1" ]; then
                FILES+=("$1")
            else
                echo "WARN: File not found: $1" >&2
            fi
            shift
            ;;
    esac
done

PATTERNS_MD="${LINT_HEAL_PATTERNS_FILE:-$HOME/.claude/memory/patterns.md}"

if [ ${#FILES[@]} -eq 0 ]; then
    # Scan all project memory dirs
    ORPHAN_CLEANUP=true
    for projdir in "$HOME"/.claude/projects/*/memory/; do
        [ -d "$projdir" ] || continue

        # Apply project filter if specified
        if [ -n "$PROJECT_FILTER" ]; then
            if ! grep -qi "$PROJECT_FILTER" <<< "$projdir"; then
                continue
            fi
        fi

        for f in "$projdir"feedback_*.md "$projdir"project_*.md "$projdir"pattern_*.md; do
            [ -f "$f" ] && FILES+=("$f")
        done
    done

    # Include shared patterns.md (cross-project, section-based)
    [ -f "$PATTERNS_MD" ] && FILES+=("$PATTERNS_MD")
fi

if [ ${#FILES[@]} -eq 0 ]; then
    echo "No pattern files to index."
    exit 0
fi

echo "=== Index Pattern Files ==="
echo "Files: ${#FILES[@]}"
echo ""

# ── Phase 1: Parse frontmatter + body → JSONL ────────────────
JSONL_FILE=$(mktemp /tmp/pattern-sections-XXXXXX.jsonl)
trap "rm -f $JSONL_FILE" EXIT

TOTAL=0
SKIPPED=0

for filepath in "${FILES[@]}"; do
    filename=$(basename "$filepath")

    # ── patterns.md: section-based parsing (no frontmatter) ───────
    # Detect by filename OR by content signature (# Pattern Store header).
    if [ "$filename" = "patterns.md" ] || [[ "$(head -1 "$filepath")" == "# Pattern Store"* ]]; then
        # Parse each ## slug section into a separate JSONL entry.
        # Confidence field sets the key type: pattern:{confidence}:{slug}
        # Uses awk to split on ## headers — avoids nested function scope issues.
        while IFS='|' read -r sec_slug sec_body; do
            [ -z "$sec_slug" ] && continue
            conf_line=$(printf '%s' "$sec_body" | grep -i '^\*\*Confidence:\*\*' 2>/dev/null || true)
            confidence=$(printf '%s' "$conf_line" | sed 's/\*\*Confidence:\*\*[[:space:]]*//' | tr -d '[:space:]' | head -1)
            [ -z "$confidence" ] && confidence="quarantine"
            key="pattern:${confidence}:${sec_slug}"
            value=$(printf '%s' "${sec_body:0:2000}" | jq -Rs '.')
            tags_json="[\"source:patterns-md\",\"type:pattern\",\"confidence:${confidence}\",\"file:patterns.md\"]"
            echo "{\"key\":\"$key\",\"value\":$value,\"namespace\":\"pattern\",\"tags\":$tags_json}" >> "$JSONL_FILE"
            TOTAL=$((TOTAL + 1))
        done < <(awk '
            /^## / {
                if (slug != "") { print slug "|" body }
                slug = substr($0, 4)
                body = ""
                next
            }
            slug != "" { body = body $0 "\n" }
            END { if (slug != "") print slug "|" body }
        ' "$filepath")

        continue
    fi

    # ── Standard frontmatter-based parsing ────────────────────────
    slug="${filename%.md}"

    # Extract frontmatter
    if [[ "$(head -1 "$filepath")" != "---" ]]; then
        echo "  SKIP: $filename (no frontmatter)"
        SKIPPED=$((SKIPPED + 1))
        continue
    fi

    # Parse frontmatter fields
    fm=$(sed -n '2,/^---$/p' "$filepath" | head -20)
    name=$(echo "$fm" | grep '^name:' | sed 's/^name: *//' | head -1)
    description=$(echo "$fm" | grep '^description:' | sed 's/^description: *//' | head -1)
    type=$(echo "$fm" | grep -E '^\s*type:' | sed 's/.*type: *//' | tr -d '[:space:]' | head -1)

    if [ -z "$name" ] || [ -z "$type" ]; then
        echo "  SKIP: $filename (missing name or type)"
        SKIPPED=$((SKIPPED + 1))
        continue
    fi

    # Extract body (everything after second ---)
    body=$(awk '/^---$/{c++; next} c>=2' "$filepath" 2>/dev/null)
    if [ -z "$body" ]; then
        echo "  SKIP: $filename (empty body)"
        SKIPPED=$((SKIPPED + 1))
        continue
    fi

    # Derive project from path (graceful — may be outside projects dir)
    project=$(echo "$filepath" | grep -oP '(?<=projects/)[^/]+' | sed 's/^-home-[^-]*-//' | sed 's/-/\//g' | head -1) || project="unknown"
    [ -z "$project" ] && project="unknown"
    # Simplify: take last path segment
    project_short=$(echo "$project" | rev | cut -d'/' -f1 | rev)

    # Build key
    key="pattern:${type}:${slug}"

    # Truncate body to ~2000 chars
    value="${body:0:2000}"

    # Escape for JSON
    value=$(printf '%s' "$value" | jq -Rs '.')
    desc_escaped=$(printf '%s' "${description:-$name}" | jq -Rs '.')

    # Build tags
    tags_json="[\"source:auto-memory\",\"type:${type}\",\"project:${project_short}\",\"file:${filename}\"]"

    echo "{\"key\":\"$key\",\"value\":$value,\"namespace\":\"pattern\",\"tags\":$tags_json}" >> "$JSONL_FILE"
    TOTAL=$((TOTAL + 1))
done

echo ""
echo "Phase 1 complete: $TOTAL entries, $SKIPPED skipped"

if [ "$TOTAL" -eq 0 ]; then
    echo "Nothing to index."
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
