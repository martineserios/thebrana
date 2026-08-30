#!/usr/bin/env bash
# Tests for generate-context-md.py (t-3163, ADR-086 §8): CONTEXT.md at the
# repo root is GENERATED from docs/domain/'s Ubiquitous Language sections —
# never hand-maintained. Contract under test:
#   1. generation extracts every Ubiquitous Language table from docs/domain/*.md
#   2. deterministic: regenerating with unchanged domain docs = byte-identical
#   3. --check exits 0 when CONTEXT.md is current, 1 when domain docs moved
#      (this exit code is /brana:reconcile's drift gauge)
#   4. no docs/domain/ → exit 0, no CONTEXT.md written (opt-in, silent)
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GEN="$SCRIPT_DIR/../generate-context-md.py"
PASS=0; FAIL=0

ok()   { echo "  PASS: $1"; (( PASS++ )) || true; }
bad()  { echo "  FAIL: $1"; (( FAIL++ )) || true; }

if [ ! -f "$GEN" ]; then
    echo "ERROR: $GEN does not exist"
    echo "Results: 0 passed, 1 failed"
    exit 1
fi

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/docs/domain"
cat > "$TMP/docs/domain/MODEL-001-test.md" <<'EOF'
# MODEL-001: test contexts

## Purpose
Testing.

## Ubiquitous Language

| Term | Definition | Context |
|------|-----------|---------|
| **Task** | A unit of work | Backlog |
| **Wave** | A drainable selector | Backlog |

## Other section
Not glossary.
EOF

echo "=== generation ==="
python3 "$GEN" "$TMP" >/dev/null 2>&1
if [ -f "$TMP/CONTEXT.md" ]; then ok "CONTEXT.md written at repo root"; else bad "CONTEXT.md not written"; fi
if grep -q "Task" "$TMP/CONTEXT.md" 2>/dev/null && grep -q "drainable selector" "$TMP/CONTEXT.md"; then
    ok "glossary terms extracted"; else bad "glossary terms missing"; fi
if grep -qi "generated" "$TMP/CONTEXT.md" 2>/dev/null && grep -q "MODEL-001-test.md" "$TMP/CONTEXT.md"; then
    ok "banner names generation + source file"; else bad "banner/source attribution missing"; fi
if grep -q "Not glossary" "$TMP/CONTEXT.md" 2>/dev/null; then
    bad "non-glossary section leaked into CONTEXT.md"; else ok "only glossary sections extracted"; fi

echo "=== determinism ==="
cp "$TMP/CONTEXT.md" "$TMP/first.md"
python3 "$GEN" "$TMP" >/dev/null 2>&1
if cmp -s "$TMP/CONTEXT.md" "$TMP/first.md"; then ok "regenerate with unchanged domain = no diff"; else bad "regeneration produced a diff"; fi

echo "=== --check drift gauge ==="
if python3 "$GEN" "$TMP" --check >/dev/null 2>&1; then ok "--check exits 0 when current"; else bad "--check nonzero on current file"; fi
# insert INSIDE the Ubiquitous Language table (an append after '## Other
# section' would land outside the extracted region — no drift, correctly)
sed -i 's#| \*\*Wave\*\* | A drainable selector | Backlog |#| **Wave** | A drainable selector | Backlog |\n| **New** | A new term | Backlog |#' "$TMP/docs/domain/MODEL-001-test.md"
if python3 "$GEN" "$TMP" --check >/dev/null 2>&1; then bad "--check missed domain drift"; else ok "--check exits 1 on drift"; fi
python3 "$GEN" "$TMP" >/dev/null 2>&1
if python3 "$GEN" "$TMP" --check >/dev/null 2>&1; then ok "regenerate clears drift"; else bad "drift persists after regenerate"; fi

echo "=== no docs/domain ==="
TMP2=$(mktemp -d)
if python3 "$GEN" "$TMP2" >/dev/null 2>&1 && [ ! -f "$TMP2/CONTEXT.md" ]; then
    ok "no domain dir: exit 0, nothing written"; else bad "no-domain behavior wrong"; fi
rm -rf "$TMP2"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
