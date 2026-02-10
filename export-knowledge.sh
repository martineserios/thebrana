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

# Layer 1: ReasoningBank (claude-flow)
echo "Exporting Layer 1 (ReasoningBank)..."
PATTERN_COUNT=0
REASONING_DB="$HOME/.swarm/memory.db"
if [ -f "$REASONING_DB" ]; then
    if command -v sqlite3 &>/dev/null; then
        sqlite3 "$REASONING_DB" "SELECT json_object('patterns', json_group_array(json_object('id', id, 'content', content, 'namespace', namespace, 'tags', tags, 'confidence', confidence, 'created_at', created_at))) FROM patterns;" > "$OUTPUT_DIR/reasoning-bank.json" 2>/dev/null || {
            echo '{"patterns": [], "note": "sqlite3 export failed — database may have different schema"}' > "$OUTPUT_DIR/reasoning-bank.json"
        }
        PATTERN_COUNT=$(sqlite3 "$REASONING_DB" "SELECT COUNT(*) FROM patterns;" 2>/dev/null || echo "0")
    else
        echo '{"patterns": [], "note": "sqlite3 not available — install sqlite3 to export ReasoningBank"}' > "$OUTPUT_DIR/reasoning-bank.json"
    fi
else
    echo '{"patterns": [], "note": "ReasoningBank not found at '"$REASONING_DB"' — claude-flow may not have been used yet"}' > "$OUTPUT_DIR/reasoning-bank.json"
fi
echo "  Found $PATTERN_COUNT patterns"

echo ""
echo "=== Export Complete ==="
echo "Location: $OUTPUT_DIR"
echo "  Native memory files: $MEMORY_COUNT"
echo "  ReasoningBank patterns: $PATTERN_COUNT"
