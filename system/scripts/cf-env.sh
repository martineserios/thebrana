#!/usr/bin/env bash
# Locate ruflo and export $CF. Source this to get $CF.
#
# Since t-1936, $CF points at ruflo-cli.sh — the single sanctioned CLI entry —
# instead of the raw npm bin. The wrapper bypasses the tarball's CRLF shebang
# (t-1934) and injects the session-contamination threshold for namespace-less
# searches, so no caller needs to know either rule.

CF=""
for _cf_candidate in \
    "$(dirname "${BASH_SOURCE[0]}")/ruflo-cli.sh" \
    "$HOME/.claude/scripts/ruflo-cli.sh" \
    "${CLAUDE_PROJECT_DIR:-}/system/scripts/ruflo-cli.sh"; do
    [ -n "$_cf_candidate" ] && [ -x "$_cf_candidate" ] && CF="$_cf_candidate" && break
done

# Last-resort fallbacks (wrapper missing — e.g. partial deploy). These hit the
# raw npm bin, which may carry the CRLF shebang (t-1934) — works only if the
# tarball is fixed upstream.
if [ -z "$CF" ]; then
    for name in ruflo claude-flow; do
        for candidate in "$HOME"/.nvm/versions/node/*/bin/$name; do
            [ -x "$candidate" ] && CF="$candidate" && break 2
        done
        [ -z "$CF" ] && [ -x "$HOME/.npm-global/bin/$name" ] && CF="$HOME/.npm-global/bin/$name" && break
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
