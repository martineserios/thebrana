#!/usr/bin/env bash
# Regression test: Step 1's own "both empty -> read-only session" wall-clock
# check must not miss a long-running session's own commits just because they
# are older than a flat 6h window (t-3006) — the same flaw t-3004 already
# fixed for SESSION_EPICS inside the CLOSE-ANCHOR-BLOCK, but Step 1's earlier,
# independent check had no equivalent safeguard.
#
# Bug (live, thebrana 2026-08-22, this session's own close): the system clock
# had jumped ~20h overnight relative to this session's own commit timestamps.
# Step 1's flat `git log --oneline --since="6 hours ago"` came back empty even
# though the session had 7 of its own commits and had just merged 3 completed
# tasks. Following the documented shortcut ("both empty -> write minimal
# handoff, skip to Step 9") would have silently discarded a substantial,
# non-read-only session as if nothing happened. Caught this time only because
# the CLOSE-ANCHOR-BLOCK's SESSION_EPICS (fixed in t-3004) was cross-checked
# manually — Step 1's own gate had no equivalent safeguard.
#
# Fix: widen Step 1's window the same way t-3004 widened SESSION_EPICS's —
# anchored on the newest session-state write across all epic files
# (UNSCOPED_LAST_CLOSE), floored at 6h so it only ever WIDENS, never narrows
# below the safe default (a concurrent lane's fresher close can't shrink this
# window — same invariant as t-3004).
#
# The snippet is EXTRACTED from system/skills/close/phases/gate-and-evidence.md
# so the test exercises the shipped procedure text, not a copy (t-1978 rot class).
#
# Fake `brana` reads $SESSIONS_JSON per invocation (env var, not a mutated
# shared file) — mirrors test-close-gate-concurrent-anchor.sh's convention.
# An earlier version of this test sed-templated and `mv`'d the fake binary
# per case; the second case's substitution silently matched nothing (already
# substituted by case 1) and re-ran case 1's fixture, so both cases exercised
# the same WIDEN branch and the floor-invariant case never actually tested
# the floor (challenger finding, t-3006 iteration 1). This version also
# asserts GATE_SINCE's literal value so the two branches (widen vs. floor)
# are distinguished directly, not inferred from a commit count both branches
# can satisfy.
#
# Run: bash tests/procedures/test-close-gate-step1-window.sh

set -uo pipefail

PASS=0
FAIL=0
TOTAL=0

assert_eq() {
    local desc="$1" expected="$2" actual="$3"
    TOTAL=$((TOTAL + 1))
    if [ "$expected" = "$actual" ]; then
        echo "  PASS: $desc"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $desc — expected [$expected], got [$actual]"
        FAIL=$((FAIL + 1))
    fi
}

assert_prefix() {
    local desc="$1" prefix="$2" actual="$3"
    TOTAL=$((TOTAL + 1))
    case "$actual" in
        "$prefix"*)
            echo "  PASS: $desc"
            PASS=$((PASS + 1))
            ;;
        *)
            echo "  FAIL: $desc — expected prefix [$prefix], got [$actual]"
            FAIL=$((FAIL + 1))
            ;;
    esac
}

echo "=== test-close-gate-step1-window.sh ==="
echo ""

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PHASE_MD="$REPO_ROOT/system/skills/close/phases/gate-and-evidence.md"
[ -f "$PHASE_MD" ] || { echo "ERROR: $PHASE_MD not found"; exit 1; }

TMPROOT="$(mktemp -d)"
trap 'rm -rf "$TMPROOT"' EXIT

# ── Extract the ```bash block that computes GATE_SINCE ──────────────────────
sed -n '/<!-- GATE-WINDOW-BLOCK -->/,/<!-- \/GATE-WINDOW-BLOCK -->/p' "$PHASE_MD" \
    | sed '1d;$d' \
    | sed '/^```/d' > "$TMPROOT/gate-window.sh"

[ -s "$TMPROOT/gate-window.sh" ] || {
    echo "ERROR: GATE-WINDOW-BLOCK markers missing or empty in $PHASE_MD"; exit 1; }
grep -q 'GATE_SINCE=' "$TMPROOT/gate-window.sh" || {
    echo "ERROR: GATE-WINDOW-BLOCK does not set GATE_SINCE — markers moved?"; exit 1; }
echo "Extracted Step 1 gate-window block ($(wc -l < "$TMPROOT/gate-window.sh") lines)"
echo ""

# ── Fake `brana`: `session read --all --json` returns $SESSIONS_JSON ────────
mkdir -p "$TMPROOT/bin"
cat > "$TMPROOT/bin/brana" <<'FAKE'
#!/usr/bin/env bash
if [ "$1" = "session" ] && [ "$2" = "read" ]; then
    for a in "$@"; do [ "$a" = "--all" ] && ALL=1; done
    if [ "${ALL:-0}" = "1" ]; then
        printf '%s\n' "${SESSIONS_JSON:-[]}"
    fi
    exit 0
fi
exit 0
FAKE
chmod +x "$TMPROOT/bin/brana"

# One shared fixture repo is fine — GATE_SINCE's own value (asserted below)
# already distinguishes the branch taken; the commit-count check just
# confirms the resulting `git log --since` picks up the right commit.
FIX="$TMPROOT/repo"
mkdir -p "$FIX"
git -C "$FIX" init -q
git -C "$FIX" config user.email t@t.t
git -C "$FIX" config user.name t

# run_case <label> <sessions_json> <own_commit_date> <expect_since_prefix> <expect_count>
run_case() {
    local label="$1" sessions_json="$2" own_commit_date="$3" expect_since_prefix="$4" expect_count="$5"

    echo "own-$RANDOM" >> "$FIX/f.txt"; git -C "$FIX" add -A
    GIT_AUTHOR_DATE="$own_commit_date" GIT_COMMITTER_DATE="$own_commit_date" \
        git -C "$FIX" -c commit.gpgsign=false commit -qm "feat(x): own (t-600)" >/dev/null

    local out since count
    out="$(cd "$FIX" && PATH="$TMPROOT/bin:$PATH" SESSIONS_JSON="$sessions_json" \
        bash -c "source '$TMPROOT/gate-window.sh' >/dev/null 2>&1; printf '%s|' \"\$GATE_SINCE\"; git log --oneline --since=\"\$GATE_SINCE\" | wc -l | tr -d ' '")"
    since="${out%%|*}"
    count="${out##*|}"

    echo "$label"
    assert_prefix "$label: GATE_SINCE" "$expect_since_prefix" "$since"
    assert_eq "$label: commits since GATE_SINCE" "$expect_count" "$count"
}

# ── Case 1: clock-jump / long-session shape (live 2026-08-22 repro) ─────────
# Prior close 25h ago (older than 6h -> widens). GATE_SINCE must become an
# "@epoch" anchor, and the widened window must pick up this session's own
# commit landed 20h ago (outside flat 6h, inside the widened 25h window).
run_case "Case 1: long session, prior close 25h ago, own commit 20h ago" \
    '[{"epic":"(orphan)","state":{"written_at":"'"$(date -u -d '25 hours ago' +%Y-%m-%dT%H:%M:%SZ)"'"}}]' \
    "$(date -d '20 hours ago' --iso-8601=seconds)" \
    "@" \
    "1"
echo ""

# ── Case 2: floor invariant — a recent prior close must NOT narrow the window ─
# Prior close 5 minutes ago (newer than 6h). GATE_SINCE must stay the literal
# "6 hours ago" fallback, not narrow to "5 minutes ago" — mirrors
# test-close-gate-concurrent-anchor.sh's narrowing-hazard case for
# SESSION_EPICS (t-2502). This session's commit landed 40 minutes ago and
# must still be picked up by the (unwidened) flat 6h default.
run_case "Case 2: floor at 6h — recent prior close doesn't narrow the window" \
    '[{"epic":"(orphan)","state":{"written_at":"'"$(date -u -d '5 minutes ago' +%Y-%m-%dT%H:%M:%SZ)"'"}}]' \
    "$(date -d '40 minutes ago' --iso-8601=seconds)" \
    "6 hours ago" \
    "1"
echo ""

echo "─────────────────────────────────"
echo "Total: $TOTAL  Pass: $PASS  Fail: $FAIL"
[ "$FAIL" -eq 0 ] || exit 1
