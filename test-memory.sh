#!/usr/bin/env bash
set -euo pipefail

# Layer 1: Memory Round-Trip Test
# Stores a test pattern via claude-flow, searches for it, verifies it comes back.
# Catches: DB schema drift, path issues, claude-flow breakage.
#
# claude-flow runs as an MCP server, but the CLI binary also works for testing.
# We locate it via: nvm global bin → npx fallback.

ERRORS=0
PASSED=0

echo "=== Memory Round-Trip Test ==="
echo ""

fail() { echo "  FAIL: $1"; ERRORS=$((ERRORS + 1)); }
pass() { echo "  PASS: $1"; PASSED=$((PASSED + 1)); }

# Locate claude-flow binary
CF=""

# 1. Check nvm global bin (most reliable — no download delay)
if [ -n "${NVM_DIR:-}" ]; then
    NVM_BIN="$NVM_DIR/versions/node/$(node -v 2>/dev/null || echo v0)/bin/claude-flow"
    if [ -x "$NVM_BIN" ]; then
        CF="$NVM_BIN"
    fi
fi

# 2. Fallback: search common nvm paths
if [ -z "$CF" ]; then
    for candidate in "$HOME"/.nvm/versions/node/*/bin/claude-flow; do
        if [ -x "$candidate" ]; then
            CF="$candidate"
            break
        fi
    done
fi

# 3. Fallback: check PATH
if [ -z "$CF" ] && command -v claude-flow &>/dev/null; then
    CF="claude-flow"
fi

# 4. Last resort: npx (slow, may download)
if [ -z "$CF" ] && command -v npx &>/dev/null; then
    CF="npx claude-flow"
    echo "  INFO: using npx fallback (may be slow on first run)"
fi

if [ -z "$CF" ]; then
    fail "claude-flow not found — cannot test memory"
    echo ""
    echo "=== Memory Test Summary ==="
    echo "Passed: 0"
    echo "Failed: 1"
    echo "MEMORY TEST FAILED"
    exit 1
fi

echo "  Using: $CF"
echo ""

# Test 1: Ensure memory DB can be initialized
echo "Testing memory init..."
if timeout 15 $CF memory init --force >/dev/null 2>&1; then
    pass "memory init succeeded"
else
    fail "memory init failed — DB may not exist"
fi
echo ""

# Test 2: Store a test pattern
TEST_KEY="test:roundtrip:$(date +%s)"
TEST_VALUE="brana-health-check-$(date +%s)"

echo "Testing memory store..."
if timeout 10 $CF memory store -k "$TEST_KEY" -v "$TEST_VALUE" --namespace test --tags "type:health-check" >/dev/null 2>&1; then
    pass "memory store succeeded (key=$TEST_KEY)"
else
    fail "memory store failed"
fi
echo ""

# Test 3: Search for the test pattern
echo "Testing memory search..."
SEARCH_RESULT=$(timeout 10 $CF memory search -q "$TEST_VALUE" 2>/dev/null || true)

if [ -z "$SEARCH_RESULT" ]; then
    fail "memory search returned empty — stored value not found"
elif echo "$SEARCH_RESULT" | grep -q "$TEST_VALUE"; then
    pass "memory search found the stored value"
else
    fail "memory search returned results but value not found in output"
    echo "  Expected to find: $TEST_VALUE"
    echo "  Got: $(echo "$SEARCH_RESULT" | head -3)"
fi
echo ""

# Test 4: Store and retrieve JSON with embedded metadata (quarantine fields)
echo "Testing metadata round-trip..."
META_KEY="test:metadata:$(date +%s)"
META_VALUE=$(jq -n -c '{problem: "test issue", solution: "test fix", confidence: 0.5, transferable: false, recall_count: 0}')

if timeout 10 $CF memory store -k "$META_KEY" -v "$META_VALUE" --namespace test --tags "type:health-check,confidence:quarantine" >/dev/null 2>&1; then
    # Retrieve by key and verify JSON fields survived the round-trip
    META_RETRIEVED=$(timeout 10 $CF memory retrieve -k "$META_KEY" --namespace test --format json 2>/dev/null || true)
    if [ -z "$META_RETRIEVED" ] || echo "$META_RETRIEVED" | grep -q 'Key not found'; then
        fail "metadata round-trip — retrieve returned empty (key=$META_KEY)"
    else
        META_CONTENT=$(echo "$META_RETRIEVED" | jq -r '.content // empty' 2>/dev/null || true)
        if [ -z "$META_CONTENT" ]; then
            fail "metadata round-trip — no content field in retrieved entry"
        elif echo "$META_CONTENT" | jq -e '.confidence' >/dev/null 2>&1 && echo "$META_CONTENT" | jq -e '.recall_count' >/dev/null 2>&1; then
            pass "metadata round-trip — confidence and recall_count fields survived"
        else
            fail "metadata round-trip — metadata fields missing from content: $META_CONTENT"
        fi
    fi
else
    fail "metadata round-trip — store failed"
fi

# Clean up metadata test
timeout 10 $CF memory delete "$META_KEY" >/dev/null 2>&1 || true
echo ""

# Test 5: Clean up basic test data
echo "Cleaning up test data..."
timeout 10 $CF memory delete "$TEST_KEY" >/dev/null 2>&1 || true
echo ""

# Summary
echo "=== Memory Test Summary ==="
echo "Passed: $PASSED"
echo "Failed: $ERRORS"
if [ "$ERRORS" -gt 0 ]; then
    echo "MEMORY TEST FAILED"
    exit 1
else
    echo "MEMORY TEST PASSED"
    exit 0
fi
