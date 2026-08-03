#!/usr/bin/env bash
# Regression test: a concurrent session's close on an UNRELATED epic must not
# shrink this session's window, even when it is the newest session-state file
# (t-2603).
#
# Bug (live, thebrana 2026-08-02, confirmed 3x same day): the close gate's
# LAST_CLOSE anchor took the max written_at across ALL epic-keyed session-state
# files unconditionally (t-2491's fix for a DIFFERENT bug — an epic-routed close
# left the default file looking stale). That fix over-corrected: a CONCURRENT
# session on a completely unrelated epic that happens to close LATER than this
# one post-dates this session's own commits, and the window collapses. Confirmed
# live: this session made 13 commits; a concurrent close at 14:39:57Z (epic
# "knowledge-pipeline", unrelated to this session's "harness-engineering" work)
# post-dated 11 of them — only the last 2 got queued for extraction.
#
# Fix: LAST_CLOSE only considers a session-state file if its epic is "(orphan)"
# (the default, always a legitimate fallback) OR an epic this session's own
# recent commits actually resolve to (resolve_epic_ancestor, same primitive as
# close/phases/session-state.md Step 9c Tier 2b / t-2618).
#
# Companion to test-close-gate-epic-anchor.sh, which covers the t-2491 case
# (this session's OWN epic-routed close correctly wins). This test covers the
# opposite: a FOREIGN epic's close, however new, must NOT win.
#
# Both blocks are EXTRACTED from the shipped procedure docs (t-1978 rot class),
# not copies.
#
# Run: bash tests/procedures/test-close-gate-foreign-epic.sh

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

echo "=== test-close-gate-foreign-epic.sh ==="
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
grep -q 'SESSION_EPICS=' "$TMPROOT/step1.sh" || { echo "ERROR: CLOSE-ANCHOR-BLOCK does not compute SESSION_EPICS — epic-scoping removed?"; exit 1; }

echo "Extracted walk.sh ($(wc -l < "$TMPROOT/walk.sh") lines) + Step 1 anchor block ($(wc -l < "$TMPROOT/step1.sh") lines)"
echo ""

# ── Timeline ─────────────────────────────────────────────────────────────────
# session's own 11 commits ... now-3h  (this session's real work — harness-engineering)
# FOREIGN close ................ now-10m (a concurrent session, unrelated epic)
# session's own 2 more commits . now-5m  (this session's tail commits)
#
# Bug (pre-fix): LAST_CLOSE = the foreign close's written_at (newest overall),
# so `git log --since=$LAST_CLOSE` only sees the last 2 commits, not all 13.
OWN_COMMIT_DATE="$(date -d '3 hours ago' --iso-8601=seconds)"
FOREIGN_TS="$(date -u -d '10 minutes ago' +%Y-%m-%dT%H:%M:%SZ)"
OWN_TAIL_DATE="$(date -d '5 minutes ago' --iso-8601=seconds)"

mkdir -p "$TMPROOT/bin"
cat > "$TMPROOT/bin/brana" <<FAKE
#!/usr/bin/env bash
if [ "\$1" = "session" ] && [ "\$2" = "read" ]; then
    for a in "\$@"; do [ "\$a" = "--all" ] && ALL=1; done
    if [ "\${ALL:-0}" = "1" ]; then
        cat <<'JSON'
[
  {"epic":"knowledge-pipeline","state":{"written_at":"__FOREIGN_TS__","epic":"knowledge-pipeline"}}
]
JSON
    else
        echo '{"written_at":null}'
    fi
    exit 0
fi
if [ "\$1" = "backlog" ] && [ "\$2" = "get" ]; then
    id="\$3"; field="\${5:-}"
    case "\$id:\$field" in
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
sed -i "s|__FOREIGN_TS__|$FOREIGN_TS|g" "$TMPROOT/bin/brana"
chmod +x "$TMPROOT/bin/brana"

FAKE_HOME="$TMPROOT/home"
mkdir -p "$FAKE_HOME/.claude/scripts"
printf '#!/usr/bin/env bash\ncat >/dev/null\necho INSTANT\n' \
    > "$FAKE_HOME/.claude/scripts/close-classify.sh"
chmod +x "$FAKE_HOME/.claude/scripts/close-classify.sh"

# ── Fixture repo: 11 of this session's own commits, then 2 more ──────────────
# (all reference t-2618, resolving to epic "harness-engineering" — NOT the
# foreign "knowledge-pipeline" epic the concurrent session closed on)
FIX="$TMPROOT/repo"
mkdir -p "$FIX"
git -C "$FIX" init -q
git -C "$FIX" config user.email t@t.t
git -C "$FIX" config user.name t
for i in $(seq 1 11); do
    echo "own$i" >> "$FIX/f.txt"; git -C "$FIX" add -A
    GIT_AUTHOR_DATE="$OWN_COMMIT_DATE" GIT_COMMITTER_DATE="$OWN_COMMIT_DATE" \
        git -C "$FIX" -c commit.gpgsign=false commit -qm "fix(x): own$i (t-2618)"
done
for i in 1 2; do
    echo "tail$i" >> "$FIX/f.txt"; git -C "$FIX" add -A
    GIT_AUTHOR_DATE="$OWN_TAIL_DATE" GIT_COMMITTER_DATE="$OWN_TAIL_DATE" \
        git -C "$FIX" -c commit.gpgsign=false commit -qm "fix(x): tail$i (t-2618)"
done

OUT="$(cd "$FIX" && PATH="$TMPROOT/bin:$PATH" HOME="$FAKE_HOME" ARGUMENTS="--continue" \
    bash -c "source '$TMPROOT/walk.sh'; source '$TMPROOT/step1.sh' 2>\"$TMPROOT/stderr.txt\"; echo \"\$LAST_CLOSE|\$COMMIT_COUNT\"")"
GOT_ANCHOR="${OUT%%|*}"
GOT_COUNT="${OUT##*|}"
STDERR="$(cat "$TMPROOT/stderr.txt" 2>/dev/null)"

echo "Foreign-epic exclusion"
assert_eq "LAST_CLOSE does NOT adopt the foreign close's written_at" "" "$GOT_ANCHOR"
assert_eq "window holds ALL 13 of this session's own commits, not 2" "13" "$GOT_COUNT"
echo ""

echo "Divergence visibility (AC2)"
TOTAL=$((TOTAL + 1))
if echo "$STDERR" | grep -qF "knowledge-pipeline"; then
    echo "  PASS: divergence warning names the excluded foreign epic's state"
    PASS=$((PASS + 1))
else
    echo "  FAIL: expected a divergence warning naming the excluded state — got: [$STDERR]"
    FAIL=$((FAIL + 1))
fi
echo ""

echo "─────────────────────────────────"
echo "Total: $TOTAL  Pass: $PASS  Fail: $FAIL"
[ "$FAIL" -eq 0 ] || exit 1
