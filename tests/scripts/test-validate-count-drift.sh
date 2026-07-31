#!/usr/bin/env bash
# Tests for validate.sh Check 13 — count drift in docs/architecture/ living docs.
# Tests Perl extraction patterns and per-component threshold logic directly
# (not the full validate.sh — avoids fixture complexity for set -euo pipefail).
# t-1443: adds hooks keyword + pattern 3 (plain list) + 80% threshold for hooks.

set -uo pipefail

PASS=0
FAIL=0
TOTAL=0

TMPROOT=$(mktemp -d)
trap 'rm -rf "$TMPROOT"' EXIT

# Reproduce the Perl extraction logic from Check 13.
# After t-1443: patterns 1+2 include hooks, pattern 3 is new (plain-list format).
check13_extract() {
    local file="$1"
    perl -ne '
        while (/\((\d+)\s+(skills|rules|agents|checks|hooks)[:\s,)]/g) { print "$.:$1:$2\n" }
        while (/(?:has|have|deploys?|includes?|contains?|runs?)\s+(\d+)\s+(skills|rules|agents|checks|hooks)\b/g) { print "$.:$1:$2\n" }
        while (/\b(\d+)\s+(skills|rules|agents|checks|hooks)(?=[,\.\)])/g) { print "$.:$1:$2\n" }
    ' "$file" 2>/dev/null || true
}

# Pattern 3 only — for isolated contextual-mention tests
check13_pattern3_only() {
    local file="$1"
    perl -ne '
        while (/\b(\d+)\s+(skills|rules|agents|checks|hooks)(?=[,\.\)])/g) { print "$.:$1:$2\n" }
    ' "$file" 2>/dev/null || true
}

# Reproduce the threshold guard from Check 13.
# hooks: 80% threshold (grew dramatically: 10→35); others: 30%.
check13_should_flag() {
    local num="$1" actual="$2" component="$3"
    local diff pct threshold
    diff=$((num - actual))
    [ "$diff" -lt 0 ] && diff=$((-diff))
    case "$component" in
        hooks) pct=80 ;;
        *)     pct=30 ;;
    esac
    threshold=$((actual * pct / 100))
    [ "$threshold" -lt 2 ] && threshold=2
    # flag = diff < threshold (close enough to be a stale total)
    if [ "$diff" -lt "$threshold" ]; then echo "flag"; else echo "skip"; fi
}

assert_contains() {
    local desc="$1" needle="$2" haystack="$3"
    TOTAL=$((TOTAL + 1))
    if [[ "$haystack" == *"$needle"* ]]; then
        echo "  PASS: $desc"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $desc — expected output to contain '$needle'"
        echo "$haystack" | sed 's/^/    /' >&2
        FAIL=$((FAIL + 1))
    fi
}

assert_not_contains() {
    local desc="$1" needle="$2" haystack="$3"
    TOTAL=$((TOTAL + 1))
    if [[ "$haystack" != *"$needle"* ]]; then
        echo "  PASS: $desc"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $desc — expected output NOT to contain '$needle', but it did"
        FAIL=$((FAIL + 1))
    fi
}

assert_eq() {
    local desc="$1" expected="$2" actual_val="$3"
    TOTAL=$((TOTAL + 1))
    if [ "$expected" = "$actual_val" ]; then
        echo "  PASS: $desc"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $desc — expected '$expected', got '$actual_val'"
        FAIL=$((FAIL + 1))
    fi
}

echo "=== test-validate-count-drift.sh ==="
echo ""

# ── Pattern extraction tests ────────────────────────────────────────────────

echo "Test group: Perl extraction — pattern 1 (bracket format)"

FIXTURE="$TMPROOT/bracket.md"
cat > "$FIXTURE" << 'EOF'
| marketplace.json | Yes | Metadata present (24 skills, 10 hooks, 11 agents) |
EOF
OUT=$(check13_extract "$FIXTURE")
assert_contains "bracket: extracts 24 skills"  "24:skills" "$OUT"
assert_contains "bracket: extracts 10 hooks"   "10:hooks"  "$OUT"
assert_contains "bracket: extracts 11 agents"  "11:agents" "$OUT"

echo ""
echo "Test group: Perl extraction — pattern 3 (plain list format, NEW)"

FIXTURE="$TMPROOT/plain_list.md"
cat > "$FIXTURE" << 'EOF'
**Current state:** Strong — 33 skills, 11 agents, 10 hooks. Well-documented.
EOF
OUT=$(check13_extract "$FIXTURE")
assert_contains "plain_list: extracts 33 skills" "33:skills" "$OUT"
assert_contains "plain_list: extracts 11 agents" "11:agents" "$OUT"
assert_contains "plain_list: extracts 10 hooks"  "10:hooks"  "$OUT"

echo ""
echo "Test group: Perl extraction — pattern 3 (em dash list format)"

FIXTURE="$TMPROOT/dash_list.md"
cat > "$FIXTURE" << 'EOF'
Phase 1 shipped: 37 skills, 10 agents, 9 hooks. What I learned building an AI brain.
EOF
OUT=$(check13_extract "$FIXTURE")
assert_contains "dash_list: extracts 37 skills" "37:skills" "$OUT"
assert_contains "dash_list: extracts 10 agents" "10:agents" "$OUT"
assert_contains "dash_list: extracts 9 hooks"   "9:hooks"   "$OUT"

echo ""
echo "Test group: Perl extraction — pattern 3 does NOT fire on contextual mentions"

# These fixtures have numbers near keywords but NOT followed by , . or ) —
# pattern 3 specifically should skip them.
FIXTURE="$TMPROOT/contextual.md"
cat > "$FIXTURE" << 'EOF'
Simplify 42 skills to ~25 by merging redundancies.
Only 3 hooks use profiles today.
31 skills ready for headless invocation
EOF
P3OUT=$(check13_pattern3_only "$FIXTURE")
# "42 skills to" — "to" follows, no comma/period/paren → NOT matched
assert_not_contains "contextual: 42 skills to: skipped by p3" "42:skills" "$P3OUT"
# "3 hooks use" — "use" follows, no punctuation → NOT matched
assert_not_contains "contextual: 3 hooks use: skipped by p3"  "3:hooks"   "$P3OUT"
# "31 skills ready" — no punctuation → NOT matched
assert_not_contains "contextual: 31 skills ready: skipped by p3" "31:skills" "$P3OUT"

echo ""
echo "Test group: Perl extraction — pattern 2 (verb prefix)"

FIXTURE="$TMPROOT/verb.md"
cat > "$FIXTURE" << 'EOF'
The system has 10 hooks registered.
The plugin deploys 35 hooks at startup.
EOF
OUT=$(check13_extract "$FIXTURE")
assert_contains "verb: extracts 'has 10 hooks'"    "10:hooks" "$OUT"
assert_contains "verb: extracts 'deploys 35 hooks'" "35:hooks" "$OUT"

echo ""

# ── Threshold tests ─────────────────────────────────────────────────────────

echo "Test group: Threshold — hooks (80% pct, actual=35)"

# "10 hooks" stale total — diff=25, threshold=28, 25 < 28 → flag
assert_eq "hooks 10 vs 35: flag (stale total)" "flag" "$(check13_should_flag 10 35 hooks)"
# "9 hooks" stale total — diff=26, threshold=28, 26 < 28 → flag
assert_eq "hooks 9 vs 35: flag (stale total)"  "flag" "$(check13_should_flag 9 35 hooks)"
# "5 hooks" subset count — diff=30, threshold=28, 30 >= 28 → skip
assert_eq "hooks 5 vs 35: skip (subset count)" "skip" "$(check13_should_flag 5 35 hooks)"
# "35 hooks" exact match — diff=0, 0 < 28 → flag (would be caught as "no drift" by outer num != actual check)
assert_eq "hooks 35 vs 35: flag (exact — outer check handles)" "flag" "$(check13_should_flag 35 35 hooks)"
# "3 hooks" subset — diff=32, threshold=28, 32 >= 28 → skip
assert_eq "hooks 3 vs 35: skip (subset)"       "skip" "$(check13_should_flag 3 35 hooks)"

echo ""
echo "Test group: Threshold — skills (30% pct, actual=32)"

# "24 skills" stale — diff=8, threshold=9, 8 < 9 → flag
assert_eq "skills 24 vs 32: flag (stale)"      "flag" "$(check13_should_flag 24 32 skills)"
# "25 skills" stale — diff=7, threshold=9, 7 < 9 → flag
assert_eq "skills 25 vs 32: flag (stale)"      "flag" "$(check13_should_flag 25 32 skills)"
# "10 skills" contextual — diff=22, threshold=9, 22 >= 9 → skip
assert_eq "skills 10 vs 32: skip (too far off)" "skip" "$(check13_should_flag 10 32 skills)"

echo ""
echo "Test group: Threshold — agents (30% pct, actual=11)"

# "10 agents" stale — diff=1, threshold=3, 1 < 3 → flag
assert_eq "agents 10 vs 11: flag (stale)"      "flag" "$(check13_should_flag 10 11 agents)"
# "5 agents" subset — diff=6, threshold=3, 6 >= 3 → skip
assert_eq "agents 5 vs 11: skip (too far off)" "skip" "$(check13_should_flag 5 11 agents)"

echo ""

# ── ACTUAL_SKILLS counting tests (t-2571) ───────────────────────────────────
# These do NOT reproduce the formula — they extract the real assignment from
# validate.sh and eval it against a fixture tree. A copy here would rot the
# moment validate.sh changed; sourcing the real line cannot.

VALIDATE_SH="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/validate.sh"

# Run validate.sh's own ACTUAL_SKILLS assignment against an arbitrary SYSTEM_DIR.
count_skills() {
    local sysdir="$1" line
    line=$(grep -m1 '^ACTUAL_SKILLS=' "$VALIDATE_SH") || return 1
    ( SYSTEM_DIR="$sysdir"; eval "$line"; echo "$ACTUAL_SKILLS" )
}

echo "Test group: ACTUAL_SKILLS counts only real skills (t-2571)"

# Fixture: 2 real skills + the two non-skill dirs that live under system/skills/.
FIXSYS="$TMPROOT/system"
mkdir -p "$FIXSYS"/skills/{alpha,beta,_shared,acquired}
: > "$FIXSYS/skills/alpha/SKILL.md"
: > "$FIXSYS/skills/beta/SKILL.md"
: > "$FIXSYS/skills/_shared/branch-prefix.md"   # shared procedure, not a skill
: > "$FIXSYS/skills/acquired/.gitkeep"          # container dir, not a skill

assert_eq "counts 2 skills, excluding _shared/ and acquired/" "2" "$(count_skills "$FIXSYS")"

# _shared/ is the specific regression: it has no SKILL.md and must not be counted.
FIXNOSHARED="$TMPROOT/system-no-shared"
mkdir -p "$FIXNOSHARED"/skills/{alpha,beta}
: > "$FIXNOSHARED/skills/alpha/SKILL.md"
: > "$FIXNOSHARED/skills/beta/SKILL.md"
assert_eq "adding _shared/ does not change the count" \
    "$(count_skills "$FIXNOSHARED")" "$(count_skills "$FIXSYS")"

# A dir with no SKILL.md is not a skill, whatever it is named.
mkdir -p "$FIXSYS/skills/not-a-skill"
: > "$FIXSYS/skills/not-a-skill/README.md"
assert_eq "dir without SKILL.md is not counted" "2" "$(count_skills "$FIXSYS")"

# Real tree: the count must equal the number of dirs that actually hold a SKILL.md.
REAL_SYS="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/system"
if [ -d "$REAL_SYS/skills" ]; then
    real_expected=$(find "$REAL_SYS/skills" -mindepth 2 -maxdepth 2 -name SKILL.md | wc -l | tr -d ' ')
    assert_eq "real tree: matches dirs containing SKILL.md ($real_expected)" \
        "$real_expected" "$(count_skills "$REAL_SYS")"
fi

echo ""
echo "=== Results: $PASS passed, $FAIL failed / $TOTAL total ==="
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
