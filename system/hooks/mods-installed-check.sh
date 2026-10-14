#!/usr/bin/env bash
# mods-installed-check.sh — SessionStart trigger for the installed-mods Law 3 scan (t-3502).
#
# validate.sh Check 77c and bootstrap 7i scan the plugin cache for ADR-096 Law 3 (a mod's
# `$.model` / `$.http` bills the subscription invisibly) — but both are point-in-time: a mod
# installed between runs (`claude plugin install` from any marketplace, `/brana:plugin add`)
# runs unscanned until the next validate or bootstrap. This hook re-runs the STATIC half of
# `mods-check.sh --installed` at every session start (MODS_INSTALLED_STATIC_ONLY=1: no
# `claude plugin validate`, no engine, ~100 ms), so a mod installed after the last bootstrap
# is reported by the next session.
#
# Advisory by design (ADR-096 Law 4 — safety stays in shell hooks that PREVENT; this one only
# reports, a gauge not a valve): one additionalContext warning line, exit 0 always, never a
# block. The remedy stays the registry's [77c]: uninstall, then re-run validate.
#
# Trust boundary (t-3502 panel): the checker is taken ONLY from the deployed sibling
# `../scripts/` or `$CLAUDE_PLUGIN_ROOT/scripts/` — never from the repo at the session's cwd
# (a hostile clone could plant one and have it run at every session start). The relayed line
# carries only the mod NAME and the RULE, sanitised to a safe character set — never the
# module path or any other mod-controlled text (a hostile module name is prompt injection
# into the session's context). Only the checker's own exit 1 is a verdict; a checker that
# dies, times out or cannot read the registry is reported as "scan did not run", with no
# uninstall remedy for a mod that was never scanned.
#
# Output: nothing when clean or nothing installed; otherwise one JSON line
#         {"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"⚠ …"}}
# Env:    CLAUDE_CONFIG_DIR (the engine's config dir; default ~/.claude)
#         BRANA_MODS_CHECK  (path to mods-check.sh — tests; default: resolved below)
# Tests:  system/hooks/tests/test-mods-installed-check.sh (must-fire with the t-3493 billing mod)
#
# No strict mode — a SessionStart hook must always exit 0 and emit valid JSON or nothing.
# stdin is deliberately never read: nothing here depends on the payload.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"

# Nothing installed: nothing to scan, nothing to say.
[ -f "$CLAUDE_DIR/plugins/installed_plugins.json" ] || exit 0

REMEDY="run ./validate.sh (Check 77c) by hand"

# safe(text, max): the only characters a relayed fragment may carry — enough for
# `name@marketplace`, a rule id and the checker's fixed wording; everything else is dropped.
safe() { printf '%s' "$1" | tr -cd 'A-Za-z0-9@._,:()/ -' | cut -c1-"${2:-80}"; }

emit() {   # one line -> one additionalContext JSON line (never a block, never a decision)
    local line esc
    line=$(printf '%s' "$1" | tr '\n' ' ' | cut -c1-600)
    esc=$(printf '%s' "$line" | jq -Rs . 2>/dev/null) || esc="\"$(printf '%s' "$line" | tr -d '"\\' | tr -d '\000-\037')\""
    printf '{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":%s}}\n' "$esc"
}

# Resolve the checker from DEPLOYED locations only: the copy of this hook lives in
# ~/.claude/hooks, whose sibling ~/.claude/scripts/ holds the flat scripts bootstrap deploys;
# then the plugin root. No repo tier (see the trust boundary above).
CHECK="${BRANA_MODS_CHECK:-}"
if [ -z "$CHECK" ]; then
    for d in "$SCRIPT_DIR/../scripts" "${CLAUDE_PLUGIN_ROOT:-/nonexistent}/scripts"; do
        [ -f "$d/mods-check.sh" ] && { CHECK="$d/mods-check.sh"; break; }
    done
fi
if [ ! -f "$CHECK" ]; then
    emit "⚠ installed-mods Law 3 scan did not run: mods-check.sh not found (next to this hook or under CLAUDE_PLUGIN_ROOT — re-run ./bootstrap.sh) — $REMEDY"
    exit 0
fi

# Ceiling: a session start must not hang on a scan. p_timeout (lib/portable.sh) when present.
# (the source must be its own `source …portable.sh` line — lint-portability.sh binds the shim call to it)
source "$SCRIPT_DIR/lib/portable.sh" 2>/dev/null || true
type p_timeout >/dev/null 2>&1 || p_timeout() { shift; "$@"; }   # no lib deployed: run unbounded rather than not at all

# Capture to a file, not $(...): a child that outlives the ceiling cannot hold our pipe open.
TMP=$(mktemp 2>/dev/null) || TMP="/tmp/mods-installed-check.$$"
p_timeout 8 env MODS_INSTALLED_STATIC_ONLY=1 bash "$CHECK" --installed "$CLAUDE_DIR" >"$TMP" 2>&1 </dev/null; RC=$?
OUT=$(cat "$TMP" 2>/dev/null); rm -f "$TMP"
[ "$RC" -eq 0 ] && exit 0

case "$RC" in
    124|137) emit "⚠ installed-mods Law 3 scan did not run: timed out after 8 s — $REMEDY"; exit 0 ;;
    1) ;;   # the checker's own verdict — handled below
    *) emit "⚠ installed-mods Law 3 scan did not run: mods-check --installed exit $RC — $REMEDY"; exit 0 ;;
esac

# Exit 1: either violations in scanned mods, or the checker failing CLOSED before scanning
# (unreadable or mis-shaped registry, python3 missing) — its summary then says "0 mod(s) scanned".
SUMMARY=$(printf '%s\n' "$OUT" | grep -E '^mods-check --installed:' | tail -n 1)
FIRST=$(printf '%s\n' "$OUT" | grep -m1 -E '^  [^ ]' | sed -E 's/^  //')
case "$SUMMARY" in
    *"0 mod(s) scanned"*)
        emit "⚠ installed-mods Law 3 scan could not run: $(safe "${FIRST##* — }" 120) ($(safe "$SUMMARY" 160)) — $REMEDY"
        exit 0 ;;
esac

# Violation line shape: `<name>: <module path>:<line>: <rule> — <why>` (the path is
# mod-controlled and is dropped; name and rule are sanitised).
NAME=$(safe "${FIRST%%:*}" 80)
RULE=$(safe "$(printf '%s' "${FIRST% — *}" | sed -E 's/.*: //')" 40)
NVIOL=$(printf '%s' "$SUMMARY" | grep -oE 'violations: [0-9]+' | grep -oE '[0-9]+')
emit "⚠ installed mods — ADR-096 Law 3 (a mod's \$.model/\$.http bills the subscription): mod ${NAME:-?} matches rule ${RULE:-?}${NVIOL:+ (${NVIOL} violation(s) in all)} — installed since the last bootstrap/validate; remedy [77c]: claude plugin uninstall <name>, then ./validate.sh"
exit 0
