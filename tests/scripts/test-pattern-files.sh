#!/usr/bin/env bash
# test-pattern-files.sh — Validate pattern file format for indexer compatibility
#
# Tests that existing memory files (feedback_*, project_*) have valid frontmatter
# and are parseable by the pattern indexer pipeline.

set -euo pipefail

PASS=0
FAIL=0

pass() { PASS=$((PASS + 1)); echo "  ✓ $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  ✗ $1"; }

echo "=== Pattern File Format Tests ==="
echo ""

# --- Test 1: Memory files exist ---
echo "Memory files:"
MEMORY_DIR="$HOME/.claude/projects/-home-martineserios-enter-thebrana-thebrana/memory"
if [ -d "$MEMORY_DIR" ]; then
    FILE_COUNT=$(find "$MEMORY_DIR" -name "feedback_*.md" -o -name "project_*.md" 2>/dev/null | wc -l)
    if [ "$FILE_COUNT" -gt 0 ]; then
        pass "found $FILE_COUNT pattern files (feedback_* + project_*)"
    else
        fail "no feedback_* or project_* files found in $MEMORY_DIR"
    fi
else
    fail "memory directory not found: $MEMORY_DIR"
    echo "=== $PASS passed, $FAIL failed ==="
    exit 1
fi

# --- Test 2: All pattern files have frontmatter ---
echo ""
echo "Frontmatter presence:"
MISSING_FM=0
while IFS= read -r file; do
    if ! head -1 "$file" | grep -q '^---$'; then
        MISSING_FM=$((MISSING_FM + 1))
        echo "    missing: $(basename "$file")"
    fi
done < <(find "$MEMORY_DIR" -name "feedback_*.md" -o -name "project_*.md" 2>/dev/null)

if [ "$MISSING_FM" -eq 0 ]; then
    pass "all $FILE_COUNT files have frontmatter delimiter"
else
    fail "$MISSING_FM files missing frontmatter"
fi

# --- Test 3: Frontmatter has required fields (name, description, type) ---
echo ""
echo "Required frontmatter fields:"
MISSING_FIELDS=0
while IFS= read -r file; do
    # Extract frontmatter (between first --- and second ---)
    fm=$(sed -n '/^---$/,/^---$/p' "$file" 2>/dev/null | head -20)

    has_name=false
    has_desc=false
    has_type=false

    echo "$fm" | grep -q '^name:' && has_name=true
    echo "$fm" | grep -q '^description:' && has_desc=true
    echo "$fm" | grep -q '^type:' && has_type=true

    if ! $has_name || ! $has_desc || ! $has_type; then
        MISSING_FIELDS=$((MISSING_FIELDS + 1))
        echo "    $(basename "$file"): name=$has_name desc=$has_desc type=$has_type"
    fi
done < <(find "$MEMORY_DIR" -name "feedback_*.md" -o -name "project_*.md" 2>/dev/null)

if [ "$MISSING_FIELDS" -eq 0 ]; then
    pass "all files have name, description, and type fields"
else
    fail "$MISSING_FIELDS files missing required frontmatter fields"
fi

# --- Test 4: Type field values are valid ---
echo ""
echo "Type field values:"
INVALID_TYPE=0
while IFS= read -r file; do
    type_val=$(sed -n '/^---$/,/^---$/p' "$file" 2>/dev/null | grep '^type:' | sed 's/^type: *//' | tr -d '[:space:]')
    case "$type_val" in
        user|feedback|project|reference) ;;
        *)
            INVALID_TYPE=$((INVALID_TYPE + 1))
            echo "    $(basename "$file"): type='$type_val'"
            ;;
    esac
done < <(find "$MEMORY_DIR" -name "feedback_*.md" -o -name "project_*.md" 2>/dev/null)

if [ "$INVALID_TYPE" -eq 0 ]; then
    pass "all type values are valid (user|feedback|project|reference)"
else
    fail "$INVALID_TYPE files have invalid type values"
fi

# --- Test 5: Filename convention matches type ---
echo ""
echo "Filename-type consistency:"
MISMATCHED=0
while IFS= read -r file; do
    basename_file=$(basename "$file")
    type_val=$(sed -n '/^---$/,/^---$/p' "$file" 2>/dev/null | grep '^type:' | sed 's/^type: *//' | tr -d '[:space:]')

    if [[ "$basename_file" == feedback_* ]] && [ "$type_val" != "feedback" ]; then
        MISMATCHED=$((MISMATCHED + 1))
        echo "    $basename_file has type=$type_val (expected feedback)"
    fi
    if [[ "$basename_file" == project_* ]] && [ "$type_val" != "project" ]; then
        MISMATCHED=$((MISMATCHED + 1))
        echo "    $basename_file has type=$type_val (expected project)"
    fi
done < <(find "$MEMORY_DIR" -name "feedback_*.md" -o -name "project_*.md" 2>/dev/null)

if [ "$MISMATCHED" -eq 0 ]; then
    pass "all filenames match their type field"
else
    fail "$MISMATCHED files have filename-type mismatch"
fi

# --- Test 6: Files have content after frontmatter ---
echo ""
echo "Content presence:"
EMPTY_CONTENT=0
while IFS= read -r file; do
    # Count lines after second ---
    content_lines=$(awk '/^---$/{c++; next} c>=2' "$file" 2>/dev/null | grep -c '[^ ]' || true)
    if [ "$content_lines" -eq 0 ]; then
        EMPTY_CONTENT=$((EMPTY_CONTENT + 1))
        echo "    empty: $(basename "$file")"
    fi
done < <(find "$MEMORY_DIR" -name "feedback_*.md" -o -name "project_*.md" 2>/dev/null)

if [ "$EMPTY_CONTENT" -eq 0 ]; then
    pass "all files have content after frontmatter"
else
    fail "$EMPTY_CONTENT files have empty content"
fi

# --- Test 7: Cross-project scan (pattern files exist in other projects too) ---
echo ""
echo "Cross-project pattern files:"
TOTAL_CROSS=0
for projdir in "$HOME"/.claude/projects/*/memory/; do
    [ -d "$projdir" ] || continue
    count=$(find "$projdir" -name "feedback_*.md" -o -name "project_*.md" 2>/dev/null | wc -l)
    TOTAL_CROSS=$((TOTAL_CROSS + count))
done
if [ "$TOTAL_CROSS" -gt 0 ]; then
    pass "found $TOTAL_CROSS pattern files across all projects"
else
    fail "no pattern files found in any project"
fi

# --- Summary ---
echo ""
echo "=== $PASS passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
