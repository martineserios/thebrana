#!/usr/bin/env bash
# Regression test: SESSION_EPICS must not miss a long-running session's own
# commits just because they are older than the flat 6h window (t-3004).
#
# Bug (live, thebrana 2026-08-20 and again 2026-08-21, this session's own
# close both times): SESSION_EPICS bounded its search with a flat
# `--since="6 hours ago"`. A session whose own commits landed 6.5h, then 16h,
# before close time fell entirely outside that window: SESSION_EPICS resolved
# empty, so the CLOSE-ANCHOR-BLOCK's epic-scoped LAST_CLOSE filter (below)
# degraded to the orphan-only fallback, landing on a session-state file that
# was weeks stale. COMMIT_COUNT then computed as the entire repo history since
# that stale anchor (679, then 686 commits) instead of the session's actual
# handful. This is exactly the tradeoff t-2784 disclosed as unconfirmed-live
# ("a session running LONGER than 6h ... Not yet observed live; flagged so it
# isn't mistaken for solved") — now confirmed live twice.
#
# Fix: widen SESSION_EPICS's window to the last known close (any epic, i.e.
# UNSCOPED_LAST_CLOSE) whenever that is OLDER than 6h ago — a reasonable proxy
# for how long this session has actually been running. Floored at 6h so a
# NEWER unscoped close (e.g. a concurrent session's) can only widen the
# window, never narrow it below the safe default — narrowing would reintroduce
# the concurrency-collapse class ADR-069 already rejects anchor heuristics for
# (t-2502; see test-close-gate-concurrent-anchor.sh Case A, which exercises
# exactly that narrower-anchor scenario and must keep passing after this fix).
#
# The snippet is EXTRACTED from system/skills/close/phases/gate-and-evidence.md
# so the test exercises the shipped procedure text, not a copy (t-1978 rot class).
#
# Run: bash tests/procedures/test-close-gate-session-epics-duration.sh

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

echo "=== test-close-gate-session-epics-duration.sh ==="
echo ""

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PHASE_MD="$REPO_ROOT/system/skills/close/phases/gate-and-evidence.md"
WALK_MD="$REPO_ROOT/system/skills/_shared/epic-ancestor-walk.md"
[ -f "$PHASE_MD" ] || { echo "ERROR: $PHASE_MD not found"; exit 1; }
[ -f "$WALK_MD" ] || { echo "ERROR: $WALK_MD not found"; exit 1; }

TMPROOT="$(mktemp -d)"
trap 'rm -rf "$TMPROOT"' EXIT

# ── Extract resolve_epic_ancestor() (named marker) — SESSION_EPICS calls it ──
sed -n '/<!-- EPIC-WALK-BLOCK -->/,/<!-- \/EPIC-WALK-BLOCK -->/p' "$WALK_MD" \
    | sed '1d;$d' | sed '/^```/d' > "$TMPROOT/walk.sh"
[ -s "$TMPROOT/walk.sh" ] || { echo "ERROR: EPIC-WALK-BLOCK empty/missing"; exit 1; }

# ── Extract the ```bash block that computes SESSION_EPICS + LAST_CLOSE ──────
sed -n '/<!-- CLOSE-ANCHOR-BLOCK -->/,/<!-- \/CLOSE-ANCHOR-BLOCK -->/p' "$PHASE_MD" \
    | sed '1d;$d' \
    | sed '/^```/d' > "$TMPROOT/step1.sh"

[ -s "$TMPROOT/step1.sh" ] || {
    echo "ERROR: CLOSE-ANCHOR-BLOCK markers missing or empty in $PHASE_MD"; exit 1; }
grep -q 'SESSION_EPICS=' "$TMPROOT/step1.sh" || {
    echo "ERROR: CLOSE-ANCHOR-BLOCK does not set SESSION_EPICS — markers moved?"; exit 1; }
echo "Extracted walk.sh ($(wc -l < "$TMPROOT/walk.sh") lines) + Step 1 anchor block ($(wc -l < "$TMPROOT/step1.sh") lines)"
echo ""

# ── Timeline (mirrors the live 2026-08-21 repro exactly) ─────────────────────
# stale orphan close ........... 3 weeks ago (what the bug falls back to)
# true prior close (own epic) .. 20h ago     (the corroborated session boundary)
# this session's own commits ... 16h ago     (outside flat 6h, inside 20h)
STALE_ORPHAN_TS="$(date -u -d '21 days ago' +%Y-%m-%dT%H:%M:%SZ)"
PRIOR_CLOSE_TS="$(date -u -d '20 hours ago' +%Y-%m-%dT%H:%M:%SZ)"
OWN_COMMIT_DATE="$(date -d '16 hours ago' --iso-8601=seconds)"

# ── Fake `brana` ─────────────────────────────────────────────────────────────
# `session read --all` returns TWO files: a weeks-stale orphan (always
# eligible, what the bug falls back to) and a "knowledge-pipeline"-epic file
# at PRIOR_CLOSE_TS (only eligible once SESSION_EPICS corroborates it — the
# widening anchor this fix wires up). `backlog get` resolves t-600 (this
# session's own commits) to epic "knowledge-pipeline".
mkdir -p "$TMPROOT/bin"
cat > "$TMPROOT/bin/brana" <<'FAKE'
#!/usr/bin/env bash
if [ "$1" = "session" ] && [ "$2" = "read" ]; then
    for a in "$@"; do [ "$a" = "--all" ] && ALL=1; done
    if [ "${ALL:-0}" = "1" ]; then
        cat <<JSON
[
  {"epic":"(orphan)","state":{"written_at":"__STALE_ORPHAN_TS__"}},
  {"epic":"knowledge-pipeline","state":{"written_at":"__PRIOR_CLOSE_TS__","epic":"knowledge-pipeline"}}
]
JSON
    else
        echo '{"written_at":"__STALE_ORPHAN_TS__"}'
    fi
    exit 0
fi
if [ "$1" = "backlog" ] && [ "$2" = "get" ]; then
    id="$3"; field="${5:-}"
    case "$id:$field" in
        t-600:type)    echo '"task"' ;;
        t-600:parent)  echo '"t-2348"' ;;
        t-2348:type)    echo '"epic"' ;;
        t-2348:parent)  echo 'null' ;;
        t-2348:subject) echo '"knowledge-pipeline"' ;;
        *) echo 'null' ;;
    esac
    exit 0
fi
exit 0
FAKE
sed -i "s|__STALE_ORPHAN_TS__|$STALE_ORPHAN_TS|g; s|__PRIOR_CLOSE_TS__|$PRIOR_CLOSE_TS|g" "$TMPROOT/bin/brana"
chmod +x "$TMPROOT/bin/brana"

# ── Fake close-classify.sh (the block pipes into it; unused by this assertion) ─
FAKE_HOME="$TMPROOT/home"
mkdir -p "$FAKE_HOME/.claude/scripts"
printf '#!/usr/bin/env bash\ncat >/dev/null\necho INSTANT\n' \
    > "$FAKE_HOME/.claude/scripts/close-classify.sh"
chmod +x "$FAKE_HOME/.claude/scripts/close-classify.sh"

# ── Fixture repo ─────────────────────────────────────────────────────────────
FIX="$TMPROOT/repo"
mkdir -p "$FIX"
git -C "$FIX" init -q
git -C "$FIX" config user.email t@t.t
git -C "$FIX" config user.name t
for i in 1 2; do
    echo "own$i" >> "$FIX/f.txt"; git -C "$FIX" add -A
    GIT_AUTHOR_DATE="$OWN_COMMIT_DATE" GIT_COMMITTER_DATE="$OWN_COMMIT_DATE" \
        git -C "$FIX" -c commit.gpgsign=false commit -qm "feat(x): own$i (t-600)"
done

# ── Run the extracted block ──────────────────────────────────────────────────
OUT="$(cd "$FIX" && PATH="$TMPROOT/bin:$PATH" HOME="$FAKE_HOME" ARGUMENTS="--continue" \
    bash -c "source '$TMPROOT/walk.sh'; source '$TMPROOT/step1.sh' >/dev/null 2>&1; echo \"\$SESSION_EPICS|\$LAST_CLOSE|\$COMMIT_COUNT\"")"
GOT_EPICS="${OUT%%|*}"
REST="${OUT#*|}"
GOT_ANCHOR="${REST%%|*}"
GOT_COUNT="${REST##*|}"

echo "Long session (16h-old own commits, 20h-old prior close)"
assert_eq "SESSION_EPICS resolves the session's own epic despite being outside the flat 6h window" \
    "knowledge-pipeline" "$GOT_EPICS"
assert_eq "LAST_CLOSE anchors on the corroborated prior close, not a stale/wrong fallback" \
    "$PRIOR_CLOSE_TS" "$GOT_ANCHOR"
assert_eq "COMMIT_COUNT is exactly this session's 2 commits, not an over-reach" \
    "2" "$GOT_COUNT"
echo ""

echo "─────────────────────────────────"
echo "Total: $TOTAL  Pass: $PASS  Fail: $FAIL"
[ "$FAIL" -eq 0 ] || exit 1
