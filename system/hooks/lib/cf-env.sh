#!/usr/bin/env bash
# Locate ruflo and export $CF. Source this to get $CF (hooks variant: adds cf_run).
#
# Since t-1936, $CF points at ruflo-cli.sh — the single sanctioned CLI entry —
# instead of the raw npm bin. The wrapper bypasses the tarball's CRLF shebang
# (t-1934) and injects the session-contamination threshold for namespace-less
# searches, so no caller needs to know either rule.

CF=""
_cf_candidates="$HOME/.claude/scripts/ruflo-cli.sh"
[ -n "${CLAUDE_PROJECT_DIR:-}" ] && _cf_candidates="$_cf_candidates ${CLAUDE_PROJECT_DIR}/system/scripts/ruflo-cli.sh"
for _cf_candidate in $_cf_candidates; do
    [ -x "$_cf_candidate" ] && CF="$_cf_candidate" && break
done

# Last-resort fallbacks (wrapper missing — may hit the CRLF-shebang bin, t-1934)
if [ -z "$CF" ]; then
    for name in ruflo claude-flow; do
        for candidate in "$HOME"/.nvm/versions/node/*/bin/$name; do
            [ -x "$candidate" ] && CF="$candidate" && break 2
        done
    done
    [ -z "$CF" ] && command -v ruflo &>/dev/null && CF="ruflo"
    [ -z "$CF" ] && command -v claude-flow &>/dev/null && CF="claude-flow"
    [ -z "$CF" ] && command -v npx &>/dev/null && CF="npx ruflo"
fi
export CF

# Wrapper: always run ruflo from $HOME so it uses ~/.swarm/memory.db
# (ruflo-cli.sh also cds to $HOME itself — this stays for raw-bin fallback paths)
cf_run() {
    (cd "$HOME" && $CF "$@")
}
