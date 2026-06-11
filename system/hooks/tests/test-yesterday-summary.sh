#!/usr/bin/env bash
# Tests: [Yesterday] daily-summary surfacing in session-start.sh (t-1975, ADR-052).
# Pure read of ~/.claude/sessions/daily-summary-{today|yesterday}.md — silent
# when absent/empty, never blocks startup.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$SCRIPT_DIR/../session-start.sh"
PASS=0; FAIL=0; TOTAL=0
TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

SAFE_PATH="/usr/bin:/bin:/usr/sbin:/sbin"
GIT_BIN="$(dirname "$(command -v git)")"
JQ_BIN="$(dirname "$(command -v jq)")"
[[ ":$SAFE_PATH:" != *":$GIT_BIN:"* ]] && SAFE_PATH="$GIT_BIN:$SAFE_PATH"
[[ ":$SAFE_PATH:" != *":$JQ_BIN:"* ]] && SAFE_PATH="$JQ_BIN:$SAFE_PATH"

setup_repo() {
    local dir="$1"; mkdir -p "$dir"
    git -C "$dir" init -q -b main
    git -C "$dir" config user.email t@t.com; git -C "$dir" config user.name T
    echo i > "$dir/README.md"; git -C "$dir" add -A && git -C "$dir" commit -qm init
}
make_home() { mkdir -p "$1/.claude/projects/fake/memory" "$1/.claude/sessions"; echo "# M" > "$1/.claude/projects/fake/memory/MEMORY.md"; }

run_hook() {
    local cwd="$1" home="$2"
    printf '{"session_id":"ys-%s","cwd":"%s","hook_event_name":"SessionStart","matcher":{}}' "$(date +%s%N)" "$cwd" | \
        PATH="$SAFE_PATH" HOME="$home" \
        CLAUDE_PLUGIN_DATA="" CLAUDE_PLUGIN_ROOT="" CLAUDE_ENV_FILE="" \
        BRANA_RECAP_OFF=1 BRANA_1M_WARN_OFF=1 BRANA_HOOK_PROFILE=standard \
        bash "$HOOK" 2>/dev/null | grep -E '^\{' | head -1
}

ctx() { echo "$1" | jq -r '.additionalContext // ""' 2>/dev/null; }

assert_has() {
    local desc="$1" pat="$2" out="$3"; TOTAL=$((TOTAL+1))
    if ctx "$out" | grep -qi "$pat"; then echo "  PASS: $desc"; PASS=$((PASS+1)); else echo "  FAIL: $desc (missing: $pat)"; FAIL=$((FAIL+1)); fi
}
assert_not() {
    local desc="$1" pat="$2" out="$3"; TOTAL=$((TOTAL+1))
    if ctx "$out" | grep -qi "$pat"; then echo "  FAIL: $desc (unexpected: $pat)"; FAIL=$((FAIL+1)); else echo "  PASS: $desc"; PASS=$((PASS+1)); fi
}

REPO="$TMPDIR/repo"; setup_repo "$REPO"
TODAY=$(date +%F)
YESTERDAY=$(date -d yesterday +%F)

SUMMARY_BODY='## thebrana feat/x (a..b) — entry q-1
- [pattern/LARGE] Sidecar locks beat inode locks: rename replaces inode.
- [errata/SMALL] validate flag renamed: --check is now --verify.
## thebrana feat/y (c..d) — entry q-2
- [field-note/SMALL] tmpfs mv not atomic: use same-dir tmp.
'

# 1. today's summary → [Yesterday] line with counts + path
H1="$TMPDIR/h1"; make_home "$H1"
printf '%s' "$SUMMARY_BODY" > "$H1/.claude/sessions/daily-summary-$TODAY.md"
OUT=$(run_hook "$REPO" "$H1")
assert_has "summary surfaces" "\[Yesterday\]" "$OUT"
assert_has "learning count present" "3 learning" "$OUT"
assert_has "summary path present" "daily-summary-$TODAY.md" "$OUT"

# 2. only yesterday's file → still surfaces (fallback)
H2="$TMPDIR/h2"; make_home "$H2"
printf '%s' "$SUMMARY_BODY" > "$H2/.claude/sessions/daily-summary-$YESTERDAY.md"
OUT=$(run_hook "$REPO" "$H2")
assert_has "yesterday fallback surfaces" "daily-summary-$YESTERDAY.md" "$OUT"

# 3. both exist → today wins
H3="$TMPDIR/h3"; make_home "$H3"
printf '%s' "$SUMMARY_BODY" > "$H3/.claude/sessions/daily-summary-$TODAY.md"
echo "- [pattern/SMALL] old" > "$H3/.claude/sessions/daily-summary-$YESTERDAY.md"
OUT=$(run_hook "$REPO" "$H3")
assert_has "today preferred over yesterday" "daily-summary-$TODAY.md" "$OUT"

# 4. no summary → silent
H4="$TMPDIR/h4"; make_home "$H4"
OUT=$(run_hook "$REPO" "$H4")
assert_not "absent file is silent" "\[Yesterday\]" "$OUT"

# 5. empty file → silent, output still valid JSON
H5="$TMPDIR/h5"; make_home "$H5"
: > "$H5/.claude/sessions/daily-summary-$TODAY.md"
OUT=$(run_hook "$REPO" "$H5")
assert_not "empty file is silent" "\[Yesterday\]" "$OUT"
TOTAL=$((TOTAL+1))
if echo "$OUT" | jq -e '.continue == true' >/dev/null 2>&1; then echo "  PASS: valid JSON with empty summary"; PASS=$((PASS+1)); else echo "  FAIL: valid JSON with empty summary"; FAIL=$((FAIL+1)); fi

# 6. summary with zero learning lines → surfaces path without bogus count
H6="$TMPDIR/h6"; make_home "$H6"
printf '## proj branch (a..b) — entry q-9\n- no notable learnings\n' > "$H6/.claude/sessions/daily-summary-$TODAY.md"
OUT=$(run_hook "$REPO" "$H6")
assert_has "no-learnings summary still surfaces" "\[Yesterday\]" "$OUT"
assert_not "no bogus learning count" "0 learnings" "$OUT"

echo ""
echo "test-yesterday-summary: $PASS/$TOTAL passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
