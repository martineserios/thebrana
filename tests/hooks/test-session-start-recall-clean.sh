#!/usr/bin/env bash
# The session-start hook injects `brana recall --json` text into session context. Slugs and snippets come
# from note files, so control and format characters (escape sequences, bidi overrides, zero-width, the
# Unicode tag block) must be dropped before injection (t-3540). Runs the filter the hook uses, and checks the hook uses it.
# Run: bash tests/hooks/test-session-start-recall-clean.sh
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
FILTER="${RECALL_CLEAN_JQ:-$ROOT/system/hooks/lib/recall-clean.jq}"   # override only for mutation testing
PASS=0; FAIL=0
assert() { if [ "$2" = "$3" ]; then PASS=$((PASS+1)); echo "  PASS: $1"; else FAIL=$((FAIL+1)); echo "  FAIL: $1 (expected '$2', got '$3')"; fi; }
echo "=== test-session-start-recall-clean.sh ==="
command -v jq >/dev/null || { echo "  SKIP: jq missing"; exit 0; }

grep -q 'lib/recall-clean.jq' "$ROOT/system/hooks/session-start.sh" && r=ok || r=missing
assert "hook uses the filter file" "ok" "$r"
run_block() { printf '%s' "$1" | jq -r -f "$FILTER"; }

# Hostile note: ESC sequence, BEL, bidi override, zero-width space, tag-block char, newline in the snippet.
RAW=$(jq -cn '[{doc:{MemoryFile:{slug:"s\u001b[31mlug‮",mtype:"t",scope:"p",path:"/x"}},
  snippet:"one\u0007\ntwo​ \u001b]0;pwned\u0007 󠁁end", rrf_score:0.5}]')
OUT=$(run_block "$RAW")
BAD=$(printf '%s' "$OUT" | LC_ALL=C grep -c -P '[\x00-\x08\x0b-\x1f\x7f]|\xe2\x80[\x8b-\x8f\xa8-\xae]|\xf3\xa0[\x80-\x81]' || true)
assert "no control, bidi, zero-width or tag characters survive" "0" "$BAD"
assert "output stays one line per hit" "1" "$(printf '%s\n' "$OUT" | wc -l | tr -d ' ')"
case "$OUT" in "- s[31mlug: one two ]0;pwned end") PASS=$((PASS+1)); echo "  PASS: readable text kept";;
  *) FAIL=$((FAIL+1)); echo "  FAIL: readable text kept (got '$OUT')";; esac

# A plain note is untouched.
OUT=$(run_block '[{"doc":{"KnowledgeEntry":{"key":"k1","namespace":"n"}},"snippet":"plain text","rrf_score":0.1}]')
assert "plain hit unchanged" "- k1: plain text" "$OUT"

echo "Results: $PASS passed, $FAIL failed"; [ "$FAIL" -eq 0 ]
