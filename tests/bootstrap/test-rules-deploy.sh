#!/usr/bin/env bash
# Tests for rules deployment (t-1946).
#
# t-760 stopped bootstrap from copying rules to ~/.claude/rules/ on the
# assumption "the plugin loads system/rules/". That assumption was FALSE —
# CC plugins cannot provide rules (verified against plugins-reference docs
# 2026-06-10). The deployed copies survived only until bootstrap's cleanup
# step finally ran; after that, the entire discipline shell was undeployed.
#
# Tests:
#   T1: bootstrap.sh syncs system/rules/ -> ~/.claude/rules/ (no skip+clean)
#   T2: bootstrap excludes README.md (authoring contract, not a rule)
#   T3: no alwaysApply: field remains in system/rules/
#   T4: every rule declares paths: or always-load: true (authoring contract)
#   T5: bootstrap dry-run (--check) lists rules deployment

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

PASS=0; FAIL=0; TOTAL=0

check() {
    local desc="$1" ok="$2" detail="${3:-}"
    TOTAL=$((TOTAL+1))
    if [ "$ok" = "0" ]; then
        PASS=$((PASS+1)); echo "  PASS: $desc"
    else
        FAIL=$((FAIL+1)); echo "  FAIL: $desc${detail:+ — $detail}"
    fi
}

echo "=== rules deployment (t-1946) ==="

# T1 — bootstrap syncs rules (and the t-760 skip+clean block is gone)
grep -q 'sync_dir "$SYSTEM_DIR/rules"' "$REPO_ROOT/bootstrap.sh"; check "T1: bootstrap syncs system/rules/" $?
! grep -q "Cleaning stale bootstrap rules" "$REPO_ROOT/bootstrap.sh"; check "T1b: t-760 cleanup block removed" $?

# T2 — README excluded from deployment
grep -q 'README' "$REPO_ROOT/bootstrap.sh" && grep -A6 'sync_dir "$SYSTEM_DIR/rules"' "$REPO_ROOT/bootstrap.sh" | grep -q 'README'; check "T2: README.md excluded from rules deploy" $?

# T3 — no alwaysApply anywhere in rules
AA=$(grep -rln "alwaysApply" "$REPO_ROOT/system/rules/" 2>/dev/null || true)
[ -z "$AA" ]; check "T3: no alwaysApply: field remains" $? "$AA"

# T4 — authoring contract: every rule declares paths: or always-load:
BAD=""
for f in "$REPO_ROOT"/system/rules/*.md; do
    [ "$(basename "$f")" = "README.md" ] && continue
    head -10 "$f" | grep -qE '^(paths:|always-load:)' || BAD="$BAD $(basename "$f")"
done
[ -z "$BAD" ]; check "T4: every rule declares paths: or always-load:" $? "$BAD"

# T5 — bootstrap --check mentions rules
OUT=$(cd "$REPO_ROOT" && timeout 60 ./bootstrap.sh --check 2>/dev/null | grep -i "rules" | head -2)
[[ "$OUT" == *"rules"* ]]; check "T5: bootstrap --check reports rules deployment" $? "$OUT"

echo ""
echo "$PASS/$TOTAL passed"
[ "$FAIL" -eq 0 ] || exit 1
