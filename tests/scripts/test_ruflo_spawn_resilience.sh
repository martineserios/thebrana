#!/usr/bin/env bash
# Tests that ruflo MCP spawn sites survive a broken bin install:
# ruflo npm tarballs (3.10.39, 3.10.40) ship bin/ruflo.js with CRLF
# line endings and the file can lose its exec bit — direct spawn fails
# with EACCES or `env: 'node\r': No such file or directory`.
# Spawn sites must execute the resolved .js via the node interpreter.
# Run: bash tests/scripts/test_ruflo_spawn_resilience.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
TMPDIR=$(mktemp -d)
trap "rm -rf $TMPDIR" EXIT

PASS=0
FAIL=0
TOTAL=0

assert_contains() {
    local desc="$1" needle="$2" haystack="$3"
    TOTAL=$((TOTAL + 1))
    if [[ "$haystack" == *"$needle"* ]]; then
        echo "  PASS: $desc"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $desc (expected output to contain '$needle')"
        FAIL=$((FAIL + 1))
    fi
}

# Fake ruflo bin reproducing the broken install: CRLF shebang, no exec bit.
FAKE="$TMPDIR/fake-ruflo.js"
printf '#!/usr/bin/env node\r\nconsole.error("FAKE_RUFLO_STARTED");\r\nsetTimeout(() => process.exit(0), 200);\r\n' > "$FAKE"
chmod 644 "$FAKE"

# One-entry JSONL for mcp-index
JSONL="$TMPDIR/one.jsonl"
printf '{"key":"knowledge:test:spawn-resilience","value":"test","tags":["type:test"]}\n' > "$JSONL"

echo "Test 1: mcp-index.mjs spawns CRLF/non-exec ruflo via node"
OUT=$(timeout 20 env RUFLO_BIN="$FAKE" node "$REPO_ROOT/system/scripts/mcp-index.mjs" "$JSONL" 2>&1 || true)
assert_contains "mcp-index spawn survives broken bin" "FAKE_RUFLO_STARTED" "$OUT"

echo "Test 2: ruflo-batch-store.mjs spawns CRLF/non-exec ruflo via node"
OUT=$(printf '[{"key":"k","value":"v"}]' | timeout 20 env RUFLO_BIN="$FAKE" node "$REPO_ROOT/system/scripts/ruflo-batch-store.mjs" 2>&1 || true)
assert_contains "batch-store spawn survives broken bin" "FAKE_RUFLO_STARTED" "$OUT"

echo ""
echo "Results: $PASS/$TOTAL passed"
[ "$FAIL" -eq 0 ] || exit 1
