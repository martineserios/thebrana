#!/usr/bin/env bash
# Tests for /brana:close Step 8b PROPAGATE — L1 deterministic checks + gate
# matrix (t-2003, ADR-056).
#
# Single source of truth (t-1978 pattern): the test extracts and executes the
# REAL L1 bash block from system/skills/close/phases/propagate.md, delimited
# by <!-- L1-BLOCK --> ... <!-- /L1-BLOCK --> markers. No replicated logic.
#
# L1 contract (pinned here, implemented in the phase file):
#   env in : CLOSE_MODE (NANO|LIGHT|LIGHT-INLINE|INSTANT|FULL)
#            ORIENTATION (continue|finish|patterns|abort|"")
#            CHANGED_FILES (newline-separated, relative to repo root)
#            ACTIVE_TASK_ID (may be empty), ACTIVE_TASK_STATUS (may be empty)
#   stdout : PROPAGATE: skip (...)            when gated off
#            PROP-GAP|tasksjson|...           dirty tasks.json (origin gap #7)
#            PROP-GAP|checkbox|<file>|...     unchecked '- [ ]' Documentation
#                                             Plan items (origin gap #3)
#            PROP-GAP|status|<file>|...       Status field vs task state
#                                             mismatch (origin gap #1)
#            PROP-CANDIDATE|promise|<file>|.. 'al cerrar'/'on close' promise
#                                             candidates for L2 judgment
#            PROPAGATE-L1: N gap(s), M candidate(s)
#   exit   : always 0 when run (close never blocks on PROPAGATE)
#
# Run: bash tests/procedures/test-close-propagate.sh

set -uo pipefail

PASS=0
FAIL=0
TOTAL=0

assert_contains() {
    local desc="$1" needle="$2" haystack="$3"
    TOTAL=$((TOTAL + 1))
    if printf '%s' "$haystack" | grep -qF -- "$needle"; then
        echo "  PASS: $desc"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $desc (missing: $needle)"
        FAIL=$((FAIL + 1))
    fi
}

assert_not_contains() {
    local desc="$1" needle="$2" haystack="$3"
    TOTAL=$((TOTAL + 1))
    if printf '%s' "$haystack" | grep -qF -- "$needle"; then
        echo "  FAIL: $desc (unexpected: $needle)"
        FAIL=$((FAIL + 1))
    else
        echo "  PASS: $desc"
        PASS=$((PASS + 1))
    fi
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PHASE_FILE="$SCRIPT_DIR/../../system/skills/close/phases/propagate.md"

echo "=== test-close-propagate.sh ==="
echo ""

if [ ! -f "$PHASE_FILE" ]; then
    echo "FAIL: $PHASE_FILE does not exist (Step 8b phase file not written yet)"
    exit 1
fi

# Extract the L1 block between markers into a runnable script.
L1_SCRIPT="$(mktemp "${TMPDIR:-/tmp}/l1-block-XXXXXX.sh")"
trap 'rm -rf "$L1_SCRIPT" "${FIXTURE:-}"' EXIT
sed -n '/<!-- L1-BLOCK -->/,/<!-- \/L1-BLOCK -->/p' "$PHASE_FILE" \
    | sed '1d;$d' \
    | sed '/^```/d' > "$L1_SCRIPT"
if [ ! -s "$L1_SCRIPT" ]; then
    echo "FAIL: L1-BLOCK markers missing or empty in $PHASE_FILE"
    exit 1
fi

# ── fixture repo: re-simulates the deterministic origin gaps of t-1306 ──────
FIXTURE="$(mktemp -d "${TMPDIR:-/tmp}/propagate-fixture-XXXXXX")"
(
    cd "$FIXTURE"
    git init -q -b main
    git config user.email t@t && git config user.name t
    mkdir -p .claude docs/specs
    # Origin gap #1: spec Status stale vs completed task
    cat > docs/specs/feature-x.md <<'EOF'
# Feature X
**Status:** live run pending

## Documentation Plan
- [ ] **User guide** — docs/guide/feature-x.md
- [x] **Tech doc** — this file
- [ ] **Existing docs to update** — test-strategy.md pointer

## Notes
El ADR se creará al cerrar F1.
EOF
    # Clean spec — must NOT be flagged (only touched files are audited)
    cat > docs/specs/untouched.md <<'EOF'
# Untouched
**Status:** pending
## Documentation Plan
- [ ] something never done
EOF
    echo '{"tasks": []}' > .claude/tasks.json
    git add -A && git commit -qm init
    # Origin gap #7: tasks.json modified but uncommitted
    echo '{"tasks": [{"id": "t-001"}]}' > .claude/tasks.json
)

# Args: CLOSE_MODE ORIENTATION CHANGED_FILES [TASK_ID] [TASK_STATUS]
run_l1() {
    (
        cd "$FIXTURE"
        CLOSE_MODE="$1" ORIENTATION="$2" CHANGED_FILES="$3" \
        ACTIVE_TASK_ID="${4:-}" ACTIVE_TASK_STATUS="${5:-}" \
            bash "$L1_SCRIPT" 2>&1
    )
}

# ── Gate matrix ──────────────────────────────────────────────────────────────

echo "Gate matrix (ADR-056 §1)"
OUT=$(run_l1 NANO "" "docs/specs/feature-x.md")
assert_contains "NANO → skip" "PROPAGATE: skip" "$OUT"
assert_not_contains "NANO emits no gaps" "PROP-GAP" "$OUT"

OUT=$(run_l1 NANO abort "src/x.rs")
assert_contains "--abort → skip" "PROPAGATE: skip" "$OUT"

OUT=$(run_l1 INSTANT finish "docs/specs/feature-x.md" t-001 completed)
assert_not_contains "--finish INSTANT runs L1 (no skip)" "PROPAGATE: skip" "$OUT"

OUT=$(run_l1 INSTANT continue "docs/specs/feature-x.md" t-001 in_progress)
assert_not_contains "--continue INSTANT runs L1 (no skip)" "PROPAGATE: skip" "$OUT"

# ── Origin gap #7: uncommitted tasks.json ────────────────────────────────────

echo ""
echo "Origin gap #7 — dirty tasks.json"
OUT=$(run_l1 INSTANT finish "docs/specs/feature-x.md" t-001 completed)
assert_contains "detects uncommitted tasks.json" "PROP-GAP|tasksjson" "$OUT"

# ── Origin gap #3: unchecked Documentation Plan checkboxes ──────────────────

echo ""
echo "Origin gap #3 — unchecked '- [ ]' in touched spec"
assert_contains "detects unchecked checkboxes in touched spec" \
    "PROP-GAP|checkbox|docs/specs/feature-x.md" "$OUT"
assert_not_contains "untouched spec is NOT audited (bounded input)" \
    "untouched.md" "$OUT"

# ── Origin gap #1: Status field vs task state ────────────────────────────────

echo ""
echo "Origin gap #1 — stale Status field vs completed task"
assert_contains "flags 'live run pending' vs completed task" \
    "PROP-GAP|status|docs/specs/feature-x.md" "$OUT"

OUT_INPROG=$(run_l1 INSTANT continue "docs/specs/feature-x.md" t-001 in_progress)
assert_not_contains "non-final Status + in_progress task → no mismatch" \
    "PROP-GAP|status" "$OUT_INPROG"

OUT_NOTASK=$(run_l1 INSTANT finish "docs/specs/feature-x.md" "" "")
assert_not_contains "task-less session skips status check (HIGH-1 rule)" \
    "PROP-GAP|status" "$OUT_NOTASK"
assert_contains "task-less session still runs other checks" \
    "PROP-GAP|tasksjson" "$OUT_NOTASK"

# ── Promise heuristic → L2 candidates ────────────────────────────────────────

echo ""
echo "Promise heuristic — 'al cerrar' surfaces as L2 candidate"
assert_contains "detects 'al cerrar' promise candidate" \
    "PROP-CANDIDATE|promise|docs/specs/feature-x.md" "$OUT"

# ── Summary line + non-blocking exit ─────────────────────────────────────────

echo ""
echo "Output contract"
assert_contains "emits summary line" "PROPAGATE-L1:" "$OUT"

(
    cd "$FIXTURE"
    CLOSE_MODE=INSTANT ORIENTATION=finish CHANGED_FILES="docs/specs/feature-x.md" \
    ACTIVE_TASK_ID=t-001 ACTIVE_TASK_STATUS=completed bash "$L1_SCRIPT" >/dev/null 2>&1
)
RC=$?
TOTAL=$((TOTAL + 1))
if [ "$RC" -eq 0 ]; then
    echo "  PASS: L1 block exits 0 (close never blocks)"
    PASS=$((PASS + 1))
else
    echo "  FAIL: L1 block exit $RC (must always exit 0)"
    FAIL=$((FAIL + 1))
fi

echo ""
echo "=== Results: $PASS/$TOTAL passed, $FAIL failed ==="

[ "$FAIL" -eq 0 ] || exit 1
