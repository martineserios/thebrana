#!/usr/bin/env bash
# Must-fire test for system/scripts/lint-portability.sh: every rule catches a
# seeded violation, the escape hatch and comment/test-dir exclusions hold.
# Run: bash tests/scripts/test-lint-portability.sh
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LINT="$(cd "$SCRIPT_DIR/../.." && pwd)/system/scripts/lint-portability.sh"
PASS=0; FAIL=0
assert() { if [ "$2" = "$3" ]; then PASS=$((PASS+1)); echo "  PASS: $1"; else FAIL=$((FAIL+1)); echo "  FAIL: $1 (expected '$2', got '$3')"; fi; }

T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
cd "$T" && git init -q . && mkdir -p system/hooks/lib tests s
run() { bash "$LINT" "$T" >/dev/null 2>&1; echo $?; }
put() { printf '%s\n' "$2" >"$1"; git add -A; }

echo "=== test-lint-portability.sh ==="
put s/clean.sh 'echo hi'; assert "clean tree passes" 0 "$(run)"
while IFS='|' read -r name code; do
    put s/bad.sh "$code"; assert "fires: $name" 1 "$(run)"
done <<'CASES'
flock|flock -n 9
date -d|x=$(date -d yesterday +%F)
date --date|x=$(date --date=yesterday +%F)
sha256sum|sha256sum f
md5sum|echo a | md5sum
stat -c|stat -c %Y f
sed -i|sed -i 's/a/b/' f
readlink -f|readlink -f x
grep -P|grep -oP 'a\Kb' f
grep -qP|grep -qP 'a' f
CASES
put s/bad.sh '# uses flock in a comment'; assert "full-line comment ignored" 0 "$(run)"
put s/bad.sh 'date -d x +%s || true  # portable-ok: guarded BSD fallback below'; assert "portable-ok escape hatch" 0 "$(run)"
rm s/bad.sh; printf '#!/usr/bin/env bash\nsed -i s/a/b/ f\n' >s/noext; git add -A; assert "fires: extensionless bash script" 1 "$(run)"
printf 'sed -i s/a/b/ f\n' >s/noext; git add -A; assert "extensionless non-shell file ignored" 0 "$(run)"
rm s/noext; put tests/t.sh 'flock -n 9'; assert "tests/ excluded" 0 "$(run)"
rm tests/t.sh; put system/hooks/lib/portable.sh 'flock -n 9'; assert "portable.sh itself excluded" 0 "$(run)"
put s/ok.sh 'x=$(p_date_d 2024-01-02)'; assert "shim calls pass" 0 "$(run)"
put s/ok.sh 'echo "reflow lockfile stats"'; assert "no substring false positives" 0 "$(run)"

echo; echo "Results: $PASS passed, $FAIL failed"; [ "$FAIL" -eq 0 ]
