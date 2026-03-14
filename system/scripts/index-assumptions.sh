#!/usr/bin/env bash
# Index assumptions and field notes from docs into ruflo memory.
#
# Creates/populates three namespaces (ADR-021):
#   - assumptions: explicit tracked claims from ADR/reflection frontmatter + tables
#   - field-notes: practical learnings from doc ## Field Notes sections
#   - decisions:   ADR decision summaries (title + decision + status)
#
# Usage:
#   index-assumptions.sh              # Index all ADRs + reflections + reasoning docs
#   index-assumptions.sh --changed    # Index only git-changed files
#   index-assumptions.sh file1.md     # Index specific file(s)

set -euo pipefail

DOCS_DIR="${BRANA_DOCS_DIR:-$(cd "$(dirname "$0")/../.." && pwd)/docs}"

# Load ruflo
source "$(dirname "$0")/cf-env.sh"

if [ -z "${CF:-}" ]; then
    echo "ERROR: ruflo not found. Cannot index." >&2
    exit 1
fi

# Determine which files to index
FILES=()
if [ "${1:-}" = "--changed" ]; then
    cd "$DOCS_DIR"
    while IFS= read -r f; do
        [ -f "$f" ] && FILES+=("$DOCS_DIR/$f")
    done < <(git diff --name-only HEAD~1 HEAD -- . 2>/dev/null | grep '\.md$' || true)
    if [ ${#FILES[@]} -eq 0 ]; then
        echo "No changed markdown files to index."
        exit 0
    fi
elif [ $# -gt 0 ]; then
    for f in "$@"; do
        [ -f "$f" ] && FILES+=("$f")
    done
else
    # All ADRs + reflections + reasoning docs
    for f in "$DOCS_DIR"/architecture/decisions/ADR-*.md; do
        [ -f "$f" ] && FILES+=("$f")
    done
    for f in "$DOCS_DIR"/reflections/*.md; do
        [ -f "$f" ] && FILES+=("$f")
    done
fi

if [ ${#FILES[@]} -eq 0 ]; then
    echo "No files to index."
    exit 0
fi

echo "=== Index Assumptions + Field Notes + Decisions ==="
echo "Files: ${#FILES[@]}"
echo ""

ASSUMPTIONS=0
FIELD_NOTES=0
DECISIONS=0
ERRORS=0

store_entry() {
    local key="$1" value="$2" namespace="$3" tags="$4"
    if cd "$HOME" && $CF memory store \
        -k "$key" \
        -v "${value:0:2000}" \
        --namespace "$namespace" \
        --tags "$tags" \
        --upsert 2>/dev/null; then
        return 0
    else
        return 1
    fi
}

for filepath in "${FILES[@]}"; do
    filename=$(basename "$filepath")
    doc_slug="${filename%.md}"

    echo "Scanning: $filename"

    content=$(<"$filepath")

    # --- Extract assumptions ---
    # Look for ## Assumptions section with table rows: | N | claim | if_wrong | verified |
    in_assumptions=false
    while IFS= read -r line; do
        if [[ "$line" =~ ^##[[:space:]]+Assumptions ]]; then
            in_assumptions=true
            continue
        fi
        if $in_assumptions && [[ "$line" =~ ^##[[:space:]] ]]; then
            in_assumptions=false
            continue
        fi
        if $in_assumptions && [[ "$line" =~ ^\|[[:space:]]*[0-9]+ ]]; then
            # Parse table row: | N | claim | if_wrong | verified |
            claim=$(echo "$line" | awk -F'|' '{gsub(/^[[:space:]]+|[[:space:]]+$/, "", $3); print $3}')
            if_wrong=$(echo "$line" | awk -F'|' '{gsub(/^[[:space:]]+|[[:space:]]+$/, "", $4); print $4}')

            if [ -n "$claim" ] && [ "$claim" != "Claim" ]; then
                key="assumption:${doc_slug}:$(echo "$claim" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/-/g' | sed 's/--*/-/g' | head -c 60)"
                value="Claim: $claim | If wrong: $if_wrong | Source: $filename"

                if store_entry "$key" "$value" "assumptions" "source:${doc_slug},type:assumption"; then
                    ASSUMPTIONS=$((ASSUMPTIONS + 1))
                else
                    ERRORS=$((ERRORS + 1))
                fi
            fi
        fi
    done <<< "$content"

    # --- Extract assumptions from YAML frontmatter ---
    if [[ "$content" =~ ^---$ ]]; then
        in_fm=true
        in_assumptions_yaml=false
        current_claim=""
        current_if_wrong=""

        while IFS= read -r line; do
            if $in_fm && [ "$line" = "---" ] && [ -n "$current_claim" ]; then
                break
            fi
            if [[ "$line" =~ ^assumptions: ]]; then
                in_assumptions_yaml=true
                continue
            fi
            if $in_assumptions_yaml; then
                if [[ "$line" =~ ^[[:space:]]*-[[:space:]]*claim: ]]; then
                    current_claim="${line#*claim:}"
                    current_claim="${current_claim## }"
                    current_claim="${current_claim%\"}"
                    current_claim="${current_claim#\"}"
                elif [[ "$line" =~ ^[[:space:]]*if_wrong: ]]; then
                    current_if_wrong="${line#*if_wrong:}"
                    current_if_wrong="${current_if_wrong## }"
                    current_if_wrong="${current_if_wrong%\"}"
                    current_if_wrong="${current_if_wrong#\"}"

                    if [ -n "$current_claim" ]; then
                        key="assumption:${doc_slug}:$(echo "$current_claim" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/-/g' | sed 's/--*/-/g' | head -c 60)"
                        value="Claim: $current_claim | If wrong: $current_if_wrong | Source: $filename"
                        if store_entry "$key" "$value" "assumptions" "source:${doc_slug},type:assumption"; then
                            ASSUMPTIONS=$((ASSUMPTIONS + 1))
                        else
                            ERRORS=$((ERRORS + 1))
                        fi
                    fi
                    current_claim=""
                    current_if_wrong=""
                elif [[ ! "$line" =~ ^[[:space:]] ]]; then
                    in_assumptions_yaml=false
                fi
            fi
        done <<< "$content"
    fi

    # --- Extract field notes ---
    in_field_notes=false
    current_note=""
    current_note_title=""

    while IFS= read -r line; do
        if [[ "$line" =~ ^##[[:space:]]+Field[[:space:]]+Notes ]]; then
            in_field_notes=true
            continue
        fi
        if $in_field_notes && [[ "$line" =~ ^##[[:space:]][^#] ]]; then
            in_field_notes=false
            continue
        fi
        if $in_field_notes; then
            if [[ "$line" =~ ^###[[:space:]]+(.*) ]]; then
                # Store previous note
                if [ -n "$current_note" ] && [ -n "$current_note_title" ]; then
                    key="field-note:${doc_slug}:$(echo "$current_note_title" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/-/g' | sed 's/--*/-/g' | head -c 60)"
                    if store_entry "$key" "$current_note" "field-notes" "source:${doc_slug},type:field-note"; then
                        FIELD_NOTES=$((FIELD_NOTES + 1))
                    else
                        ERRORS=$((ERRORS + 1))
                    fi
                fi
                current_note_title="${BASH_REMATCH[1]}"
                current_note=""
            else
                current_note+="$line"$'\n'
            fi
        fi
    done <<< "$content"
    # Store last field note
    if [ -n "$current_note" ] && [ -n "$current_note_title" ]; then
        key="field-note:${doc_slug}:$(echo "$current_note_title" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/-/g' | sed 's/--*/-/g' | head -c 60)"
        if store_entry "$key" "$current_note" "field-notes" "source:${doc_slug},type:field-note"; then
            FIELD_NOTES=$((FIELD_NOTES + 1))
        else
            ERRORS=$((ERRORS + 1))
        fi
    fi

    # --- Extract ADR decisions ---
    if [[ "$filename" =~ ^ADR- ]]; then
        # Get title from first H1
        title=$(grep -m1 '^# ' "$filepath" | sed 's/^# //')
        # Get status
        status=$(grep -m1 '^\*\*Status:\*\*\|^status:' "$filepath" | sed 's/.*: *//' | tr -d '*')
        # Get decision section (first paragraph after ## Decision)
        decision=""
        in_decision=false
        while IFS= read -r line; do
            if [[ "$line" =~ ^##[[:space:]]+Decision ]]; then
                in_decision=true
                continue
            fi
            if $in_decision; then
                if [[ "$line" =~ ^##[[:space:]] ]]; then
                    break
                fi
                if [ -n "$line" ]; then
                    decision+="$line "
                    # Just first paragraph
                    if [ ${#decision} -gt 200 ]; then
                        break
                    fi
                fi
            fi
        done < "$filepath"

        if [ -n "$title" ]; then
            key="decision:${doc_slug}"
            value="$title | Status: $status | Decision: ${decision:0:500}"
            if store_entry "$key" "$value" "decisions" "source:${doc_slug},type:adr"; then
                DECISIONS=$((DECISIONS + 1))
            else
                ERRORS=$((ERRORS + 1))
            fi
        fi
    fi

    counts=""
    [ $ASSUMPTIONS -gt 0 ] && counts+=" assumptions:$ASSUMPTIONS"
    [ $FIELD_NOTES -gt 0 ] && counts+=" field-notes:$FIELD_NOTES"
    [ $DECISIONS -gt 0 ] && counts+=" decisions:$DECISIONS"
done

echo ""
echo "=== Index Complete ==="
echo "Files:       ${#FILES[@]}"
echo "Assumptions: $ASSUMPTIONS"
echo "Field Notes: $FIELD_NOTES"
echo "Decisions:   $DECISIONS"
echo "Errors:      $ERRORS"

if [ $ERRORS -gt 0 ]; then
    exit 1
fi
