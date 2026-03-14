#!/usr/bin/env bash
# Shell aliases and functions for brana CLI
# Usage: source /path/to/system/cli/aliases.sh
#    or: add to .bashrc/.zshrc

# ── Backlog shortcuts ────────────────────────────────────────────────────

alias bq='brana backlog query'
alias bn='brana backlog next'
alias bf='brana backlog focus'
alias bs='brana backlog status'
alias bb='brana backlog blocked'
alias bsearch='brana backlog search'
alias bdiff='brana backlog diff'
alias bstale='brana backlog stale'
alias bburn='brana backlog burndown'
alias bctx='brana backlog context'
alias bgraph='brana backlog graph'

# ── Ops shortcuts ────────────────────────────────────────────────────────

alias bo='brana ops status'
alias boh='brana ops health'
alias bol='brana ops logs'
alias bor='brana ops run'
alias bod='brana ops drift'
alias boc='brana ops collisions'
alias bosync='brana ops sync'
alias boreindex='brana ops reindex'

# ── Root shortcuts ───────────────────────────────────────────────────────

alias bd='brana doctor'
alias bv='brana version'

# ── Rust-accelerated pipelines ───────────────────────────────────────────
# These bypass Python entirely for maximum speed in scripts/pipelines

_brana_rust_dir() {
    local dir
    for dir in \
        "$(dirname "$(readlink -f "${BASH_SOURCE[0]:-$0}")")/rust/target/release" \
        "$HOME/.local/bin"; do
        [ -x "$dir/brana-query" ] && echo "$dir" && return 0
    done
    return 1
}

# Fast query: bfq --tag scheduler --status pending
bfq() {
    local rust_dir
    rust_dir=$(_brana_rust_dir) || { bq "$@"; return; }
    local tasks_file
    tasks_file="$(git rev-parse --show-toplevel 2>/dev/null)/.claude/tasks.json"
    [ -f "$tasks_file" ] || { echo "tasks.json not found"; return 1; }
    "$rust_dir/brana-query" --file "$tasks_file" "$@"
}

# Fast query + themed output: bfqf --tag scheduler --theme emoji
bfqf() {
    local rust_dir theme="classic"
    rust_dir=$(_brana_rust_dir) || { bq "$@"; return; }

    # Extract --theme arg
    local args=()
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --theme) theme="$2"; shift 2 ;;
            *) args+=("$1"); shift ;;
        esac
    done

    local tasks_file
    tasks_file="$(git rev-parse --show-toplevel 2>/dev/null)/.claude/tasks.json"
    [ -f "$tasks_file" ] || { echo "tasks.json not found"; return 1; }

    local themes_file
    themes_file="$(dirname "$(readlink -f "${BASH_SOURCE[0]:-$0}")")/themes.json"

    "$rust_dir/brana-query" --file "$tasks_file" "${args[@]}" \
        | "$rust_dir/brana-fmt" --theme "$theme" --themes-file "$themes_file"
}

# Fast count: bfc --tag scheduler
bfc() {
    local rust_dir
    rust_dir=$(_brana_rust_dir) || { bq --count "$@"; return; }
    local tasks_file
    tasks_file="$(git rev-parse --show-toplevel 2>/dev/null)/.claude/tasks.json"
    [ -f "$tasks_file" ] || { echo "tasks.json not found"; return 1; }
    "$rust_dir/brana-query" --file "$tasks_file" --count "$@"
}

# ── Script wrappers ──────────────────────────────────────────────────────
# Wrap system scripts that aren't in the Python CLI

bbackup() {
    local root
    root="$(git rev-parse --show-toplevel 2>/dev/null)" || { echo "Not in git repo"; return 1; }
    bash "$root/system/scripts/backup-knowledge.sh" "$@"
}

bindex() {
    local root
    root="$(git rev-parse --show-toplevel 2>/dev/null)" || { echo "Not in git repo"; return 1; }
    bash "$root/system/scripts/index-knowledge.sh" "$@"
}

bgraph-skills() {
    local root
    root="$(git rev-parse --show-toplevel 2>/dev/null)" || { echo "Not in git repo"; return 1; }
    bash "$root/system/scripts/skill-graph.sh" "$@"
}

bvalidate() {
    local root
    root="$(git rev-parse --show-toplevel 2>/dev/null)" || { echo "Not in git repo"; return 1; }
    bash "$root/validate.sh" "$@"
}
