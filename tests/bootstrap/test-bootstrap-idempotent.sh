#!/usr/bin/env bash
# Tests for bootstrap.sh --check convergence (t-2482).
#
# bootstrap.sh claims idempotency ("safe to run multiple times") but --check
# reported changes even immediately after a successful full run. Two reporting
# bugs, both verified here:
#
#   1. settings.json attribution — CURRENT_ATTR used bare `jq`, which
#      pretty-prints across four lines, while DESIRED_ATTR was the compact
#      literal '{"commit":"","pr":""}'. The comparison could never match, so
#      --check always reported a change and every real run rewrote the file.
#   2. rules/README.md — bootstrap deliberately does not deploy it, but it was
#      deleted AFTER sync_dir ran. sync_dir saw it in src, absent in dst,
#      counted a change and re-copied it; the delete then removed it again.
#
# Tests:
#   T1: sync_dir accepts an exclusion list argument
#   T2: rules/ passes README.md to sync_dir (not a post-hoc rm)
#   T3: no post-hoc `rm -f .../rules/README.md` remains
#   T4: behavioral — sync_dir converges to 0 changes on a second run
#   T5: behavioral — an excluded file is removed once, then stays gone
#   T6: attribution comparison uses compact jq
#   T7: behavioral — pretty-printed attribution now compares equal to desired

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
BOOTSTRAP="$REPO_ROOT/bootstrap.sh"

PASS=0; FAIL=0; TOTAL=0

check() {
    local desc="$1" ok="$2" detail="${3:-}"
    TOTAL=$((TOTAL+1))
    if [ "$ok" = "0" ]; then
        PASS=$((PASS+1)); echo "  PASS: $desc"
    else
        FAIL=$((FAIL+1)); echo "  FAIL: $desc${detail:+ — $detail}"
    fi
}

echo "=== bootstrap --check convergence (t-2482) ==="

# --- static assertions -------------------------------------------------------

grep -q 'local src="$1" dst="$2" label="$3" exclude=' "$BOOTSTRAP"
check "T1: sync_dir accepts an exclusion list argument" $?

grep -q 'sync_dir "$SYSTEM_DIR/rules" "$TARGET_DIR/rules" "rules/" "README.md"' "$BOOTSTRAP"
check "T2: rules/ passes README.md as an exclusion" $?

! grep -q 'rm -f "$TARGET_DIR/rules/README.md"' "$BOOTSTRAP"
check "T3: post-hoc rm of rules/README.md removed" $?

# --- behavioral: sync_dir ----------------------------------------------------
# Extract the function from bootstrap.sh rather than sourcing the whole script
# (which would run a deploy). The extracted body is the contract.

FN=$(awk '/^sync_dir\(\) \{/{flag=1} flag{print} flag&&/^\}/{exit}' "$BOOTSTRAP")
if [ -z "$FN" ]; then
    check "T4: sync_dir extractable" 1 "could not extract function"
    check "T5: excluded file stays removed" 1 "skipped"
else
    run_sync() {
        # Runs the extracted sync_dir in a subshell, echoing its change count.
        local src="$1" dst="$2" excl="$3" checkonly="$4"
        (
            CHANGES=0
            CHECK_ONLY=$checkonly
            eval "$FN"
            sync_dir "$src" "$dst" "test/" "$excl" > /dev/null
            echo "$CHANGES"
        )
    }

    TMP=$(mktemp -d)
    trap 'rm -rf "$TMP"' EXIT
    mkdir -p "$TMP/src" "$TMP/dst"
    printf 'a\n' > "$TMP/src/rule-one.md"
    printf 'b\n' > "$TMP/src/rule-two.md"
    printf 'contract\n' > "$TMP/src/README.md"

    FIRST=$(run_sync "$TMP/src" "$TMP/dst" "README.md" false)
    SECOND=$(run_sync "$TMP/src" "$TMP/dst" "README.md" false)

    [ "$SECOND" = "0" ]
    check "T4: second sync_dir run reports 0 changes" $? "first=$FIRST second=$SECOND"

    # The excluded file must never be deployed, and a stale deployed copy must
    # be removed exactly once (not re-counted forever).
    printf 'stale\n' > "$TMP/dst/README.md"
    REMOVE=$(run_sync "$TMP/src" "$TMP/dst" "README.md" false)
    AFTER=$(run_sync "$TMP/src" "$TMP/dst" "README.md" false)
    [ ! -f "$TMP/dst/README.md" ] && [ "$REMOVE" = "1" ] && [ "$AFTER" = "0" ]
    check "T5: excluded file removed once, then stays gone" $? "remove=$REMOVE after=$AFTER"
fi

# --- attribution -------------------------------------------------------------

grep -qE 'CURRENT_ATTR=\$\(jq -c' "$BOOTSTRAP"
check "T6: attribution comparison uses compact jq" $?

if command -v jq &>/dev/null; then
    TMPS=$(mktemp)
    # Pretty-printed on disk, exactly as CC writes it.
    printf '{\n  "attribution": {\n    "commit": "",\n    "pr": ""\n  }\n}\n' > "$TMPS"
    CUR=$(jq -cS '.attribution // {}' "$TMPS" 2>/dev/null)
    DES=$(jq -cSn '{"commit":"","pr":""}')
    rm -f "$TMPS"
    [ "$CUR" = "$DES" ]
    check "T7: pretty-printed attribution compares equal to desired" $? "cur=$CUR des=$DES"
else
    check "T7: pretty-printed attribution compares equal to desired" 0 "jq absent — skipped"
fi


# --- t-2879: scripts/lib/ must actually deploy (Gate 3 ship-blocking finding) ---
# sync_dir's copy loop is `for f in "$src"/*; do [ -f "$f" ] || continue` —
# directory entries fail -f and are silently skipped, never recursed into.
# system/scripts/ already had git-hooks/, migrate/, tests/ subdirs that were
# never deployed either; lib/ became load-bearing when ac-lint.sh/ac-grade.sh
# started `source`-ing system/scripts/lib/cmd-allowlist.sh (t-2857/t-2868) —
# post-deploy that source call silently fails, undefining allowlisted_command.

echo "T8: Scripts deploy step includes a sync_dir call for scripts/lib/"
SCRIPTS_BLOCK=$(awk '/# --- Step 3: Scripts ---/{flag=1} flag{print} flag&&/# --- Step 3b: Hooks ---/{exit}' "$BOOTSTRAP")
echo "$SCRIPTS_BLOCK" | grep -q 'sync_dir "\$SYSTEM_DIR/scripts/lib" "\$TARGET_DIR/scripts/lib"'
check "T8: scripts/lib/ has its own sync_dir call in the Scripts deploy step" $?

echo "T9: behavioral — a subdir is invisible to a single sync_dir call, present after a second targeted call"
FN=$(awk '/^sync_dir\(\) \{/{flag=1} flag{print} flag&&/^\}/{exit}' "$BOOTSTRAP")
if [ -z "$FN" ]; then
    check "T9: sync_dir extractable for lib/ behavioral test" 1 "could not extract function"
else
    run_sync2() {
        local src="$1" dst="$2"
        ( CHANGES=0; CHECK_ONLY=false; eval "$FN"; sync_dir "$src" "$dst" "test/" > /dev/null )
    }
    TMP2=$(mktemp -d)
    trap 'rm -rf "$TMP2"' EXIT
    mkdir -p "$TMP2/src" "$TMP2/src/lib" "$TMP2/dst"
    printf 'a\n' > "$TMP2/src/top.sh"
    printf 'b\n' > "$TMP2/src/lib/nested.sh"

    run_sync2 "$TMP2/src" "$TMP2/dst"
    TOP_OK=0; [ -f "$TMP2/dst/top.sh" ] || TOP_OK=1
    NESTED_MISSING=0; [ -f "$TMP2/dst/lib/nested.sh" ] && NESTED_MISSING=1
    check "T9a: top-level file deployed by the plain sync_dir call" "$TOP_OK"
    check "T9b: nested file NOT deployed by the plain sync_dir call (the bug, documented)" "$NESTED_MISSING"

    run_sync2 "$TMP2/src/lib" "$TMP2/dst/lib"
    NESTED_OK=0; [ -f "$TMP2/dst/lib/nested.sh" ] || NESTED_OK=1
    check "T9c: nested file deployed once a dedicated sync_dir call targets the subdir (the fix)" "$NESTED_OK"
fi

echo ""
echo "$PASS/$TOTAL passed"
[ "$FAIL" -eq 0 ] || exit 1
