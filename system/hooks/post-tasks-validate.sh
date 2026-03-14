#!/usr/bin/env bash
# No strict mode — hooks must never fail and block the session.

# Task validation + rollup hook.
# Triggers: Write|Edit on any file matching */tasks.json
# Actions: (1) validate JSON+schema via Rust CLI (2) auto-rollup parents via Rust CLI
# Falls back to jq if Rust binary is not available.

cd /tmp 2>/dev/null || true

INPUT=$(cat) || true
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null) || true
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null) || true

# Only trigger on tasks.json writes
case "$FILE_PATH" in
    */.claude/tasks.json) ;;
    *) echo '{"continue": true}'; exit 0 ;;
esac

[ ! -f "$FILE_PATH" ] && { echo '{"continue": true}'; exit 0; }

# Locate Rust CLI binary
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BRANA="${SCRIPT_DIR}/../cli/rust/target/release/brana"
[ ! -x "$BRANA" ] && BRANA="${CLAUDE_PLUGIN_ROOT:-}/cli/rust/target/release/brana"
USE_RUST=false
[ -x "$BRANA" ] && USE_RUST=true

# ── Step 1+2: Validate JSON + schema ─────────────────────
if [ "$USE_RUST" = true ]; then
    VALIDATE_OUT=$("$BRANA" validate "$FILE_PATH" 2>/dev/null) || true
    VALID=$(echo "$VALIDATE_OUT" | jq -r '.valid // empty' 2>/dev/null) || true
    if [ "$VALID" = "false" ]; then
        ERRORS=$(echo "$VALIDATE_OUT" | jq -r '.errors // "unknown error"' 2>/dev/null) || true
        ESCAPED=$(echo "tasks.json errors: $ERRORS" | jq -Rs '.')
        echo "{\"continue\": true, \"additionalContext\": $ESCAPED}"
        exit 0
    fi
else
    # Fallback: jq validation
    if ! jq empty "$FILE_PATH" 2>/dev/null; then
        ERRORS="tasks.json has invalid JSON. Fix the syntax error before continuing."
        ESCAPED=$(echo "$ERRORS" | jq -Rs '.')
        echo "{\"continue\": true, \"additionalContext\": $ESCAPED}"
        exit 0
    fi

    SCHEMA_ERRORS=$(jq -r '
      [ if .version == null then "missing version" else empty end,
        if .project == null then "missing project" else empty end,
        if (.tasks | type) != "array" then "tasks must be array" else empty end,
        (.tasks[] |
          [ if .id == null then "task missing id" else empty end,
            if .subject == null then "task \(.id // "?") missing subject" else empty end,
            if .status == null then "task \(.id // "?") missing status" else empty end,
            if (.status | IN("pending","in_progress","completed","cancelled") | not)
              then "task \(.id // "?"): invalid status \(.status)" else empty end,
            if .type == null then "task \(.id // "?") missing type" else empty end,
            if (.type | IN("phase","milestone","task","subtask") | not)
              then "task \(.id // "?"): invalid type \(.type)" else empty end,
            if .stream == null then "task \(.id // "?") missing stream" else empty end,
            if .tags != null and (.tags | type) != "array"
              then "task \(.id // "?"): tags must be array" else empty end,
            if .tags != null and (.tags | type) == "array" and ([.tags[] | type != "string"] | any)
              then "task \(.id // "?"): tags items must be strings" else empty end,
            if .context != null and (.context | type) != "string"
              then "task \(.id // "?"): context must be string" else empty end
          ] | .[]
        )
      ] | if length > 0 then join("; ") else empty end
    ' "$FILE_PATH" 2>/dev/null) || true

    if [ -n "$SCHEMA_ERRORS" ]; then
        ERRORS="tasks.json schema errors: $SCHEMA_ERRORS. Fix these fields."
        ESCAPED=$(echo "$ERRORS" | jq -Rs '.')
        echo "{\"continue\": true, \"additionalContext\": $ESCAPED}"
        exit 0
    fi
fi

# ── Step 3: Parent rollup ──────────────────────────────
if [ "$USE_RUST" = true ]; then
    ROLLUP_OUT=$("$BRANA" backlog rollup --file "$FILE_PATH" 2>/dev/null) || true
    if [ -n "$ROLLUP_OUT" ]; then
        ROLLUP_IDS=$(echo "$ROLLUP_OUT" | jq -r '.rollup | join(",")' 2>/dev/null) || true
        if [ -n "$ROLLUP_IDS" ]; then
            ROLLUP_MSG="Auto-rollup: completed parents [${ROLLUP_IDS}] — all children done."
            ESCAPED=$(echo "$ROLLUP_MSG" | jq -Rs '.')
            echo "{\"continue\": true, \"additionalContext\": $ESCAPED}"
            exit 0
        fi
    fi
else
    # Fallback: jq rollup
    ROLLUP_NEEDED=$(jq -r '
      [.tasks[] | select(.parent != null)] as $children |
      [.tasks[] | select(.type == "milestone" or .type == "phase")] as $parents |
      [
        $parents[] |
        . as $p |
        [$children[] | select(.parent == $p.id)] as $kids |
        if ($kids | length) > 0 and ($kids | all(.status == "completed")) and $p.status != "completed"
        then $p.id
        else empty end
      ] | join(",")
    ' "$FILE_PATH" 2>/dev/null) || true

    if [ -n "$ROLLUP_NEEDED" ]; then
        IFS=',' read -ra PARENTS_TO_COMPLETE <<< "$ROLLUP_NEEDED"
        TODAY=$(date +%Y-%m-%d)

        TMP_FILE=$(mktemp)
        cp "$FILE_PATH" "$TMP_FILE"

        for PID in "${PARENTS_TO_COMPLETE[@]}"; do
            [ -z "$PID" ] && continue
            jq --arg pid "$PID" --arg today "$TODAY" --arg now "$(date -Iseconds)" '
              .tasks |= map(
                if .id == $pid then
                  .status = "completed" | .completed = $today
                else . end
              ) | .last_modified = $now
            ' "$TMP_FILE" > "${TMP_FILE}.new" && mv "${TMP_FILE}.new" "$TMP_FILE"
        done

        if ! diff -q "$FILE_PATH" "$TMP_FILE" > /dev/null 2>&1; then
            cp "$TMP_FILE" "$FILE_PATH"
            ROLLUP_MSG="Auto-rollup: completed parents [${ROLLUP_NEEDED}] — all children done."
            ESCAPED=$(echo "$ROLLUP_MSG" | jq -Rs '.')
            rm -f "$TMP_FILE"
            echo "{\"continue\": true, \"additionalContext\": $ESCAPED}"
            exit 0
        fi
        rm -f "$TMP_FILE"
    fi
fi

echo '{"continue": true}'
