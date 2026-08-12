#!/usr/bin/env bash
# Locate ruflo and export $CF. Source this to get $CF (hooks variant: adds cf_run).
#
# Since t-1936, $CF points at ruflo-cli.sh — the single sanctioned CLI entry —
# instead of the raw npm bin. The wrapper bypasses the tarball's CRLF shebang
# (t-1934) and injects the session-contamination threshold for namespace-less
# searches, so no caller needs to know either rule.

CF=""
for _cf_candidate in \
    "$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/scripts/ruflo-cli.sh" \
    "$HOME/.claude/scripts/ruflo-cli.sh" \
    "${CLAUDE_PROJECT_DIR:-}/system/scripts/ruflo-cli.sh"; do
    [ -n "$_cf_candidate" ] && [ -x "$_cf_candidate" ] && CF="$_cf_candidate" && break
done

# Last-resort fallbacks (wrapper missing — may hit the CRLF-shebang bin, t-1934).
# nvm candidates walked newest-first (sort -rV) — an unsorted glob here shadows
# the intended version with whatever order the filesystem returns (t-2632 bug
# class; unified across both cf-env.sh copies and ruflo-cli.sh, t-2754).
if [ -z "$CF" ]; then
    for name in ruflo claude-flow; do
        while IFS= read -r _cf_nvm_bin; do
            [ -x "$_cf_nvm_bin" ] && CF="$_cf_nvm_bin" && break
        done < <(find "$HOME/.nvm/versions/node" -maxdepth 3 -path "*/bin/$name" 2>/dev/null | sort -rV)
        [ -n "$CF" ] && break
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
