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
# Input:  stdin JSON (session_id, cwd, hook_event_name)
# Output: nothing when clean or nothing installed; otherwise one JSON line
#         {"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"⚠ …"}}
# Env:    CLAUDE_CONFIG_DIR (the engine's config dir; default ~/.claude)
#         BRANA_MODS_CHECK  (path to mods-check.sh — tests; default: resolved below)
# Tests:  system/hooks/tests/test-mods-installed-check.sh (must-fire with the t-3493 billing mod)
#
# No strict mode — a SessionStart hook must always exit 0 and emit valid JSON or nothing.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"

# Nothing installed: nothing to scan, nothing to say.
[ -f "$CLAUDE_DIR/plugins/installed_plugins.json" ] || exit 0

INPUT=$(cat 2>/dev/null) || INPUT=""
CWD=$(printf '%s' "$INPUT" | jq -r '.cwd // empty' 2>/dev/null) || CWD=""
[ -d "${CWD:-/nonexistent}" ] || CWD="$PWD"
GIT_ROOT=$(git -C "$CWD" rev-parse --show-toplevel 2>/dev/null) || GIT_ROOT=""

emit() {   # one line -> one additionalContext JSON line (never a block, never a decision)
    local line esc
    line=$(printf '%s' "$1" | tr '\n' ' ' | cut -c1-600)
    esc=$(printf '%s' "$line" | jq -Rs . 2>/dev/null) || esc="\"$(printf '%s' "$line" | tr -d '"\\')\""
    printf '{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":%s}}\n' "$esc"
}

# Resolve the checker the way session-start.sh resolves its helpers (t-3277): the deployed
# copy of this hook lives in ~/.claude/hooks, whose sibling ~/.claude/scripts/ holds the
# flat scripts bootstrap deploys; then the plugin root; then the session's repo.
CHECK="${BRANA_MODS_CHECK:-}"
if [ -z "$CHECK" ]; then
    for d in "$SCRIPT_DIR/../scripts" "${CLAUDE_PLUGIN_ROOT:-/nonexistent}/scripts" "${GIT_ROOT:-/nonexistent}/system/scripts"; do
        [ -f "$d/mods-check.sh" ] && { CHECK="$d/mods-check.sh"; break; }
    done
fi
if [ ! -f "$CHECK" ]; then
    emit "⚠ installed-mods Law 3 scan did not run: mods-check.sh not found (next to this hook, under CLAUDE_PLUGIN_ROOT, or in the repo) — run ./validate.sh (Check 77c) by hand"
    exit 0
fi

# Ceiling: a session start must not hang on a scan. p_timeout (lib/portable.sh) when present.
if ! source "$SCRIPT_DIR/lib/portable.sh" 2>/dev/null || ! type p_timeout >/dev/null 2>&1; then
    p_timeout() { shift; "$@"; }
fi

OUT=$(p_timeout 8 env MODS_INSTALLED_STATIC_ONLY=1 bash "$CHECK" --installed "$CLAUDE_DIR" 2>&1 </dev/null); RC=$?
[ "$RC" -eq 0 ] && exit 0

case "$RC" in
    124|137) emit "⚠ installed-mods Law 3 scan timed out after 8 s — run ./validate.sh (Check 77c) by hand"; exit 0 ;;
esac

# The checker prints each violation as an indented line and ends with a summary line; relay
# the first violation and the summary, one line, and point at the remedy.
FIRST=$(printf '%s\n' "$OUT" | grep -m1 -E '^  [^ ]' | sed -E 's/^  //')
SUMMARY=$(printf '%s\n' "$OUT" | grep -E '^mods-check --installed:' | tail -n 1)
[ -n "$FIRST" ] || FIRST=$(printf '%s\n' "$OUT" | grep -v '^$' | head -n 1)
emit "⚠ installed mods — ADR-096 Law 3 (a mod's \$.model/\$.http bills the subscription): ${FIRST} | ${SUMMARY:-mods-check --installed exit $RC} — installed since the last bootstrap/validate; remedy [77c]: claude plugin uninstall <name>, then ./validate.sh"
exit 0
