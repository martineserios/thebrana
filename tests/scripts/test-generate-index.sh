#!/usr/bin/env bash
# Tests for generate-index.sh — dimension docs INDEX.md generation.
# Run: bash tests/scripts/test-generate-index.sh

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
GENERATOR="$REPO_ROOT/system/scripts/generate-index.sh"

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

echo "=== test-generate-index.sh ==="

# ── Setup: temp knowledge dir with fixtures ──
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/dimensions"

# File 1: frontmatter with title + body H1 (new-style dim doc)
cat > "$TMP/dimensions/01-frontmatter-with-title.md" <<'EOF'
---
title: First Dim With Frontmatter
description: example
type: dimension
---

# Body Header That Should Not Win

## Section A
## Section B
## Section C
EOF

# File 2: no frontmatter, body H1 only (old-style dim doc)
cat > "$TMP/dimensions/02-body-only.md" <<'EOF'
# Plain Body Title

## Section A
## Section B
EOF

# File 3: frontmatter title, no body H1
cat > "$TMP/dimensions/03-frontmatter-only.md" <<'EOF'
---
title: Frontmatter Only Title
---

Body content with no level-1 header.

## Section A
EOF

# File 4: neither frontmatter title nor body H1 — must fall back to filename
cat > "$TMP/dimensions/04-no-title.md" <<'EOF'
Some content with no header anywhere.

Just paragraphs.
EOF

# File 5: quoted frontmatter title — quotes must be stripped
cat > "$TMP/dimensions/05-quoted-title.md" <<'EOF'
---
title: "Quoted Title Value"
---

# Body Header
EOF

# ── Run generator ──
echo "Test 1: generator runs to completion"
GEN_OUT=$(bash "$GENERATOR" "$TMP" 2>&1)
GEN_EXIT=$?
assert "generator exits 0" "0" "$GEN_EXIT"

INDEX="$TMP/dimensions/INDEX.md"
assert "INDEX.md exists" "true" "$([ -f "$INDEX" ] && echo true || echo false)"

# ── Test 2: every file gets a row ──
echo "Test 2: row count"
ROWS=$(grep -c '^| \[' "$INDEX" 2>/dev/null || true)
assert "5 fixture files produce 5 rows" "5" "$ROWS"

# ── Test 3: title extraction — frontmatter wins over body H1 ──
echo "Test 3: frontmatter title preferred over body H1"
assert "file 1: frontmatter title appears" "true" \
    "$(grep -q 'First Dim With Frontmatter' "$INDEX" && echo true || echo false)"
assert "file 1: body H1 NOT used as title" "false" \
    "$(grep -q 'Body Header That Should Not Win' "$INDEX" && echo true || echo false)"

# ── Test 4: body H1 used when no frontmatter ──
echo "Test 4: body H1 fallback"
assert "file 2: body H1 used" "true" \
    "$(grep -q 'Plain Body Title' "$INDEX" && echo true || echo false)"

# ── Test 5: frontmatter title without body H1 ──
echo "Test 5: frontmatter title without body H1"
assert "file 3: frontmatter title used" "true" \
    "$(grep -q 'Frontmatter Only Title' "$INDEX" && echo true || echo false)"

# ── Test 6: filename fallback when nothing else available ──
echo "Test 6: filename fallback"
assert "file 4: filename appears as title fallback" "true" \
    "$(grep -q '04-no-title.md' "$INDEX" && echo true || echo false)"

# ── Test 7: quoted titles get unquoted ──
echo "Test 7: quoted frontmatter titles"
assert "file 5: quoted title appears unquoted" "true" \
    "$(grep -q '| \[Quoted Title Value\]' "$INDEX" && echo true || echo false)"
assert "file 5: surrounding double-quotes removed" "false" \
    "$(grep -q '\"Quoted Title Value\"' "$INDEX" && echo true || echo false)"

# ── Test 8: section count ──
echo "Test 8: section count"
# File 1 has 3 ## headers; row should show "3"
assert "file 1: 3 sections counted" "true" \
    "$(grep -E 'First Dim With Frontmatter.*\| 3 \|' "$INDEX" >/dev/null && echo true || echo false)"

# ── Test 9: real brana-knowledge dimensions (smoke) ──
echo "Test 9: real dimensions dir smoke test"
REAL_KB="$HOME/enter_thebrana/brana-knowledge"
if [ -d "$REAL_KB/dimensions" ]; then
    REAL_TMP=$(mktemp -d)
    cp -r "$REAL_KB/dimensions" "$REAL_TMP/"
    bash "$GENERATOR" "$REAL_TMP" >/dev/null 2>&1
    REAL_ROWS=$(grep -c '^| \[' "$REAL_TMP/dimensions/INDEX.md" 2>/dev/null || true)
    REAL_FILES=$(find "$REAL_TMP/dimensions" -maxdepth 1 -name '*.md' ! -name 'INDEX.md' | wc -l)
    assert "real dim rows match file count ($REAL_FILES files)" "$REAL_FILES" "$REAL_ROWS"
    rm -rf "$REAL_TMP"
else
    echo "  SKIP: real brana-knowledge not present"
fi

echo
echo "Total: $TOTAL  Pass: $PASS  Fail: $FAIL"
[ "$FAIL" -eq 0 ]
