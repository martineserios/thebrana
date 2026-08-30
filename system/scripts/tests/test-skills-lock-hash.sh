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
echo "== skills-lock-hash.sh: wizard multi-file dir matches skills-lock.json (t-2836) =="
WIZARD_ACTUAL=$("$HASH_SCRIPT" "$REPO_ROOT/.agents/skills/wizard")
LOCK_WIZARD=$(python3 -c "
import json
with open('$REPO_ROOT/skills-lock.json') as f:
    print(json.load(f)['skills']['wizard']['computedHash'])
")
check "regenerated hash matches skills-lock.json's recorded wizard hash" "$LOCK_WIZARD" "$WIZARD_ACTUAL"

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
