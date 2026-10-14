#!/usr/bin/env bash
# Tests for mods-installed-check.sh (t-3502) — the SessionStart trigger for the
# installed-mods Law 3 scan (ADR-096). validate Check 77c and bootstrap 7i are
# point-in-time; this hook re-runs the STATIC half of `mods-check.sh --installed`
# at every session start so a mod installed between runs is reported by the next
# session. Advisory only (ADR-096 Law 4 — mods render, hooks warn; a gauge, not a
# valve): one additionalContext warning line, exit 0 always, never a block.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$SCRIPT_DIR/../mods-installed-check.sh"
ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
FIX="$ROOT/tests/fixtures/mods"
BILL="$FIX/captures/t-3493-model-billing/mod"
GOOD="$FIX/good-minimal"
PASS=0; FAIL=0; TOTAL=0

assert() { TOTAL=$((TOTAL+1)); if [ "$2" = "$3" ]; then PASS=$((PASS+1)); echo "  PASS: $1"; else FAIL=$((FAIL+1)); echo "  FAIL: $1 (expected '$2', got '$3')"; fi; }
has() { case "$2" in *"$1"*) echo yes;; *) echo no;; esac; }

T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
CFG="$T/claude"; mkdir -p "$CFG/plugins"
REG="$CFG/plugins/installed_plugins.json"

# reg name:path ... -> the engine's v2 registry shape (name@marketplace -> [entries])
reg() {
    python3 -I - "$REG" "$@" <<'PYR'
import json, sys
out = {"version": 2, "plugins": {}}
for a in sys.argv[2:]:
    n, p = a.split(":", 1)
    out["plugins"][n + "@x"] = [{"scope": "user", "installPath": p, "version": "1.0.0"}]
json.dump(out, open(sys.argv[1], "w"))
PYR
}

# run [env...] -> OUT (stdout), RC; stdin is the SessionStart payload
run_hook() {
    OUT=$(printf '{"session_id":"t","cwd":"%s","hook_event_name":"SessionStart"}' "$ROOT" \
        | env CLAUDE_CONFIG_DIR="$CFG" "$@" bash "$HOOK" 2>"$T/err"); RC=$?
}
ctx() { printf '%s' "$OUT" | jq -r '.hookSpecificOutput.additionalContext // empty' 2>/dev/null; }
valid_json_or_empty() { [ -z "$OUT" ] && { echo yes; return; }; printf '%s' "$OUT" | jq -e . >/dev/null 2>&1 && echo yes || echo no; }

echo "=== test-mods-installed-check.sh ==="

echo ""
echo "--- hook is registered as a SessionStart command ---"
HJ="$ROOT/system/hooks/hooks.json"
assert "hooks.json SessionStart runs mods-installed-check.sh" yes \
    "$(has 'mods-installed-check.sh' "$(jq -r '.hooks.SessionStart[].hooks[].command' "$HJ" 2>/dev/null)")"
assert "hook file is executable" yes "$([ -x "$HOOK" ] && echo yes || echo no)"

echo ""
echo "--- nothing installed: silent, exit 0 ---"
rm -f "$REG"
run_hook
assert "no registry: exit 0" 0 "$RC"
assert "no registry: no additionalContext" "" "$(ctx)"
assert "no registry: stdout is empty or valid JSON" yes "$(valid_json_or_empty)"

echo ""
echo "--- a clean mod: silent, exit 0 ---"
reg good:"$GOOD"
run_hook
assert "clean mod: exit 0" 0 "$RC"
assert "clean mod: no additionalContext" "" "$(ctx)"

echo ""
echo "--- MUST-FIRE: the t-3493 billing mod installed after bootstrap is reported at the next session start ---"
reg good:"$GOOD" billing:"$BILL"
run_hook
assert "billing mod: exit 0 (advisory, never blocks — Law 4)" 0 "$RC"
assert "billing mod: stdout is valid JSON" yes "$(valid_json_or_empty)"
assert "billing mod: additionalContext present" yes "$([ -n "$(ctx)" ] && echo yes || echo no)"
assert "billing mod: names Law 3" yes "$(has 'Law 3' "$(ctx)")"
assert "billing mod: names the mod" yes "$(has 'billing@x' "$(ctx)")"
assert "billing mod: points at the remedy (77c)" yes "$(has '77c' "$(ctx)")"
assert "billing mod: exactly one warning line" 1 "$(ctx | wc -l | tr -d ' ')"
assert "billing mod: never a block" no "$(has '"continue": false' "$OUT")$(has '"decision"' "$OUT" | sed 's/no//')"
assert "billing mod: nothing on stderr" "" "$(cat "$T/err")"

echo ""
echo "--- static half only: the engine is never invoked at session start ---"
FAKEBIN="$T/bin"; mkdir -p "$FAKEBIN"
printf '#!/usr/bin/env bash\necho invoked >> "%s/claude.log"\nexit 0\n' "$T" > "$FAKEBIN/claude"; chmod +x "$FAKEBIN/claude"
: > "$T/claude.log"
run_hook PATH="$FAKEBIN:$PATH"
assert "a claude on PATH is not called (MODS_INSTALLED_STATIC_ONLY)" "" "$(cat "$T/claude.log")"
assert "...and the billing mod is still reported" yes "$(has 'billing@x' "$(ctx)")"

echo ""
echo "--- checker unavailable: says so once, still exit 0 ---"
run_hook BRANA_MODS_CHECK="$T/does-not-exist.sh"
assert "checker missing: exit 0" 0 "$RC"
assert "checker missing: one line says the scan did not run" yes "$(has 'not found' "$(ctx)")"
assert "checker missing: still valid JSON" yes "$(valid_json_or_empty)"

echo ""
echo "--- registry unreadable: fail-closed message is relayed, exit 0 ---"
printf 'not json' > "$REG"
run_hook
assert "mis-shaped registry: exit 0" 0 "$RC"
assert "mis-shaped registry: relayed as a warning" yes "$(has 'fail closed' "$(ctx)")"

echo ""
echo "Results: $PASS/$TOTAL passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
