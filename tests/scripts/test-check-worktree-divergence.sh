#!/usr/bin/env bash
# Tests for system/scripts/check-worktree-divergence.sh — validate.sh Check 68 (t-2545).
#
# The check reconciles live git worktrees against their backlog task records.
# Spec: docs/architecture/features/worktree-task-divergence.md
#
# Severity contract under test (spec D2):
#   ORPHAN, FIELD-MISMATCH, LOOKUP-FAILED  -> contradiction -> exit 1
#   FIELD-NULL, IDLE, NO-TASK-ID, DETACHED -> omission       -> exit 0, reported
#
# Two of these tests exist because a context-isolated challenger found the gaps
# on 2026-07-29, and both were reproduced against the real binary before being
# believed:
#   - no_e_flag: `brana` exiting non-zero must not truncate the loop. Under
#     `set -e` the first failure aborts mid-iteration and the remaining
#     worktrees are silently never examined.
#   - schema_drift: a missing key and a null value both print `null` at exit 0
#     (`--field totally_bogus_field` -> null, exit 0), so a future field rename
#     would classify every worktree FIELD-NULL forever, silently.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
CHECK="$REPO_ROOT/system/scripts/check-worktree-divergence.sh"

# shellcheck source=tests/scripts/lib/worktree-fixture.sh
source "$SCRIPT_DIR/lib/worktree-fixture.sh"

PASS=0; FAIL=0; TOTAL=0
OUT=""; RC=0

run_check() {
    OUT=$(bash "$CHECK" "$FIXTURE_REPO" 2>&1)
    RC=$?
}

ok()   { TOTAL=$((TOTAL+1)); PASS=$((PASS+1)); echo "  PASS: $1"; }
bad()  { TOTAL=$((TOTAL+1)); FAIL=$((FAIL+1)); echo "  FAIL: $1"; [ -n "${2:-}" ] && echo "        $2"; }

assert_contains() {
    if grep -q -- "$1" <<<"$OUT"; then ok "$2"; else bad "$2" "expected output to contain '$1'; got: $(tr '\n' '|' <<<"$OUT" | cut -c1-220)"; fi
}
assert_not_contains() {
    if grep -q -- "$1" <<<"$OUT"; then bad "$2" "output unexpectedly contained '$1'"; else ok "$2"; fi
}
assert_rc() {
    if [ "$RC" -eq "$1" ]; then ok "$2"; else bad "$2" "expected exit $1, got $RC"; fi
}

echo "=== Check 68: worktree/task divergence (t-2545) ==="

if [ ! -f "$CHECK" ]; then
    echo "  FAIL: $CHECK does not exist"
    echo ""
    echo "Total: 1  Passed: 0  Failed: 1"
    exit 1
fi

# ── 1. Clean tree — every worktree agrees with its task ──────────────────────
echo "--- clean tree ---"
fixture_init
fixture_task t-100 in_progress harness/feat/t-100-alpha
fixture_worktree wt-alpha harness/feat/t-100-alpha 0
run_check
assert_rc 0 "clean tree exits 0"
assert_not_contains "ORPHAN"        "clean tree reports no orphan"
assert_not_contains "FIELD-MISMATCH" "clean tree reports no mismatch"
fixture_cleanup

# ── 2. ORPHAN — worktree alive, task completed ───────────────────────────────
echo "--- ORPHAN ---"
fixture_init
# Branch field left null on purpose: this worktree qualifies for ORPHAN *and*
# FIELD-NULL *and* IDLE at once, so the suppression assertion below is real
# rather than vacuous.
fixture_task t-200 completed null
fixture_worktree wt-orphan harness/feat/t-200-done 39
run_check
assert_rc 1 "orphan is a contradiction — exits 1"
assert_contains "ORPHAN"  "orphan is named as ORPHAN"
assert_contains "t-200"   "orphan names the task"
# Challenger sev-2: suppression must not discard the idle age.
assert_contains "39d"     "orphan line retains the idle age"
# One worktree, one finding — orphan suppresses its own field/idle categories.
assert_not_contains "FIELD-NULL" "orphan suppresses FIELD-NULL for the same worktree"
fixture_cleanup

# ── 3. FIELD-MISMATCH — task.branch names a different branch ─────────────────
echo "--- FIELD-MISMATCH ---"
fixture_init
fixture_task t-300 in_progress orbit/feat/t-300-somewhere-else
fixture_worktree wt-mismatch orbit/feat/t-300-actual 0
run_check
assert_rc 1 "field mismatch is a contradiction — exits 1"
assert_contains "FIELD-MISMATCH" "mismatch is named"
assert_contains "t-300-somewhere-else" "mismatch shows the branch the field claims"

# ── 4. FIELD-NULL — worktree exists, task.branch unset ───────────────────────
echo "--- FIELD-NULL ---"
fixture_task t-400 in_progress null
fixture_worktree wt-null harness/feat/t-400-unset 0
run_check
assert_contains "FIELD-NULL" "field-null is named"
fixture_cleanup

# FIELD-NULL alone must not turn the run red (omission, not contradiction).
fixture_init
fixture_task t-401 in_progress null
fixture_worktree wt-null-only harness/feat/t-401-unset 0
run_check
assert_rc 0 "field-null alone is an omission — exits 0"
fixture_cleanup

# ── 5. IDLE — in_progress, last commit older than the 14d threshold ──────────
echo "--- IDLE (14d threshold) ---"
fixture_init
fixture_task t-500 in_progress harness/feat/t-500-stale
fixture_worktree wt-stale harness/feat/t-500-stale 30
run_check
assert_rc 0 "idle alone is an omission — exits 0"
assert_contains "IDLE" "idle is named past the threshold"
fixture_cleanup

# Boundary: exactly 7 days must NOT trip a >7d threshold (strict inequality).
fixture_init
fixture_task t-501 in_progress harness/feat/t-501-fresh
fixture_worktree wt-fresh harness/feat/t-501-fresh 7
run_check
assert_not_contains "IDLE" "7d does not trip the 7d threshold (strict >)"
fixture_cleanup

# Boundary: 8 days must trip it.
fixture_init
fixture_task t-502 in_progress harness/feat/t-502-old
fixture_worktree wt-old harness/feat/t-502-old 8
run_check
assert_contains "IDLE" "8d trips the 7d threshold"
fixture_cleanup

# An idle worktree whose task is NOT in_progress is not "idle work" —
# it is some other category. IDLE is scoped to in_progress by the spec.
fixture_init
fixture_task t-503 pending harness/feat/t-503-pending
fixture_worktree wt-pending harness/feat/t-503-pending 40
run_check
assert_not_contains "IDLE" "IDLE does not fire on a non-in_progress task"
fixture_cleanup

# ── 6. NO-TASK-ID — branch carries no t-NNN ──────────────────────────────────
echo "--- NO-TASK-ID ---"
fixture_init
fixture_worktree wt-notask experiment/scratch-pad 0
run_check
assert_rc 0 "no-task-id is an omission — exits 0"
assert_contains "NO-TASK-ID" "branch without t-NNN is reported, not skipped"
fixture_cleanup

# ── 7. LOOKUP-FAILED — branch names a task absent from the backlog ───────────
# t-2487 class: a lookup failure is NOT a negative. This must never read clean.
echo "--- LOOKUP-FAILED ---"
fixture_init
fixture_worktree wt-ghost harness/feat/t-700-ghost 0   # no fixture_task -> brana exits 1
run_check
assert_contains "LOOKUP-FAILED" "absent task is reported distinctly"
assert_rc 1 "lookup failure must not fail open"
fixture_cleanup

# ── 8. No -e: one failing lookup must not truncate the loop ──────────────────
# Challenger sev-4. The ghost worktree sorts before the orphan; under `set -e`
# the script would die on the ghost's exit-1 and never reach the orphan.
echo "--- loop survives a failing lookup (no set -e) ---"
fixture_init
fixture_worktree aa-ghost harness/feat/t-800-ghost 0    # lookup fails
fixture_task t-801 completed harness/feat/t-801-orphan
fixture_worktree zz-orphan harness/feat/t-801-orphan 20 # must still be reached
run_check
assert_contains "LOOKUP-FAILED" "failing lookup reported"
assert_contains "ORPHAN" "worktrees after a failing lookup are still examined"
fixture_cleanup

# ── 9. Schema self-test — a renamed field must be loud, not silent ───────────
# Challenger sev-4, reproduced against the real binary: a missing key and a
# null value both print `null` at exit 0.
echo "--- schema drift self-test ---"
fixture_init
fixture_task t-900 in_progress harness/feat/t-900-x
fixture_worktree wt-schema harness/feat/t-900-x 0
FIXTURE_SCHEMA_OMIT=branch run_check
assert_rc 1 "a missing schema field fails loudly"
assert_contains "schema" "schema drift is named as such, not reported as FIELD-NULL"
assert_not_contains "FIELD-NULL" "schema drift is not misreported as FIELD-NULL"
fixture_cleanup

# ── 10. Main checkout is excluded ────────────────────────────────────────────
echo "--- main checkout excluded ---"
fixture_init
fixture_worktree wt-main-sibling harness/feat/t-950-x 0
fixture_task t-950 in_progress harness/feat/t-950-x
run_check
# The fixture's main checkout is on `dev`, which carries no t-NNN. If it were
# examined it would surface as NO-TASK-ID.
assert_not_contains "NO-TASK-ID" "main checkout is not reported as NO-TASK-ID"
fixture_cleanup

# ── 11. Detached HEAD worktree ───────────────────────────────────────────────
echo "--- detached HEAD ---"
fixture_init
fixture_worktree_detached wt-detached
run_check
assert_rc 0 "detached HEAD alone does not fail the run"
assert_contains "DETACHED" "detached worktree is reported, not silently skipped"
fixture_cleanup

# ── 12. Read-only: the check never writes to the backlog ─────────────────────
# The stub records nothing but reads; assert the check issues no `backlog set`.
echo "--- read-only guarantee ---"
TOTAL=$((TOTAL+1))
if grep -qE 'backlog[[:space:]]+set|backlog_set' "$CHECK"; then
    FAIL=$((FAIL+1)); echo "  FAIL: check writes to the backlog — it must be read-only (spec Boundaries)"
else
    PASS=$((PASS+1)); echo "  PASS: check contains no backlog write"
fi

# ── 13. Static: no `set -e` ──────────────────────────────────────────────────
TOTAL=$((TOTAL+1))
if grep -qE '^set -[a-z]*e[a-z]*[[:space:]]' "$CHECK"; then
    FAIL=$((FAIL+1)); echo "  FAIL: script uses set -e — one failing lookup will truncate the loop"
else
    PASS=$((PASS+1)); echo "  PASS: script does not use set -e"
fi

echo ""
echo "Total: $TOTAL  Passed: $PASS  Failed: $FAIL"
[ "$FAIL" -eq 0 ] || exit 1
