#!/usr/bin/env bash
# Tests for docs/brana-ontology.yaml schema validation
# Validates structure, required fields, and minimum counts.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ONTOLOGY="$SCRIPT_DIR/../../../docs/brana-ontology.yaml"
PASS=0
FAIL=0
TOTAL=0

# Requires yq (https://github.com/mikefarah/yq)
if ! command -v yq &>/dev/null; then
    echo "SKIP: yq not installed (required for YAML parsing)"
    exit 0
fi

assert_true() {
    local desc="$1"; shift
    TOTAL=$((TOTAL + 1))
    if eval "$1"; then
        echo "  PASS: $desc"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $desc"
        FAIL=$((FAIL + 1))
    fi
}

echo "Ontology Schema Tests"
echo "====================="

# --- Test 1: types section has at least 5 entries ---
TYPE_COUNT=$(yq '.types | length' "$ONTOLOGY")
assert_true "types section has >= 5 entries (got $TYPE_COUNT)" \
    '[ "$TYPE_COUNT" -ge 5 ]'

# --- Test 2: relationships section has at least 3 entries ---
REL_COUNT=$(yq '.relationships | length' "$ONTOLOGY")
assert_true "relationships section has >= 3 entries (got $REL_COUNT)" \
    '[ "$REL_COUNT" -ge 3 ]'

# --- Test 3: axioms section has at least 6 entries ---
AXIOM_COUNT=$(yq '.axioms | length' "$ONTOLOGY")
assert_true "axioms section has >= 6 entries (got $AXIOM_COUNT)" \
    '[ "$AXIOM_COUNT" -ge 6 ]'

# --- Test 4: Every active type has name, description, location, status ---
echo ""
echo "  Active type field checks:"
ACTIVE_TYPES=$(yq '.types[] | select(.status == "active") | .name' "$ONTOLOGY")
while IFS= read -r tname; do
    [ -z "$tname" ] && continue
    TOTAL=$((TOTAL + 1))
    has_name=$(yq ".types[] | select(.name == \"$tname\") | has(\"name\")" "$ONTOLOGY")
    has_desc=$(yq ".types[] | select(.name == \"$tname\") | has(\"description\")" "$ONTOLOGY")
    has_loc=$(yq ".types[] | select(.name == \"$tname\") | has(\"location\")" "$ONTOLOGY")
    has_status=$(yq ".types[] | select(.name == \"$tname\") | has(\"status\")" "$ONTOLOGY")
    if [ "$has_name" = "true" ] && [ "$has_desc" = "true" ] && [ "$has_loc" = "true" ] && [ "$has_status" = "true" ]; then
        echo "    PASS: active type '$tname' has all required fields"
        PASS=$((PASS + 1))
    else
        echo "    FAIL: active type '$tname' missing fields (name=$has_name desc=$has_desc location=$has_loc status=$has_status)"
        FAIL=$((FAIL + 1))
    fi
done <<< "$ACTIVE_TYPES"

# --- Test 5: Every active relationship has name, description, status ---
echo ""
echo "  Active relationship field checks:"
ACTIVE_RELS=$(yq '.relationships[] | select(.status == "active") | .name' "$ONTOLOGY")
while IFS= read -r rname; do
    [ -z "$rname" ] && continue
    TOTAL=$((TOTAL + 1))
    has_name=$(yq ".relationships[] | select(.name == \"$rname\") | has(\"name\")" "$ONTOLOGY")
    has_desc=$(yq ".relationships[] | select(.name == \"$rname\") | has(\"description\")" "$ONTOLOGY")
    has_status=$(yq ".relationships[] | select(.name == \"$rname\") | has(\"status\")" "$ONTOLOGY")
    if [ "$has_name" = "true" ] && [ "$has_desc" = "true" ] && [ "$has_status" = "true" ]; then
        echo "    PASS: active relationship '$rname' has all required fields"
        PASS=$((PASS + 1))
    else
        echo "    FAIL: active relationship '$rname' missing fields (name=$has_name desc=$has_desc status=$has_status)"
        FAIL=$((FAIL + 1))
    fi
done <<< "$ACTIVE_RELS"

# --- Summary ---
echo ""
echo "$PASS/$TOTAL passed"
[ "$FAIL" -eq 0 ] || exit 1
