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

# ── Fake `brana` ─────────────────────────────────────────────────────────────
mkdir -p "$TMPROOT/bin"
cat > "$TMPROOT/bin/brana" <<FAKE
#!/usr/bin/env bash
if [ "\$1" = "session" ] && [ "\$2" = "read" ]; then
    for a in "\$@"; do [ "\$a" = "--all" ] && ALL=1; done
    if [ "\${ALL:-0}" = "1" ]; then
        cat <<JSON
[{"epic":"__EPIC__","state":{"written_at":"__LAST_CLOSE_TS__"}}]
JSON
    fi
    exit 0
fi
exit 0
FAKE
chmod +x "$TMPROOT/bin/brana"

run_case() {
    local label="$1" epic="$2" last_close_ts="$3" own_commit_date="$4" expect_nonempty="$5"

    sed -e "s|__EPIC__|$epic|g" -e "s|__LAST_CLOSE_TS__|$last_close_ts|g" \
        "$TMPROOT/bin/brana" > "$TMPROOT/bin/brana.case"
    chmod +x "$TMPROOT/bin/brana.case"
    mv "$TMPROOT/bin/brana.case" "$TMPROOT/bin/brana"

    local fix="$TMPROOT/repo-$RANDOM"
    mkdir -p "$fix"
    git -C "$fix" init -q
    git -C "$fix" config user.email t@t.t
    git -C "$fix" config user.name t
    echo "own1" >> "$fix/f.txt"; git -C "$fix" add -A
    GIT_AUTHOR_DATE="$own_commit_date" GIT_COMMITTER_DATE="$own_commit_date" \
        git -C "$fix" -c commit.gpgsign=false commit -qm "feat(x): own1 (t-600)"

    local out
    out="$(cd "$fix" && PATH="$TMPROOT/bin:$PATH" \
        bash -c "source '$TMPROOT/gate-window.sh' >/dev/null 2>&1; git log --oneline --since=\"\$GATE_SINCE\" | wc -l | tr -d ' '")"

    echo "$label"
    if [ "$expect_nonempty" = "1" ]; then
        assert_eq "$label: widened window picks up the session's own commit" "1" "$out"
    else
        assert_eq "$label: unwidened (recent prior close) — flat 6h window stays empty" "0" "$out"
    fi
}

# ── Case 1: clock-jump / long-session shape (live 2026-08-22 repro) ─────────
# Prior close 25h ago (older than 6h -> widens), session's own commit 20h ago
# (outside flat 6h, inside the widened 25h window).
run_case "Case 1: long session, prior close 25h ago, own commit 20h ago" \
    "(orphan)" \
    "$(date -u -d '25 hours ago' +%Y-%m-%dT%H:%M:%SZ)" \
    "$(date -d '20 hours ago' --iso-8601=seconds)" \
    "1"
echo ""

# ── Case 2: floor invariant — a recent prior close must NOT narrow below 6h ──
# Prior close 5 minutes ago (newer than 6h). Own commit is 40 minutes ago —
# still inside the flat 6h default, so this must stay non-empty via the floor,
# not because widening kicked in (mirrors test-close-gate-concurrent-anchor.sh
# Case A's narrowing hazard for SESSION_EPICS — same invariant here).
run_case "Case 2: floor at 6h — recent prior close doesn't narrow the window" \
    "(orphan)" \
    "$(date -u -d '5 minutes ago' +%Y-%m-%dT%H:%M:%SZ)" \
    "$(date -d '40 minutes ago' --iso-8601=seconds)" \
    "1"
echo ""

echo "─────────────────────────────────"
echo "Total: $TOTAL  Pass: $PASS  Fail: $FAIL"
[ "$FAIL" -eq 0 ] || exit 1
