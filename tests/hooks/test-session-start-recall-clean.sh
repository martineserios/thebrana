#!/usr/bin/env bash
# The session-start hook injects `brana recall --json` text into session context. Slugs and snippets come
# from note files, so control and format characters (escape sequences, bidi overrides, zero-width, the
# Unicode tag block) must be dropped before injection (t-3540). Runs the filter the hook uses, and checks the hook uses it.
# Run: bash tests/hooks/test-session-start-recall-clean.sh
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
LIB="${HOOK_LIB:-$ROOT/system/hooks/lib}"   # override only for mutation testing
FILTER="$LIB/recall-clean.jq"
PASS=0; FAIL=0
assert() { if [ "$2" = "$3" ]; then PASS=$((PASS+1)); echo "  PASS: $1"; else FAIL=$((FAIL+1)); echo "  FAIL: $1 (expected '$2', got '$3')"; fi; }
echo "=== test-session-start-recall-clean.sh ==="
command -v jq >/dev/null || { echo "  SKIP: jq missing"; exit 0; }

HOOK="$ROOT/system/hooks/session-start.sh"
for f in recall-clean cf-context cf-corrections; do
  grep -q "lib/$f.jq" "$HOOK" && r=ok || r=missing; assert "hook uses lib/$f.jq" "ok" "$r"
done
grep -q "include \"clean\"; clean" "$HOOK" && r=ok || r=missing; assert "MEMORY.md fallback is cleaned" "ok" "$r"
run_block() { printf '%s' "$1" | jq -r -L "$LIB" -f "$FILTER"; }

# Hostile note: ESC sequence, BEL, bidi override, zero-width space, tag-block char, newline in the snippet.
RAW=$(jq -cn '[{doc:{MemoryFile:{slug:"s\u001b[31mlug‮",mtype:"t",scope:"p",path:"/x"}},
  snippet:"one\u0007\ntwo​ \u001b]0;pwned\u0007 󠁁end", rrf_score:0.5}]')
OUT=$(run_block "$RAW")
assert "output stays one line per hit" "1" "$(printf '%s\n' "$OUT" | wc -l | tr -d ' ')"
case "$OUT" in "- s[31mlug: one two ]0;pwned end") PASS=$((PASS+1)); echo "  PASS: readable text kept";;
  *) FAIL=$((FAIL+1)); echo "  FAIL: readable text kept (got '$OUT')";; esac

# A plain note is untouched.
OUT=$(run_block '[{"doc":{"KnowledgeEntry":{"key":"k1","namespace":"n"}},"snippet":"plain text","rrf_score":0.1}]')
assert "plain hit unchanged" "- k1: plain text" "$OUT"

# Job 1 (ruflo pattern stream) and corrections: same hostile text in key and preview.
CF=$(jq -cn '{results:[{key:"correction\u001b[2J-x\u202e",score:0.5,preview:"a\nb\u200b\u001b]0;t\u0007 c"},{key:"k2",score:0.31,preview:"ok"}]}')
OUT=$(printf '%s' "$CF" | jq -r -L "$LIB" -f "$LIB/cf-context.jq")
assert "cf-context: two clean lines" "2" "$(printf '%s\n' "$OUT" | wc -l | tr -d ' ')"
assert "cf-context: hostile text cleaned" "- correction[2J-x (score 0.5): a b]0;t c" "$(printf '%s\n' "$OUT" | head -1)"
OUT=$(printf '%s' "$CF" | jq -r -L "$LIB" -f "$LIB/cf-corrections.jq")
assert "cf-corrections: hostile text cleaned, one line" "correction[2J-x: a b]0;t c" "$OUT"
# MEMORY.md fallback: the same clean applied per line.
OUT=$(printf 'proj \033[31mred\xe2\x80\xaex\n' | jq -Rr -L "$LIB" 'include "clean"; clean')
assert "memory fallback line cleaned" "proj [31mredx" "$OUT"

echo "Results: $PASS passed, $FAIL failed"; [ "$FAIL" -eq 0 ]
