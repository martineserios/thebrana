#!/usr/bin/env bash
# Tests for the pre-compact silent snapshot (t-1988, ADR-053 §5 Layer 2).
#
# Contract pinned here:
#   1. pre-compact.sh calls close-snapshot.sh for git-repo sessions
#   2. Idempotency: same HEAD twice → snapshot invoked once
#   3. Snapshot failure → hook STILL emits valid {"continue": true...} JSON, exit 0
#   4. Non-git cwd → no snapshot attempt, normal pass-through
#   BRANA_SNAPSHOT_SCRIPT env var overrides the script path (test seam, same
#   pattern as $BRANA in close-snapshot.sh).
#
# Note: accumulate-not-dedup queue semantics (ADR-053 §7) are covered by the
# Rust suite — brana-core queue.rs dedup tests + close_queue_smoke.rs
# "same range again" case. Not replicated here.
#
# Run: bash tests/procedures/test-pre-compact-snapshot.sh

set -uo pipefail

PASS=0
FAIL=0
TOTAL=0

assert() {
    local desc="$1" cond="$2"
    TOTAL=$((TOTAL + 1))
    if eval "$cond"; then
        echo "  PASS: $desc"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $desc (condition: $cond)"
        FAIL=$((FAIL + 1))
    fi
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$SCRIPT_DIR/../../system/hooks/pre-compact.sh"

WORK=$(mktemp -d /tmp/pre-compact-test.XXXXXX)
trap 'rm -rf "$WORK"' EXIT

# Counting stub for close-snapshot.sh; CALL_LOG records each invocation's args
CALL_LOG="$WORK/calls.log"
STUB="$WORK/snapshot-stub.sh"
cat > "$STUB" << EOF
#!/usr/bin/env bash
echo "\$@" >> "$CALL_LOG"
exit 0
EOF
chmod +x "$STUB"

FAILING_STUB="$WORK/snapshot-fail.sh"
cat > "$FAILING_STUB" << EOF
#!/usr/bin/env bash
echo "\$@" >> "$CALL_LOG"
echo "simulated snapshot failure" >&2
exit 1
EOF
chmod +x "$FAILING_STUB"

# Git repo with a commit in the last 6 hours
REPO="$WORK/repo"
git init -q -b main "$REPO"
git -C "$REPO" -c user.email=t@t -c user.name=t commit -q --allow-empty -m "root"
echo x > "$REPO/x.txt"
git -C "$REPO" add x.txt
git -C "$REPO" -c user.email=t@t -c user.name=t commit -q -m "recent work"

run_hook() {
    # $1 = cwd, $2 = snapshot script override, $3 = session id
    printf '{"session_id":"%s","cwd":"%s","trigger":"auto"}' "${3:-test-sess}" "$1" | \
        BRANA_SNAPSHOT_SCRIPT="$2" BRANA_PRECOMPACT_GUARD_DIR="$WORK/guards" bash "$HOOK"
}

echo "=== test-pre-compact-snapshot.sh ==="

echo ""
echo "Snapshot invoked for git repo session"
: > "$CALL_LOG"
OUT=$(run_hook "$REPO" "$STUB" sess-a)
RC=$?
assert "exit 0" "[ $RC -eq 0 ]"
assert "valid JSON with continue:true" \
    "echo '$OUT' | jq -e '.continue == true' >/dev/null 2>&1"
assert "snapshot stub called once" "[ \"\$(grep -c . '$CALL_LOG')\" = 1 ]"
assert "stub received --git-root of the repo" "grep -q -- '--git-root $REPO' '$CALL_LOG'"
assert "additionalContext carries the snapshot notice" \
    "echo '$OUT' | jq -r '.additionalContext // \"\"' | grep -q 'snapshot saved'"

echo ""
echo "Idempotency: same HEAD again → no second call"
OUT=$(run_hook "$REPO" "$STUB" sess-a)
assert "exit 0 on repeat" "[ $? -eq 0 ]"
assert "still exactly one stub call" "[ \"\$(grep -c . '$CALL_LOG')\" = 1 ]"

echo ""
echo "New HEAD → snapshot fires again"
echo y > "$REPO/y.txt"
git -C "$REPO" add y.txt
git -C "$REPO" -c user.email=t@t -c user.name=t commit -q -m "more work"
OUT=$(run_hook "$REPO" "$STUB" sess-a)
assert "exit 0" "[ $? -eq 0 ]"
assert "second call recorded for new HEAD" "[ \"\$(grep -c . '$CALL_LOG')\" = 2 ]"

echo ""
echo "Snapshot failure → hook unaffected (challenger contract finding 4)"
: > "$CALL_LOG"
rm -rf "$WORK/guards"
OUT=$(run_hook "$REPO" "$FAILING_STUB" sess-b)
RC=$?
assert "exit 0 despite snapshot failure" "[ $RC -eq 0 ]"
assert "valid JSON despite snapshot failure" \
    "echo '$OUT' | jq -e '.continue == true' >/dev/null 2>&1"
assert "failing stub was attempted" "[ \"\$(grep -c . '$CALL_LOG')\" = 1 ]"
assert "no false notice on failure" \
    "! echo '$OUT' | jq -r '.additionalContext // \"\"' | grep -q 'snapshot saved'"

echo ""
echo "Guard-the-attempt: failure then retry at same HEAD → no second attempt"
OUT=$(run_hook "$REPO" "$FAILING_STUB" sess-b)
assert "exit 0 on retry" "[ $? -eq 0 ]"
assert "still exactly one attempt (guard wrote on failure too)" \
    "[ \"\$(grep -c . '$CALL_LOG')\" = 1 ]"

echo ""
echo "Non-git cwd → pass-through, no snapshot attempt"
: > "$CALL_LOG"
NOGIT="$WORK/plain"
mkdir -p "$NOGIT"
OUT=$(run_hook "$NOGIT" "$STUB" sess-c)
assert "exit 0" "[ $? -eq 0 ]"
assert "valid JSON" "echo '$OUT' | jq -e '.continue == true' >/dev/null 2>&1"
assert "no snapshot call for non-git cwd" "[ ! -s '$CALL_LOG' ]"

echo ""
echo "=== Results: $PASS/$TOTAL passed, $FAIL failed ==="

[ "$FAIL" -eq 0 ] || exit 1
