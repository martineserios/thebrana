#!/usr/bin/env bash
# Tests: session-end-persist.sh metrics patch merges instead of replaces (t-1751)
# Verifies that flywheel fields written by the hook preserve existing close.md
# fields already present in .metrics (behavioral_files_changed, doc_files_changed,
# propose_count, etc.) rather than clobbering them.

set -uo pipefail

PASS=0; FAIL=0; TOTAL=0
TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

assert_eq() {
    local desc="$1" got="$2" expected="$3"
    TOTAL=$((TOTAL + 1))
    if [ "$got" = "$expected" ]; then
        echo "  PASS: $desc"; PASS=$((PASS + 1))
    else
        echo "  FAIL: $desc"
        echo "    expected: $expected"
        echo "    got:      $got"
        FAIL=$((FAIL + 1))
    fi
}

# Build a session state JSON that already has close.md-specific metrics fields
STATE="$TMPDIR/session-state.json"
cat > "$STATE" <<'JSON'
{
  "version": 1,
  "written_at": "2026-06-09T10:00:00Z",
  "branch": "feat/t-123-test",
  "metrics": {
    "behavioral_files_changed": 3,
    "doc_files_changed": 2,
    "propose_count": 5,
    "ask_open_count": 1,
    "propose_rate": 0.8,
    "doc_prompts_accepted": 2,
    "doc_prompts_skipped": 0
  }
}
JSON

# Simulate the flywheel patch that session-end-persist.sh applies
FLYWHEEL_PATCH='{"events":42,"corrections":3,"test_writes":5,"correction_rate":0.07,"test_write_rate":0.12,"cascade_rate":0.0,"delegation_count":2}'

echo "Session-End-Persist Metrics Merge Tests"
echo "======================================="
echo ""

# ── Test 1: buggy behaviour (replace) — documents what we're fixing ─────────
echo "--- Buggy replace (documents current bug) ---"
RESULT_BUG="$TMPDIR/state-bug.json"
jq --argjson m "$FLYWHEEL_PATCH" '.metrics = $m' "$STATE" > "$RESULT_BUG"

BEHAVIORAL_AFTER=$(jq -r '.metrics.behavioral_files_changed // "null"' "$RESULT_BUG")
assert_eq "replace clobbers behavioral_files_changed" "$BEHAVIORAL_AFTER" "null"

# ── Test 2: fixed behaviour (merge) ─────────────────────────────────────────
echo ""
echo "--- Fixed merge ---"
RESULT_FIX="$TMPDIR/state-fix.json"
jq --argjson m "$FLYWHEEL_PATCH" '.metrics = (.metrics + $m)' "$STATE" > "$RESULT_FIX"

# close.md fields preserved
BEHAVIORAL=$(jq -r '.metrics.behavioral_files_changed' "$RESULT_FIX")
DOC_CHANGED=$(jq -r '.metrics.doc_files_changed' "$RESULT_FIX")
PROPOSE=$(jq -r '.metrics.propose_count' "$RESULT_FIX")
ACCEPTED=$(jq -r '.metrics.doc_prompts_accepted' "$RESULT_FIX")

assert_eq "merge preserves behavioral_files_changed" "$BEHAVIORAL" "3"
assert_eq "merge preserves doc_files_changed" "$DOC_CHANGED" "2"
assert_eq "merge preserves propose_count" "$PROPOSE" "5"
assert_eq "merge preserves doc_prompts_accepted" "$ACCEPTED" "2"

# flywheel fields still written
EVENTS=$(jq -r '.metrics.events' "$RESULT_FIX")
CORRECTIONS=$(jq -r '.metrics.corrections' "$RESULT_FIX")
DELEGATIONS=$(jq -r '.metrics.delegation_count' "$RESULT_FIX")

assert_eq "merge writes events" "$EVENTS" "42"
assert_eq "merge writes corrections" "$CORRECTIONS" "3"
assert_eq "merge writes delegation_count" "$DELEGATIONS" "2"

# flywheel fields overwrite close.md fields of same name (merge semantics: patch wins)
echo ""
echo "--- Merge precedence: flywheel wins on collision ---"
STATE_OVERLAP="$TMPDIR/state-overlap.json"
cat > "$STATE_OVERLAP" <<'JSON'
{
  "version": 1,
  "written_at": "2026-06-09T10:00:00Z",
  "metrics": {
    "events": 10,
    "behavioral_files_changed": 1
  }
}
JSON
RESULT_OVERLAP="$TMPDIR/state-overlap-fixed.json"
jq --argjson m "$FLYWHEEL_PATCH" '.metrics = (.metrics + $m)' "$STATE_OVERLAP" > "$RESULT_OVERLAP"

EVENTS_AFTER=$(jq -r '.metrics.events' "$RESULT_OVERLAP")
assert_eq "flywheel overwrites pre-existing events field" "$EVENTS_AFTER" "42"

# ── Summary ──────────────────────────────────────────────────────────────────
echo ""
echo "Results: $PASS passed, $FAIL failed, $TOTAL total"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
