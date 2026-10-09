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
# --installed [CLAUDE_DIR]  Law 3 over the PLUGIN CACHE (t-3493). The engine loads mods from
#                   <CLAUDE_DIR>/plugins/cache/..., from any marketplace — 77a never sees them. Reads
#                   plugins/installed_plugins.json; every function-hook mod (hooks/hooks.json with a
#                   `modules` key) is scanned for the model/http/bracket/destructure/Reflect/fetch rules,
#                   and — when `claude` is on PATH — `plugin validate --json` must pass: a mod the engine
#                   refuses at load still sits in the registry and in a headless init record's
#                   `plugins[]` (probe 2026-10-07), so a refusal is a violation, never a pass. `claude`
#                   absent: the static half runs and the summary SAYS the refusal half was skipped (the
#                   deploy-side caller, bootstrap 7i, always has the binary). MODS_INSTALLED_STATIC_ONLY=1
#                   skips the refusal half deliberately (validate --fast). Skills-only and classic-hook
#                   plugins cannot call $ and are not mods: skipped, not scanned. Fails CLOSED: an
#                   unreadable or mis-shaped registry, or a missing python3, is a violation, never
#                   "0 scanned". The scan follows the engine's own module list (hooks.json `modules`),
#                   so a module outside hooks/ or named *.test.* is scanned when listed. With the
#                   engine, the validate output's `calls:` listing is also parsed: any model.* or
#                   http.* call is a Law 3 violation even when validate succeeds (the structural
#                   proof 77b relies on). Copies follow symlinks (cp -L) so the audit never deletes
#                   inside a symlinked install; one installPath is scanned once however many
#                   registry entries point at it.
# --refusal-canary [ROOT]  Needs `claude` (FAILS without it). Runs `plugin validate` on the four
#                   captured bypass variants under tests/fixtures/mods/captures/t-3493-model-billing
#                   and FAILS if the engine now accepts any of them — the premise "the validator
#                   refuses every non-literal $ spelling, so a literal grep is a sufficient Law 3
#                   guard" must be re-proven per engine version (weekly mods-drift.yml, 77b locally).
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
    --installed) CLAUDE_DIR="${2:-${CLAUDE_CONFIG_DIR:-$HOME/.claude}}"; ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)" ;;
    --refusal-canary) ;;
    *) echo "usage: mods-check.sh --static|--engine|--refusal-canary [ROOT] | --installed [CLAUDE_DIR]" >&2; exit 2 ;;
esac
cd "$ROOT" || exit 2

ADAPTER='const run = ($: EngineInterface, argv: readonly string[]) => guard(argv, () => $.process.run(argv, { timeoutMs: DEFAULT_TIMEOUT_MS }))'
SHARED_SRC="mods/_shared/hooks"
VIOL=0
viol() { VIOL=$((VIOL + 1)); echo "  $1"; }

# Token rules (Law 2/3/4). --static applies all of them to mods/**; --installed applies the first
# seven (Law 3: model, http, bracket-*, reflect, destructure, fetch) to the plugin cache.
RULE_ID=(  model          http           bracket-model          bracket-http            reflect          destructure                                   fetch               child_process     tasks.json      git-common-dir                      fs            readFile          Bun.file       tool.call                         tool.check )
RULE_PAT=( '\$\.model\b'  '\$\.http\b'   "\[['\"]model['\"]\]"  "\[['\"]http['\"]\]"    'Reflect\.get\(' '\{[^}]*\b(model|http|process)\b[^}]*\}[[:space:]]*=[[:space:]]*\$'  '(^|[^A-Za-z0-9_.$])fetch\(' 'child_process'   'tasks\.json'   '(git-common-dir|GIT_COMMON_DIR)'   '\$\.fs\b'    '\breadFile\b'    'Bun\.file'    "on\([[:space:]]*['\"]tool\.call['\"]"  "on\([[:space:]]*['\"]tool\.check['\"]" )
RULE_WHY=( 'Law 3: no API-billed calls' 'Law 3: no network' 'Law 3: bracket access bypasses nothing' 'Law 3: bracket access bypasses nothing' 'Law 3: no reflective access to $' 'Law 3: do not pull model/http/process off $' 'Law 3: no global fetch' 'Law 3: no child processes outside run()' 'Law 2: the ledger is read by brana, never by a mod' 'Law 2: the CLI resolves the common dir' 'Law 2: no file reads' 'Law 2: no file reads' 'Law 2: no file reads' 'Law 4: mods render, never enforce' 'Law 4: mods render, never enforce' )
# Comments cannot call anything: drop // and JSDoc-body (*) lines and a line that only opens a block
# comment, but first strip a closed leading /* ... */ so code after it on the same line is still
# scanned (panel finding: `/* x */ $.model...` was invisible). Prints "<line>:<text>".
code_lines() { grep -n '' "$1" | sed -E 's#^([0-9]+:)[[:space:]]*/\*.*\*/#\1#' | grep -v -E '^[0-9]+:[[:space:]]*(//|\*|/\*)' || true; }

# ============================== --installed (Check 77c, bootstrap 7i) ==========================
LAW3_RULE_NAMES="model http bracket-model bracket-http reflect destructure fetch"   # by name, not position
if [ "$MODE" = "--installed" ]; then
    REG="$CLAUDE_DIR/plugins/installed_plugins.json"
    [ -f "$REG" ] || { echo "mods-check --installed: nothing installed ($REG absent)"; exit 0; }
    if ! command -v python3 >/dev/null 2>&1; then
        viol "$REG: python3 missing — cannot verify installed mods (fail closed)"
        echo "mods-check --installed: 0 mod(s) scanned in $REG, violations: $VIOL"; exit 1
    fi
    # name(s)<TAB>installPath<TAB>module... — one line per DISTINCT installPath (dedupe), modules
    # taken from hooks/hooks.json `modules` (the engine's own list), resolved against hooks/.
    ENTRIES="$(python3 - "$REG" <<'PYE'
import json, os, sys
try:
    d = json.load(open(sys.argv[1]))
    if not isinstance(d, dict) or not isinstance(d.get("plugins"), dict):
        raise ValueError("registry is not an object with a plugins object")
    seen = {}
    for name, entries in d["plugins"].items():
        for e in entries if isinstance(entries, list) else [entries]:
            p = (e or {}).get("installPath") if isinstance(e, dict) else None
            if not p: continue
            seen.setdefault(os.path.normpath(p), []).append(name)
    for p, names in seen.items():
        hooks = os.path.join(p, "hooks", "hooks.json")
        if not os.path.isdir(p) or not os.path.isfile(hooks): continue
        try:
            h = json.load(open(hooks))
        except Exception as ex:
            print("\t".join([",".join(sorted(set(names))), p, "ERR:hooks.json unparsable: %s" % ex])); continue
        mods = h.get("modules") if isinstance(h, dict) else None
        if not isinstance(mods, list) or not mods: continue
        files = [os.path.normpath(os.path.join(p, "hooks", m)) for m in mods if isinstance(m, str)]
        print("\t".join([",".join(sorted(set(names))), p] + files))
except Exception as ex:
    print("ERR " + str(ex)); sys.exit(3)
PYE
)"; prc=$?
    if [ "$prc" -ne 0 ] || [ "${ENTRIES#ERR}" != "$ENTRIES" ]; then
        viol "$REG: unparsable or mis-shaped (${ENTRIES#ERR }) — cannot verify installed mods (fail closed)"
        echo "mods-check --installed: 0 mod(s) scanned in $REG, violations: $VIOL"; exit 1
    fi
    HAVE_CLAUDE=false; command -v claude >/dev/null 2>&1 && [ -z "${MODS_INSTALLED_STATIC_ONLY:-}" ] && HAVE_CLAUDE=true
    WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
    nmods=0
    while IFS=$'\t' read -r name path rest; do
        [ -n "$name" ] && [ -n "$path" ] || continue
        nmods=$((nmods + 1))
        case "$rest" in ERR:*) viol "$name: ${rest#ERR:} — cannot verify (fail closed)"; continue;; esac
        # static half: exactly the modules the engine will load
        while IFS=$'\t' read -r f; do
            [ -n "$f" ] || continue
            if [ ! -f "$f" ]; then viol "$name: ${f#$path/}: listed in hooks.json modules but missing — the engine would fail the module load"; continue; fi
            code="$(code_lines "$f")"
            for rid in $LAW3_RULE_NAMES; do
                i=0; while [ "$i" -lt "${#RULE_ID[@]}" ]; do [ "${RULE_ID[$i]}" = "$rid" ] && break; i=$((i + 1)); done
                hits="$(printf '%s\n' "$code" | grep -E "${RULE_PAT[$i]}" | cut -d: -f1 || true)"
                for ln in $hits; do viol "$name: ${f#$path/}:$ln: ${RULE_ID[$i]} — ${RULE_WHY[$i]}"; done
            done
        done < <(printf '%s\n' "$rest" | tr '\t' '\n')   # trailing newline: read drops an unterminated last line
        # engine half: an isolated, symlink-resolved copy (never rm inside the real install)
        if $HAVE_CLAUDE; then
            cpy="$WORK/$nmods"; mkdir -p "$cpy"; cp -RL -- "$path/." "$cpy/"; rm -rf "$cpy/.claude-plugin/types" "$cpy/tsconfig.json"
            vjson="$WORK/validate.$nmods.json"
            claude plugin validate --json "$cpy" >"$vjson" 2>"$WORK/validate.err"; vrc=$?
            report="$(python3 - "$vjson" "$vrc" <<'PYV'
import json, re, sys
path, rc = sys.argv[1], int(sys.argv[2])
try:
    d = json.load(open(path))
except Exception as e:
    print(f"REFUSED validate output is not JSON (rc={rc}): {e}"); sys.exit(0)
if not d.get("success") or rc != 0:
    errs = [f"{e.get('path','?')}: {e.get('message','')}" for sec in [d.get("manifest") or {}] + list(d.get("contents") or []) for e in (sec.get("errors") or [])]
    print("REFUSED rc=%d: %s" % (rc, "; ".join(errs)[:300] or "no error text"))
# the engine's own calls: listing — structural, catches what a grep cannot (77b's proof)
for line in [n for sec in (d.get("contents") or []) for n in (sec.get("notes") or []) if " calls: " in n]:
    body = line.split(" calls: ", 1)[1].strip()
    if body.startswith("nothing"): continue
    for raw in body.split(","):
        c = re.sub(r"\s*\(via [^)]*\)", "", raw).strip()
        c = c[2:] if c.startswith("$.") else c
        if c.startswith("model.") or c.startswith("http."):
            print(f"LAW3 call {c} in the engine's calls: listing")
PYV
)"
            while IFS= read -r line; do
                case "$line" in
                    REFUSED*) viol "$name: refused by the engine at load (plugin validate failed, ${line#REFUSED }) — yet listed in $REG, and a headless init record's plugins[] would list it as loaded (t-3493)";;
                    LAW3*) viol "$name: ${line#LAW3 } — Law 3: no API-billed calls, no network";;
                esac
            done <<< "$report"
        fi
    done <<< "$ENTRIES"
    if $HAVE_CLAUDE; then half="refusal check ran (claude $(claude --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1))"
    else half="claude absent or MODS_INSTALLED_STATIC_ONLY: refusal check skipped"; fi
    echo "mods-check --installed: $nmods mod(s) scanned in $REG, violations: $VIOL ($half)"
    [ "$VIOL" -eq 0 ]; exit $?
fi

# ============================== --refusal-canary (mods-drift.yml, 77b locally) ================
if [ "$MODE" = "--refusal-canary" ]; then
    if ! command -v claude >/dev/null 2>&1; then
        echo "  FAIL: claude CLI not on PATH — the refusal canary needs the engine"; exit 1
    fi
    CAN="tests/fixtures/mods/captures/t-3493-model-billing"
    WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
    n=0
    for v in "$CAN"/v*/; do
        v="${v%/}"; [ -f "$v/hooks/hooks.json" ] || continue
        n=$((n + 1)); cpy="$WORK/$(basename "$v")"; mkdir -p "$cpy/.claude-plugin"; cp -RL -- "$v/hooks" "$cpy/hooks"
        printf '{"name":"%s","version":"0.0.1","description":"t-3493 refusal canary"}\n' "$(basename "$v")" > "$cpy/.claude-plugin/plugin.json"
        claude plugin validate --json "$cpy" >"$WORK/v.json" 2>/dev/null; rc=$?
        ok="$(python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print("yes" if d.get("success") else "no")' "$WORK/v.json" 2>/dev/null || echo no)"
        if [ "$rc" -eq 0 ] && [ "$ok" = yes ]; then viol "$(basename "$v"): the engine now ACCEPTS this bypass spelling — Law 3's literal grep is no longer sufficient; re-prove the guard (t-3493)"
        else echo "  ok: $(basename "$v") still refused"; fi
    done
    [ "$n" -ge 4 ] || viol "refusal canary: expected 4 captured variants under $CAN, found $n"
    echo "mods-check --refusal-canary: claude $(claude --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1), $n variant(s), violations: $VIOL"
    [ "$VIOL" -eq 0 ]; exit $?
fi

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
    # Every target runs from an isolated copy: `plugin validate|test` write .claude-plugin/types/ and
    # tsconfig.json into the folder they read, so two runs on one checkout (a local validate beside
    # mods-drift, two worktrees' sessions) would read each other's half-written files (panel finding).
    # Mods are self-contained (shared code is vendored), so a copy loads exactly as the folder does.
    targets=(); labels=()
    for mod in mods/*/; do
        mod="${mod%/}"; [ -f "$mod/.claude-plugin/plugin.json" ] || continue
        cpy="$WORK/mods/$(basename "$mod")"; mkdir -p "$WORK/mods"; cp -R "$mod" "$cpy"
        rm -rf "$cpy/.claude-plugin/types" "$cpy/tsconfig.json"
        targets+=("$cpy"); labels+=("$mod")
    done
    if [ -d tests/fixtures/mods/good-minimal ] && [ -d "$SHARED_SRC" ]; then
        iso="$WORK/good-minimal"; cp -R tests/fixtures/mods/good-minimal "$iso"; mkdir -p "$iso/hooks/_shared"
        for f in "${SHARED_FILES[@]}"; do cp "$SHARED_SRC/$f.ts" "$iso/hooks/_shared/$f.ts"; done
        targets+=("$iso"); labels+=("tests/fixtures/mods/good-minimal (isolated copy)")
    fi
    [ "${#targets[@]}" -gt 0 ] || { echo "mods-check --engine: nothing to check"; exit 0; }
    ntargets=0
    for t in "${targets[@]}"; do
        label="${labels[$ntargets]}"
        ntargets=$((ntargets + 1))
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
# Law 4, structural: the engine's own scan of what the module hooks. Catches registrations the
# 77a greps cannot (backtick event names, a renamed `on`) — panel finding.
DENY_HOOKS = {"tool.call", "tool.check", "plugin.register", "prompt.compose", "*"}
for line in [n for sec in (d.get("contents") or []) for n in (sec.get("notes") or []) if " hooks: " in n]:
    body = line.split(" hooks: ", 1)[1].strip()
    if body.startswith("nothing"):
        continue
    for raw in re.split(r",\s*(?![^{]*\})", body):
        ev = re.sub(r"\{.*\}", "", raw).strip()
        if ev in DENY_HOOKS or ev.startswith("classic."):
            print(f"ERR hooks event {ev} — mods render, never enforce or rewrite (ADR-096 Law 4)")
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
        before=$VIOL
        while IFS= read -r line; do
            case "$line" in ERR*) viol "$label: ${line#ERR }";; esac
        done <<< "$report"
        [ "$VIOL" -eq "$before" ] && echo "  ok: $label — plugin validate, calls and hooks within the allowed sets"
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

# Every extension the engine will load as a module (probed: .js/.mjs pass `plugin validate`), not just .ts.
FILES="$(git ls-files -co --exclude-standard -- mods 2>/dev/null | grep -E '\.(tsx?|mts|cts|jsx?|mjs|cjs)$' | grep -v -E '\.test\.(tsx?|mts|cts|jsx?|mjs|cjs)$' || true)"
nfiles=0
while IFS= read -r f; do
    [ -n "$f" ] && [ -f "$f" ] || continue
    nfiles=$((nfiles + 1))
    code="$(code_lines "$f")"
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
# Base ref: $MODS_BASE_REF as given; otherwise the first of origin/dev, dev, origin/main, main whose
# commit is NOT HEAD — a base equal to the commit under test makes every diff empty and the guard
# vacuous (panel finding: on the dev->main ship PR the fetched origin/dev IS HEAD). The comparison
# point is the merge-base, so a stale or ahead base cannot invent or hide changes.
BASE="${MODS_BASE_REF:-}"; NO_DISTINCT=false
HEAD_SHA="$(git rev-parse -q --verify 'HEAD^{commit}' 2>/dev/null || true)"
if [ -z "$BASE" ]; then
    seen=0
    for c in origin/dev dev origin/main main; do
        sha="$(git rev-parse -q --verify "$c^{commit}" 2>/dev/null)" || continue
        seen=$((seen + 1))
        [ "$sha" = "$HEAD_SHA" ] && continue
        BASE="$c"; break
    done
    [ -z "$BASE" ] && [ "$seen" -gt 0 ] && NO_DISTINCT=true
fi
if $NO_DISTINCT; then
    # Every known base IS the commit under test: only uncommitted edits can differ, so compare
    # the working tree with HEAD (vacuous on a clean CI checkout, which is then the truth).
    BASE="HEAD"; echo "  (version guard: no base distinct from HEAD — origin/dev, dev, origin/main, main all point at the commit under test; comparing the working tree with HEAD)"
fi
if [ -z "$BASE" ] || ! git rev-parse --verify -q "$BASE^{commit}" >/dev/null 2>&1; then
    viol "mods: version — no base ref to compare against (MODS_BASE_REF='${MODS_BASE_REF:-}', origin/dev, dev, origin/main, main absent); fetch origin/dev or set MODS_BASE_REF"
else
    MB="$(git merge-base HEAD "$BASE" 2>/dev/null || git rev-parse "$BASE^{commit}")"
    ver_of() { grep -oE '"version"[[:space:]]*:[[:space:]]*"[^"]+"' | head -1 | sed -E 's/.*"([^"]+)"$/\1/'; }
    for mod in mods/*/; do
        mod="${mod%/}"
        [ -f "$mod/.claude-plugin/plugin.json" ] || continue
        git cat-file -e "$MB:$mod/.claude-plugin/plugin.json" 2>/dev/null || continue   # new since base: nothing to bump against
        changed=false
        git diff --quiet "$MB" -- "$mod" 2>/dev/null || changed=true
        [ -n "$(git ls-files --others --exclude-standard -- "$mod")" ] && changed=true
        $changed || continue
        now="$(ver_of < "$mod/.claude-plugin/plugin.json")"
        was="$(git show "$MB:$mod/.claude-plugin/plugin.json" 2>/dev/null | ver_of)"
        [ "$now" = "$was" ] && viol "$mod/.claude-plugin/plugin.json: version — files differ from $BASE but version is still $was (bump it: the plugin cache copies by version)"
    done
fi

echo "mods-check --static: $nfiles file(s) scanned, violations: $VIOL (base ref: ${BASE:-none})"
[ "$VIOL" -eq 0 ]
