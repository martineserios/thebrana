#!/usr/bin/env bash
# Must-fire tests for system/scripts/mods-check.sh --static (validate Check 77a, t-3445) and
# system/scripts/mods-sync-shared.sh: every bad-* fixture under tests/fixtures/mods fires its
# rule, the good fixture passes, the vendored-copy drift guard and the version-bump guard
# fire, engine-written (gitignored) files are not scanned, test files are not scanned, and a
# missing base ref fails loudly. Runs without `claude` (the required `tests` CI job has none).
# Run: bash tests/scripts/test-mods-check.sh
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
CHECK="$ROOT/system/scripts/mods-check.sh"
SYNC="$ROOT/system/scripts/mods-sync-shared.sh"
FIX="$ROOT/tests/fixtures/mods"
PASS=0; FAIL=0
assert() { if [ "$2" = "$3" ]; then PASS=$((PASS+1)); echo "  PASS: $1"; else FAIL=$((FAIL+1)); echo "  FAIL: $1 (expected '$2', got '$3')"; fi; }
has() { case "$2" in *"$1"*) echo yes;; *) echo no;; esac; }

T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
G() { git -C "$T" -c user.email=t@t -c user.name=t -c commit.gpgsign=false "$@"; }
mkdir -p "$T/mods"
cp -R "$ROOT/mods/_shared" "$T/mods/_shared"; cp "$ROOT/mods/package.json" "$T/mods/"; cp "$ROOT/.gitignore" "$T/.gitignore"
cp -R "$FIX/good-minimal" "$T/mods/good-minimal"
G init -q -b dev . && bash "$SYNC" "$T" >/dev/null 2>&1; G add -A && G commit -qm base
G switch -q -c work
run() { bash "$CHECK" --static "$T" >"$T/out" 2>&1; echo $?; }
out() { cat "$T/out"; }
bump() { printf '%s\n' "$(sed -E 's/"version": "0\.1\.0"/"version": "0.1.1"/' "$T/mods/$1/.claude-plugin/plugin.json")" > "$T/mods/$1/.claude-plugin/plugin.json"; }

echo "=== test-mods-check.sh ==="
echo "--- modes"
bash "$CHECK" >/dev/null 2>&1; assert "no mode -> exit 2" 2 "$?"
bash "$CHECK" --bogus "$T" >/dev/null 2>&1; assert "unknown mode -> exit 2" 2 "$?"

echo "--- sync"
assert "sync vendored the shared files into good-minimal" yes "$(has yes "$( [ -f "$T/mods/good-minimal/hooks/_shared/run.ts" ] && [ -f "$T/mods/good-minimal/hooks/_shared/probe.ts" ] && echo yes)")"
assert "sync never copies the shared tests" no "$(has yes "$( [ -f "$T/mods/good-minimal/hooks/_shared/run.test.ts" ] && echo yes)")"
assert "vendored copy is byte-identical to the source" "" "$(cmp "$T/mods/_shared/hooks/run.ts" "$T/mods/good-minimal/hooks/_shared/run.ts" 2>&1)"
bash "$SYNC" "$T" --check >/dev/null 2>&1; assert "sync --check on a synced tree exits 0" 0 "$?"

echo "--- clean trees"
assert "_shared + good-minimal (unchanged since dev) pass" 0 "$(run)"
assert "summary line names the file count" yes "$(has 'violations: 0' "$(out)")"

echo "--- version-bump guard"
printf '\n// edit\n' >> "$T/mods/good-minimal/hooks/register.ts"
assert "an edited mod without a version bump fails" 1 "$(run)"
assert "...naming the version rule" yes "$(has 'version' "$(out)")"
bump good-minimal
assert "the same edit with a bumped version passes" 0 "$(run)"
G add -A; G commit -qm bumped
printf '\n// shared edit\n' >> "$T/mods/_shared/hooks/snapshot.ts"; bash "$SYNC" "$T" >/dev/null
assert "a _shared edit lands in the vendored copy and so needs the mod's bump too" 1 "$(run)"
assert "...naming good-minimal" yes "$(has 'good-minimal' "$(out)")"
G reset -q --hard
MODS_BASE_REF=refs/heads/nope bash "$CHECK" --static "$T" >"$T/out" 2>&1; assert "an unresolvable base ref fails (never passes silently)" 1 "$?"
assert "...naming the base ref" yes "$(has 'base ref' "$(out)")"

echo "--- vendored-copy drift"
printf '\n// drift\n' >> "$T/mods/good-minimal/hooks/_shared/run.ts"; bump good-minimal
assert "a vendored file that differs from mods/_shared fails" 1 "$(run)"
assert "...naming drift" yes "$(has 'drift' "$(out)")"
G reset -q --hard
printf 'export const x = 1\n' > "$T/mods/good-minimal/hooks/_shared/extra.ts"; bump good-minimal
assert "a vendored file with no source in mods/_shared fails" 1 "$(run)"
G reset -q --hard; rm -f "$T/mods/good-minimal/hooks/_shared/extra.ts"

echo "--- scan set"
mkdir -p "$T/mods/good-minimal/.claude-plugin/types"; printf 'declare const x: typeof $.model\n' > "$T/mods/good-minimal/.claude-plugin/types/index.d.ts"
assert "engine-written (gitignored) types are not scanned" 0 "$(run)"
rm -rf "$T/mods/good-minimal/.claude-plugin/types"
printf "import { test } from 'claude-code/testing'\ntest('x', () => { void fetch })\n" > "$T/mods/good-minimal/hooks/x.test.ts"; bump good-minimal
assert "*.test.ts files are not scanned" 0 "$(run)"
G reset -q --hard; rm -f "$T/mods/good-minimal/hooks/x.test.ts"
mkdir -p "$T/mods/newmod/.claude-plugin" "$T/mods/newmod/hooks"; cp "$FIX/good-minimal/.claude-plugin/plugin.json" "$T/mods/newmod/.claude-plugin/"; printf '{ "modules": ["./register.ts"] }\n' > "$T/mods/newmod/hooks/hooks.json"; printf "import type { Register } from 'claude-code'\nexport const register: Register = () => {}\n" > "$T/mods/newmod/hooks/register.ts"
assert "a mod absent from the base ref needs no bump (untracked files are scanned)" 0 "$(run)"
printf "export const y = () => fetch('x')\n" > "$T/mods/newmod/hooks/y.ts"
assert "an untracked, non-ignored file IS scanned" 1 "$(run)"
rm -rf "$T/mods/newmod"

echo "--- must-fire fixtures (one per rule)"
for d in "$FIX"/bad-*/; do
    name="$(basename "$d")"; rule="$(cat "$d/expect.txt")"
    cp -R "$d" "$T/mods/$name"; bash "$SYNC" "$T" >/dev/null 2>&1
    rc="$(run)"
    assert "fires: $name -> exit 1" 1 "$rc"
    assert "fires: $name names rule '$rule'" yes "$(has "$rule" "$(out)")"
    assert "fires: $name points at the fixture file:line" yes "$(has "$name/hooks/register.ts:" "$(out)")"
    rm -rf "$T/mods/$name"
done
assert "tree is clean again after the fixtures" 0 "$(run)"

echo; echo "Results: $PASS passed, $FAIL failed"; [ "$FAIL" -eq 0 ]
