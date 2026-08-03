#!/usr/bin/env bash
# Regression test: the close gate's LAST_CLOSE anchor must see epic-keyed session
# state, not just the default session-state.json (t-2491).
#
# Bug (live, thebrana 2026-07-27, on a second /brana:close --continue in one session):
# Step 1 anchored the window with `brana session read --json`, which reads ONLY the
# default session-state.json. But when the previous close set an epic (Step 9c),
# `brana session write` routes the handoff to the epic-keyed file instead. The
# default file kept its older written_at, so LAST_CLOSE came back ~2.5h stale and
# COMMIT_COUNT was 32 instead of the real 4.
#
# Blast radius of the stale anchor:
#   - Step 1b's snapshot range re-queues commits an earlier close already queued.
#     close-snapshot.sh dedups on the RANGE STRING, so a different range is NOT
#     deduped and the same work gets extracted twice.
#   - CHANGED_FILES drives weight classification off the wrong diff.
#   - Step 9c's COMPLETED accumulator over-reaches.
#
# Note the perverse incentive this removes: the more faithfully a close followed
# Step 9c (setting the epic so the handoff lands in its unit bucket, ADR-060/t-2154),
# the more certainly it broke the NEXT close's anchor. Every epic-routed close
# poisoned the following one.
#
# Updated for t-2603: the anchor is now epic-SCOPED — only session-state files
# whose epic this session's own recent commits resolve to (or the orphan/default
# file) are eligible. So this fixture's "new" commits now reference a task ID
# that resolves (via the faked `brana backlog get`) to "brana-v3-redesign",
# corroborating that epic file as genuinely this session's own — matching the
# real 2026-07-27 incident, where the epic-routed close and this session were
# the same initiative. See test-close-gate-foreign-epic.sh for the t-2603
# counter-case: an epic-keyed file that is NOT corroborated by this session's
# own commits must NOT win, even if it is the newest.
#
# The snippet is EXTRACTED from system/skills/close/phases/gate-and-evidence.md so
# the test exercises the shipped procedure text, not a copy (t-1978 rot class).
#
# Run: bash tests/procedures/test-close-gate-epic-anchor.sh

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

echo "=== test-close-gate-epic-anchor.sh ==="
echo ""

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PHASE_MD="$REPO_ROOT/system/skills/close/phases/gate-and-evidence.md"
WALK_MD="$REPO_ROOT/system/skills/_shared/epic-ancestor-walk.md"
[ -f "$PHASE_MD" ] || { echo "ERROR: $PHASE_MD not found"; exit 1; }
[ -f "$WALK_MD" ] || { echo "ERROR: $WALK_MD not found"; exit 1; }

TMPROOT="$(mktemp -d)"
trap 'rm -rf "$TMPROOT"' EXIT

# ── Extract resolve_epic_ancestor() (named marker, t-2493) — the anchor block
# calls it as of t-2603's epic-scoped corroboration ─────────────────────────
sed -n '/<!-- EPIC-WALK-BLOCK -->/,/<!-- \/EPIC-WALK-BLOCK -->/p' "$WALK_MD" \
    | sed '1d;$d' | sed '/^```/d' > "$TMPROOT/walk.sh"
[ -s "$TMPROOT/walk.sh" ] || { echo "ERROR: EPIC-WALK-BLOCK empty/missing"; exit 1; }

# ── Extract the ```bash block that computes LAST_CLOSE ────────────────────────
# Extract by NAMED MARKER (t-2493) — prose and comments can contain any content
# substring a selector might key on, so named anchors are the only stable handle.
sed -n '/<!-- CLOSE-ANCHOR-BLOCK -->/,/<!-- \/CLOSE-ANCHOR-BLOCK -->/p' "$PHASE_MD" \
    | sed '1d;$d' \
    | sed '/^```/d' > "$TMPROOT/step1.sh"

[ -s "$TMPROOT/step1.sh" ] || {
    echo "ERROR: CLOSE-ANCHOR-BLOCK markers missing or empty in $PHASE_MD"; exit 1; }
grep -q 'LAST_CLOSE=' "$TMPROOT/step1.sh" || {
    echo "ERROR: CLOSE-ANCHOR-BLOCK does not set LAST_CLOSE — markers moved?"; exit 1; }
echo "Extracted walk.sh ($(wc -l < "$TMPROOT/walk.sh") lines) + Step 1 anchor block ($(wc -l < "$TMPROOT/step1.sh") lines)"
echo ""

# ── Timeline ─────────────────────────────────────────────────────────────────
# stale default close ....... now-4h   (what the buggy anchor used)
# 3 commits ................. now-3h   (already queued by the earlier close)
# epic-routed close ......... now-2h   (the REAL anchor — newest session state)
# 2 commits ................. now-1h   (the only commits this close should see)
STALE_TS="$(date -u -d '4 hours ago' +%Y-%m-%dT%H:%M:%SZ)"
EPIC_TS="$(date -u -d '2 hours ago' +%Y-%m-%dT%H:%M:%S.123456789+00:00)"
OLD_COMMIT_DATE="$(date -d '3 hours ago' --iso-8601=seconds)"
NEW_COMMIT_DATE="$(date -d '1 hour ago' --iso-8601=seconds)"

# ── Fake `brana` ─────────────────────────────────────────────────────────────
# Mirrors the real shapes: `session read --json` returns the DEFAULT state object;
# `session read --all --json` returns [{epic, state}], with the default file
# surfacing as epic "(orphan)". `backlog get t-500 --field ...` resolves this
# session's own commits (see fixture below) to epic "brana-v3-redesign" — the
# t-2603 corroboration signal.
mkdir -p "$TMPROOT/bin"
cat > "$TMPROOT/bin/brana" <<FAKE
#!/usr/bin/env bash
if [ "\$1" = "session" ] && [ "\$2" = "read" ]; then
    for a in "\$@"; do [ "\$a" = "--all" ] && ALL=1; done
    if [ "\${ALL:-0}" = "1" ]; then
        cat <<'JSON'
[
  {"epic":"brana-v3-redesign","state":{"written_at":"__EPIC_TS__","epic":"brana-v3-redesign"}},
  {"epic":"(orphan)","state":{"written_at":"__STALE_TS__"}},
  {"epic":"retrieval","state":{"written_at":"2026-07-19T15:20:32.720816342+00:00"}}
]
JSON
    else
        echo '{"written_at":"__STALE_TS__"}'
    fi
    exit 0
fi
if [ "\$1" = "backlog" ] && [ "\$2" = "get" ]; then
    id="\$3"; field="\${5:-}"
    case "\$id:\$field" in
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
sed -i "s|__EPIC_TS__|$EPIC_TS|g; s|__STALE_TS__|$STALE_TS|g" "$TMPROOT/bin/brana"
chmod +x "$TMPROOT/bin/brana"

# ── Fake close-classify.sh (the block pipes into it; we only assert the anchor) ─
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
        git -C "$FIX" commit -qm "old$i"
done
for i in 1 2; do
    echo "new$i" >> "$FIX/f.txt"; git -C "$FIX" add -A
    GIT_AUTHOR_DATE="$NEW_COMMIT_DATE" GIT_COMMITTER_DATE="$NEW_COMMIT_DATE" \
        git -C "$FIX" commit -qm "fix(x): new$i (t-500)"
done

# ── Run the extracted block ──────────────────────────────────────────────────
OUT="$(cd "$FIX" && PATH="$TMPROOT/bin:$PATH" HOME="$FAKE_HOME" ARGUMENTS="--continue" \
    bash -c "source '$TMPROOT/walk.sh'; source '$TMPROOT/step1.sh' >/dev/null 2>&1; echo \"\$LAST_CLOSE|\$COMMIT_COUNT\"")"
GOT_ANCHOR="${OUT%%|*}"
GOT_COUNT="${OUT##*|}"

echo "Anchor resolution"
assert_eq "LAST_CLOSE is the newest state across ALL files, not the default" \
    "$EPIC_TS" "$GOT_ANCHOR"
echo ""

echo "Two-close repro (AC2)"
echo "  stale default=$STALE_TS  epic=$EPIC_TS"
assert_eq "window holds only the 2 commits since the epic-routed close (not 5)" \
    "2" "$GOT_COUNT"
echo ""

echo "─────────────────────────────────"
echo "Total: $TOTAL  Pass: $PASS  Fail: $FAIL"
[ "$FAIL" -eq 0 ] || exit 1
