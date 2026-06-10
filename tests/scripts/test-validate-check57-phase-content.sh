#!/usr/bin/env bash
# Unit test for Check 57: phase-split phase files must have section headers
# and resolvable relative cross-refs (t-1956).
#
# Tests:
#   T1 — clean skill (heading + resolving link) → no violations
#   T2 — phase file with no ##/### heading (silently emptied) → NO-HEADING
#   T3 — registered phase file missing on disk → MISSING
#   T4 — relative link target absent → DANGLING
#   T5 — template/external links (file.md, {slug}, https://) → ignored
#   T6 — no PHASES registry markers → check skips (no violations)

set -uo pipefail

PASS=0
FAIL=0
TOTAL=0

assert_empty() {
    local desc="$1" result="$2"
    TOTAL=$((TOTAL + 1))
    if [ -z "$result" ]; then
        echo "  PASS: $desc"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $desc — expected no violations, got: $result"
        FAIL=$((FAIL + 1))
    fi
}

assert_contains() {
    local desc="$1" result="$2" needle="$3"
    TOTAL=$((TOTAL + 1))
    if echo "$result" | grep -qF "$needle"; then
        echo "  PASS: $desc"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $desc — expected '$needle' in output, got: $result"
        FAIL=$((FAIL + 1))
    fi
}

# Check 57 logic — inline reproduction of the validate.sh implementation.
# Given a skill dir (containing SKILL.md and phases/), emit one line per
# violation:
#   MISSING: phases/x.md            registered file absent on disk
#   NO-HEADING: phases/x.md         no ^## / ^### section heading
#   DANGLING: phases/x.md -> link   ./ or ../ link target does not resolve
# No PHASES registry markers → emit nothing (layout test owns registry shape).
check57_violations() {
    local skill_dir="$1"
    : # stub — not implemented yet (red)
}

mk_skill() {
    # mk_skill <dir> — scaffold SKILL.md with a registry listing phases/one.md
    mkdir -p "$1/phases" "$1/../_shared"
    cat > "$1/SKILL.md" <<'MD'
# Fixture skill
<!-- PHASES -->
| Step | File | Load when |
|------|------|-----------|
| ONE | phases/one.md | always |
<!-- /PHASES -->
MD
}

# ── T1: clean skill → no violations ─────────────────────────────────────────
echo "=== T1: clean skill → no violations ==="
T1=$(mktemp -d); mk_skill "$T1/sk"
touch "$T1/_shared/helper.md"
cat > "$T1/sk/phases/one.md" <<'MD'
## Step 1: DO THE THING
Follow the [shared helper](../../_shared/helper.md).
MD
result=$(check57_violations "$T1/sk")
assert_empty "T1: clean fixture" "$result"
rm -rf "$T1"

# ── T2: emptied phase file → NO-HEADING ──────────────────────────────────────
echo "=== T2: phase file without headings → NO-HEADING ==="
T2=$(mktemp -d); mk_skill "$T2/sk"
cat > "$T2/sk/phases/one.md" <<'MD'
just prose, every heading stripped
MD
result=$(check57_violations "$T2/sk")
assert_contains "T2: heading-less file flagged" "$result" "NO-HEADING: phases/one.md"
rm -rf "$T2"

# ── T3: registered file missing → MISSING ────────────────────────────────────
echo "=== T3: registered phase file missing → MISSING ==="
T3=$(mktemp -d); mk_skill "$T3/sk"
result=$(check57_violations "$T3/sk")
assert_contains "T3: missing registered file flagged" "$result" "MISSING: phases/one.md"
rm -rf "$T3"

# ── T4: dangling relative link → DANGLING ────────────────────────────────────
echo "=== T4: dangling relative link → DANGLING ==="
T4=$(mktemp -d); mk_skill "$T4/sk"
cat > "$T4/sk/phases/one.md" <<'MD'
## Step 1: X
See [gone](../../_shared/does-not-exist.md).
MD
result=$(check57_violations "$T4/sk")
assert_contains "T4: dangling link flagged" "$result" "DANGLING: phases/one.md -> ../../_shared/does-not-exist.md"
rm -rf "$T4"

# ── T5: template/external links ignored ──────────────────────────────────────
echo "=== T5: template and external links → ignored ==="
T5=$(mktemp -d); mk_skill "$T5/sk"
cat > "$T5/sk/phases/one.md" <<'MD'
## Step 1: X
Examples: [a](file.md), [b](field-note_{slug}.md), [c](https://example.com/x.md),
and an anchored real one [d](#local-anchor).
MD
result=$(check57_violations "$T5/sk")
assert_empty "T5: non-relative-path links ignored" "$result"
rm -rf "$T5"

# ── T6: no PHASES registry → skip ─────────────────────────────────────────────
echo "=== T6: no PHASES registry markers → skip ==="
T6=$(mktemp -d); mkdir -p "$T6/sk/phases"
echo "# no registry here" > "$T6/sk/SKILL.md"
echo "no headings either" > "$T6/sk/phases/stray.md"
result=$(check57_violations "$T6/sk")
assert_empty "T6: registry-less skill skipped" "$result"
rm -rf "$T6"

# ── Summary ───────────────────────────────────────────────────────────────────
echo ""
echo "=== Check 57 test summary: $PASS/$TOTAL passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ]
