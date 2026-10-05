#!/usr/bin/env bash
# bootstrap.sh Step 7g (ruflo mods guard) and 7h (mods install by version compare) — t-3449,
# spec cockpit.md §bootstrap.sh, ADR-096 Law 6.
#   7g: an enabledPlugins entry ruflo-mods|ruflo-swarm|ruflo-console (any marketplace suffix) in
#       the user settings.json, the project .claude/settings.json or .claude/settings.local.json
#       makes --check exit non-zero naming it; a deploy prints the same and refuses the mods step.
#   7h: for each marketplace.json entry whose source starts with ./mods/: installed version
#       (plugins/installed_plugins.json, key <name>@brana) vs the repo's plugin.json —
#       missing -> `claude plugin install <name>@brana --scope user`, differing -> update,
#       equal -> '='. --check never runs `claude plugin`; it prints + / ~ / = and counts a change.
#       claude absent -> '! claude missing — mods not verified', counted, never fatal.
# Test seams (env, documented in bootstrap.sh): BRANA_MARKETPLACE_JSON, BRANA_PROJECT_SETTINGS_DIR.
# Run: bash tests/bootstrap/test-mods-step.sh
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
source "$ROOT/tests/lib/path-without.sh"
NOCLAUDE_PATH="$(path_without claude)"
PASS=0; FAIL=0
assert() { if [ "$2" = "$3" ]; then PASS=$((PASS+1)); echo "  PASS: $1"; else FAIL=$((FAIL+1)); echo "  FAIL: $1 (expected '$2', got '$3')"; fi; }
has() { case "$2" in *"$1"*) echo yes;; *) echo no;; esac; }
command -v jq >/dev/null 2>&1 || { echo "SKIP: jq required"; exit 0; }
echo "=== test-mods-step.sh ==="

T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
MP="$T/marketplace.json"
printf '{ "name": "brana", "plugins": [ { "name": "brana", "version": "1.0.0", "source": "./system" }, { "name": "cockpit-shared", "version": "0.1.0", "source": "./mods/_shared" } ] }\n' > "$MP"
PROJ="$T/proj-claude"; mkdir -p "$PROJ"
SHIM="$T/bin"; mkdir -p "$SHIM"
cat > "$SHIM/claude" <<'EOS'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "${CLAUDE_SHIM_LOG:?}"
case "$1 ${2:-}" in "--version "*) echo "2.1.288 (shim)";; esac
exit 0
EOS
chmod +x "$SHIM/claude"
newhome() { H="$(mktemp -d "$T/home.XXXXXX")"; mkdir -p "$H/.claude/plugins"; : > "$H/argv.log"; }
seed_installed() { printf '{"version":2,"plugins":{"cockpit-shared@brana":[{"scope":"user","installPath":"x","version":"%s"}]}}\n' "$1" > "$H/.claude/plugins/installed_plugins.json"; }
boot() { # boot --check [withclaude|noclaude] — the full script, dry run
    local mode="$1" cl="${2:-withclaude}" p="$NOCLAUDE_PATH"
    [ "$cl" = withclaude ] && p="$SHIM:$p"
    local args=(); [ "$mode" = --check ] && args=(--check)
    (cd "$ROOT" && HOME="$H" PATH="$p" CLAUDE_SHIM_LOG="$H/argv.log" BRANA_SCHEDULER_BACKEND=none BRANA_MARKETPLACE_JSON="$MP" BRANA_PROJECT_SETTINGS_DIR="$PROJ" ./bootstrap.sh "${args[@]}" >"$H/out" 2>&1); echo $?
}
out() { cat "$H/out"; }
plugin_calls() { grep -c '^plugin ' "$H/argv.log" 2>/dev/null || true; }

echo "--- 7h --check outcomes"
newhome; rc="$(boot --check)"
assert "--check, not installed: exit 0" 0 "$rc"
assert "...prints + would install" yes "$(has '+ cockpit-shared (would install v0.1.0)' "$(out)")"
assert "...runs no claude plugin command" 0 "$(plugin_calls)"
newhome; seed_installed 0.0.9; rc="$(boot --check)"
assert "--check, older installed: prints ~ would update old->new" yes "$(has '~ cockpit-shared (would update 0.0.9→0.1.0)' "$(out)")"
assert "...runs no claude plugin command" 0 "$(plugin_calls)"
newhome; seed_installed 0.1.0; rc="$(boot --check)"
assert "--check, equal: prints =" yes "$(has '= cockpit-shared (v0.1.0)' "$(out)")"
newhome; rc="$(boot --check noclaude)"
assert "--check, claude absent: still exit 0" 0 "$rc"
assert "...prints ! claude missing — mods not verified" yes "$(has '! claude missing — mods not verified' "$(out)")"
assert "...reaches the summary" yes "$(has 'change(s) detected' "$(out)")"

echo "--- 7h deploy outcomes (functions extracted: a real deploy refuses to run off main)"
FN="$(awk '/^mods_ruflo_guard\(\) \{/{f=1} /^mods_install_step\(\) \{/{f=1} f{print} f&&/^\}/{f=0}' "$ROOT/bootstrap.sh")"
assert "both functions extract from bootstrap.sh" yes "$(has 'mods_install_step()' "$FN")$(has 'mods_ruflo_guard()' "$FN" | sed 's/yes//')"
deploy() { # deploy [withclaude|noclaude] — runs 7g+7h as bootstrap does, CHECK_ONLY=false
    local p="$NOCLAUDE_PATH"; [ "${1:-withclaude}" = withclaude ] && p="$SHIM:$p"
    ( export PATH="$p" CLAUDE_SHIM_LOG="$H/argv.log"
      TARGET_DIR="$H/.claude"; SCRIPT_DIR="$ROOT"; INSTALLED="$H/.claude/plugins/installed_plugins.json"
      PROJECT_SETTINGS_DIR="$PROJ"; MANAGED_SETTINGS="$T/none.json"; MODS_MP="$MP"; CHECK_ONLY=false; CHANGES=0
      eval "$FN"; mods_ruflo_guard; mods_install_step; echo "CHANGES=$CHANGES" ) >"$H/out" 2>&1; echo $?
}
newhome; rc="$(deploy)"
assert "deploy, not installed: runs claude plugin install <name>@brana --scope user" yes "$(has 'plugin install cockpit-shared@brana --scope user' "$(cat "$H/argv.log")")"
assert "...prints + installed" yes "$(has '+ cockpit-shared (installed v0.1.0)' "$(out)")"
newhome; seed_installed 0.0.9; rc="$(deploy)"
assert "deploy, older installed: runs claude plugin update <name>@brana" yes "$(has 'plugin update cockpit-shared@brana' "$(cat "$H/argv.log")")"
assert "...prints ~ updated old->new" yes "$(has '~ cockpit-shared (updated 0.0.9→0.1.0)' "$(out)")"
newhome; seed_installed 0.1.0; rc="$(deploy)"
assert "deploy, equal: no claude plugin command" 0 "$(plugin_calls)"
assert "...counts no change" yes "$(has 'CHANGES=0' "$(out)")"
newhome; rc="$(deploy noclaude)"
assert "deploy, claude absent: prints the same ! line and continues (exit 0)" "0 yes" "$rc $(has '! claude missing — mods not verified' "$(out)")"

echo "--- panel findings: stdin, scope, object source, jq absent"
MP2="$T/marketplace2.json"
printf '{ "name": "brana", "plugins": [ { "name": "x", "version": "1.0.0", "source": { "source": "github", "repo": "a/b" } }, { "name": "cockpit-shared", "version": "0.1.0", "source": "./mods/_shared" }, { "name": "cockpit-shared-2", "version": "0.1.0", "source": "./mods/_shared" } ] }\n' > "$MP2"
cat > "$SHIM/claude-stdin" <<'EOS'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "${CLAUDE_SHIM_LOG:?}"
cat >/dev/null   # a subcommand that reads stdin must not eat the caller's loop input
exit 0
EOS
chmod +x "$SHIM/claude-stdin"
newhome; mkdir -p "$T/stdinbin"; ln -sf "$SHIM/claude-stdin" "$T/stdinbin/claude"
rc="$( ( export PATH="$T/stdinbin:$NOCLAUDE_PATH" CLAUDE_SHIM_LOG="$H/argv.log"
      TARGET_DIR="$H/.claude"; SCRIPT_DIR="$ROOT"; INSTALLED="$H/.claude/plugins/installed_plugins.json"
      PROJECT_SETTINGS_DIR="$PROJ"; MANAGED_SETTINGS="$T/none.json"; MODS_MP="$MP2"; CHECK_ONLY=false; CHANGES=0
      eval "$FN"; mods_ruflo_guard; mods_install_step ) >"$H/out" 2>&1; echo $?)"
assert "a claude that reads stdin cannot swallow later entries: both mods installed" 2 "$(grep -c '^plugin install' "$H/argv.log")"
assert "an object-form source neither breaks the step nor is treated as a mod" no "$(has 'x@brana' "$(cat "$H/argv.log")")"
newhome; printf '{"version":2,"plugins":{"cockpit-shared@brana":[{"scope":"project","version":"0.1.0"},{"scope":"user","version":"0.0.9"}]}}\n' > "$H/.claude/plugins/installed_plugins.json"; rc="$(boot --check)"
assert "the USER-scope install is compared (a project-scope entry first does not mask it)" yes "$(has '~ cockpit-shared (would update 0.0.9→0.1.0)' "$(out)")"
newhome; printf '{ "enabledPlugins": { "ruflo-mods@ruflo": true } }\n' > "$H/.claude/settings.json"; printf '{ "enabledPlugins": { "ruflo-swarm@ruflo": true } }\n' > "$PROJ/settings.json"; rc="$(boot --check)"; rm -f "$PROJ/settings.json"
assert "two hit files are listed separately" yes "$(has 'ruflo-mods@ruflo; ' "$(out)")"
newhome; printf '{ "enabledPlugins": { "ruflo-mods@ruflo": true } }\n' > "$T/managed.json"
rc="$(cd "$ROOT" && HOME="$H" PATH="$SHIM:$NOCLAUDE_PATH" CLAUDE_SHIM_LOG="$H/argv.log" BRANA_SCHEDULER_BACKEND=none BRANA_MARKETPLACE_JSON="$MP" BRANA_PROJECT_SETTINGS_DIR="$PROJ" BRANA_MANAGED_SETTINGS="$T/managed.json" ./bootstrap.sh --check >"$H/out" 2>&1; echo $?)"; rm -f "$T/managed.json"
assert "managed settings with ruflo-mods -> --check non-zero" yes "$( [ "$rc" != 0 ] && echo yes || echo no)"
NOJQ="$(path_without jq)"
newhome; rc="$( ( export PATH="$SHIM:$NOJQ" CLAUDE_SHIM_LOG="$H/argv.log"
      TARGET_DIR="$H/.claude"; SCRIPT_DIR="$ROOT"; INSTALLED="$H/.claude/plugins/installed_plugins.json"
      PROJECT_SETTINGS_DIR="$PROJ"; MANAGED_SETTINGS="$T/none.json"; MODS_MP="$MP"; CHECK_ONLY=true; CHANGES=0
      eval "$FN"; mods_ruflo_guard; mods_install_step; echo "CHANGES=$CHANGES" ) >"$H/out" 2>&1; echo $?)"
assert "jq absent with mods to install: the guard fails closed (cannot verify enabledPlugins)" yes "$(has 'jq missing — cannot verify enabledPlugins' "$(out)")"
assert "...and the mods step is refused" yes "$(has 'mods step refused' "$(out)")"
# (an unparsable USER settings.json already stops bootstrap in its earlier settings steps; the
#  project files are read by 7g alone, so that is where fail-closed must be proven)
newhome; printf '{ "enabledPlugins": { "ruflo-mods@ruflo": true, ' > "$PROJ/settings.local.json"; rc="$(boot --check)"; rm -f "$PROJ/settings.local.json"
assert "an unparsable settings file fails closed (cannot verify) -> --check non-zero" yes "$( [ "$rc" != 0 ] && echo yes || echo no)"
assert "...naming it unparsable" yes "$(has 'unparsable' "$(out)")"
cat > "$T/failbin-claude" <<'EOS'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "${CLAUDE_SHIM_LOG:?}"
case "$1 ${2:-}" in "plugin update"|"plugin install") exit 1;; esac
exit 0
EOS
chmod +x "$T/failbin-claude"; mkdir -p "$T/failbin"; ln -sf "$T/failbin-claude" "$T/failbin/claude"
newhome; seed_installed 0.0.9
( export PATH="$T/failbin:$NOCLAUDE_PATH" CLAUDE_SHIM_LOG="$H/argv.log"
  TARGET_DIR="$H/.claude"; SCRIPT_DIR="$ROOT"; INSTALLED="$H/.claude/plugins/installed_plugins.json"
  PROJECT_SETTINGS_DIR="$PROJ"; MANAGED_SETTINGS="$T/none.json"; MODS_MP="$MP"; CHECK_ONLY=false; CHANGES=0
  eval "$FN"; mods_ruflo_guard; mods_install_step ) >"$H/out" 2>&1
assert "update fails, uninstall succeeds, reinstall fails: says the mod is now NOT installed and how to reinstall" yes "$(has 'is now uninstalled — run: claude plugin install cockpit-shared@brana --scope user' "$(out)")"
assert "update and uninstall name the user scope" yes "$(has 'plugin update cockpit-shared@brana --scope user' "$(cat "$H/argv.log")")$(has 'plugin uninstall cockpit-shared@brana --scope user' "$(cat "$H/argv.log")" | sed 's/yes//')"

echo "--- 7g with nothing to protect (Gate 3 finding: exit 3 with no ./mods/ entry)"
MP_NOMODS="$T/marketplace-nomods.json"
printf '{ "name": "brana", "plugins": [ { "name": "brana", "version": "1.0.0", "source": "./system" } ] }\n' > "$MP_NOMODS"
newhome; printf '{ "enabledPlugins": { "ruflo-mods@ruflo": true } }\n' > "$H/.claude/settings.json"
rc="$(cd "$ROOT" && HOME="$H" PATH="$SHIM:$NOCLAUDE_PATH" CLAUDE_SHIM_LOG="$H/argv.log" BRANA_SCHEDULER_BACKEND=none BRANA_MARKETPLACE_JSON="$MP_NOMODS" BRANA_PROJECT_SETTINGS_DIR="$PROJ" BRANA_MANAGED_SETTINGS="$T/none.json" ./bootstrap.sh --check >"$H/out" 2>&1; echo $?)"
assert "no ./mods/ entry in the marketplace: an enabled ruflo-mods does NOT fail --check" 0 "$rc"
assert "...and prints no guard failure" no "$(has 'ruflo mods guard FAILED' "$(out)")"

echo "--- 7g ruflo mods guard"
for key in ruflo-mods@ruflo ruflo-swarm@ruflo ruflo-console@ruflo ruflo-mods; do
    newhome; printf '{ "enabledPlugins": { "%s": true } }\n' "$key" > "$H/.claude/settings.json"; rc="$(boot --check)"
    assert "user settings.json $key -> --check exits non-zero" yes "$( [ "$rc" != 0 ] && echo yes || echo no)"
    assert "...naming the entry" yes "$(has "$key" "$(out)")"
done
for f in settings.json settings.local.json; do
    newhome; printf '{ "enabledPlugins": { "ruflo-mods@ruflo": true } }\n' > "$PROJ/$f"; rc="$(boot --check)"; rm -f "$PROJ/$f"
    assert "project .claude/$f ruflo-mods@ruflo -> --check exits non-zero" yes "$( [ "$rc" != 0 ] && echo yes || echo no)"
    assert "...naming the file" yes "$(has "$f" "$(out)")"
done
newhome; printf '{ "enabledPlugins": { "ruflo-mods@ruflo": false, "brana@brana": true } }\n' > "$H/.claude/settings.json"; rc="$(boot --check)"
assert "a ruflo entry set to false is not a hit" 0 "$rc"
newhome; printf '{ "enabledPlugins": { "ruflo-swarm@ruflo": true } }\n' > "$H/.claude/settings.json"; rc="$(deploy)"
assert "deploy with a ruflo entry: refuses the mods step (no claude plugin command)" 0 "$(plugin_calls)"
assert "...and prints the guard line" yes "$(has 'ruflo-swarm@ruflo' "$(out)")"

echo; echo "Results: $PASS passed, $FAIL failed"; [ "$FAIL" -eq 0 ]
