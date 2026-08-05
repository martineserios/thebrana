#!/usr/bin/env bash
# Regression test: `validate.sh --fix N` dispatch (t-2630, ADR-077 Decision #6).
#
# Covers: --check/--fix mutual exclusion, the NO_REMEDY path (reason printed,
# nothing touched), the HAS_REMEDY happy path (apply + re-verify + undo hint),
# an id absent from the registry entirely, and the dispatch-safety boundary
# (a registry entry claiming HAS_REMEDY with no matching function must refuse,
# never construct-and-invoke a function name blindly).
#
# Run: bash tests/procedures/test-validate-fix-dispatch.sh

set -uo pipefail

PASS=0
FAIL=0
TOTAL=0

assert_true() {
    local desc="$1" cond="$2"
    TOTAL=$((TOTAL + 1))
    if [ "$cond" = "true" ]; then
        echo "  PASS: $desc"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $desc"
        FAIL=$((FAIL + 1))
    fi
}

REPO_ROOT=$(git rev-parse --show-toplevel)
VALIDATE_SH="$REPO_ROOT/validate.sh"

if ! grep -q -- '--fix' "$VALIDATE_SH"; then
    echo "ERROR: $VALIDATE_SH has no --fix flag yet"
    exit 1
fi

echo "=== --check and --fix are mutually exclusive ==="
OUT=$(bash "$VALIDATE_SH" --check 1 --fix 1 2>&1); RC=$?
assert_true "--check + --fix together exits non-zero" "$([ "$RC" -ne 0 ] && echo true || echo false)"
assert_true "--check + --fix together prints a mutual-exclusion message" \
    "$(echo "$OUT" | grep -qi "mutually exclusive" && echo true || echo false)"

echo ""
echo "=== --fix on a NO_REMEDY check (real repo — this path never touches a file) ==="
BEFORE=$(cd "$REPO_ROOT" && git diff --stat)
OUT=$(cd "$REPO_ROOT" && bash "$VALIDATE_SH" --fix 1 2>&1); RC=$?
AFTER=$(cd "$REPO_ROOT" && git diff --stat)
assert_true "--fix 1 (judgment-required) exits non-zero" "$([ "$RC" -ne 0 ] && echo true || echo false)"
assert_true "--fix 1 prints the NO_REMEDY reason" \
    "$(echo "$OUT" | grep -q "No remedy for check 1: judgment-required" && echo true || echo false)"
assert_true "--fix 1 touches no files (git diff unchanged)" \
    "$([ "$BEFORE" = "$AFTER" ] && echo true || echo false)"

echo ""
echo "=== --fix on an id absent from the registry entirely (real repo — safe, never applies) ==="
OUT=$(cd "$REPO_ROOT" && bash "$VALIDATE_SH" --fix 9999 2>&1); RC=$?
assert_true "--fix 9999 (no registry entry) exits non-zero" "$([ "$RC" -ne 0 ] && echo true || echo false)"
assert_true "--fix 9999 reports no registry entry, not a crash" \
    "$(echo "$OUT" | grep -q "No registry entry for check 9999" && echo true || echo false)"

# ── Fixture repo for the HAS_REMEDY happy path + dispatch-safety boundary ────
FIXTURE_REPO=$(mktemp -d)
trap 'rm -rf "$FIXTURE_REPO"' EXIT

mkdir -p "$FIXTURE_REPO/system/scripts" "$FIXTURE_REPO/system/agents" "$FIXTURE_REPO/.claude" "$FIXTURE_REPO/docs"
cp "$VALIDATE_SH" "$FIXTURE_REPO/validate.sh"
cp "$REPO_ROOT/system/scripts/validate-remedies.sh" "$FIXTURE_REPO/system/scripts/validate-remedies.sh"
echo '{}' > "$FIXTURE_REPO/docs/spec-graph.json"
echo '{"tasks":[]}' > "$FIXTURE_REPO/.claude/tasks.json"
cat > "$FIXTURE_REPO/system/agents/debrief-analyst.md" <<'EOF'
---
name: debrief-analyst
description: "test fixture"
model: opus
effort: high
---
body
EOF
( cd "$FIXTURE_REPO" && git init -q && git add -A && git -c user.email=test@test -c user.name=test commit -q -m init )

echo ""
echo "=== --fix on a HAS_REMEDY check (fixture repo — happy path) ==="
OUT=$(bash "$FIXTURE_REPO/validate.sh" --fix 42 2>&1); RC=$?
MODEL_AFTER=$(grep -m1 '^model:' "$FIXTURE_REPO/system/agents/debrief-analyst.md" | awk '{print $2}')
assert_true "--fix 42 exits zero on success" "$([ "$RC" -eq 0 ] && echo true || echo false)"
assert_true "--fix 42 actually fixed the file (model: sonnet)" "$([ "$MODEL_AFTER" = "sonnet" ] && echo true || echo false)"
assert_true "--fix 42 confirms via re-check, not just 'apply exited 0'" \
    "$(echo "$OUT" | grep -q "Fixed check 42" && echo true || echo false)"
assert_true "--fix 42 prints an undo hint" \
    "$(echo "$OUT" | grep -q "To undo:" && echo true || echo false)"

echo ""
echo "=== Dispatch safety: HAS_REMEDY entry with no matching function must refuse, not crash ==="
# Simulate a registry/implementation drift: a check id is marked HAS_REMEDY but its
# apply function was never written (or was renamed/deleted by mistake). Dispatch
# must detect this via declare -f and refuse cleanly — never construct-and-invoke
# "remedy_${N}_apply" blindly (which would surface as a raw "command not found").
sed -i 's/\[68\]="NO_REMEDY:not-fixable[^"]*"/[68]="HAS_REMEDY"/' "$FIXTURE_REPO/system/scripts/validate-remedies.sh"
OUT=$(bash "$FIXTURE_REPO/validate.sh" --fix 68 2>&1); RC=$?
assert_true "drifted registry entry (HAS_REMEDY, no function) exits non-zero" "$([ "$RC" -ne 0 ] && echo true || echo false)"
assert_true "drifted registry entry is refused with a clear message, not a raw 'command not found'" \
    "$(echo "$OUT" | grep -q "not defined — refusing to guess" && echo true || echo false)"
assert_true "drifted registry entry does not leak a raw shell error" \
    "$(! echo "$OUT" | grep -qi "command not found" && echo true || echo false)"

echo ""
echo "=== Summary ==="
echo "Total: $TOTAL | Passed: $PASS | Failed: $FAIL"
[ "$FAIL" -eq 0 ] || exit 1
