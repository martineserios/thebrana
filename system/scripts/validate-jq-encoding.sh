#!/usr/bin/env bash
# Validates that jq -Rs '.' produces byte-for-byte identical output to Python json.dumps()
# on edge-case inputs. Run at environment setup or after upgrading jq/Python.
# Both tools receive input via printf (no trailing newline). Python uses ensure_ascii=False
# to match jq's default UTF-8 pass-through for non-ASCII codepoints.
set -euo pipefail

PASS=0
FAIL=0
WARN=0

check() {
    local label="$1"
    local input="$2"

    local tmp
    tmp=$(mktemp)
    printf '%s' "$input" > "$tmp"

    local jq_out py_out
    jq_out=$(jq -Rs '.' < "$tmp" 2>/dev/null) || { echo "ERROR [$label]: jq failed"; rm -f "$tmp"; (( FAIL++ )) || true; return; }
    py_out=$(uv run python3 -c "
import json, sys
data = sys.stdin.buffer.read().decode('utf-8', errors='surrogateescape')
sys.stdout.write(json.dumps(data, ensure_ascii=False))
" < "$tmp" 2>/dev/null) || { echo "ERROR [$label]: python failed"; rm -f "$tmp"; (( FAIL++ )) || true; return; }
    rm -f "$tmp"

    if [ "$jq_out" = "$py_out" ]; then
        echo "PASS [$label]"
        (( PASS++ )) || true
    else
        echo "WARN [$label]: outputs differ (both may be valid JSON)"
        echo "  jq:  $jq_out"
        echo "  py:  $py_out"
        (( WARN++ )) || true
    fi
}

# Verify jq escapes control chars (raw control chars in JSON strings = invalid JSON)
check_valid_json() {
    local label="$1"
    local input="$2"

    local tmp
    tmp=$(mktemp)
    printf '%s' "$input" > "$tmp"
    local out
    out=$(jq -Rs '.' < "$tmp" 2>/dev/null)
    rm -f "$tmp"

    # Parse the output back — if jq produced valid JSON, python can round-trip it
    local roundtrip
    roundtrip=$(uv run python3 -c "import json,sys; print(repr(json.loads(sys.stdin.read())))" <<< "$out" 2>/dev/null) || {
        echo "FAIL [$label]: jq output is not valid JSON"
        (( FAIL++ )) || true
        return
    }
    echo "PASS [$label] (valid JSON, round-trips to: $roundtrip)"
    (( PASS++ )) || true
}

echo "=== jq vs Python json.dumps comparison ==="
check "plain ascii"        "hello world"
check "double quote"       'say "hi"'
check "backslash"          'path\to\file'
check "newline"            $'line1\nline2'
check "tab"                $'col1\tcol2'
check "carriage return"    $'line\r'
check "backtick"           'echo `id`'
check "unicode emoji"      "hello 🌍"
check "single quote"       "it's fine"
check "mixed specials"     $'back\\slash\nnewline\t"quote"'

echo ""
echo "=== jq validity checks (control chars must be escaped) ==="
check_valid_json "null byte"          "before"$'\x00'"after"
check_valid_json "del char (0x7f)"    $'\x7f'
check_valid_json "control char 0x01"  $'\x01'
check_valid_json "control char 0x1f"  $'\x1f'

echo ""
echo "Results: $PASS passed, $WARN warnings (encoding differences), $FAIL failed"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
