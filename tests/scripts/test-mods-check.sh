#!/usr/bin/env bash
# Must-fire tests for system/scripts/mods-check.sh --static (Check 77a, t-3445), --engine (Check 77b,
# t-3446, via a fake claude shim) and
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
source "$ROOT/tests/lib/path-without.sh"
NOCLAUDE_PATH="$(path_without claude)"
PASS=0; FAIL=0
assert() { if [ "$2" = "$3" ]; then PASS=$((PASS+1)); echo "  PASS: $1"; else FAIL=$((FAIL+1)); echo "  FAIL: $1 (expected '$2', got '$3')"; fi; }
has() { case "$2" in *"$1"*) echo yes;; *) echo no;; esac; }

T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
G() { git -C "$T" -c user.email=t@t -c user.name=t -c commit.gpgsign=false "$@"; }
mkdir -p "$T/mods"
cp -R "$ROOT/mods/_shared" "$T/mods/_shared"; cp "$ROOT/mods/package.json" "$T/mods/"; cp "$ROOT/.gitignore" "$T/.gitignore"
cp -R "$FIX/good-minimal" "$T/mods/good-minimal"
mkdir -p "$T/tests/fixtures/mods"; cp -R "$FIX/good-minimal" "$T/tests/fixtures/mods/good-minimal"; cp -R "$FIX/captures" "$T/tests/fixtures/mods/captures"   # a checkout has the fixture too: --engine assembles an isolated copy from it
G init -q -b dev . && bash "$SYNC" "$T" >/dev/null 2>&1; G add -A && G commit -qm base; G branch main
G switch -q -c work
run() { bash "$CHECK" --static "$T" >"$T/out" 2>&1; local r=$?; [ -n "${DEBUG_MODS:-}" ] && cat "$T/out" >&2; echo $r; }
out() { cat "$T/out"; }
bump() { python3 - "$T/mods/$1/.claude-plugin/plugin.json" <<'PYB'
import json, sys
p = sys.argv[1]; d = json.load(open(p)); a, b, c = d["version"].split("."); d["version"] = f"{a}.{b}.{int(c) + 1}"
json.dump(d, open(p, "w"))
PYB
}

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
# base = the bumped commit, so the only change since base is the shared edit landing in the copy
MODS_BASE_REF=HEAD bash "$CHECK" --static "$T" >"$T/out" 2>&1; assert "a _shared edit lands in the vendored copy and so needs the mod's bump too" 1 "$?"
assert "...naming good-minimal" yes "$(has 'good-minimal/.claude-plugin/plugin.json' "$(out)")"
assert "...and _shared itself" yes "$(has '_shared/.claude-plugin/plugin.json' "$(out)")"
G reset -q --hard
MODS_BASE_REF=refs/heads/nope bash "$CHECK" --static "$T" >"$T/out" 2>&1; assert "an unresolvable base ref fails (never passes silently)" 1 "$?"
assert "...naming the base ref" yes "$(has 'base ref' "$(out)")"

echo "--- base ref never the commit under test (panel finding: dev->main PR fetched origin/dev == HEAD)"
G branch -f main HEAD; G branch -f dev HEAD   # both bases at the last bumped commit
printf '\n// unbumped\n' >> "$T/mods/good-minimal/hooks/register.ts"; G add -A; G commit -qm unbumped; G branch -f dev HEAD
assert "dev == HEAD: the guard falls through to main and still fires" 1 "$(run)"
assert "...naming main as the base ref" yes "$(has 'base ref: main' "$(out)")"
G branch -f main HEAD
assert "every candidate == HEAD on a clean tree: nothing can differ, pass" 0 "$(run)"
assert "...saying no distinct base" yes "$(has 'no base distinct from HEAD' "$(out)")"
G reset -q --hard HEAD~1; G branch -f dev HEAD; G branch -f main HEAD

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
rm -f "$T/mods/newmod/hooks/y.ts"
for ext in mjs js cjs mts cts jsx; do
    printf "export const z = (\$: any) => \$.model.complete({})\n" > "$T/mods/newmod/hooks/z.$ext"
    assert "a .$ext module is scanned (the engine loads more than .ts)" 1 "$(run)"
    rm -f "$T/mods/newmod/hooks/z.$ext"
done
printf "/* note */ export const w = (\$: any) => \$.model.complete({})\n" > "$T/mods/newmod/hooks/w.ts"
assert "code after a leading /* ... */ on the same line is scanned" 1 "$(run)"
printf "/**\n * calls \$.model in prose only\n */\nexport const w = 1\n" > "$T/mods/newmod/hooks/w.ts"
assert "JSDoc body lines are still comments" 0 "$(run)"
rm -rf "$T/mods/newmod"

echo "--- sync import detection"
mkdir -p "$T/mods/dq/.claude-plugin" "$T/mods/dq/hooks"; cp "$FIX/good-minimal/.claude-plugin/plugin.json" "$T/mods/dq/.claude-plugin/"; printf '{ "modules": ["./register.ts"] }\n' > "$T/mods/dq/hooks/hooks.json"
printf 'import { guard } from "./_shared/run"\nexport const register = () => { void guard }\n' > "$T/mods/dq/hooks/register.ts"
bash "$SYNC" "$T" >/dev/null 2>&1
assert "a double-quoted ./_shared import is synced too" yes "$( [ -f "$T/mods/dq/hooks/_shared/run.ts" ] && echo yes || echo no)"
rm -rf "$T/mods/dq"

echo "--- must-fire fixtures (one per rule)"
for d in "$FIX"/bad-*/; do
    name="$(basename "$d")"; rule="$(cat "$d/expect.txt")"
    cp -R "$d" "$T/mods/$name"; bash "$SYNC" "$T" >/dev/null 2>&1
    rc="$(run)"
    assert "fires: $name -> exit 1" 1 "$rc"
    assert "fires: $name names rule '$rule' (as ': $rule —', not via the fixture path)" yes "$(has ": $rule —" "$(out)")"
    assert "fires: $name points at the fixture file:line" yes "$(has "$name/hooks/register.ts:" "$(out)")"
    rm -rf "$T/mods/$name"
done
assert "tree is clean again after the fixtures" 0 "$(run)"


echo "--- --engine (fake claude shim; the required tests CI job has no claude)"
# The shim answers `claude plugin validate --json <dir>` and `claude plugin test <dir>` from
# files in $FAKE: validate.json/validate.rc, test.out/test.rc; every argv is appended to argv.log.
FAKE="$T/fake"; mkdir -p "$FAKE/bin"
cat > "$FAKE/bin/claude" <<'SHIM'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$FAKE/argv.log"
case "$1 ${2:-}" in
  "plugin validate") cat "$FAKE/validate.json"; exit "$(cat "$FAKE/validate.rc")" ;;
  "plugin test")     cat "$FAKE/test.out";      exit "$(cat "$FAKE/test.rc")" ;;
  "--version "*)     echo "2.1.288 (shim)" ;;
esac
SHIM
chmod +x "$FAKE/bin/claude"
GOLD="$FIX/captures/validate-backlog-pane.json"
golden_validate() { sed '1d' "$GOLD" > "$FAKE/validate.json"; echo 0 > "$FAKE/validate.rc"; }   # drop the capture's comment line
golden_test() { printf ' 16 pass\n 0 fail\nRan 16 tests across 1 file. [0.18s]\n' > "$FAKE/test.out"; echo 0 > "$FAKE/test.rc"; }
engine() { : > "$FAKE/argv.log"; FAKE="$FAKE" PATH="$FAKE/bin:$NOCLAUDE_PATH" bash "$CHECK" --engine "$T" >"$T/out" 2>&1; echo $?; }
no_claude() { PATH="$NOCLAUDE_PATH" bash "$CHECK" --engine "$T" >"$T/out" 2>&1; echo $?; }

assert "claude absent -> exit 1" 1 "$(no_claude)"
assert "...with the documented message" yes "$(has 'claude CLI not on PATH — install it or run with --fast' "$(out)")"

golden_validate; golden_test
assert "golden validate (calls incl. '(via run)') + golden test trailer -> 0" 0 "$(engine)"
assert "every mod is validated and tested from an isolated copy (the engine writes types/tsconfig into the folder it reads)" 0 "$(grep -E '^plugin (validate --json|test) ' "$FAKE/argv.log" | grep -c -E " (mods/|$T/mods/)")"
assert "...one validate per mod under mods/ plus the good fixture" 3 "$(grep -c '^plugin validate --json ' "$FAKE/argv.log")"
assert "...labelled by repo path in the report" yes "$(has 'mods/_shared' "$(out)")"
iso="$(grep -E '^plugin test /.*/good-minimal$' "$FAKE/argv.log" | grep -v "$T/mods/" | grep -v -c "$FIX")"
assert "an isolated copy of the good fixture is exercised (not the fixture dir itself)" yes "$( [ "$iso" -ge 1 ] && echo yes || echo no)"
assert "summary names the engine version" yes "$(has '2.1.288' "$(out)")"

sed 's/\$\.ui\.open/$.http.fetch/' "$GOLD" | sed '1d' > "$FAKE/validate.json"
assert "a call outside the allowed set fails" 1 "$(engine)"
assert "...naming the call" yes "$(has 'http.fetch' "$(out)")"
assert "...and the allowed set" yes "$(has 'allowed set' "$(out)")"

golden_validate; sed -i.bak 's/register.tsx hooks: session.start/register.tsx hooks: tool.call, session.start/' "$FAKE/validate.json"   # portable-ok: BSD+GNU form with suffix
assert "a hooked tool.call reported by the engine fails (structural Law 4 — catches backtick and renamed registrations)" 1 "$(engine)"
assert "...naming the event" yes "$(has 'hooks event tool.call' "$(out)")"
for ev in tool.check plugin.register prompt.compose 'classic.PreToolUse' '*'; do
    golden_validate; sed -i.bak "s/register.tsx hooks: session.start/register.tsx hooks: $ev, session.start/" "$FAKE/validate.json"   # portable-ok: BSD+GNU form with suffix
    assert "hooking $ev fails" 1 "$(engine)"
done

golden_validate; python3 - "$FAKE/validate.json" <<'PY2'
import json,sys
p=sys.argv[1]; d=json.load(open(p))
for c in d['contents']: c['notes']=[n for n in c['notes'] if 'calls:' not in n]
json.dump(d,open(p,'w'))
PY2
assert "no calls: line at all fails (the structural proof is missing)" 1 "$(engine)"
assert "...saying so" yes "$(has 'no calls: line' "$(out)")"

golden_validate; python3 - "$FAKE/validate.json" <<'PY2'
import json,sys
p=sys.argv[1]; d=json.load(open(p)); d['success']=False; d['manifest']['errors']=[{"path":"root","message":"hooks.json must have hooks or modules"}]
json.dump(d,open(p,'w'))
PY2
echo 1 > "$FAKE/validate.rc"
assert "a failed plugin validate fails" 1 "$(engine)"
assert "...quoting the error" yes "$(has 'hooks.json must have' "$(out)")"

golden_validate; printf 'hooks/x.test.ts:\n(fail) boom\n 0 pass\n 1 fail\nRan 1 test across 1 file. [0.10s]\n' > "$FAKE/test.out"; echo 1 > "$FAKE/test.rc"
assert "a red plugin test fails" 1 "$(engine)"
assert "...showing the failing test" yes "$(has '(fail) boom' "$(out)")"

printf 'claude plugin test: x: no hooks module to load; there is no hooks/hooks.json naming one in "modules"\n' > "$FAKE/test.out"; echo 0 > "$FAKE/test.rc"
assert "plugin test exiting 0 with no 'Ran N tests' trailer fails (the engine skips a folder silently)" 1 "$(engine)"
assert "...naming the trap" yes "$(has 'no tests ran' "$(out)")"
printf ' 0 pass\n 0 fail\nRan 0 tests across 0 files. [0.01s]\n' > "$FAKE/test.out"
assert "plugin test with Ran 0 tests fails" 1 "$(engine)"

if command -v claude >/dev/null 2>&1 && [ -z "${CI:-}" ]; then
    echo "--- --engine against the real claude on this machine (skipped in CI: the validate job runs it as Check 77b)"
    bash "$CHECK" --engine "$ROOT" >"$T/real" 2>&1; rc=$?
    assert "real claude: --engine passes on this checkout" 0 "$rc"
    [ "$rc" = 0 ] || tail -20 "$T/real"
fi

echo "--- --installed (Law 3 over the plugin cache + refused-mod guard, t-3493)"
# A mod installed from ANY marketplace lands in <claude-dir>/plugins/cache/...; 77a never sees it.
# --installed reads plugins/installed_plugins.json, scans each function-hook mod (hooks/hooks.json
# with a modules key) for the Law 3 model/http rules, and — when `claude` is present — runs
# `plugin validate` on it: a mod the engine refuses at load still sits in the registry (and in a
# headless init record's plugins[]), so a refusal is a violation, never a pass.
BILL="$FIX/captures/t-3493-model-billing/mod"
H2="$T/home2"; mkdir -p "$H2/.claude/plugins"
reg() { # reg name:path ... -> installed_plugins.json
    python3 - "$H2/.claude/plugins/installed_plugins.json" "$@" <<'PYR'
import json, sys
out = {"version": 2, "plugins": {}}
for a in sys.argv[2:]:
    n, p = a.split(":", 1); out["plugins"][n + "@x"] = [{"scope": "user", "installPath": p, "version": "1.0.0"}]
json.dump(out, open(sys.argv[1], "w"))
PYR
}
inst() { PATH="$NOCLAUDE_PATH" bash "$CHECK" --installed "$H2/.claude" >"$T/out" 2>&1; echo $?; }
inst_engine() { : > "$FAKE/argv.log"; FAKE="$FAKE" PATH="$FAKE/bin:$NOCLAUDE_PATH" bash "$CHECK" --installed "$H2/.claude" >"$T/out" 2>&1; echo $?; }
rm -f "$H2/.claude/plugins/installed_plugins.json"
assert "no registry -> exit 0, nothing installed" 0 "$(inst)"
assert "...says so" yes "$(has 'nothing installed' "$(out)")"
mkdir -p "$H2/skillsonly/skills/a"; echo "# a" > "$H2/skillsonly/skills/a/SKILL.md"
mkdir -p "$H2/classic/hooks"; printf '{"hooks":{"PreToolUse":[]}}' > "$H2/classic/hooks/hooks.json"
reg good:"$T/mods/good-minimal" skillsonly:"$H2/skillsonly" classic:"$H2/classic" gone:"$H2/does-not-exist"
assert "good mod + skills-only + classic-hook plugin + missing path: exit 0 without claude" 0 "$(inst)"
assert "...only the function-hook mod is scanned (1 mod)" yes "$(has '1 mod(s) scanned' "$(out)")"
assert "...claude absent is said, not hidden" yes "$(has 'claude absent' "$(out)")"
reg good:"$T/mods/good-minimal" billing:"$BILL"
assert "an installed mod with a literal \$.model call fails" 1 "$(inst)"
assert "...naming the model rule" yes "$(has 'model — Law 3' "$(out)")"
assert "...and the mod" yes "$(has 'billing@x' "$(out)")"
reg good:"$T/mods/good-minimal"
golden_validate; golden_test
assert "with claude: a validating mod passes" 0 "$(inst_engine)"
assert "...plugin validate ran on the mod" yes "$(has 'plugin validate' "$(cat "$FAKE/argv.log")")"
sed '1d' "$FIX/captures/t-3493-model-billing/v1-bracket/validate.json" > "$FAKE/validate.json" 2>/dev/null || cp "$FIX/captures/t-3493-model-billing/v1-bracket/validate.json" "$FAKE/validate.json"
echo 1 > "$FAKE/validate.rc"
assert "with claude: a mod the engine refuses at load fails (listed as installed, would show as loaded)" 1 "$(inst_engine)"
assert "...naming the refusal" yes "$(has 'refused' "$(out)")"
golden_validate

echo; echo "Results: $PASS passed, $FAIL failed"; [ "$FAIL" -eq 0 ]
