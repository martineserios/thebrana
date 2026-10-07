#!/usr/bin/env bash
# t-3458: session-end-persist.sh must store the session summary as VALID JSON.
# Bug: a "{}" default written inside ${SUMMARY_JSON:-...} closes at the first brace, leaving a literal "}",
# so every SET summary gained a trailing brace (721 of 860 rows broken), and the
# store fell back to the raw corrupted text when jq rejected it.
# Contract: a valid summary round-trips unchanged; an unset one stores {}; an invalid
# one is never stored raw — it is wrapped so the stored value still parses.
set -uo pipefail
HOOK="$(cd "$(dirname "$0")/.." && pwd)/session-end-persist.sh"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  PASS: $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL: $1 — $2"; }

mkdir -p "$T/home/.claude/scripts" "$T/bin"
cat > "$T/bin/cf-stub" <<'STUB'
#!/usr/bin/env bash
# records the -v value of `memory store --namespace session`
ns=""; v=""; while [ $# -gt 0 ]; do case "$1" in -v) v="$2"; shift ;; --namespace) ns="$2"; shift ;; esac; shift; done
[ "$ns" = "session" ] && printf '%s' "$v" > "$CF_STUB_OUT"
exit 0
STUB
chmod +x "$T/bin/cf-stub"
echo "CF=$T/bin/cf-stub" > "$T/home/.claude/scripts/cf-env.sh"

run() { # $1 = SUMMARY_JSON value, or __UNSET__
  rm -f "$T/stored"
  local args=(PATH="$PATH" HOME="$T/home" CF_STUB_OUT="$T/stored" BRANA_RUN_STATE_DIR="$T/rs"
              PROJECT=p SESSION_ID=s1 TIMESTAMP=2026-10-07T00:00:00Z LAYER0_DIR= STORED_L1=false)
  [ "$1" = "__UNSET__" ] || args+=("SUMMARY_JSON=$1")
  env -i "${args[@]}" bash "$HOOK" >/dev/null 2>&1
  cat "$T/stored" 2>/dev/null
}

echo "session-end-persist summary JSON"
out=$(run '{"a":1,"b":"x"}')
echo "$out" | jq -e . >/dev/null 2>&1 && ok "MUST-FIRE: a set valid summary is stored as valid JSON" || bad "set summary parses" "stored [$out]"
[ "$(echo "$out" | jq -c . 2>/dev/null)" = '{"a":1,"b":"x"}' ] && ok "a set summary round-trips unchanged" || bad "round-trip" "stored [$out]"
out=$(run __UNSET__)
[ "$out" = "{}" ] && ok "an unset summary stores {}" || bad "unset -> {}" "stored [$out]"
out=$(run 'not json {')
echo "$out" | jq -e . >/dev/null 2>&1 && ok "an invalid summary is never stored raw (stored value parses)" || bad "invalid summary wrapped" "stored [$out]"
[ "$(echo "$out" | jq -r '.raw // empty' 2>/dev/null)" = "not json {" ] && ok "an invalid summary keeps its text under .raw" || bad ".raw keeps text" "stored [$out]"
echo; echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
