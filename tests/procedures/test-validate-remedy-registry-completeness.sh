#!/usr/bin/env bash
# Regression test: REMEDY_REGISTRY completeness — every validate.sh check id
# must resolve to HAS_REMEDY or NO_REMEDY:<reason>, no third (silent) state (t-2630, ADR-077).
#
# THE BUG THIS GUARDS AGAINST. A naive extraction of "# Check N" ids from validate.sh
# has two independent failure modes, both verified against the live file during SPECIFY:
#   1. Column-0-anchored regex (^# Check [0-9]) misses real checks indented inside a
#      conditional block — e.g. Check 51 is indented 4 spaces (validate.sh:503).
#   2. Widening to a leading-whitespace-tolerant regex alone then ALSO matches fake ids
#      from Python-heredoc comments nested inside Check 18's embedded script
#      (validate.sh:1125-1205, between `<<'PYEOF'` and `PYEOF`) — those comments are
#      themselves at column 0 inside the heredoc body, so whitespace-tolerance doesn't
#      help distinguish them from real top-level checks.
# extract_check_ids() (system/scripts/validate-remedies.sh) must handle both: tolerate
# leading whitespace AND blank out heredoc regions before matching.
#
# Run: bash tests/procedures/test-validate-remedy-registry-completeness.sh

set -uo pipefail

PASS=0
FAIL=0
TOTAL=0

assert_true() {
    local desc="$1" cond="$2"
    TOTAL=$((TOTAL + 1))
    if [ "$cond" = "true" ]; then
        echo "  PASS: $desc"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $desc"
        FAIL=$((FAIL + 1))
    fi
}

REPO_ROOT=$(git rev-parse --show-toplevel)
REMEDIES_SH="$REPO_ROOT/system/scripts/validate-remedies.sh"
VALIDATE_SH="$REPO_ROOT/validate.sh"
TMPDIR_T=$(mktemp -d)
trap 'rm -rf "$TMPDIR_T"' EXIT

if [ ! -f "$REMEDIES_SH" ]; then
    echo "ERROR: $REMEDIES_SH does not exist yet"
    exit 1
fi

# shellcheck source=/dev/null
source "$REMEDIES_SH"

if ! declare -f extract_check_ids >/dev/null; then
    echo "ERROR: extract_check_ids() not defined by $REMEDIES_SH"
    exit 1
fi
if ! declare -p REMEDY_REGISTRY >/dev/null 2>&1; then
    echo "ERROR: REMEDY_REGISTRY associative array not defined by $REMEDIES_SH"
    exit 1
fi

echo "=== Fixture: indented real check + heredoc-embedded fake ids ==="

FIXTURE="$TMPDIR_T/fixture-validate.sh"
cat > "$FIXTURE" <<'FIXEOF'
#!/usr/bin/env bash
# Check 5: a real top-level check
echo "check 5 body"

if true; then
    # Check 6: a real check indented inside a conditional block (mirrors Check 51)
    echo "check 6 body"
fi

# Check 7: precedes an embedded interpreter block
if python3 - <<'PYEOF'
# Check 999: fake id inside a heredoc-embedded Python script — must NOT be extracted
# Check 1000: a second fake id in the same heredoc
print("hi")
PYEOF
then
    echo "ran"
fi

# Check 8: a real check after the heredoc closes
echo "check 8 body"
FIXEOF

FIXTURE_IDS=$(extract_check_ids "$FIXTURE" | sort -n | tr '\n' ' ')
EXPECTED_IDS="5 6 7 8 "

assert_true "fixture: real + indented + post-heredoc ids extracted, heredoc fakes excluded" \
    "$([ "$FIXTURE_IDS" = "$EXPECTED_IDS" ] && echo true || echo false)"
if [ "$FIXTURE_IDS" != "$EXPECTED_IDS" ]; then
    echo "    expected: [$EXPECTED_IDS]  actual: [$FIXTURE_IDS]"
fi

echo ""
echo "=== Live validate.sh: indented Check 51 must be extracted ==="

LIVE_IDS=$(extract_check_ids "$VALIDATE_SH")
assert_true "Check 51 (indented inside a conditional block) is extracted from validate.sh" \
    "$(printf '%s\n' "$LIVE_IDS" | grep -qx '51' && echo true || echo false)"

echo ""
echo "=== Live validate.sh: heredoc-embedded fake ids (1/2) must not leak from Check 18's script ==="

# Check 18's embedded Python script has its own "# Check 1" / "# Check 2" comments.
# Both happen to collide with real, already-registered check ids, so their mere
# presence in REMEDY_REGISTRY can't prove exclusion — cross-check that extraction
# inside EVERY `<<'PYEOF' ... PYEOF` heredoc span contributes nothing by deleting
# all such spans a second, independent way (line numbers located dynamically —
# never hardcoded, since any edit above a heredoc shifts its line numbers) and
# confirming the id set is unchanged (a leak would only ever ADD ids, never
# remove real ones).
NO_HEREDOC_FILE="$TMPDIR_T/no-heredoc.sh"
awk '
    /<<['\''"]?PYEOF['\''"]?[[:space:]]*$/ { in_heredoc = 1; next }
    in_heredoc && /^PYEOF[[:space:]]*$/ { in_heredoc = 0; next }
    in_heredoc { next }
    { print }
' "$VALIDATE_SH" > "$NO_HEREDOC_FILE"
SLICE_WITHOUT_HEREDOC=$(extract_check_ids "$NO_HEREDOC_FILE")
IDS_INSIDE_HEREDOC_SPAN=$(comm -23 <(printf '%s\n' "$LIVE_IDS" | sort -u) <(printf '%s\n' "$SLICE_WITHOUT_HEREDOC" | sort -u))
assert_true "no check id is extracted only from inside a PYEOF heredoc span (Check 18's embedded script)" \
    "$([ -z "$IDS_INSIDE_HEREDOC_SPAN" ] && echo true || echo false)"
if [ -n "$IDS_INSIDE_HEREDOC_SPAN" ]; then
    echo "    ids found only inside heredoc span: $IDS_INSIDE_HEREDOC_SPAN"
fi

echo ""
echo "=== Registry completeness: every extracted id has a REMEDY_REGISTRY entry ==="

MISSING=""
while IFS= read -r id; do
    [ -z "$id" ] && continue
    if [ -z "${REMEDY_REGISTRY[$id]+x}" ]; then
        MISSING="$MISSING $id"
    fi
done <<< "$LIVE_IDS"

assert_true "every check id extracted from validate.sh has a REMEDY_REGISTRY entry" \
    "$([ -z "$MISSING" ] && echo true || echo false)"
if [ -n "$MISSING" ]; then
    echo "    missing registry entries for check ids:$MISSING"
fi

echo ""
echo "=== Registry entries are well-formed: HAS_REMEDY or NO_REMEDY:<reason> ==="

MALFORMED=""
for id in "${!REMEDY_REGISTRY[@]}"; do
    val="${REMEDY_REGISTRY[$id]}"
    if [ "$val" != "HAS_REMEDY" ] && [[ "$val" != NO_REMEDY:* ]]; then
        MALFORMED="$MALFORMED $id"
    fi
done
assert_true "every registry entry is HAS_REMEDY or NO_REMEDY:<reason> (no third state)" \
    "$([ -z "$MALFORMED" ] && echo true || echo false)"
if [ -n "$MALFORMED" ]; then
    echo "    malformed entries for check ids:$MALFORMED"
fi

echo ""
echo "=== Summary ==="
echo "Total: $TOTAL | Passed: $PASS | Failed: $FAIL"
[ "$FAIL" -eq 0 ] || exit 1
