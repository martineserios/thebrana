#!/usr/bin/env bash
# Tests for signal-capture.sh (t-251)
# UserPromptSubmit hook: detect ratings/sentiment, write to ratings.jsonl

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$SCRIPT_DIR/../signal-capture.sh"
PASS=0; FAIL=0; TOTAL=0
TMPDIR_TEST=$(mktemp -d)
trap 'rm -rf "$TMPDIR_TEST"' EXIT

# Override ratings dir for tests
export BRANA_RATINGS_DIR="$TMPDIR_TEST/ratings"
export BRANA_FAILURES_DIR="$TMPDIR_TEST/failures"
mkdir -p "$BRANA_RATINGS_DIR" "$BRANA_FAILURES_DIR"

RATINGS_FILE="$BRANA_RATINGS_DIR/ratings.jsonl"

assert_json_continue() {
    local desc="$1" output="$2"
    TOTAL=$((TOTAL + 1))
    if echo "$output" | jq -e '.continue == true' >/dev/null 2>&1; then
        echo "  PASS: $desc"; PASS=$((PASS + 1))
    else
        echo "  FAIL: $desc (expected .continue == true)"
        echo "    got: $output"
        FAIL=$((FAIL + 1))
    fi
}

assert_file_contains() {
    local desc="$1" file="$2" needle="$3"
    TOTAL=$((TOTAL + 1))
    if [ -f "$file" ] && grep -q "$needle" "$file" 2>/dev/null; then
        echo "  PASS: $desc"; PASS=$((PASS + 1))
    else
        echo "  FAIL: $desc (expected '$needle' in $file)"
        [ -f "$file" ] && echo "    file: $(cat "$file" | head -3)" || echo "    file: not found"
        FAIL=$((FAIL + 1))
    fi
}

assert_file_not_exists() {
    local desc="$1" file="$2"
    TOTAL=$((TOTAL + 1))
    if [ ! -f "$file" ]; then
        echo "  PASS: $desc"; PASS=$((PASS + 1))
    else
        echo "  FAIL: $desc (file should not exist: $file)"
        FAIL=$((FAIL + 1))
    fi
}

run_hook() {
    local input="$1"
    echo "$input" | bash "$HOOK" 2>/dev/null
}

SESSION="test-sig-$$"

echo "=== test-signal-capture.sh ==="

echo ""
echo "--- Neutral prompts: pass through, no signal written ---"

OUT=$(run_hook "{\"prompt\":\"what should I do next?\",\"session_id\":\"$SESSION\"}")
assert_json_continue "neutral prompt: continue true" "$OUT"
assert_file_not_exists "neutral prompt: no ratings file" "$RATINGS_FILE"

OUT=$(run_hook "{\"prompt\":\"run the tests\",\"session_id\":\"$SESSION\"}")
assert_json_continue "command prompt: continue true" "$OUT"

echo ""
echo "--- Explicit positive ratings: logged as positive ---"

OUT=$(run_hook "{\"prompt\":\"5/5 exactly what I needed\",\"session_id\":\"$SESSION\"}")
assert_json_continue "5/5 rating: continue true" "$OUT"
assert_file_contains "5/5 rating: logged to ratings.jsonl" "$RATINGS_FILE" "positive"

OUT=$(run_hook "{\"prompt\":\"perfect, that's exactly right\",\"session_id\":\"$SESSION\"}")
assert_json_continue "perfect: continue true" "$OUT"
assert_file_contains "perfect: logged as positive" "$RATINGS_FILE" "positive"

OUT=$(run_hook "{\"prompt\":\"👍\",\"session_id\":\"$SESSION\"}")
assert_json_continue "thumbs up: continue true" "$OUT"
assert_file_contains "thumbs up: logged as positive" "$RATINGS_FILE" "positive"

echo ""
echo "--- Explicit negative ratings: logged + failure captured ---"

# Reset for clean failure tracking
rm -f "$RATINGS_FILE"

OUT=$(run_hook "{\"prompt\":\"1/5 that was completely wrong\",\"session_id\":\"$SESSION\"}")
assert_json_continue "1/5 rating: continue true" "$OUT"
assert_file_contains "1/5 rating: logged to ratings.jsonl" "$RATINGS_FILE" "negative"
# Low rating should write to FAILURES dir
FAIL_FILES=$(ls "$BRANA_FAILURES_DIR/" 2>/dev/null | wc -l)
TOTAL=$((TOTAL + 1))
if [ "$FAIL_FILES" -gt 0 ]; then
    echo "  PASS: 1/5 rating: failure context captured"; PASS=$((PASS + 1))
else
    echo "  FAIL: 1/5 rating: expected failure file in $BRANA_FAILURES_DIR"
    FAIL=$((FAIL + 1))
fi

OUT=$(run_hook "{\"prompt\":\"no that's wrong, you missed the point\",\"session_id\":\"$SESSION\"}")
assert_json_continue "negative sentiment: continue true" "$OUT"
assert_file_contains "negative sentiment: logged" "$RATINGS_FILE" "negative"

OUT=$(run_hook "{\"prompt\":\"👎\",\"session_id\":\"$SESSION\"}")
assert_json_continue "thumbs down: continue true" "$OUT"
assert_file_contains "thumbs down: logged as negative" "$RATINGS_FILE" "negative"

echo ""
echo "--- Spanish positive phrases ---"

OUT=$(run_hook "{\"prompt\":\"vamoooo\",\"session_id\":\"$SESSION\"}")
assert_json_continue "vamoooo: continue true" "$OUT"
assert_file_contains "vamoooo: logged as positive" "$RATINGS_FILE" "positive"

OUT=$(run_hook "{\"prompt\":\"vamos!\",\"session_id\":\"$SESSION\"}")
assert_json_continue "vamos: continue true" "$OUT"
assert_file_contains "vamos: logged as positive" "$RATINGS_FILE" "positive"

rm -f "$RATINGS_FILE"
OUT=$(run_hook "{\"prompt\":\"dale!\",\"session_id\":\"$SESSION\"}")
assert_json_continue "dale: continue true" "$OUT"
assert_file_contains "dale: logged as positive" "$RATINGS_FILE" "positive"

rm -f "$RATINGS_FILE"
OUT=$(run_hook "{\"prompt\":\"dale ya, perfecto\",\"session_id\":\"$SESSION\"}")
assert_json_continue "dale+perfecto: continue true" "$OUT"
assert_file_contains "dale+perfecto: logged as positive" "$RATINGS_FILE" "positive"

rm -f "$RATINGS_FILE"
OUT=$(run_hook "{\"prompt\":\"genial!\",\"session_id\":\"$SESSION\"}")
assert_json_continue "genial: continue true" "$OUT"
assert_file_contains "genial: logged as positive" "$RATINGS_FILE" "positive"

rm -f "$RATINGS_FILE"
OUT=$(run_hook "{\"prompt\":\"geniales, exactamente eso\",\"session_id\":\"$SESSION\"}")
assert_json_continue "geniales: continue true" "$OUT"
assert_file_contains "geniales: logged as positive" "$RATINGS_FILE" "positive"

rm -f "$RATINGS_FILE"
OUT=$(run_hook "{\"prompt\":\"perfecto!\",\"session_id\":\"$SESSION\"}")
assert_json_continue "perfecto: continue true" "$OUT"
assert_file_contains "perfecto: logged as positive" "$RATINGS_FILE" "positive"

rm -f "$RATINGS_FILE"
OUT=$(run_hook "{\"prompt\":\"qué bueno que funcionó\",\"session_id\":\"$SESSION\"}")
assert_json_continue "bueno: continue true" "$OUT"
assert_file_contains "bueno: logged as positive" "$RATINGS_FILE" "positive"

rm -f "$RATINGS_FILE"
OUT=$(run_hook "{\"prompt\":\"bueno!\",\"session_id\":\"$SESSION\"}")
assert_json_continue "bueno bare: continue true" "$OUT"
assert_file_contains "bueno bare: logged as positive" "$RATINGS_FILE" "positive"

rm -f "$RATINGS_FILE"
OUT=$(run_hook "{\"prompt\":\"bárbaro\",\"session_id\":\"$SESSION\"}")
assert_json_continue "bárbaro: continue true" "$OUT"
assert_file_contains "bárbaro: logged as positive" "$RATINGS_FILE" "positive"

rm -f "$RATINGS_FILE"
OUT=$(run_hook "{\"prompt\":\"barbaro, justo lo que necesitaba\",\"session_id\":\"$SESSION\"}")
assert_json_continue "barbaro (no accent): continue true" "$OUT"
assert_file_contains "barbaro (no accent): logged as positive" "$RATINGS_FILE" "positive"

echo ""
echo "--- Spanish negative phrases ---"

rm -f "$RATINGS_FILE"
OUT=$(run_hook "{\"prompt\":\"nada que ver con lo que pedí\",\"session_id\":\"$SESSION\"}")
assert_json_continue "nada que ver: continue true" "$OUT"
assert_file_contains "nada que ver: logged as negative" "$RATINGS_FILE" "negative"

rm -f "$RATINGS_FILE"
OUT=$(run_hook "{\"prompt\":\"eso es nada que ver\",\"session_id\":\"$SESSION\"}")
assert_json_continue "nada que ver inline: continue true" "$OUT"
assert_file_contains "nada que ver inline: logged as negative" "$RATINGS_FILE" "negative"

rm -f "$RATINGS_FILE"
OUT=$(run_hook "{\"prompt\":\"pesimo, no sirve\",\"session_id\":\"$SESSION\"}")
assert_json_continue "pesimo: continue true" "$OUT"
assert_file_contains "pesimo: logged as negative" "$RATINGS_FILE" "negative"

rm -f "$RATINGS_FILE"
OUT=$(run_hook "{\"prompt\":\"pésimo resultado\",\"session_id\":\"$SESSION\"}")
assert_json_continue "pésimo (accent): continue true" "$OUT"
assert_file_contains "pésimo (accent): logged as negative" "$RATINGS_FILE" "negative"

echo ""
echo "--- Ratings JSONL structure: required fields present ---"

# Check the latest entry has required fields
LAST_ENTRY=$(tail -1 "$RATINGS_FILE" 2>/dev/null)
TOTAL=$((TOTAL + 1))
if echo "$LAST_ENTRY" | jq -e '.ts and .session_id and .signal and .category' >/dev/null 2>&1; then
    echo "  PASS: JSONL entry has required fields (ts, session_id, signal, category)"
    PASS=$((PASS + 1))
else
    echo "  FAIL: JSONL entry missing required fields"
    echo "    got: $LAST_ENTRY"
    FAIL=$((FAIL + 1))
fi

echo ""
echo "--- Empty/missing prompt: graceful passthrough ---"

OUT=$(run_hook '{"prompt":"","session_id":"test-empty"}')
assert_json_continue "empty prompt: continue true" "$OUT"

OUT=$(run_hook '{"session_id":"test-no-prompt"}')
assert_json_continue "no prompt field: continue true" "$OUT"

echo ""
echo "Results: $PASS/$TOTAL passed, $FAIL failed"
[ "$FAIL" -gt 0 ] && exit 1
exit 0
