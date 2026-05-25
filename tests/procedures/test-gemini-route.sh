#!/usr/bin/env bash
# Tests for /brana:gemini ROUTE step — routing classification (t-1651).
#
# Replicates the ROUTE + ENRICH convention-sensitive threshold logic from
# system/procedures/gemini.md as a bash classify function and asserts the
# 4 core scenarios:
#
#   (1) ruflo unavailable + convention-sensitive task → abort-convention-sensitive
#   (2) ruflo unavailable + non-sensitive task        → warn-proceed
#   (3) ruflo available + zero source:thebrana hits   → prompt-user (ENRICH gate)
#   (4) any 4-question answer is NO                  → claude-inline
#
# Run: bash tests/procedures/test-gemini-route.sh

set -uo pipefail

PASS=0
FAIL=0
TOTAL=0

# ── Helpers ───────────────────────────────────────────────────────────────────

assert_eq() {
    local desc="$1" expected="$2" actual="$3"
    TOTAL=$((TOTAL + 1))
    if [ "$expected" = "$actual" ]; then
        echo "  PASS: $desc"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $desc"
        echo "        expected: $expected"
        echo "        actual:   $actual"
        FAIL=$((FAIL + 1))
    fi
}

# ── ROUTE classify function ───────────────────────────────────────────────────
# Replicates system/procedures/gemini.md ROUTE + ENRICH convention-sensitive gate.
#
# Args:
#   $1  ruflo_available      — yes | no
#   $2  task_type            — boilerplate | test-scaffolding | adr-draft | research | other
#   $3  atomic               — yes | no
#   $4  system_isolated      — yes | no
#   $5  context_enrichable   — yes | no
#   $6  speed_benefit        — yes | no
#   $7  thebrana_hits        — integer (source:thebrana ruflo results; only relevant when ruflo=yes)
#
# Outputs one of:
#   claude-inline              — 4-question routing failed; delegate to Claude instead
#   abort-convention-sensitive — ruflo required but unavailable for convention-sensitive task
#   warn-proceed               — ruflo unavailable for non-sensitive task; warn + continue
#   prompt-user                — ruflo available but zero source:thebrana hits for ⚠️ type
#   proceed                    — all clear; delegate to Gemini

route() {
    local ruflo="$1"
    local task_type="$2"
    local atomic="$3"
    local sys_iso="$4"
    local ctx_enrich="$5"
    local speed="$6"
    local thebrana_hits="${7:-1}"

    # Convention-sensitive types from gemini.md
    local is_convention_sensitive="no"
    case "$task_type" in
        boilerplate|test-scaffolding|adr-draft) is_convention_sensitive="yes" ;;
    esac

    # Step 1: 4-question routing test (gemini.md ROUTE — "if any answer is no, abort")
    if [ "$atomic" = "no" ] || [ "$sys_iso" = "no" ] || \
       [ "$ctx_enrich" = "no" ] || [ "$speed" = "no" ]; then
        echo "claude-inline"
        return
    fi

    # Step 2: ruflo availability × convention-sensitive hard-block (gemini.md ROUTE)
    if [ "$ruflo" = "no" ] && [ "$is_convention_sensitive" = "yes" ]; then
        echo "abort-convention-sensitive"
        return
    fi

    # Step 3: ruflo unavailable + non-sensitive → warn + proceed (implied by gemini.md ROUTE)
    if [ "$ruflo" = "no" ]; then
        echo "warn-proceed"
        return
    fi

    # Step 4: ruflo available + convention-sensitive + zero source:thebrana → prompt (gemini.md ENRICH)
    if [ "$is_convention_sensitive" = "yes" ] && [ "$thebrana_hits" -eq 0 ]; then
        echo "prompt-user"
        return
    fi

    echo "proceed"
}

echo "=== test-gemini-route.sh ==="
echo ""

# ── Case 1: ruflo unavailable + convention-sensitive → abort ──────────────────

echo "Case 1: ruflo unavailable + convention-sensitive task → abort-convention-sensitive"

result=$(route "no" "boilerplate"     "yes" "yes" "yes" "yes" "0")
assert_eq "boilerplate + no ruflo → abort-convention-sensitive" \
    "abort-convention-sensitive" "$result"

result=$(route "no" "test-scaffolding" "yes" "yes" "yes" "yes" "0")
assert_eq "test-scaffolding + no ruflo → abort-convention-sensitive" \
    "abort-convention-sensitive" "$result"

result=$(route "no" "adr-draft"       "yes" "yes" "yes" "yes" "0")
assert_eq "adr-draft + no ruflo → abort-convention-sensitive" \
    "abort-convention-sensitive" "$result"

# ── Case 2: ruflo unavailable + non-sensitive → warn + proceed ────────────────

echo ""
echo "Case 2: ruflo unavailable + non-sensitive task → warn-proceed"

result=$(route "no" "research" "yes" "yes" "yes" "yes" "0")
assert_eq "research + no ruflo → warn-proceed" \
    "warn-proceed" "$result"

result=$(route "no" "other" "yes" "yes" "yes" "yes" "0")
assert_eq "generic task + no ruflo → warn-proceed" \
    "warn-proceed" "$result"

# ── Case 3: ruflo available + zero source:thebrana for ⚠️ type → prompt ──────

echo ""
echo "Case 3: ruflo available + zero source:thebrana results for ⚠️ task type → prompt-user"

result=$(route "yes" "boilerplate"     "yes" "yes" "yes" "yes" "0")
assert_eq "boilerplate + ruflo + 0 thebrana hits → prompt-user" \
    "prompt-user" "$result"

result=$(route "yes" "test-scaffolding" "yes" "yes" "yes" "yes" "0")
assert_eq "test-scaffolding + ruflo + 0 thebrana hits → prompt-user" \
    "prompt-user" "$result"

result=$(route "yes" "adr-draft" "yes" "yes" "yes" "yes" "0")
assert_eq "adr-draft + ruflo + 0 thebrana hits → prompt-user" \
    "prompt-user" "$result"

# With hits present → should proceed, not prompt
result=$(route "yes" "boilerplate" "yes" "yes" "yes" "yes" "3")
assert_eq "boilerplate + ruflo + 3 thebrana hits → proceed (not prompt)" \
    "proceed" "$result"

# ── Case 4: any 4-question answer is NO → claude-inline ──────────────────────

echo ""
echo "Case 4: any 4-question answer is NO → claude-inline"

result=$(route "yes" "research" "no"  "yes" "yes" "yes" "1")
assert_eq "not atomic → claude-inline" "claude-inline" "$result"

result=$(route "yes" "research" "yes" "no"  "yes" "yes" "1")
assert_eq "not system-isolated → claude-inline" "claude-inline" "$result"

result=$(route "yes" "research" "yes" "yes" "no"  "yes" "1")
assert_eq "not context-enrichable → claude-inline" "claude-inline" "$result"

result=$(route "yes" "research" "yes" "yes" "yes" "no"  "1")
assert_eq "no speed benefit → claude-inline" "claude-inline" "$result"

# 4-question gate fires before ruflo check (not atomic + convention + no ruflo → claude-inline)
result=$(route "no" "boilerplate" "no" "yes" "yes" "yes" "0")
assert_eq "not atomic overrides convention-sensitive abort (4Q fires first) → claude-inline" \
    "claude-inline" "$result"

# ── Happy paths ───────────────────────────────────────────────────────────────

echo ""
echo "Happy paths"

result=$(route "yes" "research" "yes" "yes" "yes" "yes" "2")
assert_eq "research + ruflo + 4Q pass → proceed" "proceed" "$result"

result=$(route "yes" "other" "yes" "yes" "yes" "yes" "0")
assert_eq "non-sensitive + ruflo + 0 thebrana hits → proceed (thebrana_hits only checked for ⚠️ types)" \
    "proceed" "$result"

# ── Summary ───────────────────────────────────────────────────────────────────

echo ""
echo "=== Results: $PASS/$TOTAL passed, $FAIL failed ==="

[ "$FAIL" -eq 0 ] || exit 1
