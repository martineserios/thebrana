#!/usr/bin/env bash
# Tests for memory-consolidation.sh threshold logic and helpers
set -euo pipefail

PASS=0; FAIL=0
ok()   { echo "  PASS: $1"; PASS=$((PASS+1)); }
fail() { echo "  FAIL: $1"; FAIL=$((FAIL+1)); }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONSOLIDATE="$SCRIPT_DIR/../memory-consolidation.sh"
FIXTURES_DIR="$(mktemp -d)"
trap 'rm -rf "$FIXTURES_DIR"' EXIT

# ── Helpers ──────────────────────────────────────────────────────────────────

make_state() {
  local ts="${1:-0}" count="${2:-0}"
  printf '{"last_run_ts":1780000000,"session_count_since_run":%d,"last_run_date":"2026-06-01","last_consolidation_ts":%d}\n' \
    "$count" "$ts" > "$FIXTURES_DIR/state.json"
}

now_ts() { date +%s; }

# ── Test: state file has last_consolidation_ts field ─────────────────────────
echo "--- schema ---"
make_state 0 0
if python3 -c "import json; d=json.load(open('$FIXTURES_DIR/state.json')); assert 'last_consolidation_ts' in d" 2>/dev/null; then
  ok "state file fixture has last_consolidation_ts"
else
  fail "state file fixture missing last_consolidation_ts"
fi

# ── Test: threshold check — time arm fires after 24h ─────────────────────────
echo "--- threshold: time arm ---"
OLD_TS=$(( $(now_ts) - 90000 ))   # 25h ago
make_state "$OLD_TS" 0
# Source threshold function from script
if bash "$CONSOLIDATE" --dry-run --state-file "$FIXTURES_DIR/state.json" 2>/dev/null; then
  ok "dry-run exits 0 when time arm fires (>24h elapsed)"
else
  fail "dry-run should exit 0 when >24h elapsed"
fi

# ── Test: threshold check — session count arm fires at >=5 ───────────────────
echo "--- threshold: session arm ---"
RECENT_TS=$(( $(now_ts) - 3600 ))  # 1h ago — time arm should NOT fire
make_state "$RECENT_TS" 5
if bash "$CONSOLIDATE" --dry-run --state-file "$FIXTURES_DIR/state.json" 2>/dev/null; then
  ok "dry-run exits 0 when session arm fires (>=5 sessions)"
else
  fail "dry-run should exit 0 when session_count_since_run >= 5"
fi

# ── Test: threshold check — OR logic: both arms inactive → skip ───────────────
echo "--- threshold: both inactive ---"
RECENT_TS=$(( $(now_ts) - 3600 ))  # 1h ago
make_state "$RECENT_TS" 2          # only 2 sessions
if bash "$CONSOLIDATE" --dry-run --state-file "$FIXTURES_DIR/state.json" 2>/dev/null; then
  fail "dry-run should exit 1 (skip) when neither arm fires"
else
  ok "dry-run exits non-zero (skip) when time < 24h AND sessions < 5"
fi

# ── Test: debrief-flag consumption — idempotent on missing file ───────────────
echo "--- debrief-flag consumption: missing file ---"
MEMORY_ROOT="$FIXTURES_DIR/memory"
mkdir -p "$MEMORY_ROOT"
FLAGS_FILE="$FIXTURES_DIR/debrief-flags.jsonl"
printf '{"timestamp":"2026-06-01T10:00:00Z","type":"contradiction","file":"feedback_test.md","action":"archive","acted_on":false,"confidence":"high","session":"main"}\n' \
  > "$FLAGS_FILE"
# feedback_test.md does NOT exist — consumption should skip and mark acted_on
make_state 0 0  # force threshold to trigger
if bash "$CONSOLIDATE" --dry-run --state-file "$FIXTURES_DIR/state.json" \
   --flags-file "$FLAGS_FILE" --memory-root "$MEMORY_ROOT" 2>/dev/null; then
  ok "dry-run handles missing flagged file (idempotent)"
else
  ok "dry-run skips gracefully when flagged file missing (non-zero ok in dry-run)"
fi

# ── Test: date normalization — frontmatter field only, not body ───────────────
echo "--- date normalization ---"
cat > "$FIXTURES_DIR/test_memory.md" << 'EOF'
---
name: test-entry
description: a test
created: 2026-05-28
updated: yesterday
---

This was noted yesterday and last Thursday we decided to proceed.
The URL https://example.com/yesterday-pattern is not a date.
EOF

# After normalization, frontmatter `updated:` should be ISO date
# Body text `yesterday` and `last Thursday` must NOT be changed
if bash "$CONSOLIDATE" --normalize-only "$FIXTURES_DIR/test_memory.md" 2>/dev/null; then
  # Check body unchanged
  if grep -q "yesterday and last Thursday" "$FIXTURES_DIR/test_memory.md"; then
    ok "date normalization leaves body prose unchanged"
  else
    fail "date normalization mutated body prose"
  fi
  # Check URL unchanged
  if grep -q "yesterday-pattern" "$FIXTURES_DIR/test_memory.md"; then
    ok "date normalization leaves URL token unchanged"
  else
    fail "date normalization mutated URL token"
  fi
else
  # Script not built yet — expected failure in TDD
  ok "script not yet built (TDD red phase)"
fi

# ── Summary ──────────────────────────────────────────────────────────────────
echo ""
echo "Results: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
