#!/usr/bin/env bash
# Tests for verify-docs.sh --scope claudemd
# Spec: system/scripts/verify-docs.spec.md
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
VERIFY="$REPO_ROOT/system/scripts/verify-docs.sh"

PASS=0
FAIL=0

assert_eq() {
  local label="$1" expected="$2" actual="$3"
  if [[ "$expected" == "$actual" ]]; then
    echo "  PASS: $label"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $label (expected '$expected', got '$actual')"
    FAIL=$((FAIL + 1))
  fi
}

assert_contains() {
  local label="$1" needle="$2" haystack="$3"
  if [[ "$haystack" == *"$needle"* ]]; then
    echo "  PASS: $label"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $label (expected output to contain '$needle')"
    FAIL=$((FAIL + 1))
  fi
}

# Create an isolated portfolio with synthetic CLAUDE.md files
setup_portfolio() {
  local dir
  dir=$(mktemp -d)

  # Clean project — no violations
  mkdir -p "$dir/clean/project"
  cat > "$dir/clean/project/CLAUDE.md" <<'EOF'
# Clean Project

This project has no volatile-content violations.
It uses stable references only.
EOF

  # DATED_STATUS violations: lines with 202X-MM-DD dates
  mkdir -p "$dir/dated/project"
  cat > "$dir/dated/project/CLAUDE.md" <<'EOF'
# Dated Project

> **ON HOLD — 2026-05-08. No active work until client resumes.**

Project started 2025-12-01 with initial scope.
Context dump: inbox/context-2026-04-15.md
EOF

  # PRICING violations: $N/mes or ARS N/mes
  mkdir -p "$dir/pricing/project"
  cat > "$dir/pricing/project/CLAUDE.md" <<'EOF'
# Pricing Project

Service costs:
- API: $500/mes
- Storage: ARS 15000/mes

Stable content here.
EOF

  # TRACKER_TABLE violations: | Status | Priority | table headers
  mkdir -p "$dir/tracker/project"
  cat > "$dir/tracker/project/CLAUDE.md" <<'EOF'
# Tracker Project

| Task | Status | Priority | Assigned |
|------|--------|----------|----------|
| Build API | Done | P1 | Martin |
EOF

  # Multiple violations in one file
  mkdir -p "$dir/multi/project"
  cat > "$dir/multi/project/CLAUDE.md" <<'EOF'
# Multi-violation Project

> **Last updated 2026-03-15**

Cost: $200/mes

| Feature | Status | Effort |
|---------|--------|--------|
| Auth | Done | M |
EOF

  echo "$dir"
}

echo "=== test-verify-docs-claudemd.sh ==="

# 1. Script exists and is executable
echo "Test: script exists and is executable"
assert_eq "script exists" "true" "$([[ -f "$VERIFY" ]] && echo true || echo false)"
assert_eq "script is executable" "true" "$([[ -x "$VERIFY" ]] && echo true || echo false)"

PORTFOLIO=$(setup_portfolio)
trap 'rm -rf "$PORTFOLIO"' EXIT

# 2. Clean file — exit 0, no violations
echo "Test: clean CLAUDE.md exits 0"
ec=0
BRANA_PORTFOLIO_ROOT="$PORTFOLIO/clean" "$VERIFY" --scope claudemd >/dev/null 2>&1 || ec=$?
assert_eq "clean exits 0" "0" "$ec"

# 3. DATED_STATUS violation — exit 1
echo "Test: DATED_STATUS violation exits 1"
ec=0
BRANA_PORTFOLIO_ROOT="$PORTFOLIO/dated" "$VERIFY" --scope claudemd >/dev/null 2>&1 || ec=$?
assert_eq "dated exits 1" "1" "$ec"

# 4. DATED_STATUS output mentions violation type
echo "Test: DATED_STATUS output"
OUT=$(BRANA_PORTFOLIO_ROOT="$PORTFOLIO/dated" "$VERIFY" --scope claudemd 2>&1) || true
assert_contains "dated output has DATED_STATUS" "DATED_STATUS" "$OUT"
assert_contains "dated output has VIOLATIONS" "VIOLATIONS" "$OUT"

# 5. PRICING violation — exit 1
echo "Test: PRICING violation exits 1"
ec=0
BRANA_PORTFOLIO_ROOT="$PORTFOLIO/pricing" "$VERIFY" --scope claudemd >/dev/null 2>&1 || ec=$?
assert_eq "pricing exits 1" "1" "$ec"

# 6. PRICING output mentions violation type
echo "Test: PRICING output"
OUT=$(BRANA_PORTFOLIO_ROOT="$PORTFOLIO/pricing" "$VERIFY" --scope claudemd 2>&1) || true
assert_contains "pricing output has PRICING" "PRICING" "$OUT"

# 7. TRACKER_TABLE violation — exit 1
echo "Test: TRACKER_TABLE violation exits 1"
ec=0
BRANA_PORTFOLIO_ROOT="$PORTFOLIO/tracker" "$VERIFY" --scope claudemd >/dev/null 2>&1 || ec=$?
assert_eq "tracker exits 1" "1" "$ec"

# 8. TRACKER_TABLE output mentions violation type
echo "Test: TRACKER_TABLE output"
OUT=$(BRANA_PORTFOLIO_ROOT="$PORTFOLIO/tracker" "$VERIFY" --scope claudemd 2>&1) || true
assert_contains "tracker output has TRACKER_TABLE" "TRACKER_TABLE" "$OUT"

# 9. Multi-violation counts
echo "Test: multi-violation counts"
OUT=$(BRANA_PORTFOLIO_ROOT="$PORTFOLIO/multi" "$VERIFY" --scope claudemd 2>&1) || true
assert_contains "multi has DATED_STATUS" "DATED_STATUS" "$OUT"
assert_contains "multi has PRICING" "PRICING" "$OUT"
assert_contains "multi has TRACKER_TABLE" "TRACKER_TABLE" "$OUT"

# 10. JSON output — valid JSON with violation keys
echo "Test: --json output is valid JSON with violation keys"
JSON_OUT=$(BRANA_PORTFOLIO_ROOT="$PORTFOLIO/multi" "$VERIFY" --scope claudemd --json 2>&1) || true
if echo "$JSON_OUT" | jq . >/dev/null 2>&1; then
  PASS=$((PASS + 1)); echo "  PASS: JSON is valid"
else
  FAIL=$((FAIL + 1)); echo "  FAIL: JSON is not valid ($JSON_OUT)"
fi
assert_contains "JSON has total_violations" "total_violations" "$JSON_OUT"
assert_contains "JSON has violations" '"violations"' "$JSON_OUT"

# 11. JSON clean file — total_violations: 0
echo "Test: --json clean file shows 0 violations"
JSON_CLEAN=$(BRANA_PORTFOLIO_ROOT="$PORTFOLIO/clean" "$VERIFY" --scope claudemd --json 2>&1) || true
TOTAL=$(echo "$JSON_CLEAN" | jq -r '.total_violations // empty' 2>/dev/null) || TOTAL="err"
assert_eq "JSON clean total_violations=0" "0" "$TOTAL"

# 12. Scanned file count appears in output
echo "Test: output includes scanned file count"
OUT=$(BRANA_PORTFOLIO_ROOT="$PORTFOLIO/dated" "$VERIFY" --scope claudemd 2>&1) || true
assert_contains "output has Scanned" "Scanned" "$OUT"

# 13. Missing portfolio root — exit 2
echo "Test: missing portfolio root exits 2"
ec=0
BRANA_PORTFOLIO_ROOT="/nonexistent/path/$$" "$VERIFY" --scope claudemd >/dev/null 2>&1 || ec=$?
assert_eq "missing portfolio exits 2" "2" "$ec"

# Summary
echo ""
echo "Results: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]] && exit 0 || exit 1
