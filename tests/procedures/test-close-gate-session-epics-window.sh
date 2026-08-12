#!/usr/bin/env bash
# Regression test: SESSION_EPICS must not resolve epics from commits outside
# this session's own window (t-2784).
#
# Bug (live, thebrana 2026-08-12, this session's own close): SESSION_EPICS
# computed its candidate epic set via a flat `git log --oneline -20` — a
# commit-COUNT window with no relationship to session boundaries. A low-commit
# session's -20 tail can overflow past its own commits into an unrelated PRIOR
# close's commits, resolving that close's epic as if it were this session's
# own. That epic then wrongly qualifies as "corroborated" for LAST_CLOSE's file
# filter (CLOSE-ANCHOR-BLOCK, below), letting a stale/foreign session-state
# file win the anchor.
#
# SESSION_EPICS cannot anchor on LAST_CLOSE to bound itself (chicken-and-egg:
# it runs to compute the file filter LAST_CLOSE itself depends on). Fix: bound
# by TIME instead of commit count, reusing the same 6h fallback window this
# file's own CLOSE-ANCHOR-BLOCK comment already documents as the first-session
# default — not a new number.
#
# Scope (stated in-code and here, not just in the task): this closes the
# overflow-into-an-older-close failure mode covered by this test. It does NOT
# fix a concurrent session's commits landing on the shared `dev` checkout
# within the same time window — confirmed live twice more (t-2764's close,
# and this session's own close) after this test was written. Per ADR-069
# (D0-D3, not yet shipped), no window — time or count — closes that class;
# only per-commit/per-lane attribution does. See gate-and-evidence.md's
# in-code comment above SESSION_EPICS for the same statement.
#
# The snippet is EXTRACTED from system/skills/close/phases/gate-and-evidence.md
# so the test exercises the shipped procedure text, not a copy (t-1978 rot class).
#
# Run: bash tests/procedures/test-close-gate-session-epics-window.sh

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

echo "=== test-close-gate-session-epics-window.sh ==="
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

# ── Timeline ─────────────────────────────────────────────────────────────────
# old close's commits ....... 30h ago  (belongs to a PRIOR, unrelated close)
# this session's commits .... 1h ago   (the only commits this session made)
# Total commit count = 5, well under a flat -20 window, so the old commits
# would appear in `git log -20` even though they're 30h stale.
OLD_COMMIT_DATE="$(date -d '30 hours ago' --iso-8601=seconds)"
NEW_COMMIT_DATE="$(date -d '1 hour ago' --iso-8601=seconds)"

# ── Fake `brana` ─────────────────────────────────────────────────────────────
# `session read` responses are unused by this assertion but required for the
# block to run without error. `backlog get` resolves t-501 (old, foreign) to
# epic "old-initiative" and t-500 (this session's own) to "brana-v3-redesign".
mkdir -p "$TMPROOT/bin"
cat > "$TMPROOT/bin/brana" <<'FAKE'
#!/usr/bin/env bash
if [ "$1" = "session" ] && [ "$2" = "read" ]; then
    for a in "$@"; do [ "$a" = "--all" ] && ALL=1; done
    if [ "${ALL:-0}" = "1" ]; then
        echo '[{"epic":"(orphan)","state":{"written_at":"2026-08-11T00:00:00Z"}}]'
    else
        echo '{"written_at":"2026-08-11T00:00:00Z"}'
    fi
    exit 0
fi
if [ "$1" = "backlog" ] && [ "$2" = "get" ]; then
    id="$3"; field="${5:-}"
    case "$id:$field" in
        t-501:type)    echo '"task"' ;;
        t-501:parent)  echo '"t-901"' ;;
        t-901:type)    echo '"epic"' ;;
        t-901:parent)  echo 'null' ;;
        t-901:subject) echo '"old-initiative"' ;;
        t-500:type)    echo '"task"' ;;
        t-500:parent)  echo '"t-900"' ;;
        t-900:type)    echo '"epic"' ;;
        t-900:parent)  echo 'null' ;;
        t-900:subject) echo '"brana-v3-redesign"' ;;
        *) echo 'null' ;;
    esac
    exit 0
fi
exit 0
FAKE
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
for i in 1 2 3; do
    echo "old$i" >> "$FIX/f.txt"; git -C "$FIX" add -A
    GIT_AUTHOR_DATE="$OLD_COMMIT_DATE" GIT_COMMITTER_DATE="$OLD_COMMIT_DATE" \
        git -C "$FIX" commit -qm "fix(x): old$i (t-501)"
done
for i in 1 2; do
    echo "new$i" >> "$FIX/f.txt"; git -C "$FIX" add -A
    GIT_AUTHOR_DATE="$NEW_COMMIT_DATE" GIT_COMMITTER_DATE="$NEW_COMMIT_DATE" \
        git -C "$FIX" commit -qm "fix(x): new$i (t-500)"
done

# ── Run the extracted block ──────────────────────────────────────────────────
GOT_EPICS="$(cd "$FIX" && PATH="$TMPROOT/bin:$PATH" HOME="$FAKE_HOME" ARGUMENTS="--continue" \
    bash -c "source '$TMPROOT/walk.sh'; source '$TMPROOT/step1.sh' >/dev/null 2>&1; echo \"\$SESSION_EPICS\"" \
    | tr '\n' ',' | sed 's/,$//')"

echo "SESSION_EPICS window"
echo "  old close's commits: 30h ago (t-501 -> old-initiative)"
echo "  this session's commits: 1h ago (t-500 -> brana-v3-redesign)"
assert_eq "SESSION_EPICS excludes the 30h-old foreign commit's epic" \
    "brana-v3-redesign" "$GOT_EPICS"
echo ""

echo "─────────────────────────────────"
echo "Total: $TOTAL  Pass: $PASS  Fail: $FAIL"
[ "$FAIL" -eq 0 ] || exit 1
