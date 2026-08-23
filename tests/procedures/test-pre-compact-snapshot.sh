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

# ── Widened commit-count window (t-3017, sibling of t-3004/t-3006) ──────────
# Bug: COMMIT_COUNT here used a flat `--since="6 hours ago"`, identical to the
# flaw t-3004/t-3006 already fixed in gate-and-evidence.md. A session whose
# last commit landed >6h before compaction (clock skew, or a long session)
# computed COMMIT_COUNT=0, so close-snapshot.sh (COMMIT_COUNT -le 0 -> silent
# no-op) never queued the pre-compaction safety-net — undermining this hook's
# own "nothing from this session is lost to compaction" guarantee. Fix: widen
# using the same UNSCOPED_LAST_CLOSE-anchored, floored-at-6h formula, via
# `$BRANA session read --all --json` (unlike gate-and-evidence.md's
# RECENT_COMMITS sibling fix, this site has no LAST_CLOSE/anchor concept at
# all, so the widening formula applies directly with no structural bound).
#
# Fake `brana` reads $FAKE_SESSIONS_JSON per invocation (env var, not a
# mutated shared file) — env-var-per-subshell convention, same lesson t-3006's
# own test rewrite applied (a sed+mv-per-case fake binary silently aliased
# cases there; challenger finding).
FAKE_BIN="$WORK/fakebin"
mkdir -p "$FAKE_BIN"
cat > "$FAKE_BIN/brana" <<'FAKE'
#!/usr/bin/env bash
if [ "$1" = "session" ] && [ "$2" = "read" ]; then
    for a in "$@"; do [ "$a" = "--all" ] && ALL=1; done
    if [ "${ALL:-0}" = "1" ]; then
        printf '%s\n' "${FAKE_SESSIONS_JSON:-[]}"
    fi
    exit 0
fi
echo '[]'
exit 0
FAKE
chmod +x "$FAKE_BIN/brana"

mk_widen_repo() {   # mk_widen_repo <dir>
    # Two commits, OLDEST FIRST (chronological parent->child order): one at
    # 20h ago (outside flat 6h, inside a widened ~25h window) and one at 2h
    # ago (inside flat 6h regardless of widening). The 2h-old commit is what
    # makes the floor case discriminating — see run_widen_case below. An
    # un-dated ("now") commit must NEVER be the FIRST commit here: `git log
    # --since` prunes traversal once it hits a commit outside the range,
    # assuming committer dates decrease monotonically toward the root: a
    # "now"-dated root under a 20h-old child makes the history non-monotonic
    # and silently hides the parent regardless of the window — bit the first
    # draft of this test.
    local dir="$1"
    git init -q -b main "$dir"
    echo old > "$dir/old.txt"
    git -C "$dir" add old.txt
    local old_date; old_date="$(date -d '20 hours ago' --iso-8601=seconds)"
    GIT_AUTHOR_DATE="$old_date" GIT_COMMITTER_DATE="$old_date" \
        git -C "$dir" -c user.email=t@t -c user.name=t -c commit.gpgsign=false commit -q -m "old work (t-600)"
    echo recent >> "$dir/old.txt"
    git -C "$dir" add old.txt
    local recent_date; recent_date="$(date -d '2 hours ago' --iso-8601=seconds)"
    GIT_AUTHOR_DATE="$recent_date" GIT_COMMITTER_DATE="$recent_date" \
        git -C "$dir" -c user.email=t@t -c user.name=t -c commit.gpgsign=false commit -q -m "in-window work (t-600)"
}

# CLAUDE_PLUGIN_ROOT/CLAUDE_PLUGIN_DATA are unset in both runs below: this
# suite runs inside a live Claude Code session that sets CLAUDE_PLUGIN_ROOT,
# and resolve-brana.sh checks it BEFORE PATH — left set, it resolves $BRANA
# to the real deployed binary and silently defeats this test's fake `brana`
# on PATH (discovered live authoring this test, t-3017: the widened-window
# assertion failed with --commit-count 0 even though the fix was already
# applied and correct).
run_widen_case() {   # run_widen_case <label> <sessions_json> <expect_count>
    local label="$1" sessions="$2" expect="$3"
    local repo="$WORK/widen-repo-$RANDOM"
    mk_widen_repo "$repo"
    : > "$CALL_LOG"
    local out
    out=$(printf '{"session_id":"sess-old","cwd":"%s","trigger":"auto"}' "$repo" | \
        env -u CLAUDE_PLUGIN_ROOT -u CLAUDE_PLUGIN_DATA PATH="$FAKE_BIN:$PATH" \
            FAKE_SESSIONS_JSON="$sessions" BRANA_SNAPSHOT_SCRIPT="$STUB" \
            BRANA_PRECOMPACT_GUARD_DIR="$WORK/guards-$RANDOM" bash "$HOOK")
    local rc=$?
    echo "$label"
    assert "$label: exit 0" "[ $rc -eq 0 ]"
    assert "$label: valid JSON" "echo '$out' | jq -e '.continue == true' >/dev/null 2>&1"
    assert "$label: snapshot script invoked" "[ \"\$(grep -c . '$CALL_LOG')\" = 1 ]"
    assert "$label: commit-count is $expect" "grep -q -- '--commit-count $expect' '$CALL_LOG'"
}

echo ""
OLD_CLOSE_TS="$(date -u -d '25 hours ago' +%Y-%m-%dT%H:%M:%SZ)"
run_widen_case "Widened window: both commits counted incl. the 20h-old one (clock-skew shape)" \
    "[{\"epic\":\"(orphan)\",\"state\":{\"written_at\":\"$OLD_CLOSE_TS\"}}]" \
    "2"

echo ""
RECENT_CLOSE_TS="$(date -u -d '5 minutes ago' +%Y-%m-%dT%H:%M:%SZ)"
run_widen_case "Floor at 6h: only the 2h-old commit counted — 20h-old one stays excluded, window not over-narrowed either" \
    "[{\"epic\":\"(orphan)\",\"state\":{\"written_at\":\"$RECENT_CLOSE_TS\"}}]" \
    "1"

echo ""
echo "=== Results: $PASS/$TOTAL passed, $FAIL failed ==="

[ "$FAIL" -eq 0 ] || exit 1
