#!/usr/bin/env bash
# Regression test: CLOSE-ANCHOR-BLOCK's RECENT_COMMITS (the diagnostic signal
# behind the ANCHOR_ZERO_WINDOW visibility guard) shares the same flat
# `--since="6 hours ago"` flaw t-3004/t-3006 already fixed for SESSION_EPICS
# and Step 1's own gate — untouched by either fix (t-3017, sibling finding
# from the t-3006 challenger review).
#
# Bug: RECENT_COMMITS exists ONLY to answer "were there commits nearby that
# the (possibly-truncated) LAST_CLOSE anchor is hiding" — the guard fires
# when COMMIT_COUNT==0 (LAST_CLOSE postdates our commits) AND RECENT_COMMITS
# says otherwise (recent commits DO exist). If a session's last commit landed
# >6h before close (clock skew, or a long session — the exact t-3006 shape)
# WHILE a concurrent-or-unrelated close ALSO postdates it (causing the
# zero-window), the flat 6h RECENT_COMMITS check misses the old-but-real
# commit too, and the guard stays silent — exactly the "silent" failure mode
# the guard exists to prevent.
#
# IMPORTANT — why this is NOT "apply t-3004's UNSCOPED_LAST_CLOSE-anchored
# widening formula" (that formula IS the fix for pre-compact.sh's sibling
# instance, see test-pre-compact-snapshot.sh): LAST_CLOSE is always <=
# UNSCOPED_LAST_CLOSE by construction (LAST_CLOSE is chosen from a subset of
# the same ALL_SESSIONS_JSON that UNSCOPED_LAST_CLOSE maxes over). Whenever
# COMMIT_COUNT==0, LAST_CLOSE already postdates all recent commits, so
# UNSCOPED_LAST_CLOSE does too — no UNSCOPED_LAST_CLOSE-anchored widening can
# ever reach back further than the very anchor that caused the zero window in
# the first place. Reusing SESSION_EPICS_SINCE here would be a structural
# no-op, verified by direct construction before writing this test. The actual
# fix is a wider FLAT fallback (24h, independent of any session-state anchor)
# — simple and safe because RECENT_COMMITS is diagnostic-only (feeds a
# stderr warning, never gates real behavior).
#
# The block is EXTRACTED from the shipped procedure doc (t-1978 rot class),
# not copied. Companion: test-close-gate-concurrent-anchor.sh (t-2502, same
# extraction/fake-brana pattern).
#
# Run: bash tests/procedures/test-close-gate-recent-commits-window.sh

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

assert_contains() {
    local desc="$1" needle="$2" haystack="$3"
    TOTAL=$((TOTAL + 1))
    if printf '%s' "$haystack" | grep -qF -- "$needle"; then
        echo "  PASS: $desc"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $desc — expected to find [$needle] in: [$haystack]"
        FAIL=$((FAIL + 1))
    fi
}

assert_not_contains() {
    local desc="$1" needle="$2" haystack="$3"
    TOTAL=$((TOTAL + 1))
    if printf '%s' "$haystack" | grep -qF -- "$needle"; then
        echo "  FAIL: $desc — did not expect [$needle] in: [$haystack]"
        FAIL=$((FAIL + 1))
    else
        echo "  PASS: $desc"
        PASS=$((PASS + 1))
    fi
}

echo "=== test-close-gate-recent-commits-window.sh ==="
echo ""

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PHASE_MD="$REPO_ROOT/system/skills/close/phases/gate-and-evidence.md"
WALK_MD="$REPO_ROOT/system/skills/_shared/epic-ancestor-walk.md"
[ -f "$PHASE_MD" ] || { echo "ERROR: $PHASE_MD not found"; exit 1; }
[ -f "$WALK_MD" ] || { echo "ERROR: $WALK_MD not found"; exit 1; }

TMPROOT="$(mktemp -d)"
trap 'rm -rf "$TMPROOT"' EXIT

sed -n '/<!-- EPIC-WALK-BLOCK -->/,/<!-- \/EPIC-WALK-BLOCK -->/p' "$WALK_MD" \
    | sed '1d;$d' | sed '/^```/d' > "$TMPROOT/walk.sh"
[ -s "$TMPROOT/walk.sh" ] || { echo "ERROR: EPIC-WALK-BLOCK empty/missing"; exit 1; }

sed -n '/<!-- CLOSE-ANCHOR-BLOCK -->/,/<!-- \/CLOSE-ANCHOR-BLOCK -->/p' "$PHASE_MD" \
    | sed '1d;$d' | sed '/^```/d' > "$TMPROOT/step1.sh"
[ -s "$TMPROOT/step1.sh" ] || { echo "ERROR: CLOSE-ANCHOR-BLOCK empty/missing"; exit 1; }
grep -q 'RECENT_COMMITS=' "$TMPROOT/step1.sh" || {
    echo "ERROR: CLOSE-ANCHOR-BLOCK does not set RECENT_COMMITS — markers moved?"; exit 1; }

echo "Extracted walk.sh ($(wc -l < "$TMPROOT/walk.sh") lines) + Step 1 anchor block ($(wc -l < "$TMPROOT/step1.sh") lines)"
echo ""

FAKE_HOME="$TMPROOT/home"
mkdir -p "$FAKE_HOME/.claude/scripts"
printf '#!/usr/bin/env bash\ncat >/dev/null\necho INSTANT\n' \
    > "$FAKE_HOME/.claude/scripts/close-classify.sh"
chmod +x "$FAKE_HOME/.claude/scripts/close-classify.sh"

# Fake brana: `session read --all --json` returns $SESSIONS_JSON (per case);
# `backlog get` resolves t-2618 -> epic harness-engineering (matches the
# convention in test-close-gate-concurrent-anchor.sh).
mkdir -p "$TMPROOT/bin"
cat > "$TMPROOT/bin/brana" <<'FAKE'
#!/usr/bin/env bash
if [ "$1" = "session" ] && [ "$2" = "read" ]; then
    for a in "$@"; do [ "$a" = "--all" ] && ALL=1; done
    if [ "${ALL:-0}" = "1" ]; then
        printf '%s\n' "${SESSIONS_JSON:-[]}"
    else
        echo '{"written_at":null}'
    fi
    exit 0
fi
if [ "$1" = "backlog" ] && [ "$2" = "get" ]; then
    id="$3"; field="${5:-}"
    case "$id:$field" in
        t-2618:type)    echo '"task"' ;;
        t-2618:parent)  echo '"t-2346"' ;;
        t-2346:type)    echo '"epic"' ;;
        t-2346:parent)  echo 'null' ;;
        t-2346:subject) echo '"harness-engineering"' ;;
        *) echo 'null' ;;
    esac
    exit 0
fi
exit 0
FAKE
chmod +x "$TMPROOT/bin/brana"

# run_block <repo> <sessions_json>  →  prints "COMMIT_COUNT|ANCHOR_ZERO_WINDOW"; stderr in $TMPROOT/stderr.txt
run_block() {
    local repo="$1" sessions="$2"
    (cd "$repo" && PATH="$TMPROOT/bin:$PATH" HOME="$FAKE_HOME" ARGUMENTS="--continue" \
        SESSIONS_JSON="$sessions" \
        bash -c "source '$TMPROOT/walk.sh'; source '$TMPROOT/step1.sh' 2>\"$TMPROOT/stderr.txt\"; echo \"\${COMMIT_COUNT}|\${ANCHOR_ZERO_WINDOW:-0}\"")
}

mk_repo() {
    local dir="$1"
    mkdir -p "$dir"
    git -C "$dir" init -q
    git -C "$dir" config user.email t@t.t
    git -C "$dir" config user.name t
}
commit_at() {   # commit_at <repo> <date> <msg>
    echo "$3" >> "$1/f.txt"; git -C "$1" add -A
    GIT_AUTHOR_DATE="$2" GIT_COMMITTER_DATE="$2" \
        git -C "$1" -c commit.gpgsign=false commit -qm "$3"
}

# ── Case A: clock-skew commit + zero-window truncation, compound shape ──────
# Own commit at 10h ago (outside flat 6h; inside a generous 24h fallback).
# The only known session-state file is an orphan close at 2h ago, which
# postdates the commit -> LAST_CLOSE=2h-ago, COMMIT_COUNT=0 (zero window).
# Pre-fix: RECENT_COMMITS (flat 6h) also misses the 10h-old commit ->
# ANCHOR_ZERO_WINDOW stays 0, guard silent. Post-fix: RECENT_COMMITS (flat
# 24h) catches it -> ANCHOR_ZERO_WINDOW=1, guard fires.
echo "Case A — compound: 10h-old own commit + zero-window truncation"
REPO_A="$TMPROOT/repo-a"; mk_repo "$REPO_A"
OWN_TS_ISO="$(date -d '10 hours ago' --iso-8601=seconds)"
commit_at "$REPO_A" "$OWN_TS_ISO" "fix(x): own1 (t-2618)"
ORPHAN_TS="$(date -u -d '2 hours ago' +%Y-%m-%dT%H:%M:%SZ)"
SESS_A="[{\"epic\":\"(orphan)\",\"state\":{\"written_at\":\"$ORPHAN_TS\"}}]"
OUT="$(run_block "$REPO_A" "$SESS_A")"
IFS='|' read -r A_COUNT A_ZERO <<< "$OUT"
STDERR_A="$(cat "$TMPROOT/stderr.txt" 2>/dev/null)"
assert_eq "COMMIT_COUNT is 0 (anchor postdates the 10h-old commit)" "0" "$A_COUNT"
assert_eq "ANCHOR_ZERO_WINDOW=1 fires — RECENT_COMMITS' widened fallback catches the 10h-old commit" \
    "1" "$A_ZERO"
assert_contains "warning names the anchor's source ((orphan))" "(orphan)" "$STDERR_A"
assert_contains "warning says the window is empty" "EMPTY" "$STDERR_A"
assert_contains "warning's commit-count reflects the widened 24h count" "post-dates all 1 commit(s) of the last 24h" "$STDERR_A"
echo ""

# ── Case B: genuinely read-only, nothing to catch even at 24h ───────────────
# No commits at all within 24h (ancient history only) -> RECENT_COMMITS must
# stay 0 and the guard must stay quiet, same invariant as
# test-close-gate-concurrent-anchor.sh Case D.
echo "Case B — genuinely read-only within 24h: guard stays quiet"
REPO_B="$TMPROOT/repo-b"; mk_repo "$REPO_B"
OLD_TS_ISO="$(date -d '3 days ago' --iso-8601=seconds)"
commit_at "$REPO_B" "$OLD_TS_ISO" "chore: ancient (t-2618)"
OUT="$(run_block "$REPO_B" "$SESS_A")"
IFS='|' read -r B_COUNT B_ZERO <<< "$OUT"
STDERR_B="$(cat "$TMPROOT/stderr.txt" 2>/dev/null)"
assert_eq "COMMIT_COUNT is 0" "0" "$B_COUNT"
assert_eq "no zero-window flag — even the widened 24h fallback finds nothing" "0" "$B_ZERO"
assert_not_contains "no EMPTY warning on a truly read-only session" "EMPTY" "$STDERR_B"
echo ""

echo "─────────────────────────────────"
echo "Total: $TOTAL  Pass: $PASS  Fail: $FAIL"
[ "$FAIL" -eq 0 ] || exit 1
