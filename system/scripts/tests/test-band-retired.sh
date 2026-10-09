#!/usr/bin/env bash
# t-3503 (ADR-098): the ADR-084 vendored band is retired. Pins (1) the adapters,
# organs, symlinks, lock entries and helper scripts are gone; (2) /brana:fix calls
# the installed Pocock plugin's diagnosing-bugs by its plugin name, with an inline
# fallback; (3) the class detector from t-3489: a skill carrying
# `disable-model-invocation: true` blocks the Skill tool, so none may be a Skill-tool
# dependency anywhere in system/ (ADR-076 verified finding #3).
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
PASS=0; FAIL=0
check() { if [ "$2" = "$3" ]; then PASS=$((PASS+1)); echo "  PASS: $1"; else FAIL=$((FAIL+1)); echo "  FAIL: $1"; echo "    expected: $2"; echo "    actual:   $3"; fi; }
absent() { check "$1 is gone" "no" "$([ -e "$2" ] || [ -L "$2" ] && echo yes || echo no)"; }

echo "test-band-retired: ADR-098 retirement is complete and the class detector holds"

for a in diagnose-hard-bug two-axis-review provisioning-wizard; do absent "adapter system/skills/$a" "$REPO_ROOT/system/skills/$a"; done
for o in diagnosing-bugs code-review wizard; do
  absent "organ .agents/skills/$o" "$REPO_ROOT/.agents/skills/$o"
  absent "symlink .claude/skills/$o" "$REPO_ROOT/.claude/skills/$o"
done
for s in two-axis-spec-lookup wizard-scaffold; do absent "script system/scripts/$s.sh" "$REPO_ROOT/system/scripts/$s.sh"; done
for t in test-two-axis-spec-lookup test-wizard-scaffold; do absent "test system/scripts/tests/$t.sh" "$REPO_ROOT/system/scripts/tests/$t.sh"; done

left=$(python3 -c "
import json
d=json.load(open('$REPO_ROOT/skills-lock.json'))
print(','.join(k for k,v in d['skills'].items() if v.get('source')=='mattpocock/skills'))")
check "skills-lock.json has no mattpocock/skills entries" "" "$left"

fix="$REPO_ROOT/system/skills/fix/SKILL.md"
check "fix no longer names the retired adapter" "0" "$(grep -c 'diagnose-hard-bug' "$fix" || true)"
check "fix calls the plugin's diagnosing-bugs by plugin name" "yes" "$(grep -q 'mattpocock-skills:diagnosing-bugs' "$fix" && echo yes || echo no)"
check "fix keeps an inline fallback when the plugin is absent" "yes" "$(grep -qiE 'plugin.*(absent|not installed)|inline' "$fix" && echo yes || echo no)"

# ── class detector (one function, called for the real tree AND the fixture) ──
# SCOPE (honest): scans system/**/*.md for a literal, quoted `Skill(... "name" ...)` call
# naming a skill whose frontmatter carries disable-model-invocation: true. It does NOT see
# dynamically built calls (e.g. backlog/phases/start.md `Skill(skill="brana:{name}")`) or
# unquoted/shell-side calls; those are tracked as a follow-up. Prints "examined=N" first so
# a moved flag cannot pass vacuously.
scan() {
  local root="$1" examined=0 viol="" sf name callers
  for sf in "$root"/system/skills/*/SKILL.md; do
    [ -f "$sf" ] || continue
    name=$(basename "$(dirname "$sf")")
    sed -n '/^---$/,/^---$/p' "$sf" | grep -qE '^disable-model-invocation:[[:space:]]*true' || continue
    examined=$((examined+1))
    callers=$(grep -rln "Skill(" "$root/system" --include='*.md' 2>/dev/null \
      | grep -v "/system/skills/$name/" \
      | xargs grep -lE "Skill\([^)]*[\"'\`](brana:)?$name[\"'\`]" 2>/dev/null || true)
    [ -n "$callers" ] && viol="$viol $name"
  done
  echo "examined=$examined"; echo "violations=$viol"
}
real=$(scan "$REPO_ROOT")
check "real tree: detector examined at least 3 quarantined skills (not vacuous)" "yes" "$([ "$(echo "$real" | sed -n 's/examined=//p')" -ge 3 ] && echo yes || echo no)"
check "real tree: no quarantined skill is called through the Skill tool in system/" "" "$(echo "$real" | sed -n 's/violations=//p')"

fx=$(mktemp -d); trap 'rm -rf "$fx"' EXIT
mk() { mkdir -p "$fx/$1/system/skills/q" "$fx/$1/system/skills/c" "$fx/$1/system/skills/u"
  printf -- '---\nname: q\ndisable-model-invocation: true\n---\nq\n' > "$fx/$1/system/skills/q/SKILL.md"
  printf -- '---\nname: u\n---\nu\n' > "$fx/$1/system/skills/u/SKILL.md"
  printf -- '---\nname: c\n---\n%s\n' "$2" > "$fx/$1/system/skills/c/SKILL.md"; }
mk a 'Call Skill(skill: "brana:q")';        check "must-fire: prefixed double-quoted call to a quarantined skill" " q" "$(scan "$fx/a" | sed -n 's/violations=//p')"
mk b "Call Skill(skill: 'q')";               check "must-fire: bare single-quoted call to a quarantined skill"   " q" "$(scan "$fx/b" | sed -n 's/violations=//p')"
mk c 'Call Skill(skill: "brana:u")';         check "negative: call to an UNflagged skill is not a violation"      ""  "$(scan "$fx/c" | sed -n 's/violations=//p')"
mk d 'Run /brana:q by hand, no Skill call';  check "negative: prose mention without Skill( is not a violation"    ""  "$(scan "$fx/d" | sed -n 's/violations=//p')"
check "fixture: examined counts the one flagged skill" "1" "$(scan "$fx/a" | sed -n 's/examined=//p')"

echo "  summary: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
