#!/usr/bin/env bash
# /brana:ship hardening (t-3483) — the gaps the 2026-10-06 ship (PR #1093) fell into:
#   1. pre-flight never ran CI's `tests` job (a rules-headroom miss failed CI after the PR opened;
#      same miss as PR #1076) -> pre-flight must run run-test-suites.sh in a throwaway worktree
#      and the rules-headroom test when system/rules changed
#   2. `gh pr checks --watch` right after `gh pr create` exits 1 "no checks reported" -> wait/retry
#   3. jobs "cancelled — not acquired by Runner" are infra, not test failures -> rerun, don't stop
#   4. the Tier-2 ship never rebuilt/installed brana-cli -> rebuild + verify after bootstrap
# (2)+(3) are one runnable helper block in SKILL.md (SHIP-CHECKS-BLOCK), executed here against a
# stubbed `gh`; (1)+(4) are procedure text, pinned by grep.
# Run: bash tests/procedures/test-ship-hardening.sh
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SKILL="$ROOT/system/skills/ship/SKILL.md"
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  PASS: $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL: $1"; }
assert() { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1 (expected '$2', got '$3')"; fi; }
has() { grep -qF -- "$2" "$1" && echo yes || echo no; }

echo "=== test-ship-hardening.sh ==="
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT

echo "--- procedure text (pre-flight + verify)"
assert "pre-flight names CI's suite runner" yes "$(has "$SKILL" 'run-test-suites.sh')"
assert "pre-flight runs it in a throwaway worktree" yes "$(has "$SKILL" 'git worktree add --detach')"
assert "pre-flight has the targeted rules-headroom minimum" yes "$(has "$SKILL" 'test-context-budget-split.sh')"
assert "verify step rebuilds brana-cli after deploy" yes "$(has "$SKILL" 'cargo build --release -p brana-cli')"
assert "verify step checks the installed binary, not the build's exit code" yes "$(has "$SKILL" 'verify the installed binary')"

echo "--- SHIP-CHECKS-BLOCK (stubbed gh)"
awk '/<!-- SHIP-CHECKS-BLOCK -->/{g=1;next} /<!-- \/SHIP-CHECKS-BLOCK -->/{g=0} g' "$SKILL" | sed '/^```/d' > "$T/block.sh"
if [ ! -s "$T/block.sh" ]; then
    bad "SHIP-CHECKS-BLOCK present in SKILL.md"
    echo "=== Results: $PASS passed, $FAIL failed ==="; exit 1
fi
ok "SHIP-CHECKS-BLOCK present in SKILL.md"

# Stub gh. Scenario files under $T/sc: nochecks_n (calls that answer "no checks reported"),
# watch_rc, links (lines "<url>"), infra_ids (job ids whose annotation says not-acquired).
mkdir -p "$T/bin" "$T/sc"
cat > "$T/bin/gh" <<'STUB'
#!/usr/bin/env bash
S="$GH_STUB_DIR"
case "$1 $2" in
  "pr checks")
    shift 2; shift   # drop PR number
    if [ "${1:-}" = "--watch" ]; then exit "$(cat "$S/watch_rc")"; fi
    if [ "${1:-}" = "--json" ]; then cat "$S/links"; exit 0; fi
    n=$(cat "$S/calls" 2>/dev/null || echo 0); echo $((n+1)) > "$S/calls"
    if [ "$n" -lt "$(cat "$S/nochecks_n")" ]; then echo "no checks reported on the 'dev' branch"; exit 1; fi
    echo "validate	pass"; exit 0 ;;
  "api "*) jid=$(printf '%s' "$2" | sed -E 's#.*/check-runs/([0-9]+)/annotations.*#\1#')
    if grep -qx "$jid" "$S/infra_ids" 2>/dev/null; then echo "The job was not acquired by Runner of type hosted even after multiple attempts"; fi
    exit 0 ;;
  "run rerun") echo "$3" >> "$S/reruns"; exit 0 ;;
esac
exit 0
STUB
chmod +x "$T/bin/gh"

run_scenario() {  # name nochecks_n watch_rc "links" "infra_ids" tries -> echoes "rc|reruns"
    local d="$T/sc/$1"; mkdir -p "$d"; rm -f "$d/calls" "$d/reruns"
    echo "$2" > "$d/nochecks_n"; echo "$3" > "$d/watch_rc"
    printf '%s' "$4" > "$d/links"; printf '%s' "$5" > "$d/infra_ids"
    local out
    out=$(GH_STUB_DIR="$d" PATH="$T/bin:$PATH" SHIP_CHECKS_TRIES="$6" SHIP_CHECKS_GAP=0 \
          bash -c "source '$T/block.sh'; ship_checks_wait 7; rc=\$?; if [ \$rc -eq 3 ]; then ship_rerun_unacquired 7; fi; echo RC=\$rc" 2>/dev/null)
    echo "$(printf '%s' "$out" | sed -n 's/^RC=//p')|$(sort -u "$d/reruns" 2>/dev/null | tr '\n' ',')"
}
L='https://github.com/o/r/actions/runs/900/job/111
https://github.com/o/r/actions/runs/900/job/222
'
assert "green: returns 0" "0|" "$(run_scenario green 0 0 '' '' 3)"
assert "checks appear late (2 empty polls): still returns 0" "0|" "$(run_scenario late 2 0 '' '' 5)"
assert "no checks ever appear: returns 2 (not a silent pass)" "2|" "$(run_scenario never 99 0 '' '' 3)"
assert "real test failure: returns 1, no rerun" "1|" "$(run_scenario real 0 1 "$L" '' 3)"
assert "mixed real + infra failure: returns 1, no rerun" "1|" "$(run_scenario mixed 0 1 "$L" '111' 3)"
assert "all failures are not-acquired: returns 3 and reruns run 900" "3|900," "$(run_scenario infra 0 1 "$L" '111
222' 3)"

echo "=== Results: $PASS passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ]
