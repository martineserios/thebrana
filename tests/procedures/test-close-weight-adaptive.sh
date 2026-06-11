#!/usr/bin/env bash
# Tests for /brana:close weight-adaptive NANO/LIGHT/INSTANT/FULL classification
# (t-1655 original; updated t-1973 for Track 1 / ADR-052 §5).
#
# Since Track 1, auto-classified heavy sessions are INSTANT (snapshot + queue +
# handoff, extraction deferred to the nightly cron); FULL fires only on an
# explicit --full. NANO and LIGHT behavior is unchanged — these assertions are
# the regression net the t-1970 plan challenger required.
#
# Run: bash tests/procedures/test-close-weight-adaptive.sh

set -uo pipefail

PASS=0
FAIL=0
TOTAL=0

assert_mode() {
    local desc="$1" expected="$2" actual="$3"
    TOTAL=$((TOTAL + 1))
    if [ "$expected" = "$actual" ]; then
        echo "  PASS: $desc"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $desc (expected $expected, got $actual)"
        FAIL=$((FAIL + 1))
    fi
}

# Replicate the classification bash from phases/gate-and-evidence.md Step 1
# verbatim. Args: COMMIT_COUNT, CHANGED_FILES (newline-separated), ARGUMENTS.
classify() {
    local COMMIT_COUNT="${1:-1}"
    local CHANGED_FILES="$2"
    local ARGUMENTS="${3:-}"
    local CLOSE_MODE BEHAVIORAL_JSON FILE_COUNT

    FILE_COUNT=$(echo "$CHANGED_FILES" | grep -c . || echo 0)
    BEHAVIORAL_JSON=$(echo "$CHANGED_FILES" | grep -E '^(system|\.claude)/.*\.json$' \
                     | grep -v '^\.claude/tasks\.json$' || true)

    if [[ "$ARGUMENTS" == *"--light"* ]]; then CLOSE_MODE="LIGHT"
    elif [[ "$ARGUMENTS" == *"--full"* ]]; then CLOSE_MODE="FULL"
    elif [[ "$ARGUMENTS" == *"--nano"* ]]; then CLOSE_MODE="NANO"
    elif [[ "${COMMIT_COUNT:-0}" -ge 2 ]]; then CLOSE_MODE="INSTANT"
    elif echo "$CHANGED_FILES" | grep -qE '\.(rs|ts|tsx|js|jsx|py|sh|toml|yaml|yml)$'; then CLOSE_MODE="INSTANT"
    elif [[ -n "$BEHAVIORAL_JSON" ]]; then CLOSE_MODE="INSTANT"
    elif [[ "${COMMIT_COUNT:-0}" -eq 1 ]] && [[ "${FILE_COUNT:-0}" -le 5 ]]; then CLOSE_MODE="NANO"
    else CLOSE_MODE="LIGHT"
    fi

    echo "$CLOSE_MODE"
}

echo "=== test-close-weight-adaptive.sh ==="
echo ""

# ── Behavioral changes → INSTANT (was FULL pre-Track-1) ──────────────────────

echo "Behavioral changes → INSTANT"
MODE=$(classify 1 "system/hooks/pre-tool-use.sh")
assert_mode ".sh file → INSTANT" "INSTANT" "$MODE"

MODE=$(classify 1 ".claude/settings.json")
assert_mode ".claude/settings.json → INSTANT" "INSTANT" "$MODE"

MODE=$(classify 1 "system/plugin.json")
assert_mode "system/*.json → INSTANT" "INSTANT" "$MODE"

MODE=$(classify 1 ".claude/tasks.json
.claude/settings.json")
assert_mode "tasks.json + settings.json → INSTANT" "INSTANT" "$MODE"

MODE=$(classify 2 "README.md")
assert_mode "2 commits + only .md → INSTANT" "INSTANT" "$MODE"

for ext in rs ts tsx js jsx py toml yaml yml; do
    MODE=$(classify 1 "src/file.$ext")
    assert_mode ".$ext → INSTANT" "INSTANT" "$MODE"
done

# ── NANO regression (unchanged by Track 1) ───────────────────────────────────

echo ""
echo "NANO regression — unchanged"
MODE=$(classify 1 ".claude/tasks.json")
assert_mode "tasks.json only, 1 commit → NANO" "NANO" "$MODE"

MODE=$(classify 1 ".claude/tasks.json
docs/some-note.md")
assert_mode "tasks.json + .md, 1 commit → NANO" "NANO" "$MODE"

MODE=$(classify 1 "docs/note.md")
assert_mode "single .md, 1 commit → NANO" "NANO" "$MODE"

# ── LIGHT regression (unchanged by Track 1) ──────────────────────────────────

echo ""
echo "LIGHT regression — unchanged"
MODE=$(classify 1 "docs/a.md
docs/b.md
docs/c.md
docs/d.md
docs/e.md
docs/f.md")
assert_mode "1 commit, 6 non-code files → LIGHT" "LIGHT" "$MODE"

MODE=$(classify 0 "docs/a.md
docs/b.md
docs/c.md
docs/d.md
docs/e.md
docs/f.md")
assert_mode "0 commits, uncommitted .md spread → LIGHT" "LIGHT" "$MODE"

# ── Escape hatches ────────────────────────────────────────────────────────────

echo ""
echo "Escape hatches"
MODE=$(classify 1 "system/hooks/pre-tool-use.sh" "--light")
assert_mode "--light overrides .sh (→ LIGHT)" "LIGHT" "$MODE"

MODE=$(classify 1 ".claude/tasks.json" "--full")
assert_mode "--full is the ONLY route to FULL" "FULL" "$MODE"

MODE=$(classify 3 "src/main.rs" "--full")
assert_mode "--full overrides INSTANT auto-class" "FULL" "$MODE"

MODE=$(classify 3 "src/main.rs" "--nano")
assert_mode "--nano overrides INSTANT auto-class" "NANO" "$MODE"

# ── No auto path reaches FULL (Track 1 invariant) ────────────────────────────

echo ""
echo "Track 1 invariant: FULL requires --full"
for args in "" "--light" "--nano"; do
    for files in "src/x.rs" ".claude/settings.json" "README.md"; do
        MODE=$(classify 5 "$files" "$args")
        TOTAL=$((TOTAL + 1))
        if [ "$MODE" != "FULL" ]; then
            echo "  PASS: commit=5 files=$files args='$args' → $MODE (not FULL)"
            PASS=$((PASS + 1))
        else
            echo "  FAIL: commit=5 files=$files args='$args' auto-classified FULL"
            FAIL=$((FAIL + 1))
        fi
    done
done

echo ""
echo "=== Results: $PASS/$TOTAL passed, $FAIL failed ==="

[ "$FAIL" -eq 0 ] || exit 1
