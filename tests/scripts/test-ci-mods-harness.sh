#!/usr/bin/env bash
# CI side of the mods enforcement harness (t-3448; spec cockpit.md §ci.yml, ADR-096 Law 6):
#   ci.yml  — workflow env CC_VERSION pins the claude CLI and equals mods/_shared SUPPORTED;
#             the validate job installs that exact version and asserts `claude --version`
#             BEFORE "Run validation" (absent/wrong binary = red, the exit-127 class);
#             it fetches origin/dev first (Check 77a's version guard needs a base ref on a
#             depth-1 checkout); "Check version sync" delegates to marketplace-version-sync.sh;
#             the macOS job says how 77a reaches it (the suite, not validate.sh).
#   mods-drift.yml — scheduled + dispatchable, installs the LATEST claude, runs
#             mods-check.sh --engine; a red run is the signal to bump CC_VERSION and SUPPORTED.
#   marketplace-version-sync.sh — selects the brana entry BY NAME (never plugins[0]) and
#             checks every ./mods/* entry's version against its plugin.json.
# Run: bash tests/scripts/test-ci-mods-harness.sh
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
PASS=0; FAIL=0
# The workflow files are parsed with PyYAML. GitHub's ubuntu image ships it; stock macOS does
# not (CI run 37140367665). The files are the same bytes on both, so the required ubuntu
# `tests` job is the proof: there a missing PyYAML is a FAIL, on macOS a named SKIP.
if ! python3 -c 'import yaml' 2>/dev/null; then
    if [ "$(uname -s)" = Darwin ]; then echo "=== test-ci-mods-harness.sh ==="; echo "  SKIP: PyYAML absent on this macOS runner — the ubuntu tests job checks the workflow files"; exit 0; fi
    echo "  FAIL: PyYAML (python3 -c 'import yaml') is required to parse the workflow files"; exit 1
fi
assert() { if [ "$2" = "$3" ]; then PASS=$((PASS+1)); echo "  PASS: $1"; else FAIL=$((FAIL+1)); echo "  FAIL: $1 (expected '$2', got '$3')"; fi; }
has() { case "$2" in *"$1"*) echo yes;; *) echo no;; esac; }
cd "$ROOT" || exit 2
CI=.github/workflows/ci.yml; DRIFT=.github/workflows/mods-drift.yml; SYNC=system/scripts/marketplace-version-sync.sh
echo "=== test-ci-mods-harness.sh ==="

echo "--- ci.yml"
Q() { python3 - "$CI" "$@" <<'PY'
import sys, yaml
wf = yaml.safe_load(open(sys.argv[1]))
what = sys.argv[2]
def steps(job): return wf['jobs'][job]['steps']
def idx(job, needle):
    for i, s in enumerate(steps(job)):
        if needle in (s.get('name') or '') or needle in (s.get('run') or ''): return i
    return -1
if what == 'env': print((wf.get('env') or {}).get('CC_VERSION', ''))
elif what == 'install-before-validate':
    i, j = idx('validate', 'npm install -g "@anthropic-ai/claude-code@${CC_VERSION}"'), idx('validate', 'Run validation')
    print('yes' if 0 <= i < j else f'no (install={i}, validate={j})')
elif what == 'install-asserts-version':
    i = idx('validate', 'npm install -g @anthropic-ai/claude-code@')
    run = steps('validate')[i].get('run', '') if i >= 0 else ''
    print('yes' if 'claude --version' in run and 'CC_VERSION' in run and 'exit 1' in run else 'no')
elif what == 'install-ubuntu-only':
    i = idx('validate', 'npm install -g @anthropic-ai/claude-code@')
    print('yes' if i >= 0 and wf['jobs']['validate']['runs-on'].startswith('ubuntu') and idx('macos', 'npm install -g @anthropic-ai/claude-code@') < 0 else 'no')
elif what == 'fetch-dev-before-validate':
    i, j = idx('validate', 'refs/heads/dev:refs/remotes/origin/dev'), idx('validate', 'Run validation')
    run = steps('validate')[i].get('run', '') if i >= 0 else ''
    print('yes' if 0 <= i < j and 'git fetch' in run else f'no (fetch={i}, validate={j})')
elif what == 'version-sync-delegates':
    i = idx('validate', 'Check version sync')
    run = steps('validate')[i].get('run', '') if i >= 0 else ''
    print('yes' if 'marketplace-version-sync.sh' in run and "plugins'][0]" not in run and 'plugins[0]' not in run else 'no')
PY
}
PIN="$(Q env)"
assert "workflow env CC_VERSION is a release core" yes "$( [[ "$PIN" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] && echo yes || echo "no ($PIN)")"
assert "CC_VERSION is listed in mods/_shared probe.ts SUPPORTED" yes "$(has "'$PIN'" "$(grep -E '^export const SUPPORTED' mods/_shared/hooks/probe.ts)")"
assert "validate job installs the pinned CLI before Run validation" yes "$(Q install-before-validate)"
assert "the install step asserts claude --version prints the pin (else exit 1)" yes "$(Q install-asserts-version)"
assert "the install is ubuntu-only (macOS job has none)" yes "$(Q install-ubuntu-only)"
assert "validate job fetches origin/dev before Run validation (77a version guard base ref)" yes "$(Q fetch-dev-before-validate)"
assert "Check version sync delegates to marketplace-version-sync.sh and no longer reads plugins[0]" yes "$(Q version-sync-delegates)"
assert "macOS job comment names how 77a reaches it (77a) and that 77b is not run there" yes "$(has 77a "$(sed -n '/^  macos:/,$p' "$CI")")$(has 77b "$(sed -n '/^  macos:/,$p' "$CI")" | sed 's/yes//')"
assert "the exit-127 lesson is cited at the install step" yes "$(has 'exit-127' "$(sed -n '/^  validate:/,/^  tests:/p' "$CI")")"

echo "--- mods-drift.yml"
assert "mods-drift.yml exists" yes "$( [ -f "$DRIFT" ] && echo yes || echo no)"
D() { python3 - "$DRIFT" "$@" <<'PY' 2>/dev/null
import sys, yaml
wf = yaml.safe_load(open(sys.argv[1])); what = sys.argv[2]
on = wf.get('on') or wf.get(True) or {}
runs = "\n".join((s.get('run') or '') for j in wf['jobs'].values() for s in j['steps'])
if what == 'schedule': print('yes' if isinstance(on, dict) and on.get('schedule') and on['schedule'][0].get('cron') else 'no')
elif what == 'dispatch': print('yes' if isinstance(on, dict) and 'workflow_dispatch' in on else 'no')
elif what == 'latest': print('yes' if '@anthropic-ai/claude-code@latest' in runs else 'no')
elif what == 'engine': print('yes' if 'mods-check.sh --engine' in runs else 'no')
elif what == 'version-printed': print('yes' if 'claude --version' in runs else 'no')
elif what == 'supported-compared': print('yes' if 'SUPPORTED' in runs and 'probe.ts' in runs else 'no')
elif what == 'perms': print('yes' if (wf.get('permissions') or {}).get('contents') == 'read' else 'no')
PY
}
assert "runs on a schedule (cron)" yes "$(D schedule)"
assert "can be dispatched by hand" yes "$(D dispatch)"
assert "installs the LATEST claude" yes "$(D latest)"
assert "runs mods-check.sh --engine" yes "$(D engine)"
assert "prints the installed version" yes "$(D version-printed)"
assert "compares the installed version with probe.ts SUPPORTED (the bump signal)" yes "$(D supported-compared)"
assert "least privilege: contents read" yes "$(D perms)"

echo "--- marketplace-version-sync.sh"
assert "script exists and is executable" yes "$( [ -x "$SYNC" ] && echo yes || echo no)"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
mk() { # mk <dir> <brana-ver> <mod-ver-in-marketplace> <mod-plugin-ver|none>
    mkdir -p "$1/.claude-plugin" "$1/system/.claude-plugin" "$1/mods/cockpit-band/.claude-plugin"
    printf '{ "name": "brana", "version": "%s" }\n' "$2" > "$1/system/.claude-plugin/plugin.json"
    [ "$4" = none ] || printf '{ "name": "cockpit-band", "version": "%s" }\n' "$4" > "$1/mods/cockpit-band/.claude-plugin/plugin.json"
    printf '{ "name": "brana", "plugins": [ { "name": "cockpit-band", "version": "%s", "source": "./mods/cockpit-band" }, { "name": "brana", "version": "1.0.0", "source": "./system" } ] }\n' "$3" > "$1/.claude-plugin/marketplace.json"
}
run_sync() { bash "$SYNC" "$1" >"$T/out" 2>&1; echo $?; }
mk "$T/ok" 1.0.0 0.1.0 0.1.0;      assert "brana by name (not plugins[0]) + mod in sync -> 0" 0 "$(run_sync "$T/ok")"
mk "$T/brana" 1.0.1 0.1.0 0.1.0;   assert "brana version mismatch -> 1" 1 "$(run_sync "$T/brana")"; assert "...naming brana" yes "$(has brana "$(cat "$T/out")")"
mk "$T/mod" 1.0.0 0.1.0 0.1.1;     assert "mod marketplace version != its plugin.json -> 1" 1 "$(run_sync "$T/mod")"; assert "...naming the mod" yes "$(has cockpit-band "$(cat "$T/out")")"
mk "$T/nomod" 1.0.0 0.1.0 none;    assert "a ./mods/* entry whose dir has no manifest -> 1" 1 "$(run_sync "$T/nomod")"
assert "the real repo is in sync" 0 "$(run_sync "$ROOT")"

echo; echo "Results: $PASS passed, $FAIL failed"; [ "$FAIL" -eq 0 ]
