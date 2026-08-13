#!/usr/bin/env bash
# Tests for pipeline-digest.sh (t-2823) — L0 Reporter read-only gauge.
#
# The digest is the first loop of the loop-first direction (t-2820 epic):
# a read-only report of pipeline state. AC: (1) digest artifact produced,
# (2) zero write operations against observed pipeline state (git/backlog/inbox).

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
DIGEST_SH="$REPO_ROOT/system/scripts/pipeline-digest.sh"
PASS=0; FAIL=0; TOTAL=0

check() {
    local desc="$1" ok="$2"
    TOTAL=$((TOTAL+1))
    if [ "$ok" = "0" ]; then PASS=$((PASS+1)); echo "  PASS: $desc"
    else FAIL=$((FAIL+1)); echo "  FAIL: $desc"; fi
}

echo "=== pipeline-digest (t-2823) ==="

# T1 — script exists and is executable
[ -x "$DIGEST_SH" ]; check "T1: pipeline-digest.sh exists and is executable" $?
if [ ! -x "$DIGEST_SH" ]; then
    echo ""; echo "$PASS/$TOTAL passed (aborting — script missing)"; exit 1
fi

# --- Fixture: temp git repo with dev base, unmerged branch, merged-stale branch, inbox ---
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
FIX="$TMP/repo"
DIGEST_DIR="$TMP/digest-out"
mkdir -p "$FIX"
git -C "$FIX" init -q -b main
git -C "$FIX" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
git -C "$FIX" branch dev
# unmerged feature branch: 1 ahead of dev
git -C "$FIX" checkout -q -b topic/feat-a dev
echo a > "$FIX/a.txt"; git -C "$FIX" add a.txt
git -C "$FIX" -c user.email=t@t -c user.name=t commit -q -m "feat a"
# merged-stale branch: merged into dev, not deleted
git -C "$FIX" checkout -q -b topic/merged-b dev
echo b > "$FIX/b.txt"; git -C "$FIX" add b.txt
git -C "$FIX" -c user.email=t@t -c user.name=t commit -q -m "feat b"
git -C "$FIX" checkout -q dev
git -C "$FIX" -c user.email=t@t -c user.name=t merge -q --no-ff -m "merge b" topic/merged-b
# inbox with names-only expectation
mkdir -p "$FIX/inbox"
echo "SECRET-CONTENT-MARKER" > "$FIX/inbox/note-1.md"
touch "$FIX/inbox/audio-2.m4a"

# snapshot state before run (read-only verification baseline)
REFS_BEFORE="$(git -C "$FIX" for-each-ref)"
STATUS_BEFORE="$(git -C "$FIX" status --porcelain)"
OBJ_BEFORE=$(find "$FIX/.git/objects" -type f | wc -l)

# T2 — run produces the digest artifact
BRANA_DIGEST_DIR="$DIGEST_DIR" "$DIGEST_SH" "$FIX" >/dev/null 2>&1
check "T2: script exits 0 on fixture repo" $?
[ -s "$DIGEST_DIR/latest.md" ]; check "T2b: latest.md artifact produced" $?

DIGEST="$(cat "$DIGEST_DIR/latest.md" 2>/dev/null || true)"

# T3 — digest carries the four sections
echo "$DIGEST" | grep -q "## Unmerged branches";      check "T3a: unmerged-branches section" $?
echo "$DIGEST" | grep -q "## Stale merged branches";  check "T3b: stale-merged section" $?
echo "$DIGEST" | grep -q "## Inbox";                  check "T3c: inbox section" $?
echo "$DIGEST" | grep -q "## Backlog";                check "T3d: backlog section" $?

# T4 — content assertions
echo "$DIGEST" | grep -q "topic/feat-a";   check "T4a: unmerged branch listed" $?
echo "$DIGEST" | grep -q "topic/merged-b"; check "T4b: merged-stale branch listed" $?
echo "$DIGEST" | grep -q "note-1.md";      check "T4c: inbox item named" $?
! echo "$DIGEST" | grep -q "SECRET-CONTENT-MARKER"; check "T4d: inbox contents never read into digest" $?

# T5 — read-only: repo refs and working tree unchanged
REFS_AFTER="$(git -C "$FIX" for-each-ref)"
STATUS_AFTER="$(git -C "$FIX" status --porcelain)"
[ "$REFS_BEFORE" = "$REFS_AFTER" ];     check "T5a: git refs unchanged after run" $?
[ "$STATUS_BEFORE" = "$STATUS_AFTER" ]; check "T5b: working tree unchanged after run" $?

# T6 — static guard: no mutating git subcommands in the script source
! grep -nE 'git[^|;&]*\b(commit|merge|rebase|push|reset|checkout|switch|clean|stash)\b' "$DIGEST_SH" \
    | grep -vE '^\s*#|merge-base|merge-tree' | grep -q .
check "T6: no mutating git subcommands in script source" $?

# T7 — history line appended per beat (two runs -> two lines);
#      second identical run prints a short no-change line, not the full digest
OUT2="$(BRANA_DIGEST_DIR="$DIGEST_DIR" "$DIGEST_SH" "$FIX" 2>/dev/null)"
LINES=$(wc -l < "$DIGEST_DIR/history.jsonl" 2>/dev/null || echo 0)
[ "$LINES" -eq 2 ]; check "T7: history.jsonl has one line per run" $?
echo "$OUT2" | grep -q "no change"; check "T7b: unchanged beat prints no-change line" $?
[ "$(printf '%s\n' "$OUT2" | wc -l)" -le 3 ]; check "T7c: unchanged beat output is short (no full digest)" $?

# T7d — loose-object count unchanged (merge-tree probe must not write into
#       the observed repo's object store — challenger finding 1)
OBJ_AFTER=$(find "$FIX/.git/objects" -type f | wc -l)
[ "$OBJ_BEFORE" -eq "$OBJ_AFTER" ]; check "T7d: no objects written into observed repo" $?

# T8 — boundary: missing inbox dir does not fail the beat
rm -rf "$FIX/inbox"
BRANA_DIGEST_DIR="$DIGEST_DIR" "$DIGEST_SH" "$FIX" >/dev/null 2>&1
check "T8: exits 0 with no inbox dir" $?

# T9 — boundary: brana CLI absent -> backlog section degrades, beat still succeeds
PATH="/usr/bin:/bin" BRANA_DIGEST_DIR="$DIGEST_DIR" "$DIGEST_SH" "$FIX" >/dev/null 2>&1
check "T9: exits 0 without brana on PATH" $?

echo ""; echo "$PASS/$TOTAL passed"
[ "$FAIL" -eq 0 ] || exit 1
