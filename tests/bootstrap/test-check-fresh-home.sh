#!/usr/bin/env bash
# bootstrap.sh --check on a FRESH machine (empty HOME) must run to its summary and exit 0 (t-3385).
# A new machine runs `--check` FIRST, and it used to die silently with exit 2: it ran `jq` on
# ~/.claude/plugins/known_marketplaces.json before anything had created it, jq exits 2 for a missing
# file, and `set -e` made that the script's exit status — no message at all. Found by the first real
# macOS CI run; the real (non-check) run creates the file first, so only the dry run was broken.
# Run: bash tests/bootstrap/test-check-fresh-home.sh
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
PASS=0; FAIL=0
assert() { if [ "$2" = "$3" ]; then PASS=$((PASS+1)); echo "  PASS: $1"; else FAIL=$((FAIL+1)); echo "  FAIL: $1 (expected '$2', got '$3')"; fi; }
has() { case "$2" in *"$1"*) echo yes;; *) echo no;; esac; }
echo "=== test-check-fresh-home.sh ==="
H="$(mktemp -d)"; trap 'rm -rf "$H"' EXIT
OUT="$(cd "$ROOT" && HOME="$H" BRANA_SCHEDULER_BACKEND=none ./bootstrap.sh --check 2>&1)"; RC=$?
assert "--check on an empty HOME exits 0 (changes pending is not an error)" 0 "$RC"
assert "--check reaches its summary line" yes "$(has 'change(s) detected' "$OUT")"
assert "--check on an empty HOME created nothing under HOME (it is a dry run)" "" "$(find "$H" -type f 2>/dev/null | head -1)"
echo; echo "Results: $PASS passed, $FAIL failed"; [ "$FAIL" -eq 0 ]
