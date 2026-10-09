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

# class detector: quarantined skills must not be Skill-tool dependencies
viol=""
for sf in "$REPO_ROOT"/system/skills/*/SKILL.md; do
  name=$(basename "$(dirname "$sf")")
  sed -n '/^---$/,/^---$/p' "$sf" | grep -qE '^disable-model-invocation:[[:space:]]*true' || continue
  callers=$(grep -rln "Skill(" "$REPO_ROOT/system" --include='*.md' 2>/dev/null \
    | grep -v "/system/skills/$name/" \
    | xargs grep -lE "Skill\([^)]*[\"'\`](brana:)?$name[\"'\`]" 2>/dev/null || true)
  [ -n "$callers" ] && viol="$viol $name<-$(echo "$callers" | tr '\n' ',')"
done
check "no quarantined skill is called through the Skill tool anywhere in system/" "" "$viol"

# detector must-fire: a planted quarantined skill with a caller IS caught
fx=$(mktemp -d); trap 'rm -rf "$fx"' EXIT
mkdir -p "$fx/system/skills/q" "$fx/system/skills/c"
printf -- '---\nname: q\ndisable-model-invocation: true\n---\nq\n' > "$fx/system/skills/q/SKILL.md"
printf -- '---\nname: c\n---\nCall Skill(skill: "brana:q")\n' > "$fx/system/skills/c/SKILL.md"
fv=""
for sf in "$fx"/system/skills/*/SKILL.md; do
  name=$(basename "$(dirname "$sf")")
  sed -n '/^---$/,/^---$/p' "$sf" | grep -qE '^disable-model-invocation:[[:space:]]*true' || continue
  callers=$(grep -rln "Skill(" "$fx/system" --include='*.md' | grep -v "/system/skills/$name/" | xargs grep -lE "Skill\([^)]*[\"'\`](brana:)?$name[\"'\`]" 2>/dev/null || true)
  [ -n "$callers" ] && fv="$fv $name"
done
check "detector must-fire: planted quarantined dependency is caught" " q" "$fv"

echo "  summary: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
