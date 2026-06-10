#!/usr/bin/env bash
# E2E test for skill routing → acquire-skills trigger (t-1003)
#
# Simulates the full backlog start → skill suggest → breadcrumb → build safety net flow.
# Creates a temporary task, runs skill suggest, writes/reads breadcrumb, cleans up.
#
# Usage: bash system/scripts/test-skill-routing.sh

set -uo pipefail

PASS=0
FAIL=0
SYSTEM_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

pass() { echo "  PASS: $1"; ((PASS++)) || true; }
fail() { echo "  FAIL: $1"; ((FAIL++)) || true; }

echo "=== E2E: Skill Routing Contract ==="
echo ""

# ── Phase 1: Procedure structure ────────────────────────────────────────

echo "Phase 1: Procedure structure"

# t-1942: big-four bodies live in skills/{name}/SKILL.md + phases/*.md — concat the effective body
effective_body_file() {
    local n="$1" tmp
    tmp=$(mktemp "${TMPDIR:-/tmp}/effective-body-$n.XXXXXX")
    [ -f "$SYSTEM_DIR/procedures/$n.md" ] && cat "$SYSTEM_DIR/procedures/$n.md" >> "$tmp"
    [ -f "$SYSTEM_DIR/skills/$n/SKILL.md" ] && cat "$SYSTEM_DIR/skills/$n/SKILL.md" >> "$tmp"
    [ -d "$SYSTEM_DIR/skills/$n/phases" ] && cat "$SYSTEM_DIR/skills/$n"/phases/*.md >> "$tmp" 2>/dev/null
    echo "$tmp"
}
BACKLOG_PROC="$(effective_body_file backlog)"
BUILD_PROC="$(effective_body_file build)"

# 1a. backlog.md has MANDATORY marker on low-score path
if grep -q "MANDATORY acquisition offer" "$BACKLOG_PROC" 2>/dev/null; then
    pass "backlog.md step 5d has MANDATORY acquisition offer marker"
else
    fail "backlog.md step 5d missing MANDATORY acquisition offer marker"
fi

# 1b. backlog.md writes breadcrumb after skill gap check
if grep -q "skill_gap_checked" "$BACKLOG_PROC" 2>/dev/null; then
    pass "backlog.md writes skill_gap_checked breadcrumb"
else
    fail "backlog.md missing skill_gap_checked breadcrumb instruction"
fi

# 1c. build.md step 4a checks breadcrumb (not unconditional skip)
if grep -q "skill_gap_checked" "$BUILD_PROC" 2>/dev/null; then
    pass "build.md step 4a checks skill_gap_checked breadcrumb"
else
    fail "build.md step 4a missing skill_gap_checked guard"
fi

# 1d. build.md has safety net path (runs 4a when breadcrumb absent)
if grep -q "safety net" "$BUILD_PROC" 2>/dev/null; then
    pass "build.md step 4a has safety net for missing breadcrumb"
else
    fail "build.md step 4a missing safety net path"
fi

# 1e. backlog.md references acquire-skills skill invocation
if grep -q 'Skill(skill="brana:acquire-skills"' "$BACKLOG_PROC" 2>/dev/null; then
    pass "backlog.md invokes brana:acquire-skills on low scores"
else
    fail "backlog.md missing acquire-skills invocation"
fi

echo ""

# ── Phase 2: CLI skill suggest returns parseable JSON ───────────────────

echo "Phase 2: CLI skill suggest (low-score query)"

SUGGEST_OUTPUT=$(brana skills suggest --query "xyzzy quantum blockchain unicorn" 2>/dev/null)

if [ -z "$SUGGEST_OUTPUT" ]; then
    fail "brana skills suggest returned empty output"
else
    # 2a. Output is valid JSON array
    if echo "$SUGGEST_OUTPUT" | jq '.' > /dev/null 2>&1; then
        pass "skill suggest returns valid JSON"
    else
        fail "skill suggest output is not valid JSON"
    fi

    # 2b. All scores below 0.3 for a nonsense query
    MAX_SCORE=$(echo "$SUGGEST_OUTPUT" | jq -r '([.[].score] | max) // 0' 2>/dev/null)

    if [ -n "$MAX_SCORE" ] && awk "BEGIN { exit ($MAX_SCORE < 0.3) ? 0 : 1 }"; then
        pass "all scores below 0.3 for nonsense query (max: $MAX_SCORE)"
    else
        fail "expected all scores < 0.3 for nonsense query, got max: $MAX_SCORE"
    fi

    # 2c. Results have required fields (name, score, reason)
    FIELDS_OK=$(echo "$SUGGEST_OUTPUT" | jq -r '
      if length == 0 then "empty"
      elif all(has("name") and has("score") and has("reason")) then "ok"
      else "missing"
      end
    ' 2>/dev/null)

    if [ "$FIELDS_OK" = "ok" ]; then
        pass "each result has name, score, reason fields"
    elif [ "$FIELDS_OK" = "empty" ]; then
        pass "no results returned (valid for nonsense query)"
    else
        fail "results missing required fields (name, score, reason)"
    fi
fi

echo ""

# ── Phase 3: Breadcrumb round-trip via CLI ──────────────────────────────

echo "Phase 3: Breadcrumb write/read round-trip"

# Create ephemeral test task
TASK_JSON=$(brana backlog add --subject "EPHEMERAL: skill routing e2e test" --tags "test,ephemeral" --stream tech-debt 2>/dev/null)
TASK_ID=$(echo "$TASK_JSON" | jq -r '.id // ""' 2>/dev/null)

if [ -z "$TASK_ID" ]; then
    fail "could not create ephemeral test task"
    echo ""
    echo "=== Results: $PASS passed, $FAIL failed ==="
    exit 1
fi

echo "  (created $TASK_ID for testing)"

# 3a. Write breadcrumb
brana backlog set "$TASK_ID" context --append "skill_gap_checked: true (score < 0.3, user chose: Skip)" >/dev/null 2>&1

# 3b. Read it back and verify
CONTEXT=$(brana backlog get "$TASK_ID" --field context 2>/dev/null)

if [[ "$CONTEXT" == *"skill_gap_checked: true"* ]]; then
    pass "breadcrumb skill_gap_checked written and readable"
else
    fail "breadcrumb not found in task context after write (got: $CONTEXT)"
fi

# 3c. Verify build.md safety net would skip (breadcrumb present)
if [[ "$CONTEXT" == *"skill_gap_checked"* ]]; then
    pass "build.md step 4a would skip (breadcrumb present) — correct"
else
    fail "build.md step 4a would run unnecessarily (breadcrumb missing)"
fi

# 3d. Test the inverse — task without breadcrumb triggers safety net
TASK2_JSON=$(brana backlog add --subject "EPHEMERAL: no-breadcrumb test" --tags "test,ephemeral" --stream tech-debt 2>/dev/null)
TASK2_ID=$(echo "$TASK2_JSON" | jq -r '.id // ""' 2>/dev/null)

if [ -n "$TASK2_ID" ]; then
    CONTEXT2=$(brana backlog get "$TASK2_ID" --field context 2>/dev/null)
    if [[ "$CONTEXT2" == *"skill_gap_checked"* ]]; then
        fail "fresh task should NOT have skill_gap_checked"
    else
        pass "fresh task has no breadcrumb — build.md safety net would fire"
    fi
    # Cleanup
    brana backlog set "$TASK2_ID" status cancelled >/dev/null 2>&1
    echo "  (cleaned up $TASK2_ID)"
fi

# Cleanup
brana backlog set "$TASK_ID" status cancelled >/dev/null 2>&1
echo "  (cleaned up $TASK_ID)"

echo ""

# ── Summary ─────────────────────────────────────────────────────────────

echo "=== Results: $PASS passed, $FAIL failed ==="
if [ "$FAIL" -gt 0 ]; then
    exit 1
else
    exit 0
fi
