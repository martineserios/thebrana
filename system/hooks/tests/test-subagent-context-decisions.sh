#!/usr/bin/env bash
# Tests the decisions block of subagent-context.sh (t-1939, hardened t-3357) with a stub brana.
HOOK="$(cd "$(dirname "$0")/.." && pwd)/subagent-context.sh"
PASS=0; FAIL=0
ok()  { echo "  PASS: $1"; PASS=$((PASS + 1)); }
bad() { echo "  FAIL: $1"; FAIL=$((FAIL + 1)); }
command -v jq >/dev/null 2>&1 || { echo "SKIP: jq not available"; exit 0; }

TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/proj"
cat > "$TMP/brana" <<'STUB'
#!/usr/bin/env bash
case "$*" in
  *"backlog query"*) echo '[{"id":"t-9","subject":"demo","status":"in_progress","strategy":"s","build_step":"build","tags":[]}]' ;;
  *"decisions read --relevant"*)
    case "${STUB_MODE:-new}" in
      old)  echo "error: unexpected argument '--relevant' found" >&2; exit 2 ;;
      many) for i in 1 2 3 4 5; do echo "[2026-03-2$i] a/decision: entry $i"; done ;;
      *)    echo "[2026-03-21] a/decision: use X over Y" ;;
    esac ;;
esac
STUB
chmod +x "$TMP/brana"
run() { echo '{"agent_type":"Explore"}' | BRANA="$TMP/brana" CLAUDE_PROJECT_DIR="$TMP/proj" STUB_MODE="$1" bash "$HOOK" 2>"$TMP/err"; }

echo "=== new binary: decisions injected, labelled untrusted ==="
OUT=$(run new)
CTX=$(echo "$OUT" | jq -r '.additionalContext // ""')
if echo "$CTX" | grep -q "use X over Y"; then ok "decision text injected"; else bad "decision not injected: $CTX"; fi
if echo "$CTX" | grep -qi "untrusted"; then ok "block labelled untrusted history"; else bad "block not labelled untrusted"; fi
if echo "$OUT" | jq -e '.continue == true' >/dev/null 2>&1; then ok "continue:true"; else bad "continue not true"; fi

echo "=== old binary (flag rejected): still exits ok, injects nothing, says why on stderr ==="
OUT=$(run old)
if echo "$OUT" | jq -e '.continue == true' >/dev/null 2>&1; then ok "continue:true with old binary"; else bad "invalid output with old binary: $OUT"; fi
if echo "$OUT" | jq -r '.additionalContext // ""' | grep -q "Recent decisions"; then bad "decisions block present with old binary"; else ok "no decisions block"; fi
if grep -q "lacks 'decisions read --relevant'" "$TMP/err"; then ok "stderr hint names the missing flag"; else bad "no stderr hint: $(cat "$TMP/err")"; fi

echo "=== output bounded to 3 lines even if a binary returns more ==="
OUT=$(run many)
N=$(echo "$OUT" | jq -r '.additionalContext // ""' | grep -c "a/decision: entry")
if [ "$N" = "3" ]; then ok "at most 3 entries injected"; else bad "$N entries injected"; fi

echo ""; echo "=== Results: $PASS passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ]
