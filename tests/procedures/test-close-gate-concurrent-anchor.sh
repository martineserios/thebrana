#!/usr/bin/env bash
# Regression test (t-2502, visibility slice): a CONCURRENT session's close that
# post-dates this session's commits must never SILENTLY collapse the window, and
# a window whose commits resolve to several epics must say so.
#
# Bug (live, recorded 7+ times in t-2502 between 2026-07-27 and 2026-08-17):
# LAST_CLOSE is a wall-clock proxy for "when did THIS session last close", but
# the session store carries no lane identity (ADR-069), so any file every
# session may legitimately anchor on — the default "(orphan)" file, or a
# same-epic peer's file — can be written by a DIFFERENT concurrent session
# minutes ago. Two silent failure shapes follow:
#
#   (a) ZERO WINDOW: the foreign close post-dates ALL of this session's commits,
#       COMMIT_COUNT comes back 0, CHANGED_FILES becomes a null diff, and Step
#       1b's snapshot exits without queueing anything — the session's work is
#       never extracted and nothing says so (2026-07-28, 2026-07-31, 2026-08-01,
#       all live). Step 1's genuine read-only shortcut is decided by the
#       wall-clock 6h listing, so a truncated anchor never reaches it — the loss
#       is silent, not misrouted.
#   (b) OVER-REACH: on the shared `dev` checkout the window contains other
#       lanes' commits; SESSION_EPICS resolving to several epics is the visible
#       symptom (2026-08-17 live: 4 epics, 24 commits, 2 own).
#
# No anchor heuristic fixes either half (ADR-069 Rejected: "epic-scoped close
# anchor — the category error in smaller form"; three withdrawn proposals in
# t-2502's own record). The reachable win, per ADR-069 D3, is VISIBILITY: the
# block must (a) flag an empty window that has a live anchor while commits
# exist nearby, naming the anchor's source so the closer can judge, and set
# ANCHOR_ZERO_WINDOW=1 for downstream consumers (session-state.md Tier0
# corroboration reuses the same anchor and reads the flag);
# (b) warn when SESSION_EPICS spans more than one epic. Neither guard may fire
# on a clean single-epic window, and (a) must stay quiet on a genuinely
# read-only session (no commits at all in the fallback window).
#
# The anchor block is EXTRACTED from the shipped procedure doc (t-1978 rot
# class), not copied. Companion tests: test-close-gate-epic-anchor.sh (t-2491),
# test-close-gate-foreign-epic.sh (t-2603).
#
# Run: bash tests/procedures/test-close-gate-concurrent-anchor.sh

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

echo "=== test-close-gate-concurrent-anchor.sh ==="
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

echo "Extracted walk.sh ($(wc -l < "$TMPROOT/walk.sh") lines) + Step 1 anchor block ($(wc -l < "$TMPROOT/step1.sh") lines)"
echo ""

FAKE_HOME="$TMPROOT/home"
mkdir -p "$FAKE_HOME/.claude/scripts"
printf '#!/usr/bin/env bash\ncat >/dev/null\necho INSTANT\n' \
    > "$FAKE_HOME/.claude/scripts/close-classify.sh"
chmod +x "$FAKE_HOME/.claude/scripts/close-classify.sh"

# Fake brana: `session read --all --json` returns $SESSIONS_JSON (per case);
# `backlog get` resolves t-2618 -> epic harness-engineering, t-2826 -> loop-first.
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
        t-2826:type)    echo '"task"' ;;
        t-2826:parent)  echo '"t-2700"' ;;
        t-2700:type)    echo '"epic"' ;;
        t-2700:parent)  echo 'null' ;;
        t-2700:subject) echo '"loop-first"' ;;
        *) echo 'null' ;;
    esac
    exit 0
fi
exit 0
FAKE
chmod +x "$TMPROOT/bin/brana"

# run_block <repo> <sessions_json>  →  prints "LAST_CLOSE|COMMIT_COUNT|ANCHOR_ZERO_WINDOW"; stderr in $TMPROOT/stderr.txt
run_block() {
    local repo="$1" sessions="$2"
    (cd "$repo" && PATH="$TMPROOT/bin:$PATH" HOME="$FAKE_HOME" ARGUMENTS="--continue" \
        SESSIONS_JSON="$sessions" \
        bash -c "source '$TMPROOT/walk.sh'; source '$TMPROOT/step1.sh' 2>\"$TMPROOT/stderr.txt\"; echo \"\${LAST_CLOSE}|\${COMMIT_COUNT}|\${ANCHOR_ZERO_WINDOW:-0}\"")
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

OWN_TS_ISO="$(date -d '40 minutes ago' --iso-8601=seconds)"
OWN_CLOSE_TS="$(date -u -d '2 hours ago' +%Y-%m-%dT%H:%M:%SZ)"       # this session's own previous close
FOREIGN_TS="$(date -u -d '5 minutes ago' +%Y-%m-%dT%H:%M:%SZ)"       # concurrent lane closes AFTER our commits

# ── Case A: zero window — concurrent ORPHAN close post-dates all own commits ──
# Timeline: own close (2h ago, epic harness-engineering) → own commits (40m ago,
# t-2618) → concurrent session writes the default/orphan file (5m ago).
# The orphan file is always an eligible anchor, so LAST_CLOSE = FOREIGN_TS and
# `--since` matches nothing. Pre-fix: COMMIT_COUNT=0, silence, read-only.
echo "Case A — zero window from a concurrent orphan close (2026-07-28 live shape)"
REPO_A="$TMPROOT/repo-a"; mk_repo "$REPO_A"
for i in 1 2 3; do commit_at "$REPO_A" "$OWN_TS_ISO" "fix(x): own$i (t-2618)"; done
SESS_A="[
  {\"epic\":\"harness-engineering\",\"state\":{\"written_at\":\"$OWN_CLOSE_TS\",\"epic\":\"harness-engineering\"}},
  {\"epic\":\"(orphan)\",\"state\":{\"written_at\":\"$FOREIGN_TS\"}}
]"
OUT="$(run_block "$REPO_A" "$SESS_A")"
IFS='|' read -r A_ANCHOR A_COUNT A_ZERO <<< "$OUT"
STDERR_A="$(cat "$TMPROOT/stderr.txt" 2>/dev/null)"
assert_eq "anchor resolves to the concurrent orphan close (the bug's precondition)" "$FOREIGN_TS" "$A_ANCHOR"
assert_eq "window is empty (COMMIT_COUNT=0) — the bug reproduces" "0" "$A_COUNT"
assert_eq "ANCHOR_ZERO_WINDOW=1 is set so Step 1 cannot silently go read-only" "1" "$A_ZERO"
assert_contains "warning names the anchor's source ((orphan))" "(orphan)" "$STDERR_A"
assert_contains "warning says the window is empty / truncated" "EMPTY" "$STDERR_A"
assert_contains "warning names the recovery lever (--git-range)" "--git-range" "$STDERR_A"
assert_contains "warning names the task so the closer does not re-file it" "t-2502" "$STDERR_A"
echo ""

# ── Case B: multi-epic window — shared checkout holds two lanes' commits ─────
echo "Case B — window spans two epics (2026-08-17 live shape)"
REPO_B="$TMPROOT/repo-b"; mk_repo "$REPO_B"
commit_at "$REPO_B" "$OWN_TS_ISO" "fix(x): own1 (t-2618)"
commit_at "$REPO_B" "$OWN_TS_ISO" "feat(y): peer lane (t-2826)"
commit_at "$REPO_B" "$OWN_TS_ISO" "fix(x): own2 (t-2618)"
SESS_B="[
  {\"epic\":\"harness-engineering\",\"state\":{\"written_at\":\"$OWN_CLOSE_TS\",\"epic\":\"harness-engineering\"}}
]"
OUT="$(run_block "$REPO_B" "$SESS_B")"
IFS='|' read -r B_ANCHOR B_COUNT B_ZERO <<< "$OUT"
STDERR_B="$(cat "$TMPROOT/stderr.txt" 2>/dev/null)"
assert_eq "window holds all 3 commits (own + peer — the over-reach)" "3" "$B_COUNT"
assert_eq "no zero-window flag on a non-empty window" "0" "$B_ZERO"
assert_contains "over-reach warning fires and names the first epic" "harness-engineering" "$STDERR_B"
assert_contains "over-reach warning names the second epic" "loop-first" "$STDERR_B"
assert_contains "over-reach warning says the window spans several epics" "spans 2 epics" "$STDERR_B"
echo ""

# ── Case C: clean single-epic window — no noise ─────────────────────────────
echo "Case C — clean single-epic non-empty window: neither guard fires"
REPO_C="$TMPROOT/repo-c"; mk_repo "$REPO_C"
for i in 1 2; do commit_at "$REPO_C" "$OWN_TS_ISO" "fix(x): own$i (t-2618)"; done
OUT="$(run_block "$REPO_C" "$SESS_B")"
IFS='|' read -r C_ANCHOR C_COUNT C_ZERO <<< "$OUT"
STDERR_C="$(cat "$TMPROOT/stderr.txt" 2>/dev/null)"
assert_eq "window holds both own commits" "2" "$C_COUNT"
assert_eq "no zero-window flag" "0" "$C_ZERO"
assert_not_contains "no over-reach warning on a single epic" "spans" "$STDERR_C"
assert_not_contains "no zero-window warning on a non-empty window" "EMPTY" "$STDERR_C"
echo ""

# ── Case D: genuinely read-only — no commits at all in the fallback window ───
echo "Case D — genuinely read-only session: zero-window guard stays quiet"
REPO_D="$TMPROOT/repo-d"; mk_repo "$REPO_D"
OLD_TS_ISO="$(date -d '2 days ago' --iso-8601=seconds)"
commit_at "$REPO_D" "$OLD_TS_ISO" "chore: ancient (t-2618)"
OUT="$(run_block "$REPO_D" "$SESS_A")"
IFS='|' read -r D_ANCHOR D_COUNT D_ZERO <<< "$OUT"
STDERR_D="$(cat "$TMPROOT/stderr.txt" 2>/dev/null)"
assert_eq "window is empty" "0" "$D_COUNT"
assert_eq "no zero-window flag when there are no recent commits to have been truncated" "0" "$D_ZERO"
assert_not_contains "no EMPTY warning on a truly read-only session" "EMPTY" "$STDERR_D"
echo ""

echo "─────────────────────────────────"
echo "Total: $TOTAL  Pass: $PASS  Fail: $FAIL"
[ "$FAIL" -eq 0 ] || exit 1
