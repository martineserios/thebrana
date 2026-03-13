#!/usr/bin/env bash
set -euo pipefail

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
OUTPUT_DIR="${1:-./knowledge-export-$TIMESTAMP}"

echo "=== Brana Knowledge Export ==="
echo "Output: $OUTPUT_DIR"
echo ""

mkdir -p "$OUTPUT_DIR"

# Layer 0: Native auto memory
echo "Exporting Layer 0 (native auto memory)..."
MEMORY_COUNT=0
if [ -d "$HOME/.claude/projects" ]; then
    for proj_dir in "$HOME/.claude/projects"/*/; do
        if [ -d "${proj_dir}memory" ]; then
            proj_name=$(basename "$proj_dir")
            mkdir -p "$OUTPUT_DIR/native-memory/$proj_name"
            cp -r "${proj_dir}memory/"* "$OUTPUT_DIR/native-memory/$proj_name/" 2>/dev/null || true
            MEMORY_COUNT=$((MEMORY_COUNT + $(find "${proj_dir}memory" -type f | wc -l)))
        fi
    done
fi
echo "  Found $MEMORY_COUNT memory files"

# Layer 1: ruflo memory DB
echo "Exporting Layer 1 (ruflo memory)..."
PATTERN_COUNT=0

# Find memory DB: prefer $HOME/.swarm/memory.db, fall back to CWD .swarm/memory.db
REASONING_DB=""
if [ -f "$HOME/.swarm/memory.db" ]; then
    REASONING_DB="$HOME/.swarm/memory.db"
elif [ -f ".swarm/memory.db" ]; then
    REASONING_DB=".swarm/memory.db"
fi

if [ -n "$REASONING_DB" ]; then
    # Primary: use claude-flow export command
    if command -v npx &>/dev/null; then
        if cd "$HOME" && npx ruflo memory export --output "$OUTPUT_DIR/reasoning-bank.json" --format json 2>/dev/null; then
            PATTERN_COUNT=$(jq 'length // 0' "$OUTPUT_DIR/reasoning-bank.json" 2>/dev/null || echo "0")
        else
            echo '{"patterns": [], "note": "claude-flow export failed"}' > "$OUTPUT_DIR/reasoning-bank.json"
        fi
    # Fallback: direct sqlite3 query
    elif command -v sqlite3 &>/dev/null; then
        sqlite3 "$REASONING_DB" "SELECT json_object('patterns', json_group_array(json_object('id', id, 'content', content, 'namespace', namespace, 'tags', tags, 'confidence', confidence, 'created_at', created_at))) FROM patterns;" > "$OUTPUT_DIR/reasoning-bank.json" 2>/dev/null || {
            echo '{"patterns": [], "note": "sqlite3 export failed — database may have different schema"}' > "$OUTPUT_DIR/reasoning-bank.json"
        }
        PATTERN_COUNT=$(sqlite3 "$REASONING_DB" "SELECT COUNT(*) FROM patterns;" 2>/dev/null || echo "0")
    else
        echo '{"patterns": [], "note": "Neither npx nor sqlite3 available for export"}' > "$OUTPUT_DIR/reasoning-bank.json"
    fi
else
    echo '{"patterns": [], "note": "Memory DB not found at $HOME/.swarm/memory.db or .swarm/memory.db — claude-flow may not have been used yet"}' > "$OUTPUT_DIR/reasoning-bank.json"
fi
echo "  Found $PATTERN_COUNT patterns"

echo ""
echo "=== Export Complete ==="
echo "Location: $OUTPUT_DIR"
echo "  Native memory files: $MEMORY_COUNT"
echo "  ReasoningBank patterns: $PATTERN_COUNT"
