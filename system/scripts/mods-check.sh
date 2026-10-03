#!/usr/bin/env bash
# mods-check.sh — the mods enforcement harness behind validate.sh Check 77a (--static) and
# 77b (--engine). ADR-096 Laws 2/3/4/6; spec docs/architecture/features/cockpit.md §Check 77.
#
# --static [ROOT]   No `claude` needed; runs under --fast and on macOS. Scans every .ts/.tsx
#                   that git does not ignore under mods/ (tracked or untracked — the engine
#                   writes .claude-plugin/types/ inside each mod and .gitignore covers it;
#                   *.test.ts(x) never load in a session and are skipped) and FAILS on:
#                     model, http            $.model / $.http (Law 3: no API-billed calls)
#                     bracket-model/-http    $['model'] / $["http"]  (bypass forms)
#                     reflect                Reflect.get(
#                     destructure            { model | http | process } pulled off $
#                     fetch                  global fetch(
#                     child_process          child_process
#                     tasks.json             reading the ledger (Law 2: reads go via brana)
#                     git-common-dir         resolving the common dir (the CLI does it)
#                     fs, readFile, Bun.file $.fs / readFile( / Bun.file(
#                     tool.call, tool.check  hooks that enforce (Law 4: mods render only)
#                     process                any `$.process` other than the canonical adapter
#                                            line (see mods/_shared/hooks/run.ts) — spawn included
#                     drift                  a mods/<mod>/hooks/_shared/*.ts not byte-identical
#                                            to mods/_shared/hooks/, or with no source there
#                     version                a mod whose files differ from the base ref while
#                                            its plugin.json version is unchanged (the install
#                                            cache copies by version: bump or it never reaches
#                                            the session — bootstrap 7g). Base ref: $MODS_BASE_REF,
#                                            else origin/dev, else dev; none resolvable = FAIL,
#                                            never a silent pass (CI fetches origin/dev first).
#                   Must-fire fixtures: tests/fixtures/mods/bad-*; suite tests/scripts/test-mods-check.sh.
# --engine [ROOT]   Needs `claude` (FAILS without it). For every mods/<mod>/ and an isolated
#                   vendored copy of tests/fixtures/mods/good-minimal: plugin validate --json
#                   must pass, every `calls:` entry must be in ALLOWED (no calls: line = FAIL),
#                   plugin test must exit 0 and report `Ran N tests` with N >= 1.
#
# Convention (validate.sh header): static assertions never live inside a check gated by --fast
# or by an optional binary; the gated half FAILS when its binary is absent.
# Exit: 0 clean, 1 violations, 2 usage/environment.
set -u
MODE="${1:-}"
ROOT="${2:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
case "$MODE" in
    --static|--engine) ;;
    *) echo "usage: mods-check.sh --static|--engine [ROOT]" >&2; exit 2 ;;
esac
cd "$ROOT" || exit 2

ADAPTER='const run = ($: EngineInterface, argv: readonly string[]) => guard(argv, () => $.process.run(argv, { timeoutMs: DEFAULT_TIMEOUT_MS }))'
SHARED_SRC="mods/_shared/hooks"
VIOL=0
viol() { VIOL=$((VIOL + 1)); echo "  $1"; }

# ============================== --engine (Check 77b) ===========================================
# Needs the real engine: `claude plugin validate --json` must pass and its `calls:` lines must
# stay inside ALLOWED (structural — catches indirection the greps miss); `claude plugin test`
# must exit 0 AND report `Ran N tests` with N >= 1 (the engine exits 0 without running anything
# when a folder has no hooks module — tests/fixtures/mods/captures/test-backlog-pane.txt, t-3446).
# Targets: every mods/<mod>/ with a manifest (_shared included) plus an isolated, freshly
# vendored copy of tests/fixtures/mods/good-minimal, so the pinned CLI in CI meets a real mod
# even while mods/ holds none yet. `claude` absent = FAIL (never a silent pass).
ALLOWED=(process.run prompt.fill ui.open ui.resolve ui.status ui.toast state.get state.set session.usage session.version command.register clock.now)
SHARED_FILES=(allowlist run state probe snapshot)
if [ "$MODE" = "--engine" ]; then
    if ! command -v claude >/dev/null 2>&1; then
        echo "  FAIL: claude CLI not on PATH — install it or run with --fast"
        exit 1
    fi
    CLAUDE_VER="$(claude --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)"
    WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
    targets=()
    for mod in mods/*/; do mod="${mod%/}"; [ -f "$mod/.claude-plugin/plugin.json" ] && targets+=("$mod"); done
    if [ -d tests/fixtures/mods/good-minimal ] && [ -d "$SHARED_SRC" ]; then
        iso="$WORK/good-minimal"; cp -R tests/fixtures/mods/good-minimal "$iso"; mkdir -p "$iso/hooks/_shared"
        for f in "${SHARED_FILES[@]}"; do cp "$SHARED_SRC/$f.ts" "$iso/hooks/_shared/$f.ts"; done
        targets+=("$iso")
    fi
    [ "${#targets[@]}" -gt 0 ] || { echo "mods-check --engine: nothing to check"; exit 0; }
    ntargets=0
    for t in "${targets[@]}"; do
        ntargets=$((ntargets + 1))
        label="$t"; case "$t" in "$WORK"/*) label="tests/fixtures/mods/$(basename "$t") (isolated copy)";; esac
        # -- validate + calls allowed-set
        vjson="$WORK/validate.$ntargets.json"
        claude plugin validate --json "$t" >"$vjson" 2>"$WORK/validate.err"; vrc=$?
        report="$(python3 - "$vjson" "$vrc" "${ALLOWED[@]}" <<'PYV'
import json, re, sys
path, rc, allowed = sys.argv[1], int(sys.argv[2]), set(sys.argv[3:])
try:
    d = json.load(open(path))
except Exception as e:
    print(f"ERR validate output is not JSON (rc={rc}): {e}"); sys.exit(0)
errs = []
for sec in [d.get("manifest") or {}] + list(d.get("contents") or []):
    for e in sec.get("errors") or []:
        errs.append(f"{e.get('path','?')}: {e.get('message','')}")
if not d.get("success") or rc != 0:
    print("ERR validate failed (rc=%d): %s" % (rc, "; ".join(errs) or "no error text"))
calls_lines = [n for sec in (d.get("contents") or []) for n in (sec.get("notes") or []) if " calls: " in n]
if not calls_lines:
    print("ERR no calls: line in plugin validate output — the structural proof is missing (is hooks/hooks.json naming a module?)")
for line in calls_lines:
    body = line.split(" calls: ", 1)[1].strip()
    if body.startswith("nothing"):
        continue
    for raw in body.split(","):
        c = re.sub(r"\s*\(via [^)]*\)", "", raw).strip()
        c = c[2:] if c.startswith("$.") else c
        if c and c not in allowed:
            print(f"ERR call {c} is outside the allowed set ({', '.join(sorted(allowed))})")
print("OK calls: " + " | ".join(calls_lines) if calls_lines else "OK")
PYV
)"
        while IFS= read -r line; do
            case "$line" in ERR*) viol "$label: ${line#ERR }";; esac
        done <<< "$report"
        # -- plugin test: rc 0 and a real trailer
        tout="$WORK/test.$ntargets.out"
        claude plugin test "$t" >"$tout" 2>&1; trc=$?
        ran="$(grep -oE 'Ran [0-9]+ tests? across' "$tout" | grep -oE '[0-9]+' | head -1)"
        if [ "$trc" -ne 0 ]; then
            viol "$label: plugin test failed (rc=$trc):"; grep -E '^\(fail\)|^  |^hooks/|^tests/|pass$|fail$|^Ran ' "$tout" | tail -25 | sed 's/^/      /'
        elif [ -z "$ran" ] || [ "$ran" -eq 0 ]; then
            viol "$label: no tests ran — plugin test exited 0 without a 'Ran N tests' trailer (N>=1): $(head -1 "$tout")"
        fi
    done
    echo "mods-check --engine: claude $CLAUDE_VER, $ntargets target(s), violations: $VIOL"
    [ "$VIOL" -eq 0 ]; exit $?
fi

[ -d mods ] || { echo "mods-check --static: no mods/ directory under $ROOT — nothing to check"; exit 0; }

# ---- 1. token rules over the git-visible, non-test sources ---------------------------------
RULE_ID=(  model          http           bracket-model          bracket-http            reflect          destructure                                   fetch               child_process     tasks.json      git-common-dir                      fs            readFile          Bun.file       tool.call                         tool.check )
RULE_PAT=( '\$\.model\b'  '\$\.http\b'   "\[['\"]model['\"]\]"  "\[['\"]http['\"]\]"    'Reflect\.get\(' '\{[^}]*\b(model|http|process)\b[^}]*\}[[:space:]]*=[[:space:]]*\$'  '(^|[^A-Za-z0-9_.$])fetch\(' 'child_process'   'tasks\.json'   '(git-common-dir|GIT_COMMON_DIR)'   '\$\.fs\b'    '\breadFile\b'    'Bun\.file'    "on\([[:space:]]*['\"]tool\.call['\"]"  "on\([[:space:]]*['\"]tool\.check['\"]" )
RULE_WHY=( 'Law 3: no API-billed calls' 'Law 3: no network' 'Law 3: bracket access bypasses nothing' 'Law 3: bracket access bypasses nothing' 'Law 3: no reflective access to $' 'Law 3: do not pull model/http/process off $' 'Law 3: no global fetch' 'Law 3: no child processes outside run()' 'Law 2: the ledger is read by brana, never by a mod' 'Law 2: the CLI resolves the common dir' 'Law 2: no file reads' 'Law 2: no file reads' 'Law 2: no file reads' 'Law 4: mods render, never enforce' 'Law 4: mods render, never enforce' )

FILES="$(git ls-files -co --exclude-standard -- mods 2>/dev/null | grep -E '\.tsx?$' | grep -v -E '\.test\.tsx?$' || true)"
nfiles=0
while IFS= read -r f; do
    [ -n "$f" ] && [ -f "$f" ] || continue
    nfiles=$((nfiles + 1))
    # full-line comments cannot call anything
    code="$(grep -n -v -E '^[[:space:]]*(//|\*|/\*)' "$f")"
    i=0
    while [ "$i" -lt "${#RULE_ID[@]}" ]; do
        hits="$(printf '%s\n' "$code" | grep -E "${RULE_PAT[$i]}" | cut -d: -f1 || true)"
        for ln in $hits; do viol "$f:$ln: ${RULE_ID[$i]} — ${RULE_WHY[$i]}"; done
        i=$((i + 1))
    done
    # process: only the canonical adapter line may touch $.process at all
    hits="$(printf '%s\n' "$code" | grep -E '\$\.process\b' || true)"
    while IFS= read -r hit; do
        [ -n "$hit" ] || continue
        ln="${hit%%:*}"; text="${hit#*:}"
        trimmed="$(printf '%s' "$text" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//')"
        [ "$trimmed" = "$ADAPTER" ] && continue
        viol "$f:$ln: process — only the canonical adapter line may call \$.process.run (mods/_shared/hooks/run.ts); spawn is never allowed"
    done <<< "$hits"
done <<< "$FILES"

# ---- 2. vendored copies must be byte-identical to mods/_shared --------------------------------
for dir in mods/*/hooks/_shared; do
    [ -d "$dir" ] || continue
    case "$dir" in mods/_shared/*) continue ;; esac
    for copy in "$dir"/*.ts; do
        [ -f "$copy" ] || continue
        src="$SHARED_SRC/$(basename "$copy")"
        if [ ! -f "$src" ]; then viol "$copy: drift — no such file in $SHARED_SRC (stale vendored copy; delete it)"
        elif ! cmp -s "$src" "$copy"; then viol "$copy: drift — differs from $src (run system/scripts/mods-sync-shared.sh)"; fi
    done
done

# ---- 3. version-bump guard against the base ref ----------------------------------------------
BASE="${MODS_BASE_REF:-}"
if [ -z "$BASE" ]; then
    for c in origin/dev dev; do git rev-parse --verify -q "$c^{commit}" >/dev/null 2>&1 && { BASE="$c"; break; }; done
fi
if [ -z "$BASE" ] || ! git rev-parse --verify -q "$BASE^{commit}" >/dev/null 2>&1; then
    viol "mods: version — no base ref to compare against (MODS_BASE_REF='${MODS_BASE_REF:-}', origin/dev and dev absent); fetch origin/dev or set MODS_BASE_REF"
else
    ver_of() { grep -oE '"version"[[:space:]]*:[[:space:]]*"[^"]+"' | head -1 | sed -E 's/.*"([^"]+)"$/\1/'; }
    for mod in mods/*/; do
        mod="${mod%/}"
        [ -f "$mod/.claude-plugin/plugin.json" ] || continue
        git cat-file -e "$BASE:$mod/.claude-plugin/plugin.json" 2>/dev/null || continue   # new since base: nothing to bump against
        changed=false
        git diff --quiet "$BASE" -- "$mod" 2>/dev/null || changed=true
        [ -n "$(git ls-files --others --exclude-standard -- "$mod")" ] && changed=true
        $changed || continue
        now="$(ver_of < "$mod/.claude-plugin/plugin.json")"
        was="$(git show "$BASE:$mod/.claude-plugin/plugin.json" 2>/dev/null | ver_of)"
        [ "$now" = "$was" ] && viol "$mod/.claude-plugin/plugin.json: version — files differ from $BASE but version is still $was (bump it: the plugin cache copies by version)"
    done
fi

echo "mods-check --static: $nfiles file(s) scanned, violations: $VIOL (base ref: ${BASE:-none})"
[ "$VIOL" -eq 0 ]
