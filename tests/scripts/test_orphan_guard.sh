#!/usr/bin/env bash
# Tests for the orphan-cleanup safety guard shared by bulk-index.mjs and
# mcp-index.mjs (t-2613).
#
# Regression under test: a full reindex builds `storedKeys` from markdown docs
# only, then deletes every other active key in the namespace. Producers other
# than the doc parser (process-url -> knowledge:url:, feed indexing ->
# knowledge:feed:) can never appear in storedKeys, so set subtraction classified
# them as orphans and hard-deleted them. Two further hazards found while tracing:
# a run killed part-way would prune everything it failed to re-store, and a run
# covering only some doc types would prune the types it never touched.
#
# Run: bash tests/scripts/test_orphan_guard.sh

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
GUARD="$REPO_ROOT/system/scripts/lib/orphan-guard.mjs"

PASS=0
FAIL=0
TOTAL=0

assert() {
    local desc="$1" expected="$2" actual="$3"
    TOTAL=$((TOTAL + 1))
    if [ "$expected" = "$actual" ]; then
        echo "  PASS: $desc"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $desc (expected '$expected', got '$actual')"
        FAIL=$((FAIL + 1))
    fi
}

echo "=== test_orphan_guard.sh ==="

# ── Test 0: the guard module exists ──
echo "Test 0: guard module present"
assert "orphan-guard.mjs exists" "true" "$([ -f "$GUARD" ] && echo true || echo false)"

if [ ! -f "$GUARD" ]; then
    echo ""
    echo "=== Results: $PASS/$TOTAL passed, $FAIL failed ==="
    echo "guard module missing — remaining assertions skipped"
    exit 1
fi

# Helper: run a node snippet against the guard, print its stdout.
guard_eval() {
    node --input-type=module -e "
import { selectOrphans, isDocDerived } from '$GUARD';
$1
" 2>&1
}

# ── Test 1: non-doc-derived keys are never orphans ──
# This is the exact data-loss case: a link stored by process-url sits in the
# knowledge namespace, the reindex regenerates only doc sections, and the link
# must survive.
echo "Test 1: knowledge:url: entry survives a complete full reindex"
OUT=$(guard_eval "
const orphans = selectOrphans({
  existingKeys: ['knowledge:url:some-linkedin-post', 'knowledge:feature:x:1', 'knowledge:feature:stale:9'],
  storedKeys:   new Set(['knowledge:feature:x:1']),
  namespace: 'knowledge',
  runComplete: true,
});
console.log(orphans.join(','));
")
assert "url key not selected for deletion" "knowledge:feature:stale:9" "$OUT"

echo "Test 1b: knowledge:feed: entry survives too"
OUT=$(guard_eval "
const orphans = selectOrphans({
  existingKeys: ['knowledge:feed:some-article', 'knowledge:idea:y:1'],
  storedKeys:   new Set(['knowledge:idea:y:1']),
  namespace: 'knowledge',
  runComplete: true,
});
console.log(orphans.length);
")
assert "feed key not selected for deletion" "0" "$OUT"

# ── Test 2: an incomplete run prunes nothing ──
# The 2026-08-02 run died at 86% and the scheduler still reported SUCCESS. Had
# it reached cleanup, set subtraction would have deleted the ~14% it never
# re-stored.
echo "Test 2: incomplete run selects no orphans at all"
OUT=$(guard_eval "
const orphans = selectOrphans({
  existingKeys: ['knowledge:feature:a:1', 'knowledge:feature:b:1', 'knowledge:idea:c:1'],
  storedKeys:   new Set(['knowledge:feature:a:1']),
  namespace: 'knowledge',
  runComplete: false,
});
console.log(orphans.length);
")
assert "killed run deletes nothing" "0" "$OUT"

# ── Test 3: only doc types the run actually produced get pruned ──
# A run that indexes no dimension docs must not conclude that every existing
# dimension entry is an orphan.
echo "Test 3: doc types absent from the run are left alone"
OUT=$(guard_eval "
const orphans = selectOrphans({
  existingKeys: ['knowledge:dimension:d:1', 'knowledge:feature:f:1', 'knowledge:feature:gone:1'],
  storedKeys:   new Set(['knowledge:feature:f:1']),
  namespace: 'knowledge',
  runComplete: true,
});
console.log(orphans.join(','));
")
assert "untouched doc type survives; touched type still prunes" "knowledge:feature:gone:1" "$OUT"

# ── Test 4: isDocDerived classification ──
echo "Test 4: key classification"
OUT=$(guard_eval "console.log([
  isDocDerived('knowledge:dimension:a:b'),
  isDocDerived('knowledge:decision:a:b'),
  isDocDerived('knowledge:feature:a:b'),
  isDocDerived('knowledge:architecture:a:b'),
  isDocDerived('knowledge:reflection:a:b'),
  isDocDerived('knowledge:idea:a:b'),
  isDocDerived('knowledge:research:a:b'),
].every(Boolean));")
assert "all seven doc types classified doc-derived" "true" "$OUT"

OUT=$(guard_eval "console.log([
  isDocDerived('knowledge:url:x'),
  isDocDerived('knowledge:feed:x'),
  isDocDerived('knowledge:whatever-new-producer:x'),
].some(Boolean));")
assert "url/feed/unknown producers are not doc-derived" "false" "$OUT"

# ── Test 5: non-knowledge namespaces prune normally ──
# The pattern namespace is fully doc/JSONL-driven; guarding it would strand
# genuine orphans there forever.
echo "Test 5: other namespaces keep prior prune behaviour"
OUT=$(guard_eval "
const orphans = selectOrphans({
  existingKeys: ['pattern:feedback:old', 'pattern:feedback:current'],
  storedKeys:   new Set(['pattern:feedback:current']),
  namespace: 'pattern',
  runComplete: true,
});
console.log(orphans.join(','));
")
assert "pattern namespace still prunes its orphans" "pattern:feedback:old" "$OUT"

# ── Test 6: both indexers import the shared guard (no replicated logic) ──
echo "Test 6: both indexers use the shared module"
for f in bulk-index.mjs mcp-index.mjs; do
    assert "$f imports orphan-guard" "true" \
        "$(grep -q "orphan-guard.mjs" "$REPO_ROOT/system/scripts/$f" && echo true || echo false)"
done

echo ""
echo "=== Results: $PASS/$TOTAL passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ]
