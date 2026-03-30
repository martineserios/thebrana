#!/usr/bin/env bash
# Locate ruflo (formerly claude-flow) binary: nvm global → PATH → npx fallback.
# Source this to get $CF variable.

CF=""
# Prefer ruflo, fall back to claude-flow (legacy alias)
for name in ruflo claude-flow; do
    # nvm global installs
    for candidate in "$HOME"/.nvm/versions/node/*/bin/$name; do
        [ -x "$candidate" ] && CF="$candidate" && break 2
    done
    # npm prefix installs (no nvm)
    [ -z "$CF" ] && [ -x "$HOME/.npm-global/bin/$name" ] && CF="$HOME/.npm-global/bin/$name" && break
done
[ -z "$CF" ] && command -v ruflo &>/dev/null && CF="ruflo"
[ -z "$CF" ] && command -v claude-flow &>/dev/null && CF="claude-flow"
[ -z "$CF" ] && command -v npx &>/dev/null && CF="npx ruflo"
export CF
