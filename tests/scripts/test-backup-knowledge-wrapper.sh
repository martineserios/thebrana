#!/usr/bin/env bash
# Test for system/scripts/backup-knowledge.sh (t-3468 challenger finding 5).
# Contract: no brana-knowledge clone -> exit 0, silent (machines without the repo);
# clone present but backup.sh not executable -> exit 1 with a WARNING naming the file
# (a commit that drops the exec bit, like 6c102b37 on 2026-10-05, must not turn every
# close's backup off silently); executable -> runs it and passes its exit code through.
set -uo pipefail
WRAP="$(cd "$(dirname "$0")/../.." && pwd)/system/scripts/backup-knowledge.sh"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  PASS: $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL: $1 — $2"; }
echo "backup-knowledge wrapper tests"
HOME="$T/h1" bash "$WRAP" >"$T/o1" 2>&1; rc=$?
[ "$rc" -eq 0 ] && [ ! -s "$T/o1" ] && ok "no clone: exit 0, silent" || bad "no clone: exit 0, silent" "rc=$rc out=$(cat "$T/o1")"
mkdir -p "$T/h2/enter_thebrana/brana-knowledge"; printf '#!/bin/bash\necho ran\n' > "$T/h2/enter_thebrana/brana-knowledge/backup.sh"; chmod 644 "$T/h2/enter_thebrana/brana-knowledge/backup.sh"
HOME="$T/h2" bash "$WRAP" >"$T/o2" 2>&1; rc=$?
[ "$rc" -eq 1 ] && ok "MUST-FIRE: not executable -> exit 1" || bad "not executable -> exit 1" "rc=$rc"
grep -q "WARNING.*not executable" "$T/o2" && ok "not executable -> WARNING names the problem" || bad "warning" "$(cat "$T/o2")"
grep -q "^ran$" "$T/o2" && bad "not executable -> script not run" "ran" || ok "not executable -> script not run"
chmod 755 "$T/h2/enter_thebrana/brana-knowledge/backup.sh"; printf '#!/bin/bash\necho ran\nexit 3\n' > "$T/h2/enter_thebrana/brana-knowledge/backup.sh"
HOME="$T/h2" bash "$WRAP" >"$T/o3" 2>&1; rc=$?
grep -q "^ran$" "$T/o3" && [ "$rc" -eq 3 ] && ok "executable -> runs, exit code passed through" || bad "executable passthrough" "rc=$rc"
# clone present but backup.sh MISSING (deleted/renamed) must not be silent (Gate 3 regression finding)
mkdir -p "$T/h4/enter_thebrana/brana-knowledge"
HOME="$T/h4" bash "$WRAP" >"$T/o4" 2>&1; rc=$?
[ "$rc" -eq 1 ] && ok "MUST-FIRE: clone without backup.sh -> exit 1" || bad "clone without backup.sh -> exit 1" "rc=$rc"
grep -q "WARNING.*backup.sh" "$T/o4" && ok "clone without backup.sh -> WARNING" || bad "missing-file warning" "$(cat "$T/o4")"
# the warning must lead with the company-Mac instruction, not with chmod
grep -q "DO NOT chmod" "$T/o2" && ok "not-executable warning says DO NOT chmod on a company Mac" || bad "warning leads with the Mac rule" "$(cat "$T/o2")"

echo; echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
