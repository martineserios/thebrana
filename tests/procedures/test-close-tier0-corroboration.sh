#!/usr/bin/env bash
# Regression test: close Step 9c Tier 0 (persistent focus) must corroborate
# the focus slug against this session's own commits before trusting it (t-2618).
#
# Bug (live, thebrana 2026-08-02, closing the receipts session): Tier 0 reads
# `brana session epic status --json | .focus`, a GLOBAL persistent file. Whichever
# concurrent session last called `brana session epic focus` captures routing for
# every session that closes afterward — Tier 0 had no corroboration gate at all,
# and it runs FIRST, skipping every other tier. Since `brana session write` keys
# handoffs by epic and REPLACES rather than merges, a wrong slug destroys the
# other epic's live state (the t-2263 clobber class Tier 2a/2b's corroboration
# requirement was added to prevent — Tier 0 was left ungated).
#
# This test asserts:
#   1. Focus slug NOT reachable from this session's own commits -> NOT trusted,
#      falls through, and a warning naming both slugs is emitted (never silent).
#   2. Focus slug IS reachable from this session's own commits -> trusted silently.
#   3. No focus slug set -> falls through silently, no warning.
#
# Both extracted blocks are sourced from the SHIPPED procedure docs (t-1978 rot
# class) — system/skills/_shared/epic-ancestor-walk.md and
# system/skills/close/phases/session-state.md — not copies.
#
# Run: bash tests/procedures/test-close-tier0-corroboration.sh

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
    local desc="$1" haystack="$2" needle="$3"
    TOTAL=$((TOTAL + 1))
    if printf '%s' "$haystack" | grep -qF "$needle"; then
        echo "  PASS: $desc"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $desc — expected to find [$needle] in [$haystack]"
        FAIL=$((FAIL + 1))
    fi
}

echo "=== test-close-tier0-corroboration.sh ==="
echo ""

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WALK_MD="$REPO_ROOT/system/skills/_shared/epic-ancestor-walk.md"
SS_MD="$REPO_ROOT/system/skills/close/phases/session-state.md"
[ -f "$WALK_MD" ] || { echo "ERROR: $WALK_MD not found"; exit 1; }
[ -f "$SS_MD" ] || { echo "ERROR: $SS_MD not found"; exit 1; }

TMPROOT="$(mktemp -d)"
trap 'rm -rf "$TMPROOT"' EXIT

# ── Extract resolve_epic_ancestor() (named marker, t-2493) ────────────────────
sed -n '/<!-- EPIC-WALK-BLOCK -->/,/<!-- \/EPIC-WALK-BLOCK -->/p' "$WALK_MD" \
    | sed '1d;$d' | sed '/^```/d' > "$TMPROOT/walk.sh"
[ -s "$TMPROOT/walk.sh" ] || { echo "ERROR: EPIC-WALK-BLOCK empty/missing"; exit 1; }

# ── Extract the Tier 0 corroboration block (named marker, t-2493) ─────────────
sed -n '/<!-- TIER0-CORROBORATION-BLOCK -->/,/<!-- \/TIER0-CORROBORATION-BLOCK -->/p' "$SS_MD" \
    | sed '1d;$d' | sed '/^```/d' > "$TMPROOT/tier0.sh"
[ -s "$TMPROOT/tier0.sh" ] || { echo "ERROR: TIER0-CORROBORATION-BLOCK empty/missing"; exit 1; }
grep -q 'TIER2B_SLUGS=' "$TMPROOT/tier0.sh" || { echo "ERROR: TIER0-CORROBORATION-BLOCK does not set TIER2B_SLUGS — markers moved?"; exit 1; }

echo "Extracted walk.sh ($(wc -l < "$TMPROOT/walk.sh") lines) + tier0.sh ($(wc -l < "$TMPROOT/tier0.sh") lines)"
echo ""

# ── Fake `brana`: session epic status (focus) + backlog get (epic walk) ───────
# Fixture: t-100's parent chain resolves to epic "epic-b". This session's
# own commits (git log) reference t-100. `brana session epic status` returns
# whatever $FAKE_FOCUS is set to by each case below.
mkdir -p "$TMPROOT/bin"
cat > "$TMPROOT/bin/brana" <<'FAKE'
#!/usr/bin/env bash
if [ "$1" = "session" ] && [ "$2" = "epic" ] && [ "$3" = "status" ]; then
    printf '{"focus":%s}\n' "$(cat "${FAKE_FOCUS_FILE}" 2>/dev/null || echo null)"
    exit 0
fi
if [ "$1" = "backlog" ] && [ "$2" = "get" ]; then
    id="$3"; field="${5:-}"
    case "$id:$field" in
        t-100:type)    echo '"task"' ;;
        t-100:parent)  echo '"t-999"' ;;
        t-999:type)   echo '"epic"' ;;
        t-999:parent) echo 'null' ;;
        t-999:subject) echo '"epic-b"' ;;
        t-200:type)    echo '"task"' ;;
        t-200:parent)  echo '"t-998"' ;;
        t-998:type)   echo '"epic"' ;;
        t-998:parent) echo 'null' ;;
        t-998:subject) echo '"epic-a"' ;;
        *) echo 'null' ;;
    esac
    exit 0
fi
exit 0
FAKE
chmod +x "$TMPROOT/bin/brana"
export PATH="$TMPROOT/bin:$PATH"

# ── Fixture repo: one commit referencing t-100 (this session's own history) ──
FIX="$TMPROOT/repo"
mkdir -p "$FIX"
git -C "$FIX" init -q
git -C "$FIX" config user.email t@t.t
git -C "$FIX" config user.name t
echo one >> "$FIX/f.txt"; git -C "$FIX" add -A
git -C "$FIX" -c commit.gpgsign=false commit -qm "fix(x): resolve t-100 issue"

# ── Fixture repo 2 (t-2768): an OLD out-of-session commit (t-200 -> epic-a) plus
# a NEW this-session commit (t-100 -> epic-b), straddling a LAST_CLOSE anchor —
# isolated from $FIX so it doesn't perturb cases 1-3's commit count/window.
FIX2="$TMPROOT/repo2"
mkdir -p "$FIX2"
git -C "$FIX2" init -q
git -C "$FIX2" config user.email t@t.t
git -C "$FIX2" config user.name t
echo old >> "$FIX2/f.txt"; git -C "$FIX2" add -A
GIT_AUTHOR_DATE="2026-08-01T00:00:00Z" GIT_COMMITTER_DATE="2026-08-01T00:00:00Z" \
    git -C "$FIX2" -c commit.gpgsign=false commit -qm "chore(y): unrelated t-200 work, out-of-session"
echo new >> "$FIX2/f.txt"; git -C "$FIX2" add -A
GIT_AUTHOR_DATE="2026-08-12T00:00:00Z" GIT_COMMITTER_DATE="2026-08-12T00:00:00Z" \
    git -C "$FIX2" -c commit.gpgsign=false commit -qm "fix(x): resolve t-100 issue, this session"

# shellcheck disable=SC1090
source "$TMPROOT/walk.sh"

run_tier0() {
    # $1 = focus value to serve ("null" or a quoted slug), run inside the fixture repo
    # $2 = optional LAST_CLOSE anchor (t-2768) — same session-scope anchor
    #      gate-and-evidence.md's Step 0 GATE computes; unset for cases that don't care.
    # $3 = fixture repo dir to run inside (default: $FIX)
    local focus_json="$1" last_close="${2:-}" repo="${3:-$FIX}"
    printf '%s' "$focus_json" > "$TMPROOT/focus.txt"
    (
        cd "$repo" || exit 1
        export FAKE_FOCUS_FILE="$TMPROOT/focus.txt"
        [ -n "$last_close" ] && export LAST_CLOSE="$last_close"
        TIER0_SLUG=$(brana session epic status --json 2>/dev/null | jq -r '.focus // empty')
        source "$TMPROOT/tier0.sh" 2>"$TMPROOT/stderr.txt"
        echo "INITIATIVE_SLUG=${INITIATIVE_SLUG:-}"
    )
}

# ── Case 1: uncorroborated focus slug — must NOT be trusted ───────────────────
echo "Case 1: focus=epic-a, session's own commits resolve to epic-b (uncorroborated)"
OUT=$(run_tier0 '"epic-a"')
GOT_SLUG="${OUT#INITIATIVE_SLUG=}"
assert_eq "does NOT adopt the uncorroborated focus slug" "" "$GOT_SLUG"
STDERR="$(cat "$TMPROOT/stderr.txt" 2>/dev/null)"
assert_contains "warning names the focus slug" "$STDERR" "epic-a"
assert_contains "warning names the corroborating slug" "$STDERR" "epic-b"
echo ""

# ── Case 2: corroborated focus slug — trusted silently ─────────────────────────
echo "Case 2: focus=epic-b, session's own commits also resolve to epic-b (corroborated)"
OUT=$(run_tier0 '"epic-b"')
GOT_SLUG="${OUT#INITIATIVE_SLUG=}"
assert_eq "adopts the corroborated focus slug" "epic-b" "$GOT_SLUG"
STDERR="$(cat "$TMPROOT/stderr.txt" 2>/dev/null)"
assert_eq "no warning on the corroborated path" "" "$STDERR"
echo ""

# ── Case 3: no focus set — falls through silently ──────────────────────────────
echo "Case 3: no persistent focus set"
OUT=$(run_tier0 'null')
GOT_SLUG="${OUT#INITIATIVE_SLUG=}"
assert_eq "no slug adopted" "" "$GOT_SLUG"
STDERR="$(cat "$TMPROOT/stderr.txt" 2>/dev/null)"
assert_eq "no warning when focus is empty" "" "$STDERR"
echo ""

# ── Case 4 (t-2768): stale focus slug only reachable from an OLDER, out-of-session
# commit — must NOT corroborate even though a flat `git log -20` window would still
# see that old commit in a low-commit-count repo. Anchors TIER2B_SLUGS on LAST_CLOSE
# (2026-08-10, between the two fixture commits) so only the post-anchor commit
# (t-100 -> epic-b) counts as "this session's own" — the stale focus (epic-a, from
# the pre-anchor t-200 commit) must fall through unchanged.
echo "Case 4: focus=epic-a (only reachable from a commit BEFORE LAST_CLOSE) — must not corroborate"
OUT=$(run_tier0 '"epic-a"' "2026-08-10T00:00:00Z" "$FIX2")
GOT_SLUG="${OUT#INITIATIVE_SLUG=}"
assert_eq "does NOT adopt a focus slug reachable only from a pre-session commit" "" "$GOT_SLUG"
STDERR="$(cat "$TMPROOT/stderr.txt" 2>/dev/null)"
assert_contains "warning names the stale focus slug" "$STDERR" "epic-a"
echo ""

echo "─────────────────────────────────"
echo "Total: $TOTAL  Pass: $PASS  Fail: $FAIL"
[ "$FAIL" -eq 0 ] || exit 1
