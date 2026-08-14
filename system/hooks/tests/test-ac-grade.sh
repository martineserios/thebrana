#!/usr/bin/env bash
# Tests for system/scripts/ac-grade.sh — standalone, read-only AC-grammar
# heuristic execution (t-2869, ADR-081 D1).
#
# Interface under test: ac-grade.sh <task-id> [--json] [--cwd <path>]
#   stdout JSON: {"task_id":..., "graded":[{"criterion":..., "verdict":...}],
#                 "counts":{"pass":N,"fail":N,"unknown":N}}
# Never writes any task field. Resolves WORK_DIR from the task's branch via
# `git worktree list` unless --cwd is given explicitly.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GRADER="$SCRIPT_DIR/../../scripts/ac-grade.sh"

PASS=0
FAIL=0
TOTAL=0

if [ ! -f "$GRADER" ]; then
    echo "SKIP: $GRADER not found (implement in t-2869)"
    exit 0
fi

TMPDIR_TEST=$(mktemp -d)
trap 'rm -rf "$TMPDIR_TEST"' EXIT

# ── Stub brana CLI — deterministic backlog get responses, no real tasks.json ──
STUBDIR="$TMPDIR_TEST/bin"
mkdir -p "$STUBDIR"
cat > "$STUBDIR/brana" <<'STUB'
#!/usr/bin/env bash
# Stub: brana backlog get <id> --field <field>
if [ "$1" = "backlog" ] && [ "$2" = "get" ]; then
    id="$3"
    field=""
    for a in "$@"; do
        [ "$prev" = "--field" ] && field="$a"
        prev="$a"
    done
    case "$id:$field" in
        t-fix:acceptance_criteria) echo '["file fixture.md exists","\"true\" passes"]' ;;
        t-fix:branch) echo '"stub/fix-branch"' ;;
        t-nobranch:acceptance_criteria) echo '["file fixture.md exists"]' ;;
        t-nobranch:branch) echo 'null' ;;
        t-orphan:acceptance_criteria) echo '["file fixture.md exists"]' ;;
        t-orphan:branch) echo '"stub/no-such-worktree-branch"' ;;
        t-empty:acceptance_criteria) echo 'null' ;;
        t-inj:acceptance_criteria) echo '["demoable: pytest && touch INJECTED"]' ;;
        t-inj:branch) echo '"stub/fix-branch"' ;;
        *) echo 'null' ;;
    esac
    exit 0
fi
echo "stub: unhandled args: $*" >&2
exit 1
STUB
chmod +x "$STUBDIR/brana"

assert() {
    local desc="$1" cond="$2"
    TOTAL=$((TOTAL + 1))
    if eval "$cond"; then
        echo "  PASS: $desc"; PASS=$((PASS + 1))
    else
        echo "  FAIL: $desc"; FAIL=$((FAIL + 1))
    fi
}

# ── Fixture repo + worktree (real git, for worktree-resolution tests) ────────
MAIN_REPO="$TMPDIR_TEST/main-repo"
mkdir -p "$MAIN_REPO"
(
    cd "$MAIN_REPO" || exit 1
    git init -q
    git config user.email "t@t.com"; git config user.name "T"
    echo "fixture" > fixture.md
    git add -A; git commit -q -m "baseline"
    git branch "stub/fix-branch"
)
FIX_WORKTREE="$TMPDIR_TEST/fix-worktree"
git -C "$MAIN_REPO" worktree add -q "$FIX_WORKTREE" "stub/fix-branch" 2>/dev/null
echo "fixture" > "$FIX_WORKTREE/fixture.md"

# resolve-brana.sh checks CLAUDE_PLUGIN_DATA first, ahead of PATH — override it
# (not PATH) so the stub actually wins over any real installed brana, matching
# the established pattern in test-goal-completion.sh's G1-G9 fixtures.
export PATH="$STUBDIR:$PATH"
export CLAUDE_PLUGIN_DATA="$STUBDIR"

# ── Worktree resolution: branch → real worktree path ─────────────────────────
echo "Test: worktree resolution finds the right path for a recorded branch"
OUT=$(cd "$MAIN_REPO" && bash "$GRADER" t-fix --json 2>&1)
assert "resolved and graded (no resolution error)" '! grep -qi "no worktree\|no branch\|error" <<<"$OUT" || echo "$OUT" | jq -e ".graded" >/dev/null 2>&1'
assert "counts.pass includes the file-exists heuristic (fixture.md present in worktree)" 'echo "$OUT" | jq -e ".counts.pass >= 1" >/dev/null 2>&1'

echo "Test: task with no recorded branch → loud error, never defaults to caller cwd"
OUT_NB=$(cd "$MAIN_REPO" && bash "$GRADER" t-nobranch --json 2>&1); RC_NB=$?
assert "no-branch case exits non-zero" '[ "$RC_NB" -ne 0 ]'
assert "no-branch case names the task id in the error" 'grep -qF "t-nobranch" <<<"$OUT_NB"'

echo "Test: task with a branch but no matching worktree → loud error, never defaults"
OUT_ORPHAN=$(cd "$MAIN_REPO" && bash "$GRADER" t-orphan --json 2>&1); RC_ORPHAN=$?
assert "orphan-branch case exits non-zero" '[ "$RC_ORPHAN" -ne 0 ]'
assert "orphan-branch case does not silently grade against caller cwd" '! echo "$OUT_ORPHAN" | jq -e ".graded" >/dev/null 2>&1'

echo "Test: --cwd override bypasses worktree lookup entirely"
OUT_CWD=$(bash "$GRADER" t-fix --json --cwd "$FIX_WORKTREE" 2>&1)
assert "--cwd override succeeds without any worktree lookup" 'echo "$OUT_CWD" | jq -e ".graded" >/dev/null 2>&1'

# ── Heuristic execution + JSON shape ──────────────────────────────────────────
echo "Test: JSON shape — task_id, graded[], counts"
OUT_SHAPE=$(bash "$GRADER" t-fix --json --cwd "$FIX_WORKTREE" 2>&1)
assert "task_id echoed" 'echo "$OUT_SHAPE" | jq -e ".task_id == \"t-fix\"" >/dev/null 2>&1'
assert "graded is an array of 2 (matches 2 criteria)" 'echo "$OUT_SHAPE" | jq -e ".graded | length == 2" >/dev/null 2>&1'
assert "counts.pass + counts.fail + counts.unknown == graded length" \
  'echo "$OUT_SHAPE" | jq -e "(.counts.pass + .counts.fail + .counts.unknown) == (.graded | length)" >/dev/null 2>&1'

echo "Test: no acceptance_criteria (null) → empty graded, all counts zero, no error"
OUT_EMPTY=$(bash "$GRADER" t-empty --json --cwd "$FIX_WORKTREE" 2>&1); RC_EMPTY=$?
assert "empty-criteria task exits 0" '[ "$RC_EMPTY" -eq 0 ]'
assert "empty-criteria task has zero graded entries" 'echo "$OUT_EMPTY" | jq -e ".graded | length == 0" >/dev/null 2>&1'

# ── Injection guard (shares lib/cmd-allowlist.sh with ac-lint.sh, t-2868) ─────
echo "Test: metachar-injected demoable command never executes, classifies unknown"
CANARY="$FIX_WORKTREE/INJECTED"
rm -f "$CANARY"
OUT_INJ=$(bash "$GRADER" t-inj --json --cwd "$FIX_WORKTREE" 2>&1)
assert "injected command never executed (canary file absent)" '[ ! -f "$CANARY" ]'
assert "injected criterion classifies unknown, not silently dropped" \
  'echo "$OUT_INJ" | jq -e ".counts.unknown == 1" >/dev/null 2>&1'

# ── Gauge law: zero writes ────────────────────────────────────────────────────
echo "Test: ac-grade.sh never writes to tasks.json or any task field (gauge law)"
STUB_CALL_LOG="$TMPDIR_TEST/stub-calls.log"
cat > "$STUBDIR/brana" <<STUB2
#!/usr/bin/env bash
echo "\$*" >> "$STUB_CALL_LOG"
if [ "\$1" = "backlog" ] && [ "\$2" = "set" ]; then
    echo "STUB: refusing to simulate a write — this call itself is the finding" >&2
    exit 1
fi
if [ "\$1" = "backlog" ] && [ "\$2" = "get" ]; then
    id="\$3"; field=""
    for a in "\$@"; do
        [ "\${prev:-}" = "--field" ] && field="\$a"
        prev="\$a"
    done
    case "\$id:\$field" in
        t-fix:acceptance_criteria) echo '["file fixture.md exists"]' ;;
        t-fix:branch) echo '"stub/fix-branch"' ;;
        *) echo 'null' ;;
    esac
    exit 0
fi
exit 1
STUB2
chmod +x "$STUBDIR/brana"
: > "$STUB_CALL_LOG"
bash "$GRADER" t-fix --json --cwd "$FIX_WORKTREE" >/dev/null 2>&1
assert "no 'backlog set' call ever issued during grading" '! grep -q "backlog set" "$STUB_CALL_LOG"'

# ── Summary ────────────────────────────────────────────────────────────────────
echo ""
echo "=== ac-grade.sh results: $PASS passed, $FAIL failed, $TOTAL total ==="
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
