#!/usr/bin/env bash
# t-2834 (ADR-084 §2, challenge finding #2): skills-lock.json's computedHash
# must cover every file under a vendored skill dir, not SKILL.md alone, and
# must be independently regeneratable -- a hand-typed hash that nothing
# recomputes is unverifiable and silently stops detecting drift. This test
# pins the algorithm (sha256 over sorted relpath+content, no separators) and
# guards skills-lock.json's stored values against it.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
HASH_SCRIPT="$REPO_ROOT/system/scripts/skills-lock-hash.sh"
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

echo "== skills-lock-hash.sh: known fixture (deterministic algorithm) =="
FIXTURE=$(mktemp -d)
trap 'rm -rf "$FIXTURE"' EXIT
mkdir -p "$FIXTURE/sub"
printf 'alpha content\n' > "$FIXTURE/SKILL.md"
printf 'beta content\n' > "$FIXTURE/sub/helper.sh"
# expected = sha256("SKILL.md" + "alpha content\n" + "sub/helper.sh" + "beta content\n")
# (piped directly into sha256sum, not round-tripped through a $(...) capture,
# which would strip the files' trailing newlines and silently corrupt the fixture)
EXPECTED=$( { printf '%s' "SKILL.md"; cat "$FIXTURE/SKILL.md"; printf '%s' "sub/helper.sh"; cat "$FIXTURE/sub/helper.sh"; } | sha256sum | awk '{print $1}')
ACTUAL=$("$HASH_SCRIPT" "$FIXTURE")
check "fixture hash matches manual sha256 over sorted path+content" "$EXPECTED" "$ACTUAL"

echo ""
echo "== skills-lock-hash.sh: matches existing single-file precedent (ADR-012) =="
SINGLE_EXPECTED=$(python3 -c "
import hashlib
with open('$REPO_ROOT/.agents/skills/inversion/SKILL.md', 'rb') as f:
    print(hashlib.sha256(b'SKILL.md' + f.read()).hexdigest())
")
SINGLE_ACTUAL=$("$HASH_SCRIPT" "$REPO_ROOT/.agents/skills/inversion")
check "single-file skill hash reduces to sha256(SKILL.md+content)" "$SINGLE_EXPECTED" "$SINGLE_ACTUAL"

LOCK_INVERSION=$(python3 -c "
import json
with open('$REPO_ROOT/skills-lock.json') as f:
    print(json.load(f)['skills']['inversion']['computedHash'])
")
check "regenerated hash matches skills-lock.json's recorded inversion hash" "$LOCK_INVERSION" "$SINGLE_ACTUAL"

echo ""
echo "== skills-lock-hash.sh: diagnosing-bugs multi-file dir matches skills-lock.json =="
DIAG_ACTUAL=$("$HASH_SCRIPT" "$REPO_ROOT/.agents/skills/diagnosing-bugs")
LOCK_DIAG=$(python3 -c "
import json
with open('$REPO_ROOT/skills-lock.json') as f:
    print(json.load(f)['skills']['diagnosing-bugs']['computedHash'])
")
check "regenerated hash matches skills-lock.json's recorded diagnosing-bugs hash" "$LOCK_DIAG" "$DIAG_ACTUAL"

echo ""
echo "== skills-lock.json: every entry's computedHash matches a live recomputation (t-3239) =="
# Supersedes the earlier per-skill checks above and the hardcoded
# code-review/wizard checks (t-2835/t-2836) -- this loop covers every
# entry generically, code-review and wizard included.
# t-3239: t-2834's original test only ever checked 2 hand-picked entries
# (inversion, diagnosing-bugs). That missed 9 more entries whose
# computedHash was hand-typed/stale and never re-verified. This loop covers
# every entry in skills-lock.json generically, so a 10th drifted entry is
# caught automatically without anyone remembering to add a new check.
ALL_NAMES=$(python3 -c "
import json
with open('$REPO_ROOT/skills-lock.json') as f:
    for name in json.load(f)['skills']:
        print(name)
")
while IFS= read -r name; do
  [ -n "$name" ] || continue
  if [ -d "$REPO_ROOT/.agents/skills/$name" ]; then
    SKILL_DIR="$REPO_ROOT/.agents/skills/$name"
  elif [ -d "$REPO_ROOT/system/skills/$name" ]; then
    SKILL_DIR="$REPO_ROOT/system/skills/$name"
  else
    FAIL=$((FAIL + 1))
    echo "  FAIL: $name -> no vendored directory found under .agents/skills/ or system/skills/"
    continue
  fi
  LIVE_HASH=$("$HASH_SCRIPT" "$SKILL_DIR")
  LOCK_HASH=$(python3 -c "
import json
with open('$REPO_ROOT/skills-lock.json') as f:
    print(json.load(f)['skills']['$name']['computedHash'])
")
  check "$name: computedHash matches live recomputation ($SKILL_DIR)" "$LOCK_HASH" "$LIVE_HASH"
done <<< "$ALL_NAMES"

echo ""
echo "== skills-lock-hash.sh: errors on missing/empty dir =="
"$HASH_SCRIPT" "$REPO_ROOT/no-such-skill-dir" >/dev/null 2>&1
RC=$?
if [ "$RC" -ne 0 ]; then
  PASS=$((PASS + 1))
  echo "  PASS: missing dir -> non-zero exit"
else
  FAIL=$((FAIL + 1))
  echo "  FAIL: missing dir -> exit 0 (expected failure)"
fi

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
