#!/usr/bin/env bash
# t-3489 (ADR-097 P0, Challenge record rows 1/3/10): the ADR-084 band's call
# path must actually be reachable. `disable-model-invocation: true` blocks the
# Skill tool (ADR-076 verified finding #3), yet the adapters carried it while
# /brana:fix called them through the Skill tool -- so no adapter was ever
# loadable from another skill, and no invocation record could exist. This test
# pins four things: (1) no band adapter carries the blocking flag; (2) a shared
# resolver says whether an organ is present so callers can take the inline
# fallback in repos that never vendored it; (3) a shared recorder appends one
# JSON line per entry so ADR-084 s7's invocation proxy becomes readable;
# (4) every adapter calls both, and keeps its routing description short
# (context-budget.sh had 11 bytes of headroom when this was written).

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
RESOLVE="$REPO_ROOT/system/scripts/organ-resolve.sh"
RECORD="$REPO_ROOT/system/scripts/organ-record.sh"
PASS=0
FAIL=0

check() {
  local desc="$1" expected="$2" actual="$3"
  if [ "$expected" = "$actual" ]; then
    PASS=$((PASS + 1))
    echo "  PASS: $desc"
  else
    FAIL=$((FAIL + 1))
    echo "  FAIL: $desc"
    echo "    expected: $expected"
    echo "    actual:   $actual"
  fi
}

# adapter -> organ it wraps
declare -A ORGAN_OF=(
  [diagnose-hard-bug]=diagnosing-bugs
  [two-axis-review]=code-review
  [provisioning-wizard]=wizard
)

echo "test-organ-call-path: adapters are reachable, organs resolvable, entries recorded"

# ── 1. no adapter carries the Skill-tool-blocking flag ──────────────────────
for adapter in "${!ORGAN_OF[@]}"; do
  sf="$REPO_ROOT/system/skills/$adapter/SKILL.md"
  fm=$(sed -n '/^---$/,/^---$/p' "$sf")
  flag=$(echo "$fm" | grep -c '^disable-model-invocation:[[:space:]]*true' || true)
  check "$adapter has no disable-model-invocation flag" "0" "$flag"
done

# ── 2. resolver: present organ -> 0 + path; absent organ -> 1 + fallback hint ─
check "organ-resolve.sh exists and is executable" "yes" "$([ -x "$RESOLVE" ] && echo yes || echo no)"
if [ -x "$RESOLVE" ]; then
  for adapter in "${!ORGAN_OF[@]}"; do
    organ="${ORGAN_OF[$adapter]}"
    out=$(cd "$REPO_ROOT" && "$RESOLVE" "$organ" 2>/dev/null); rc=$?
    check "resolve $organ in this repo exits 0" "0" "$rc"
    check "resolve $organ prints the SKILL.md path" "yes" "$([ -f "$out" ] && echo yes || echo no)"
  done
  fixture=$(mktemp -d)
  out=$(cd "$fixture" && "$RESOLVE" diagnosing-bugs 2>&1); rc=$?
  check "resolve in a repo without the organ exits 1" "1" "$rc"
  check "absent organ names the inline fallback" "yes" "$(echo "$out" | grep -qi 'fallback' && echo yes || echo no)"
  out=$("$RESOLVE" 2>&1); rc=$?
  check "resolve with no organ name exits 2 (usage)" "2" "$rc"
  rm -rf "$fixture"
fi

# ── 3. recorder: one JSON line per entry, append-only, under $HOME ──────────
check "organ-record.sh exists and is executable" "yes" "$([ -x "$RECORD" ] && echo yes || echo no)"
if [ -x "$RECORD" ]; then
  fakehome=$(mktemp -d)
  HOME="$fakehome" "$RECORD" diagnosing-bugs t-3489 fix >/dev/null 2>&1; rc=$?
  check "record exits 0" "0" "$rc"
  log="$fakehome/.claude/run-state/pocock-diagnosing-bugs.jsonl"
  check "record creates the run-state log" "yes" "$([ -f "$log" ] && echo yes || echo no)"
  check "record writes exactly one line" "1" "$(wc -l < "$log" 2>/dev/null | tr -d ' ')"
  line=$(tail -n1 "$log" 2>/dev/null)
  check "line is JSON with organ/task_id/caller/event" "yes" "$(echo "$line" | python3 -c 'import json,sys; d=json.load(sys.stdin); print("yes" if d.get("organ")=="diagnosing-bugs" and d.get("task_id")=="t-3489" and d.get("caller")=="fix" and d.get("event")=="entry" and d.get("ts") else "no")' 2>/dev/null)"
  HOME="$fakehome" "$RECORD" diagnosing-bugs t-3489 fix >/dev/null 2>&1
  check "second record appends, never rewrites" "2" "$(wc -l < "$log" | tr -d ' ')"
  out=$(HOME="$fakehome" "$RECORD" 2>&1); rc=$?
  check "record with missing args exits 2 (usage)" "2" "$rc"
  rm -rf "$fakehome"
fi

# ── 4. every adapter calls both scripts and keeps its description short ──────
for adapter in "${!ORGAN_OF[@]}"; do
  sf="$REPO_ROOT/system/skills/$adapter/SKILL.md"
  check "$adapter references organ-resolve.sh" "yes" "$(grep -q 'organ-resolve.sh' "$sf" && echo yes || echo no)"
  check "$adapter references organ-record.sh" "yes" "$(grep -q 'organ-record.sh' "$sf" && echo yes || echo no)"
  desc_len=$(sed -n '/^---$/,/^---$/p' "$sf" | grep '^description:' | wc -c | tr -d ' ')
  check "$adapter description line <= 80 bytes (budget)" "yes" "$([ "$desc_len" -le 80 ] && echo yes || echo no)"
done

echo "  summary: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
