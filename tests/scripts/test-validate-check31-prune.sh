#!/usr/bin/env bash
# Tests for validate.sh Check 31a auto-prune logic (t-1453).
#
# Tests the prune_patterns() function which mirrors Check 31a:
# when patterns.md >= cap (50), remove oldest quarantine entries
# (sorted by Added: date) until count < cap.
#
# Mirrors the exact awk used in validate.sh so any drift is a test failure.
#
# Return codes from prune_patterns():
#   pruned:N:count      — pruned N entries, now at count
#   no-quarantine:count — at cap but no quarantine entries remain
#   warn:count          — in warn zone (40–49), no modification
#   pass:count          — below warn threshold, no modification
#   skip                — file does not exist

set -uo pipefail

PASS=0; FAIL=0; TOTAL=0
TMPROOT=$(mktemp -d)
trap 'rm -rf "$TMPROOT"' EXIT

assert_eq() {
    local desc="$1" expected="$2" actual="$3"
    TOTAL=$((TOTAL+1))
    if [ "$actual" = "$expected" ]; then
        PASS=$((PASS+1)); echo "  PASS: $desc"
    else
        FAIL=$((FAIL+1)); echo "  FAIL: $desc — expected '$expected', got '$actual'"
    fi
}

assert_contains() {
    local desc="$1" needle="$2" haystack="$3"
    TOTAL=$((TOTAL+1))
    if echo "$haystack" | grep -qF "$needle"; then
        PASS=$((PASS+1)); echo "  PASS: $desc"
    else
        FAIL=$((FAIL+1)); echo "  FAIL: $desc — '$needle' not found"
    fi
}

assert_not_contains() {
    local desc="$1" needle="$2" haystack="$3"
    TOTAL=$((TOTAL+1))
    if echo "$haystack" | grep -qF "$needle"; then
        FAIL=$((FAIL+1)); echo "  FAIL: $desc — '$needle' unexpectedly found"
    else
        PASS=$((PASS+1)); echo "  PASS: $desc"
    fi
}

# ── prune_patterns: mirrors Check 31a auto-prune logic from validate.sh ──────
# Return: pruned:N:count | no-quarantine:count | warn:count | pass:count | skip
prune_patterns() {
    local file="$1"
    local cap="${2:-50}"
    local warn_at="${3:-40}"

    if [ ! -f "$file" ]; then echo "skip"; return; fi
    local count
    count=$(grep -c '^## ' "$file" 2>/dev/null) || count=0

    if [ "$count" -lt "$warn_at" ]; then
        echo "pass:$count"
        return
    fi
    if [ "$count" -lt "$cap" ]; then
        echo "warn:$count"
        return
    fi

    # count >= cap: auto-prune oldest quarantine entries
    local pruned=0
    local current="$count"
    while [ "$current" -ge "$cap" ]; do
        local oldest
        oldest=$(awk '
/^## /                  { if (slug!="" && conf=="quarantine") printf "%s|%s\n", date, slug
                          slug=substr($0,4); date=""; conf="" }
/^\*\*Confidence:\*\* / { conf=$NF }
/^\*\*Added:\*\* /       { date=$NF }
END                     { if (slug!="" && conf=="quarantine") printf "%s|%s\n", date, slug }
' "$file" | sort | head -1)

        if [ -z "$oldest" ]; then
            echo "no-quarantine:$current"
            return
        fi

        local slug="${oldest#*|}"
        awk -v target="## $slug" '
BEGIN { skip=0 }
/^## / { skip=($0==target) }
!skip  { print }
' "$file" > "${file}.tmp" && mv "${file}.tmp" "$file"

        pruned=$(( pruned + 1 ))
        current=$(grep -c '^## ' "$file" 2>/dev/null) || current=0
    done

    echo "pruned:$pruned:$current"
}

# ── Fixture helpers ───────────────────────────────────────────────────────────

# Append one entry with full metadata (Confidence + Added fields)
append_entry() {
    local file="$1" slug="$2" confidence="${3:-confirmed}" date="${4:-2026-01-01}"
    cat >> "$file" <<EOF

## $slug

**Problem:** some problem for $slug
**Solution:** some solution
**Confidence:** $confidence
**Added:** $date
EOF
}

# Create a patterns.md with N confirmed entries (no quarantine)
make_patterns_file() {
    local file="$1" n="$2"
    printf '# Pattern Store\n\n<!-- cap: 50 | warn-at: 40 | auto-pruned: oldest quarantine first -->\n' > "$file"
    local i=1
    while [ "$i" -le "$n" ]; do
        append_entry "$file" "entry-$i" confirmed "2026-01-$(printf '%02d' $(( (i % 28) + 1 )))"
        i=$(( i + 1 ))
    done
}

echo "=== Validate Check 31a — auto-prune quarantine entries (t-1453) ==="
echo ""

# ── T1: 50 entries, 3 quarantine → prune 1 to reach 49 ──────────────────────
echo "T1: 50 entries (3 quarantine) → prune 1 → pruned:1:49"
F1="$TMPROOT/patterns-t1.md"
make_patterns_file "$F1" 47
append_entry "$F1" "q-old-jan"  quarantine "2026-01-05"
append_entry "$F1" "q-mid-feb"  quarantine "2026-02-10"
append_entry "$F1" "q-new-mar"  quarantine "2026-03-15"
assert_eq "T1: result code" "pruned:1:49" "$(prune_patterns "$F1")"
assert_eq "T1: 49 entries remain in file" 49 "$(grep -c '^## ' "$F1")"

# ── T2: 50 entries, no quarantine → no-quarantine:50 ────────────────────────
echo ""
echo "T2: 50 entries (0 quarantine) → cannot prune → no-quarantine:50"
F2="$TMPROOT/patterns-t2.md"
make_patterns_file "$F2" 50
assert_eq "T2: result code" "no-quarantine:50" "$(prune_patterns "$F2")"
assert_eq "T2: file unchanged (50 entries)" 50 "$(grep -c '^## ' "$F2")"

# ── T3: 52 entries, 5 quarantine → prune 3 to reach 49 ──────────────────────
echo ""
echo "T3: 52 entries (5 quarantine) → prune 3 → pruned:3:49"
F3="$TMPROOT/patterns-t3.md"
make_patterns_file "$F3" 47
append_entry "$F3" "q-2025-nov" quarantine "2025-11-01"
append_entry "$F3" "q-2026-jan" quarantine "2026-01-10"
append_entry "$F3" "q-2026-feb" quarantine "2026-02-20"
append_entry "$F3" "q-2026-mar" quarantine "2026-03-30"
append_entry "$F3" "q-2026-apr" quarantine "2026-04-05"
assert_eq "T3: result code" "pruned:3:49" "$(prune_patterns "$F3")"
assert_eq "T3: 49 entries remain in file" 49 "$(grep -c '^## ' "$F3")"

# ── T4: 45 entries (warn zone) → warn, no file modification ─────────────────
echo ""
echo "T4: 45 entries (warn zone 40–49) → warn:45, no prune"
F4="$TMPROOT/patterns-t4.md"
make_patterns_file "$F4" 43
append_entry "$F4" "q-warn-1" quarantine "2026-01-01"
append_entry "$F4" "q-warn-2" quarantine "2026-01-02"
assert_eq "T4: result code" "warn:45" "$(prune_patterns "$F4")"
assert_eq "T4: file unchanged (45 entries)" 45 "$(grep -c '^## ' "$F4")"

# ── T5: 38 entries → pass ────────────────────────────────────────────────────
echo ""
echo "T5: 38 entries → pass:38"
F5="$TMPROOT/patterns-t5.md"
make_patterns_file "$F5" 38
assert_eq "T5: result code" "pass:38" "$(prune_patterns "$F5")"

# ── T6: file absent → skip ───────────────────────────────────────────────────
echo ""
echo "T6: file absent → skip"
assert_eq "T6: result code" "skip" "$(prune_patterns "$TMPROOT/nonexistent.md")"

# ── T7: ordering — oldest quarantine entry removed first ─────────────────────
echo ""
echo "T7: ordering — oldest quarantine entry is removed, newer one kept"
F7="$TMPROOT/patterns-t7.md"
make_patterns_file "$F7" 48
append_entry "$F7" "newer-quarantine" quarantine "2026-05-01"
append_entry "$F7" "older-quarantine" quarantine "2026-01-01"
# Total: 50 entries (2 quarantine); older date → older-quarantine removed first
prune_patterns "$F7" > /dev/null
C7=$(cat "$F7")
assert_not_contains "T7: older entry removed"     "older-quarantine" "$C7"
assert_contains     "T7: newer entry kept"         "newer-quarantine" "$C7"
assert_eq "T7: 49 entries remain" 49 "$(grep -c '^## ' "$F7")"

# ── T8: only quarantine entries removed, confirmed intact ────────────────────
echo ""
echo "T8: confirmed entries not touched — only quarantine removed"
F8="$TMPROOT/patterns-t8.md"
make_patterns_file "$F8" 49
append_entry "$F8" "only-quarantine" quarantine "2026-01-01"
# Total: 50 entries (49 confirmed + 1 quarantine)
prune_patterns "$F8" > /dev/null
C8=$(cat "$F8")
assert_not_contains "T8: quarantine entry removed"       "only-quarantine" "$C8"
assert_eq           "T8: 49 confirmed entries intact" 49 "$(grep -c '^## ' "$F8")"

# ── Summary ──────────────────────────────────────────────────────────────────
echo ""
echo "Results: $PASS passed, $FAIL failed (of $TOTAL total)"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
