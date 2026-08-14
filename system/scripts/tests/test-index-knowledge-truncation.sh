#!/usr/bin/env bash
# Tests for index-knowledge.sh truncation signaling (t-2616).
#
# The 2026-08-02 incident: the indexer died at 86%, printed no completion
# summary, and the run still exited 0 — the scheduler recorded SUCCESS.
# index-knowledge.sh must treat a missing completion summary, or a census
# that doesn't account for every section, as a hard failure.
#
# Hermetic: doc dirs via BRANA_KNOWLEDGE_DIR/BRANA_THEBRANA_DIR, the node
# indexer replaced by a stub via the NODE env override, USE_SQLITE=1 to pin
# the code path.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INDEXER="$SCRIPT_DIR/../index-knowledge.sh"
PASS=0
FAIL=0
TOTAL=0
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

check() {
    local label="$1" expected="$2" actual="$3"
    TOTAL=$((TOTAL + 1))
    if [ "$actual" = "$expected" ]; then
        PASS=$((PASS + 1)); echo "  PASS: $label"
    else
        FAIL=$((FAIL + 1)); echo "  FAIL: $label"; echo "    expected: $expected"; echo "    actual:   $actual"
    fi
}

# ── Fixture: one doc, two ## sections ─────────────────────────
mkdir -p "$TMP/dims" "$TMP/thebrana"
cat > "$TMP/dims/sample.md" <<'MD'
# Sample

## Alpha
Alpha body text.

## Beta
Beta body text.
MD

export BRANA_KNOWLEDGE_DIR="$TMP/dims"
export BRANA_THEBRANA_DIR="$TMP/thebrana"
export USE_SQLITE=1

# ── Node stub: output controlled by STUB_OUTPUT_FILE ──────────
cat > "$TMP/node-stub" <<'STUB'
#!/usr/bin/env bash
cat "$STUB_OUTPUT_FILE"
exit "${STUB_EXIT:-0}"
STUB
chmod +x "$TMP/node-stub"
export NODE="$TMP/node-stub"

run_indexer() { bash "$INDEXER" >"$TMP/out.log" 2>&1; echo $?; }

echo "== index-knowledge truncation tests =="

# 1. Truncated run: progress output only, no completion summary, exit 0
#    (a killed node process whose parent shell still sees 0 — or any path
#    that loses the summary). Must FAIL the run.
cat > "$TMP/stub-out" <<'OUT'
=== Bulk Index ===
Sections:  2
  50% (1/2) — 10/s — 0.1s elapsed
OUT
export STUB_OUTPUT_FILE="$TMP/stub-out"
rc=$(run_indexer)
check "truncated output (no summary) exits non-zero" "1" "$rc"
grep -qi "truncat" "$TMP/out.log"
check "truncated output names truncation" "0" "$?"

# 2. Complete run with full census: Stored+Errors == sections. Must PASS.
cat > "$TMP/stub-out" <<'OUT'
=== Bulk Index Complete ===
Stored:   2
Errors:   0
OUT
rc=$(run_indexer)
check "complete run with full census exits 0" "0" "$rc"
grep -q "verified complete" "$TMP/out.log"
check "complete run reports verified census" "0" "$?"

# 3. Summary present but census short (stored+errors < sections):
#    a partial run that still printed a summary must FAIL.
cat > "$TMP/stub-out" <<'OUT'
=== Bulk Index Complete ===
Stored:   1
Errors:   0
OUT
rc=$(run_indexer)
check "short census exits non-zero" "1" "$rc"

# 4. Errors counted toward census: 1 stored + 1 error == 2 sections is a
#    complete (non-truncated) run — the existing 5% error-rate gate then
#    decides pass/fail on its own terms (50% >= 5% → exit 1, but with the
#    error-rate message, not the truncation message).
cat > "$TMP/stub-out" <<'OUT'
=== Bulk Index Complete ===
Stored:   1
Errors:   1
OUT
rc=$(run_indexer)
check "full census with errors is not 'truncated' (error-rate gate fires instead)" "1" "$rc"
grep -qi "truncat" "$TMP/out.log"
check "error-rate failure does not claim truncation" "1" "$?"

echo "== $PASS/$TOTAL passed, $FAIL failed =="
[ "$FAIL" -eq 0 ]
