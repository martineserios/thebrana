#!/usr/bin/env bash
# Unit tests for system/scripts/check-selector.sh (t-1899).
#
# Coverage:
#   - core() block (checks 1-14) emitted for all expected trigger paths
#   - Checks 15+ emitted individually for their specific trigger paths
#   - Empty input exits 0 with no output
#   - Multiple triggers for the same check deduplicated by sort -u

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SELECTOR="$SCRIPT_DIR/../../system/scripts/check-selector.sh"

PASS=0; FAIL=0; TOTAL=0

assert_contains() {
    local desc="$1" needle="$2" haystack="$3"
    TOTAL=$((TOTAL+1))
    if [[ "$haystack" == *"$needle"* ]]; then
        PASS=$((PASS+1)); echo "  PASS: $desc"
    else
        FAIL=$((FAIL+1)); echo "  FAIL: $desc — '$needle' not found in output"
        echo "         output was: $(echo "$haystack" | tr '\n' ' ')"
    fi
}

assert_not_contains() {
    local desc="$1" needle="$2" haystack="$3"
    TOTAL=$((TOTAL+1))
    if [[ "$haystack" == *"$needle"* ]]; then
        FAIL=$((FAIL+1)); echo "  FAIL: $desc — '$needle' unexpectedly present"
        echo "         output was: $(echo "$haystack" | tr '\n' ' ')"
    else
        PASS=$((PASS+1)); echo "  PASS: $desc"
    fi
}

# Exact line match — use for check numbers to avoid "1" matching inside "18", "21", etc.
assert_has_num() {
    local desc="$1" needle="$2" haystack="$3"
    TOTAL=$((TOTAL+1))
    if echo "$haystack" | grep -qE "^${needle}$"; then
        PASS=$((PASS+1)); echo "  PASS: $desc"
    else
        FAIL=$((FAIL+1)); echo "  FAIL: $desc — check '$needle' not in output"
        echo "         output was: $(echo "$haystack" | tr '\n' ' ')"
    fi
}

assert_not_num() {
    local desc="$1" needle="$2" haystack="$3"
    TOTAL=$((TOTAL+1))
    if echo "$haystack" | grep -qE "^${needle}$"; then
        FAIL=$((FAIL+1)); echo "  FAIL: $desc — check '$needle' unexpectedly present"
        echo "         output was: $(echo "$haystack" | tr '\n' ' ')"
    else
        PASS=$((PASS+1)); echo "  PASS: $desc"
    fi
}

assert_exits_zero() {
    local desc="$1"; shift
    TOTAL=$((TOTAL+1))
    if "$@" > /dev/null 2>&1; then
        PASS=$((PASS+1)); echo "  PASS: $desc"
    else
        FAIL=$((FAIL+1)); echo "  FAIL: $desc — expected exit 0, got non-zero"
    fi
}

assert_empty() {
    local desc="$1" haystack="$2"
    TOTAL=$((TOTAL+1))
    if [ -z "$haystack" ]; then
        PASS=$((PASS+1)); echo "  PASS: $desc"
    else
        FAIL=$((FAIL+1)); echo "  FAIL: $desc — expected empty, got: $(echo "$haystack" | tr '\n' ' ')"
    fi
}

assert_count_eq() {
    local desc="$1" expected="$2" needle="$3" haystack="$4"
    TOTAL=$((TOTAL+1))
    local actual
    actual=$(echo "$haystack" | grep -c "^${needle}$" || true)
    if [ "$actual" -eq "$expected" ]; then
        PASS=$((PASS+1)); echo "  PASS: $desc"
    else
        FAIL=$((FAIL+1)); echo "  FAIL: $desc — expected $expected occurrence(s) of '$needle', got $actual"
    fi
}

run() { echo "$1" | bash "$SELECTOR"; }
runm() { printf '%s\n' "$@" | bash "$SELECTOR"; }

echo "=== check-selector.sh unit tests (t-1899) ==="
echo ""

# ── Empty input ───────────────────────────────────────────────────────────────
echo "--- Empty input ---"
assert_exits_zero   "empty piped input exits 0" bash -c "echo '' | bash '$SELECTOR'"
assert_empty        "empty piped input produces no output" "$(echo "" | bash "$SELECTOR" || true)"
assert_exits_zero   "stdin /dev/null exits 0" bash -c "bash '$SELECTOR' < /dev/null"
assert_empty        "stdin /dev/null produces no output" "$(bash "$SELECTOR" < /dev/null || true)"
assert_exits_zero   "unknown file path exits 0" bash -c "echo 'random/unknown/file.txt' | bash '$SELECTOR'"
assert_empty        "unknown file path produces no output" "$(run "random/unknown/file.txt" || true)"

# ── core() block — triggers emitting check 1 ─────────────────────────────────
echo ""
echo "--- core() triggers (expect check 1 in output) ---"

OUT=$(run "system/skills/mybuild/SKILL.md"); assert_contains "SKILL.md → 1" "1" "$OUT"
OUT=$(run "system/skills/mybuild/hook.sh"); assert_contains  "skills/** → 1" "1" "$OUT"
OUT=$(run "system/rules/my-rule.md"); assert_contains        "rules/* → 1" "1" "$OUT"
OUT=$(run "system/settings.json"); assert_contains           "settings.json → 1" "1" "$OUT"
OUT=$(run "system/agents/analyst.md"); assert_contains       "agents/*.md → 1" "1" "$OUT"
OUT=$(run "system/procedures/close.md"); assert_contains     "procedures/close.md → 1" "1" "$OUT"
OUT=$(run "system/procedures/build.md"); assert_contains     "procedures/build.md → 1" "1" "$OUT"
OUT=$(run "system/procedures/reconcile.md"); assert_contains "procedures/*.md → 1" "1" "$OUT"
OUT=$(run "system/hooks/lib/resolve-brana.sh"); assert_contains "hooks/lib/*.sh → 1" "1" "$OUT"
OUT=$(run "system/hooks/session-start.sh"); assert_contains  "hooks/*.sh → 1" "1" "$OUT"
OUT=$(run "system/commands/brana-build.md"); assert_contains "commands/* → 1" "1" "$OUT"
OUT=$(run "system/scripts/feed-summarize.sh"); assert_contains "feed-summarize.sh → 1" "1" "$OUT"
OUT=$(run "system/scripts/check-selector.sh"); assert_contains "scripts/*.sh → 1" "1" "$OUT"
OUT=$(run "docs/18-lean-roadmap.md"); assert_contains        "docs/* → 1" "1" "$OUT"
OUT=$(run "system/unknown-file.txt"); assert_contains        "system/* catch-all → 1" "1" "$OUT"

# ── Checks 15+ — individually emitted for specific paths ─────────────────────
echo ""
echo "--- Checks 15+ (individually emitted) ---"

# spec-graph.json → 18 19 20 21 (no 1)
OUT=$(run "docs/spec-graph.json")
assert_has_num  "spec-graph.json → 18" "18" "$OUT"
assert_has_num  "spec-graph.json → 19" "19" "$OUT"
assert_has_num  "spec-graph.json → 20" "20" "$OUT"
assert_has_num  "spec-graph.json → 21" "21" "$OUT"
assert_not_num  "spec-graph.json → no 1" "1" "$OUT"

# tasks.json → 25 26 (no 1)
OUT=$(run ".claude/tasks.json")
assert_has_num  "tasks.json → 25" "25" "$OUT"
assert_has_num  "tasks.json → 26" "26" "$OUT"
assert_not_num  "tasks.json → no 1" "1" "$OUT"

# plugin.json → 35 (no 1)
OUT=$(run "system/plugin.json")
assert_has_num  "plugin.json → 35" "35" "$OUT"
assert_not_num  "plugin.json → no 1" "1" "$OUT"

# hooks.json → 39 48 (no 1)
OUT=$(run ".claude/hooks.json")
assert_has_num  "hooks.json → 39" "39" "$OUT"
assert_has_num  "hooks.json → 48" "48" "$OUT"
assert_not_num  "hooks.json → no 1" "1" "$OUT"

# docs/architecture/hooks.md → 48 49 (no 1 — explicit match before docs/* fallback)
OUT=$(run "docs/architecture/hooks.md")
assert_has_num  "docs/architecture/hooks.md → 48" "48" "$OUT"
assert_has_num  "docs/architecture/hooks.md → 49" "49" "$OUT"
assert_not_num  "docs/architecture/hooks.md → no 1" "1" "$OUT"

# hooks/tests/* — NOTE: in bash case, system/hooks/*.sh (listed first) also matches
# system/hooks/tests/*, so the hooks/tests/*) branch is unreachable. Current behavior:
# hooks test files emit core(1) + 28 30 37 47 (same as hooks/*.sh). Documented as
# ordering issue; tested here to pin the actual behavior.
OUT=$(run "system/hooks/tests/test-foo.sh")
assert_has_num  "hooks/tests/* → core(1) via hooks/*.sh match" "1" "$OUT"
assert_has_num  "hooks/tests/* → 28 (hooks/*.sh match)" "28" "$OUT"

# SKILL.md additionally emits 33
OUT=$(run "system/skills/build/SKILL.md")
assert_contains     "SKILL.md → 33" "33" "$OUT"

# agents/*.md additionally emits 42
OUT=$(run "system/agents/debrief-analyst.md")
assert_contains     "agents → 42" "42" "$OUT"

# procedures/close.md additionally emits 23 36 40 43 44 45
OUT=$(run "system/procedures/close.md")
for n in 23 36 40 43 44 45; do
    assert_contains "close.md → $n" "$n" "$OUT"
done

# procedures/*.md (non-close/build) emits 23 36 40 45 (not 43 44)
OUT=$(run "system/procedures/reconcile.md")
for n in 23 36 40 45; do
    assert_contains "procedures/*.md → $n" "$n" "$OUT"
done

# t-1942 phase-split paths: SKILL.md + phases/*.md map to effective-body checks
OUT=$(run "system/skills/build/phases/load.md")
for n in 33 23 36 40 45 52 54 56; do
    assert_contains "build phases → $n" "$n" "$OUT"
done
OUT=$(run "system/skills/close/SKILL.md")
for n in 33 23 36 40 43 44 45 55; do
    assert_contains "close SKILL.md → $n" "$n" "$OUT"
done
OUT=$(run "system/skills/backlog/phases/start.md")
for n in 33 23 36 40 45; do
    assert_contains "backlog phases → $n" "$n" "$OUT"
done
OUT=$(run "system/skills/reconcile/phases/security.md")
for n in 33 23 36 40 45; do
    assert_contains "reconcile phases → $n" "$n" "$OUT"
done
assert_not_contains "procedures/*.md → no 43" "43" "$OUT"
assert_not_contains "procedures/*.md → no 44" "44" "$OUT"

# hooks/*.sh emits 28 30 37 47
OUT=$(run "system/hooks/pre-tool-use.sh")
for n in 28 30 37 47; do
    assert_contains "hooks/*.sh → $n" "$n" "$OUT"
done

# feed-summarize.sh additionally emits 41
OUT=$(run "system/scripts/feed-summarize.sh")
assert_contains     "feed-summarize.sh → 41" "41" "$OUT"

# docs/* additionally emits 15 16
OUT=$(run "docs/18-lean-roadmap.md")
assert_contains     "docs/* → 15" "15" "$OUT"
assert_contains     "docs/* → 16" "16" "$OUT"

# ── Deduplication via sort -u ─────────────────────────────────────────────────
echo ""
echo "--- Deduplication ---"

# Two SKILL.md files both trigger core → only one "1" in output
OUT=$(runm "system/skills/build/SKILL.md" "system/skills/backlog/SKILL.md")
assert_count_eq "two SKILL.md → exactly one '1'" 1 "1" "$OUT"
assert_count_eq "two SKILL.md → exactly one '33'" 1 "33" "$OUT"

# Two hooks both trigger 28 → only one "28"
OUT=$(runm "system/hooks/session-start.sh" "system/hooks/pre-tool-use.sh")
assert_count_eq "two hooks → exactly one '28'" 1 "28" "$OUT"
assert_count_eq "two hooks → exactly one '1'" 1 "1" "$OUT"

# Mixed triggers: spec-graph + tasks.json → union, no dups
OUT=$(runm "docs/spec-graph.json" ".claude/tasks.json")
assert_has_num  "mixed → 18" "18" "$OUT"
assert_has_num  "mixed → 25" "25" "$OUT"
assert_not_num  "mixed → no 1" "1" "$OUT"

# Same file listed twice → deduped
OUT=$(runm "docs/spec-graph.json" "docs/spec-graph.json")
assert_count_eq "duplicate spec-graph → one '18'" 1 "18" "$OUT"

echo ""
echo "=== Results: $PASS passed, $FAIL failed, $TOTAL total ==="
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
