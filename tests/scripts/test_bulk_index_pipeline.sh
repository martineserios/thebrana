#!/usr/bin/env bash
# Tests for the bulk-index pipeline: JSONL generation from index-knowledge.sh
# and bulk-index.mjs interface contract.
# Run: bash tests/scripts/test_bulk_index_pipeline.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
TMPDIR=$(mktemp -d)
trap "rm -rf $TMPDIR" EXIT

PASS=0
FAIL=0
TOTAL=0

assert() {
    local desc="$1" expected="$2" actual="$3"
    TOTAL=$((TOTAL + 1))
    if [ "$expected" = "$actual" ]; then
        echo "  PASS: $desc"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $desc (expected '$expected', got '$actual')"
        FAIL=$((FAIL + 1))
    fi
}

assert_contains() {
    local desc="$1" needle="$2" haystack="$3"
    TOTAL=$((TOTAL + 1))
    if [[ "$haystack" == *"$needle"* ]]; then
        echo "  PASS: $desc"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $desc (expected to contain '$needle')"
        FAIL=$((FAIL + 1))
    fi
}

echo "=== test_bulk_index_pipeline.sh ==="

# ── Setup: create test markdown files ──
mkdir -p "$TMPDIR/dimensions" "$TMPDIR/ideas"

cat > "$TMPDIR/dimensions/test-doc.md" << 'MARKDOWN'
---
title: Test Doc
---

# Test Doc

Intro paragraph.

## First Section

Content of the first section with some details.

## Second Section

Content of the second section.

### Subsection (h3 — should NOT split)

Still part of second section.

## Third Section

Final section content.
MARKDOWN

cat > "$TMPDIR/ideas/brainstorm.md" << 'MARKDOWN'
# Brainstorm

## Only Section

Just one section here.
MARKDOWN

# ── Test 1: JSONL generation (simulate the parsing logic) ──
echo "Test 1: Markdown parsing → JSONL"

# Replicate the parsing logic from index-knowledge.sh
generate_jsonl() {
    local filepath="$1" doc_type="$2" doc_tier="$3" doc_source="$4"
    local filename doc_slug
    filename=$(basename "$filepath")
    doc_slug="${filename%.md}"
    local tags_json="[\"${doc_source}\",\"type:${doc_type}\",\"doc:${filename}\",\"tier:${doc_tier}\"]"

    local current_section="" current_title="" section_count=0

    while IFS= read -r line; do
        if [[ "$line" =~ ^##[[:space:]]+(.*) ]]; then
            if [ -n "$current_section" ] && [ -n "$current_title" ]; then
                local section_slug
                section_slug=$(echo "$current_title" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/-/g' | sed 's/--*/-/g' | sed 's/^-//' | sed 's/-$//' | head -c 60)
                local key="knowledge:${doc_type}:${doc_slug}:${section_slug}"
                local value="${current_section:0:2000}"
                # Escape for JSON
                value=$(echo "$value" | sed ':a;N;$!ba;s/\n/\\n/g' | sed 's/"/\\"/g')
                echo "{\"key\":\"$key\",\"value\":\"$value\",\"tags\":$tags_json}"
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

    # Last section
    if [ -n "$current_section" ] && [ -n "$current_title" ]; then
        local section_slug
        section_slug=$(echo "$current_title" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/-/g' | sed 's/--*/-/g' | sed 's/^-//' | sed 's/-$//' | head -c 60)
        local key="knowledge:${doc_type}:${doc_slug}:${section_slug}"
        local value="${current_section:0:2000}"
        value=$(echo "$value" | sed ':a;N;$!ba;s/\n/\\n/g' | sed 's/"/\\"/g')
        echo "{\"key\":\"$key\",\"value\":\"$value\",\"tags\":$tags_json}"
    fi
}

JSONL_OUT="$TMPDIR/output.jsonl"
generate_jsonl "$TMPDIR/dimensions/test-doc.md" "dimension" "semantic" "source:brana-knowledge" > "$JSONL_OUT"
generate_jsonl "$TMPDIR/ideas/brainstorm.md" "idea" "working" "source:thebrana" >> "$JSONL_OUT"

LINE_COUNT=$(wc -l < "$JSONL_OUT")
assert "test-doc produces 3 sections + brainstorm 1 = 4 lines" "4" "$LINE_COUNT"

# ── Test 2: JSONL is valid JSON ──
echo "Test 2: JSONL validity"
VALID=true
while IFS= read -r line; do
    if ! echo "$line" | python3 -c "import sys,json; json.load(sys.stdin)" 2>/dev/null; then
        VALID=false
        break
    fi
done < "$JSONL_OUT"
assert "all JSONL lines are valid JSON" "true" "$VALID"

# ── Test 3: Key format ──
echo "Test 3: Key format in JSONL"
FIRST_KEY=$(head -1 "$JSONL_OUT" | python3 -c "import sys,json; print(json.load(sys.stdin)['key'])")
assert "first key format" "knowledge:dimension:test-doc:first-section" "$FIRST_KEY"

LAST_KEY=$(tail -1 "$JSONL_OUT" | python3 -c "import sys,json; print(json.load(sys.stdin)['key'])")
assert "last key format" "knowledge:idea:brainstorm:only-section" "$LAST_KEY"

# ── Test 4: Tags array in JSONL ──
echo "Test 4: Tags in JSONL entries"
FIRST_TAGS=$(head -1 "$JSONL_OUT" | python3 -c "import sys,json; print(','.join(json.load(sys.stdin)['tags']))")
assert_contains "tags contain source" "source:brana-knowledge" "$FIRST_TAGS"
assert_contains "tags contain type" "type:dimension" "$FIRST_TAGS"
assert_contains "tags contain tier" "tier:semantic" "$FIRST_TAGS"
assert_contains "tags contain doc" "doc:test-doc.md" "$FIRST_TAGS"

# ── Test 5: H3 headers don't create splits ──
echo "Test 5: Only ## headers split sections"
SECOND_KEY=$(sed -n '2p' "$JSONL_OUT" | python3 -c "import sys,json; print(json.load(sys.stdin)['key'])")
assert "second section key" "knowledge:dimension:test-doc:second-section" "$SECOND_KEY"

SECOND_VALUE=$(sed -n '2p' "$JSONL_OUT" | python3 -c "import sys,json; print(json.load(sys.stdin)['value'])")
assert_contains "h3 content stays in parent section" "Subsection" "$SECOND_VALUE"
assert_contains "h3 content preserved" "Still part of second section" "$SECOND_VALUE"

# ── Test 6: Value truncation at 2000 chars ──
echo "Test 6: Value truncation"
# Create a doc with a very long section
LONG_SECTION=$(python3 -c "print('x' * 3000)")
cat > "$TMPDIR/dimensions/long-doc.md" << MARKDOWN
## Huge Section

$LONG_SECTION
MARKDOWN

LONG_JSONL="$TMPDIR/long-output.jsonl"
generate_jsonl "$TMPDIR/dimensions/long-doc.md" "dimension" "semantic" "source:brana-knowledge" > "$LONG_JSONL"
VALUE_LEN=$(head -1 "$LONG_JSONL" | python3 -c "import sys,json; print(len(json.load(sys.stdin)['value']))")
assert "value truncated to ≤2000 chars" "true" "$([ "$VALUE_LEN" -le 2000 ] && echo true || echo false)"

# ── Test 7: bulk-index.mjs contract — accepts path arg ──
echo "Test 7: bulk-index.mjs accepts JSONL path arg"
BULK_SCRIPT="$REPO_ROOT/system/scripts/bulk-index.mjs"
assert "bulk-index.mjs exists" "true" "$([ -f "$BULK_SCRIPT" ] && echo true || echo false)"
assert "bulk-index.mjs is executable or has node shebang" "true" "$([[ "$(head -1 "$BULK_SCRIPT")" == *"node"* ]] && echo true || echo false)"

# ── Test 8: Empty file produces no JSONL ──
echo "Test 8: Empty/no-section file"
cat > "$TMPDIR/dimensions/empty-doc.md" << 'MARKDOWN'
# Just a title

No h2 sections here, only h1.
MARKDOWN
EMPTY_JSONL="$TMPDIR/empty-output.jsonl"
generate_jsonl "$TMPDIR/dimensions/empty-doc.md" "dimension" "semantic" "source:brana-knowledge" > "$EMPTY_JSONL"
EMPTY_LINES=$(wc -l < "$EMPTY_JSONL")
assert "no-section doc produces 0 JSONL lines" "0" "$EMPTY_LINES"

echo ""
echo "=== Results: $PASS/$TOTAL passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
